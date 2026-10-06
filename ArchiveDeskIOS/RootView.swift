import SwiftUI
import UIKit
import UniformTypeIdentifiers

// Separate template assets retain closed/open silhouettes in native selected
// tabs; tint and dark-mode colors remain under the system's control.
enum ArchiveActionIcon {
    static let extract = "ArchiveBoxOpen"
    static let create = "ArchiveBoxClosed"
}

struct RootView: View {
    @StateObject private var model = WorkspaceModel()
    @State private var isDestinationChoicePresented = false
    @State private var isDestinationPickerPresented = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        tabs
            .modifier(DuoObservation(model: model))
            .fileImporter(isPresented: $model.isImporterPresented, allowedContentTypes: [.zip, .archive, .data], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls): if let url = urls.first { model.importArchive(url) }
                case .failure(let error): model.errorMessage = error.localizedDescription
                }
            }
            .confirmationDialog("Extraction destination", isPresented: $isDestinationChoicePresented, titleVisibility: .visible) {
                Button("ArchiveDesk on this device") { Task { @MainActor in model.extractSelected() } }
                Button("Choose folder in Files…") { Task { @MainActor in isDestinationPickerPresented = true } }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Write to local storage, an external drive, or iCloud. Other cloud drives are read-only. A new folder is created; existing files are never replaced.")
            }
            .sheet(isPresented: $isDestinationPickerPresented) {
                // Keep the system controller intact: its adaptive bars handle
                // Duo's camera, hinge and provider-specific folder actions.
                DestinationFolderPicker { folder in
                    isDestinationPickerPresented = false
                    Task { @MainActor in model.extractSelected(to: folder) }
                } onCancel: { isDestinationPickerPresented = false }
                .safeAreaInset(edge: .bottom) {
                    // Some compact folder-picker presentations omit a native
                    // close action. Keep an accessible exit away from cameras.
                    Button("Cancel", role: .cancel) { isDestinationPickerPresented = false }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(.bar)
                }
                .presentationDetents([.large])
            }
            .alert("ArchiveDesk", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
                Button("OK", role: .cancel) { model.errorMessage = nil }
            } message: { Text(model.errorMessage ?? "") }
            .sheet(isPresented: $model.isPasswordPresented, onDismiss: {
                if model.isPasswordPresented == false { model.cancelPassword() }
            }) { ArchivePasswordView(model: model) }
            .onChange(of: scenePhase) { _, phase in
                // Foreground-only MVP. Folding itself never cancels or resets state.
                if phase == .background { model.setForeground(false) }
                else if phase == .active { model.setForeground(true) }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
                model.handleMemoryPressure()
            }
            .onAppear {
                model.setForeground(scenePhase == .active)
                #if DEBUG
                model.loadDebugArchiveIfRequested()
                #endif
            }
    }

    private var tabs: some View {
        TabView(selection: $model.section) {
            Tab("Files", image: ArchiveActionIcon.extract, value: WorkspaceSection.files) {
                // Rebuild native navigation chrome when crossing compact/regular
                // displays. Workspace state lives above this identity boundary.
                browser.id(horizontalSizeClass)
            }
            Tab("Create archive", image: ArchiveActionIcon.create, value: WorkspaceSection.packing) {
                NavigationStack { PackingView(model: model) }
            }
            Tab("Tasks", systemImage: "list.bullet.rectangle", value: WorkspaceSection.tasks) {
                NavigationStack { TaskView(model: model) }
            }
            Tab("Information", systemImage: "info.circle", value: WorkspaceSection.information) {
                NavigationStack { InformationView(model: model) }
            }
        }
        // Let native tabs adapt to each display. Forcing a sidebar on the
        // current Duo beta can hide section navigation beside a split view.
        .tabViewStyle(.sidebarAdaptable)
    }

    private var browser: some View {
        NavigationSplitView(columnVisibility: $model.columnVisibility, preferredCompactColumn: $model.compactColumn) {
            Group {
                if model.archive != nil {
                    List(selection: Binding(get: { model.navigation.selection }, set: { model.select($0) })) {
                        if !model.navigation.folder.isEmpty {
                            Button(action: model.goUp) { Label("Parent folder", systemImage: "arrow.up") }
                                .accessibilityIdentifier("parentFolder")
                        }
                        ForEach(model.browserItems) { item in
                            if item.isDirectory {
                                Button { model.enterFolder(item.path) } label: {
                                    Label(item.name, systemImage: "folder").foregroundStyle(.primary)
                                }.accessibilityIdentifier("folder.\(item.path)")
                            } else {
                                NavigationLink(value: item.path) {
                                    HStack {
                                        Label(item.name, systemImage: item.entry?.isEncrypted == true ? "lock.doc" : "doc")
                                        Spacer()
                                        if let entry = item.entry {
                                            Text(entry.uncompressedSize.formatted(.byteCount(style: .file)))
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                }.accessibilityIdentifier("entry.\(item.path)")
                            }
                        }
                    }
                    .searchable(text: $model.navigation.search, prompt: "Search files")
                    .overlay {
                        if model.isListing && model.browserItems.isEmpty { ProgressView("Loading folder…") }
                        else if !model.isListing && model.browserItems.isEmpty && !model.navigation.search.isEmpty {
                            ContentUnavailableView.search(text: model.navigation.search)
                        }
                    }
                } else {
                    ContentUnavailableView {
                        Label("Open an archive", image: ArchiveActionIcon.extract)
                    } description: {
                        Text("Choose an archive from Files or a cloud provider.")
                    } actions: { openButton }
                }
            }
            .navigationTitle(model.navigation.folder.isEmpty ? (model.archive?.url.lastPathComponent ?? "ArchiveDesk") : (model.navigation.folder as NSString).lastPathComponent)
            .navigationSplitViewColumnWidth(min: 240, ideal: 300, max: 420)
            .toolbar { ToolbarItem(placement: .primaryAction) { openButton } }
        } detail: {
            EntryDetailView(model: model)
                .toolbar { ArchiveToolbar(model: model) { isDestinationChoicePresented = true } }
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var openButton: some View {
        Button { model.isImporterPresented = true } label: { Label("Open", systemImage: "folder.badge.plus") }
            .disabled(model.isBusy).accessibilityIdentifier("openArchive")
    }
}

struct ArchiveToolbar: ToolbarContent {
    @ObservedObject var model: WorkspaceModel
    let requestExtraction: () -> Void
    var body: some ToolbarContent {
        if #available(iOS 27.1, *) {
            ToolbarItem(placement: .primaryAction) { open }.axisBehavior(.verticalPreferred)
            ToolbarItem(placement: .primaryAction) { extract }.axisBehavior(.verticalPreferred)
        } else {
            ToolbarItem(placement: .primaryAction) { open }
            ToolbarItem(placement: .primaryAction) { extract }
        }
    }
    private var open: some View {
        Button { model.isImporterPresented = true } label: { Label("Open", systemImage: "folder.badge.plus") }
            .keyboardShortcut("o", modifiers: .command).disabled(model.isBusy)
            .accessibilityIdentifier("openArchiveToolbar")
    }
    private var extract: some View {
        Button(action: requestExtraction) { Label("Extract", image: ArchiveActionIcon.extract) }
            .keyboardShortcut("e", modifiers: .command)
            .disabled(model.isBusy || model.selectedEntry?.isExtractable != true)
            .accessibilityIdentifier("extractSelected")
    }
}

struct EntryDetailView: View {
    @ObservedObject var model: WorkspaceModel
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var textSize

    var body: some View {
        GeometryReader { geometry in
            if let entry = model.selectedEntry {
                if sizeClass == .regular && geometry.size.width >= 720 && !textSize.isAccessibilitySize {
                    #if DUO_SDK
                    if #available(iOS 27.1, *) {
                        ArrangementView {
                            EntryPreview(entry: entry, text: model.previewText)
                        } secondary: { metadata(entry) }
                        .arrangementViewStyle(.split)
                    } else { wideDetail(entry) }
                    #else
                    wideDetail(entry)
                    #endif
                } else {
                    // Both preview and actions stay reachable at compact widths.
                    Form {
                        Section("Preview") { EntryPreview(entry: entry, text: model.previewText).frame(minHeight: 180) }
                        fields(entry)
                    }
                }
            } else { ContentUnavailableView("Select an item", systemImage: "doc.text.magnifyingglass") }
        }
        .navigationTitle(model.selectedEntry.map { ($0.path as NSString).lastPathComponent } ?? String(localized: "Preview"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func metadata(_ entry: ArchiveEntry) -> some View { Form { fields(entry) } }
    private func wideDetail(_ entry: ArchiveEntry) -> some View {
        HStack(spacing: 0) {
            EntryPreview(entry: entry, text: model.previewText).frame(maxWidth: .infinity)
            metadata(entry).frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder private func fields(_ entry: ArchiveEntry) -> some View {
        PerformanceSection(model: model)
        Section("Entry") {
            AdaptiveValueRow("Path", value: entry.path).textSelection(.enabled)
            AdaptiveValueRow("Size", value: entry.uncompressedSize.formatted(.byteCount(style: .file)))
            AdaptiveValueRow("Format", value: model.archive?.formatName ?? "ZIP")
            AdaptiveValueRow("Method", value: entry.methodName)
            AdaptiveValueRow("Encrypted", value: entry.isEncrypted ? String(localized: "Yes") : String(localized: "No"))
            if entry.hasCRC { AdaptiveValueRow("CRC-32", value: String(format: "%08X", entry.crc32)) }
            else { Text("Format integrity checks run during extraction.").foregroundStyle(.secondary) }
        }
        if let location = model.extractionLocation, model.exportedEntryPath == entry.path {
            Section("Export") {
                Label("Extraction complete", systemImage: "checkmark.circle").accessibilityIdentifier("extractionReceipt")
                AdaptiveValueRow("Saved folder", value: location).textSelection(.enabled)
                Text("Open the destination in Files to view the extracted file.").foregroundStyle(.secondary)
            }
        }
        if !entry.isExtractable {
            Section { Text("This entry can be browsed. Its compression or encryption method is not available for extraction yet.").foregroundStyle(.secondary) }
        }
    }
}

struct EntryPreview: View {
    let entry: ArchiveEntry
    let text: String?
    var body: some View {
        if let text {
            ScrollView {
                Text(verbatim: text).font(.body.monospaced()).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding()
            }.accessibilityIdentifier("textPreview")
        } else {
            ContentUnavailableView("Preview unavailable", systemImage: "doc", description: Text("Small supported UTF-8 text files can be previewed. Extract other supported files to view them in Files."))
        }
    }
}

struct TaskView: View {
    @ObservedObject var model: WorkspaceModel
    var body: some View {
        Form {
            Section("Status") {
                Text(model.status)
                if model.isBusy { Button("Cancel", role: .cancel, action: model.cancel).accessibilityIdentifier("cancelTask") }
            }
            PerformanceSection(model: model)
            if let location = model.extractionLocation {
                Section("Export") { LabeledContent("Saved folder", value: location).textSelection(.enabled) }
            }
        }.navigationTitle("Tasks")
    }
}

struct InformationView: View {
    @ObservedObject var model: WorkspaceModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    var body: some View {
        List {
            Section("Formats") {
                LabeledContent("ZIP browsing", value: String(localized: "Available"))
                LabeledContent("ZIP stored / Deflate", value: String(localized: "Available"))
                LabeledContent("7z, RAR, TAR, ISO", value: String(localized: "Native format decoder"))
                LabeledContent("gzip, bzip2, XZ / LZMA", value: String(localized: "Native format decoder"))
                LabeledContent("Password-protected RAR4 / RAR5", value: String(localized: "Available"))
                LabeledContent("ZIP / TAR creation", value: String(localized: "Available"))
                Text("RAR supports password extraction, including tested solid and encrypted-header archives. Multi-volume archives, encrypted ZIP / 7z and encrypted creation are not available. RAR creation is never offered.")
                NavigationLink("Open-source notices") { CodecNoticesView() }
            }
            Section("Storage access") {
                Text("Read archives from any provider available in Files, including external storage.")
                Text("Write to local storage, an external drive, or iCloud. Other cloud drives are read-only. A new folder is created; existing files are never replaced.")
                Text("Unidentified locations are read-only. If access is revoked or a drive is disconnected, choose the folder again.")
            }
            #if DEBUG
            Section("Layout diagnostics") {
                LabeledContent("Interface environment", value: isRegularPhoneEnvironment ? "Phone, regular × regular" : "Standard")
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Interface environment")
                    .accessibilityValue(isRegularPhoneEnvironment ? "regularPhone" : "standard")
                    .accessibilityIdentifier("interfaceEnvironmentDiagnostic")
                LabeledContent("Window", value: "\(Int(model.diagnostics.width)) × \(Int(model.diagnostics.height))")
                LabeledContent("Active divisions", value: String(model.diagnostics.divisionCount))
                    .accessibilityIdentifier("divisionCountDiagnostic")
                    .accessibilityValue(String(model.diagnostics.divisionCount))
                LabeledContent("Hinge", value: model.hingeStatus)
                LabeledContent("Side insets", value: "\(Int(model.diagnostics.leadingInset)) / \(Int(model.diagnostics.trailingInset))")
                LabeledContent("Folder", value: model.navigation.folder)
                LabeledContent("Selection", value: model.navigation.selection ?? "—")
            }
            #endif
        }.navigationTitle("Information")
    }

    private var isRegularPhoneEnvironment: Bool {
        UIDevice.current.userInterfaceIdiom == .phone && horizontalSizeClass == .regular && verticalSizeClass == .regular
    }
}

private struct CodecNoticesView: View {
    @State private var paragraphs: [String] = []
    var body: some View {
        ScrollView {
            // A single 225 KiB Text exceeds practical rendering bounds on the
            // Duo beta. Keep the complete notices, but lay out lazy paragraphs.
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                    Text(verbatim: paragraph).font(.footnote).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }.padding()
        }.navigationTitle("Open-source notices")
        .overlay { if paragraphs.isEmpty { ProgressView() } }
        .task {
            guard paragraphs.isEmpty else { return }
            let url = Bundle.main.url(forResource: "CodecNotices", withExtension: "txt")
            let worker = Task.detached {
                let text = url.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
                    ?? "Open-source notices are unavailable."
                return text.components(separatedBy: "\n\n")
            }
            let loaded = await worker.value
            if !Task.isCancelled { paragraphs = loaded }
        }
    }
}

private struct DuoObservation: ViewModifier {
    @ObservedObject var model: WorkspaceModel
    @ViewBuilder func body(content: Content) -> some View {
        #if DEBUG && DUO_SDK
        if #available(iOS 27.1, *) {
            content.onHingeChange { _, context in
                // Observation is for debugging only; layout is driven by regions.
                if let hinge = context.hinge {
                    let status = hinge.status == .closed ? "Closed" : hinge.status == .fullyOpen ? "Fully open" : "Partially open"
                    if model.hingeStatus != status { model.hingeStatus = status }
                } else { model.hingeStatus = "Unavailable" }
            }
            .onGeometryChange(for: LayoutDiagnostics.self) { proxy in
                LayoutDiagnostics(width: proxy.size.width, height: proxy.size.height,
                    divisionCount: proxy.reservedRegions(kind: .division).count,
                    leadingInset: proxy.safeAreaInsets.leading, trailingInset: proxy.safeAreaInsets.trailing)
            } action: { model.diagnostics = $0 }
        } else {
            content.onGeometryChange(for: LayoutDiagnostics.self) { proxy in
                LayoutDiagnostics(width: proxy.size.width, height: proxy.size.height,
                    leadingInset: proxy.safeAreaInsets.leading, trailingInset: proxy.safeAreaInsets.trailing)
            } action: { model.diagnostics = $0 }
        }
        #else
        content
        #endif
    }
}

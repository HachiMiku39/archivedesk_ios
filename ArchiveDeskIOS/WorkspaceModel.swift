import Foundation
import SwiftUI
import Combine

private enum ArchiveImportResult: Sendable {
    case opened(ArchiveContainer), passwordRequired(URL)
}
private enum PasswordAction {
    case open(URL), preview(String), extract(String, URL?)
}

struct LayoutDiagnostics: Equatable {
    var width: Double = 0
    var height: Double = 0
    var divisionCount = 0
    var leadingInset: Double = 0
    var trailingInset: Double = 0
}

@MainActor
final class WorkspaceModel: ObservableObject {
    @Published var section: WorkspaceSection = .files
    @Published var archive: ArchiveContainer?
    @Published var navigation = ArchiveNavigation()
    // Start with the archive browser, not an empty detail-only iPad window.
    // SwiftUI still collapses these columns for compact phone widths.
    @Published var columnVisibility: NavigationSplitViewVisibility = .all
    @Published var isImporterPresented = false
    @Published var isBusy = false
    @Published var status = String(localized: "Ready")
    @Published var errorMessage: String?
    @Published var previewText: String?
    @Published var exportedURL: URL?
    @Published var exportedEntryPath: String?
    @Published var extractionLocation: String?
    @Published var diagnostics = LayoutDiagnostics()
    @Published var hingeStatus = "Unavailable"
    @Published var packingSources: [PackingSource] = []
    @Published var packingFormat: PackingFormat = .zip
    @Published var packingName = "Archive"
    @Published var packingProgress: Double = 0
    @Published var packingReceipt: String?
    @Published var isPasswordPresented = false
    @Published var passwordError: String?
    private var passwordAction: PasswordAction?
    private var operation: Task<Void, Never>?
    private var previewOperation: Task<Void, Never>?
    private var packingGeneration = UUID()

    isolated deinit {
        for source in packingSources { try? FileManager.default.removeItem(at: source.snapshotDirectory) }
    }

    var selectedEntry: ArchiveEntry? { archive?.entries.first { $0.path == navigation.selection } }
    var browserItems: [BrowserItem] { ArchiveBrowser.items(entries: archive?.entries ?? [], navigation: navigation) }

    func importArchive(_ url: URL, alreadyPrivate: Bool = false, password: String? = nil) {
        guard !isBusy else { return }
        isBusy = true; status = String(localized: "Preparing file…")
        operation = Task {
            let worker = Task.detached(priority: .userInitiated) {
                let snapshot = alreadyPrivate ? url : try CoordinatedFileAccess.snapshot(of: url)
                do {
                    let opened = try ArchiveContainer.open(url: snapshot, password: password)
                    try Task.checkCancellation()
                    return ArchiveImportResult.opened(opened)
                }
                catch RARFailure.passwordRequired { return ArchiveImportResult.passwordRequired(snapshot) }
                catch {
                    if !alreadyPrivate { try? FileManager.default.removeItem(at: snapshot.deletingLastPathComponent()) }
                    throw error
                }
            }
            do {
                let result = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                let snapshot: URL
                switch result { case .opened(let opened): snapshot = opened.url; case .passwordRequired(let url): snapshot = url }
                if Task.isCancelled {
                    try? FileManager.default.removeItem(at: snapshot.deletingLastPathComponent())
                    throw CancellationError()
                }
                guard case .opened(let opened) = result else {
                    requestPassword(.open(snapshot)); isBusy = false; return
                }
                previewOperation?.cancel()
                let previous = archive?.url
                archive = opened; navigation = ArchiveNavigation(); previewText = nil; exportedURL = nil
                exportedEntryPath = nil; extractionLocation = nil
                columnVisibility = .all
                if let previous, previous != opened.url { try? FileManager.default.removeItem(at: previous.deletingLastPathComponent()) }
                status = String(localized: "Archive ready")
            } catch {
                if alreadyPrivate, password != nil, case RARFailure.passwordOrDamage = error {
                    requestPassword(.open(url), error: error.localizedDescription)
                } else {
                    if alreadyPrivate, archive?.url != url { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
                    finish(error)
                }
            }
            isBusy = false
        }
    }

    func select(_ path: String?, password: String? = nil) {
        navigation.selection = path
        previewOperation?.cancel(); previewText = nil
        guard let archive, let entry = selectedEntry else { return }
        if archive.requiresPassword(entry), password == nil, entry.uncompressedSize <= 256 * 1024,
           ["txt", "md", "json", "xml", "csv", "log", "swift", "plist", "yaml", "yml"].contains((entry.path as NSString).pathExtension.lowercased()) {
            requestPassword(.preview(entry.path)); return
        }
        previewOperation = Task {
            let worker = Task.detached { try archive.previewText(entry, password: password) }
            do {
                let text = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                try Task.checkCancellation()
                if navigation.selection == path { previewText = text }
            } catch is CancellationError { }
            catch {
                if navigation.selection == path {
                    if case RARFailure.passwordOrDamage = error, archive.requiresPassword(entry) { requestPassword(.preview(entry.path), error: error.localizedDescription) }
                    else { errorMessage = error.localizedDescription }
                }
            }
        }
    }

    func enterFolder(_ path: String) { previewOperation?.cancel(); previewText = nil; navigation.enter(path) }
    func goUp() { previewOperation?.cancel(); previewText = nil; navigation.goUp() }

    func extractSelected(to pickedFolder: URL? = nil, password: String? = nil) {
        guard !isBusy, let archive, let entry = selectedEntry, entry.isExtractable else { return }
        if archive.requiresPassword(entry), password == nil { requestPassword(.extract(entry.path, pickedFolder)); return }
        isBusy = true; status = String(localized: "Extracting…"); exportedURL = nil
        exportedEntryPath = nil; extractionLocation = nil
        operation = Task {
            let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Extractions", isDirectory: true)
            let worker = Task.detached(priority: .userInitiated) {
                if let pickedFolder { return try CoordinatedFileAccess.extract(archive, paths: [entry.path], to: pickedFolder, password: password) }
                return ExtractionResult(directory: try archive.extract(paths: [entry.path], outputRoot: root, password: password), destination: .appDocuments)
            }
            do {
                let result = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                exportedURL = result.directory.appendingPathComponent(try ArchiveSafety.outputPath(entry.path))
                exportedEntryPath = entry.path
                // Display the receipt only; do not read the external URL after its grant ends.
                extractionLocation = (pickedFolder?.lastPathComponent ?? String(localized: "ArchiveDesk on this device"))
                    + "/" + result.directory.lastPathComponent
                status = String(localized: "Extraction complete")
            } catch {
                if case RARFailure.passwordOrDamage = error, archive.requiresPassword(entry) { requestPassword(.extract(entry.path, pickedFolder), error: error.localizedDescription) }
                else { finish(error) }
            }
            isBusy = false
        }
    }

    func cancel() { operation?.cancel(); previewOperation?.cancel(); cancelPassword() }

    private func requestPassword(_ action: PasswordAction, error: String? = nil) {
        passwordAction = action; passwordError = error; isPasswordPresented = true
        status = String(localized: "Password required")
    }
    func submitPassword(_ password: String) {
        guard !isBusy, let action = passwordAction else { return }
        passwordAction = nil; passwordError = nil; isPasswordPresented = false
        switch action {
        case .open(let url): importArchive(url, alreadyPrivate: true, password: password)
        case .preview(let path): if navigation.selection == path { select(path, password: password) }
        case .extract(let path, let folder): if navigation.selection == path { extractSelected(to: folder, password: password) }
        }
    }
    func cancelPassword() {
        if passwordAction != nil { status = String(localized: "Cancelled") }
        if case .open(let url) = passwordAction, archive?.url != url {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        passwordAction = nil; passwordError = nil; isPasswordPresented = false
    }

    func addPackingSources(_ urls: [URL]) {
        guard !isBusy, !urls.isEmpty else { return }
        isBusy = true; status = String(localized: "Preparing files…")
        let existing = packingSources
        operation = Task {
            let worker = Task.detached(priority: .userInitiated) {
                var added: [PackingSource] = []
                var success = false
                defer { if !success { for source in added { try? FileManager.default.removeItem(at: source.snapshotDirectory) } } }
                var names = Set(existing.map(\.name))
                for url in urls {
                    try Task.checkCancellation()
                    let name = try PackingInput.uniqueName(url.lastPathComponent, used: names)
                    let source = try PackingInput.snapshot(url, name: name)
                    added.append(source); names.insert(name)
                    _ = try ArchiveSafety.validate(entries: (existing + added).flatMap(\.items).map(\.entry), archiveBytes: 0)
                }
                try Task.checkCancellation(); success = true
                return added
            }
            do {
                let added = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                if Task.isCancelled {
                    for source in added { try? FileManager.default.removeItem(at: source.snapshotDirectory) }
                    throw CancellationError()
                }
                packingSources += added; packingReceipt = nil
                status = String(localized: "Files ready")
            } catch { finish(error) }
            isBusy = false
        }
    }

    func removePackingSources(at indices: IndexSet) {
        guard !isBusy else { return }
        for index in indices.sorted(by: >) {
            try? FileManager.default.removeItem(at: packingSources[index].snapshotDirectory)
            packingSources.remove(at: index)
        }
    }

    func createArchive(to pickedFolder: URL? = nil) {
        guard !isBusy, !packingSources.isEmpty else { return }
        let sources = packingSources, format = packingFormat, name = packingName
        isBusy = true; status = String(localized: "Creating archive…")
        let generation = UUID(); packingGeneration = generation
        packingProgress = 0; packingReceipt = nil
        operation = Task { [self] in
            let progress: @Sendable (UInt64, UInt64) -> Void = { [weak self] done, total in
                Task { @MainActor in
                    guard let self, self.isBusy, self.packingGeneration == generation else { return }
                    self.packingProgress = total == 0 ? 0 : Double(done) / Double(total)
                }
            }
            let worker = Task.detached(priority: .userInitiated) {
                if let pickedFolder {
                    return try CoordinatedFileAccess.pack(sources: sources, format: format, name: name, to: pickedFolder, progress: progress)
                }
                let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Archives", isDirectory: true)
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                return try ArchivePacker.create(sources: sources, format: format, name: name, in: root, progress: progress)
            }
            do {
                let url = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                packingReceipt = (pickedFolder?.lastPathComponent ?? String(localized: "ArchiveDesk on this device"))
                    + "/" + url.deletingLastPathComponent().lastPathComponent + "/" + url.lastPathComponent
                packingProgress = 1; status = String(localized: "Archive created")
            } catch { finish(error) }
            isBusy = false
        }
    }

    private func finish(_ error: Error) {
        if error is CancellationError { status = String(localized: "Cancelled") }
        else { errorMessage = error.localizedDescription; status = String(localized: "Failed") }
    }

    #if DEBUG
    func loadDebugArchiveIfRequested() {
        if ProcessInfo.processInfo.arguments.contains("--packing-fixtures"), packingSources.isEmpty, !isBusy {
            do { section = .packing; addPackingSources(try DebugArchiveFixture.packingSources()) }
            catch { errorMessage = error.localizedDescription }
            return
        }
        guard ProcessInfo.processInfo.arguments.contains("--demo-archive"), archive == nil, !isBusy else { return }
        do {
            let exerciseRead = ProcessInfo.processInfo.arguments.contains("--coordinated-read-fixture")
            importArchive(try DebugArchiveFixture.create(), alreadyPrivate: !exerciseRead)
        }
        catch { errorMessage = error.localizedDescription }
    }
    #endif
}

import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct PackingView: View {
    @ObservedObject var model: WorkspaceModel
    @State private var sourcesPresented = false
    @State private var destinationChoice = false
    @State private var destinationPresented = false
    var body: some View {
        Form {
            Section("Sources") {
                Text("Add files and folders from different locations. Each source is copied into a private snapshot; originals are not changed.")
                Button { sourcesPresented = true } label: { Label("Add files or folders…", systemImage: "folder.badge.plus") }
                    .disabled(model.isBusy).accessibilityIdentifier("addPackingSources")
                ForEach(model.packingSources) { source in
                    VStack(alignment: .leading) {
                        Text(verbatim: source.name)
                        Text(source.bytes.formatted(.byteCount(style: .file))).font(.caption).foregroundStyle(.secondary)
                    }.accessibilityIdentifier("packingSource.\(source.name)")
                }.onDelete(perform: model.removePackingSources)
            }
            Section("Archive options") {
                TextField("Archive name", text: $model.packingName)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("packingName")
                Picker("Format", selection: $model.packingFormat) {
                    Text("ZIP").tag(PackingFormat.zip)
                    Text("TAR").tag(PackingFormat.tar)
                }.pickerStyle(.segmented).accessibilityIdentifier("packingFormat")
                Text("ZIP uses Deflate. TAR is uncompressed. Password creation and RAR creation are not available.").font(.footnote).foregroundStyle(.secondary)
                Button { destinationChoice = true } label: {
                    Label("Create archive", image: ArchiveActionIcon.create)
                }
                    .disabled(model.isBusy || model.packingSources.isEmpty || model.packingName.isEmpty)
                    .accessibilityIdentifier("createArchive")
            }.disabled(model.isBusy)
            if model.isBusy {
                Section("Status") {
                    Text(model.status)
                    Button("Cancel", role: .cancel, action: model.cancel)
                }
            }
            PerformanceSection(model: model)
            if let receipt = model.packingReceipt {
                Section("Export") {
                    Label("Archive created", systemImage: "checkmark.circle").accessibilityIdentifier("packingReceipt")
                    Text(verbatim: receipt).textSelection(.enabled)
                    Text("Open the destination in Files to view the archive.")
                }
            }
        }
        .navigationTitle("Create archive")
        .sheet(isPresented: $sourcesPresented) {
            PackingSourcePicker { urls in
                sourcesPresented = false
                model.addPackingSources(urls)
            } onCancel: { sourcesPresented = false }
            .safeAreaInset(edge: .bottom) {
                Button("Cancel", role: .cancel) { sourcesPresented = false }
                    .buttonStyle(.bordered).frame(maxWidth: .infinity).padding(.vertical, 8).background(.bar)
            }
        }
        .confirmationDialog("Archive destination", isPresented: $destinationChoice, titleVisibility: .visible) {
            Button("ArchiveDesk on this device") { Task { @MainActor in model.createArchive() } }
            Button("Choose folder in Files…") { Task { @MainActor in destinationPresented = true } }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Write to any writable folder authorized in Files, including local storage, USB drives and cloud providers. A new folder is created; existing files are never replaced.")
        }
        .sheet(isPresented: $destinationPresented) {
            DestinationFolderPicker { folder in
                destinationPresented = false; model.createArchive(to: folder)
            } onCancel: { destinationPresented = false }
            .safeAreaInset(edge: .bottom) {
                Button("Cancel", role: .cancel) { destinationPresented = false }
                    .buttonStyle(.bordered).frame(maxWidth: .infinity).padding(.vertical, 8).background(.bar)
            }
        }
    }
}

struct PackingSourcePicker: UIViewControllerRepresentable {
    let onPick: ([URL]) -> Void
    let onCancel: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item, .folder], asCopy: false)
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) { }
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: PackingSourcePicker
        init(_ parent: PackingSourcePicker) { self.parent = parent }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { parent.onPick(urls) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { parent.onCancel() }
    }
}

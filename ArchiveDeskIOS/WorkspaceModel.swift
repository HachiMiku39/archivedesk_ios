import Foundation
import SwiftUI
import Combine

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
    private var operation: Task<Void, Never>?
    private var previewOperation: Task<Void, Never>?

    var selectedEntry: ArchiveEntry? { archive?.entries.first { $0.path == navigation.selection } }
    var browserItems: [BrowserItem] { ArchiveBrowser.items(entries: archive?.entries ?? [], navigation: navigation) }

    func importArchive(_ url: URL, alreadyPrivate: Bool = false) {
        guard !isBusy else { return }
        isBusy = true; status = String(localized: "Preparing file…")
        operation = Task {
            let worker = Task.detached(priority: .userInitiated) {
                let snapshot = alreadyPrivate ? url : try CoordinatedFileAccess.snapshot(of: url)
                do {
                    let opened = try ArchiveContainer.open(url: snapshot)
                    try Task.checkCancellation()
                    return opened
                }
                catch {
                    if !alreadyPrivate { try? FileManager.default.removeItem(at: snapshot.deletingLastPathComponent()) }
                    throw error
                }
            }
            do {
                let opened = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                previewOperation?.cancel()
                let previous = archive?.url
                archive = opened; navigation = ArchiveNavigation(); previewText = nil; exportedURL = nil
                exportedEntryPath = nil; extractionLocation = nil
                columnVisibility = .all
                if let previous, previous != opened.url { try? FileManager.default.removeItem(at: previous.deletingLastPathComponent()) }
                status = String(localized: "Archive ready")
            } catch { finish(error) }
            isBusy = false
        }
    }

    func select(_ path: String?) {
        navigation.selection = path
        previewOperation?.cancel(); previewText = nil
        guard let archive, let entry = selectedEntry else { return }
        previewOperation = Task {
            let worker = Task.detached { try archive.previewText(entry) }
            do {
                let text = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                try Task.checkCancellation()
                if navigation.selection == path { previewText = text }
            } catch is CancellationError { }
            catch { if navigation.selection == path { errorMessage = error.localizedDescription } }
        }
    }

    func enterFolder(_ path: String) { previewOperation?.cancel(); previewText = nil; navigation.enter(path) }
    func goUp() { previewOperation?.cancel(); previewText = nil; navigation.goUp() }

    func extractSelected(to pickedFolder: URL? = nil) {
        guard !isBusy, let archive, let entry = selectedEntry, entry.isExtractable else { return }
        isBusy = true; status = String(localized: "Extracting…"); exportedURL = nil
        exportedEntryPath = nil; extractionLocation = nil
        operation = Task {
            let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Extractions", isDirectory: true)
            let worker = Task.detached(priority: .userInitiated) {
                if let pickedFolder { return try CoordinatedFileAccess.extract(archive, paths: [entry.path], to: pickedFolder) }
                return ExtractionResult(directory: try archive.extract(paths: [entry.path], outputRoot: root), destination: .appDocuments)
            }
            do {
                let result = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                exportedURL = result.directory.appendingPathComponent(try ArchiveSafety.outputPath(entry.path))
                exportedEntryPath = entry.path
                // Display the receipt only; do not read the external URL after its grant ends.
                extractionLocation = (pickedFolder?.lastPathComponent ?? String(localized: "ArchiveDesk on this device"))
                    + "/" + result.directory.lastPathComponent
                status = String(localized: "Extraction complete")
            } catch { finish(error) }
            isBusy = false
        }
    }

    func cancel() { operation?.cancel(); previewOperation?.cancel() }

    private func finish(_ error: Error) {
        if error is CancellationError { status = String(localized: "Cancelled") }
        else { errorMessage = error.localizedDescription; status = String(localized: "Failed") }
    }

    #if DEBUG
    func loadDebugArchiveIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("--demo-archive"), archive == nil, !isBusy else { return }
        do {
            let exerciseRead = ProcessInfo.processInfo.arguments.contains("--coordinated-read-fixture")
            importArchive(try DebugArchiveFixture.create(), alreadyPrivate: !exerciseRead)
        }
        catch { errorMessage = error.localizedDescription }
    }
    #endif
}

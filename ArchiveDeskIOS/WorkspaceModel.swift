import Foundation
import SwiftUI
import Combine

private enum ArchiveImportResult: Sendable {
    case opened(ArchiveContainer), passwordRequired(URL)
}
private enum PasswordAction {
    case open(URL), preview(String), extract(ArchiveExtractionScope, URL?)
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
    @Published var archive: ArchiveContainer? {
        didSet {
            cachedFolder = nil; cachedRows = []
            allExtractionAvailability = nil; folderExtractionAvailability = nil; itemsExtractionAvailability = nil
            refreshSelection(); refreshBrowser()
        }
    }
    @Published var navigation = ArchiveNavigation() {
        didSet {
            if navigation.selection != oldValue.selection { refreshSelection() }
            if navigation.folder != oldValue.folder || navigation.search != oldValue.search {
                refreshBrowser(debounce: navigation.folder == oldValue.folder)
            }
        }
    }
    @Published private(set) var selectedEntry: ArchiveEntry?
    @Published private(set) var browserItems: [BrowserItem] = []
    @Published private(set) var isListing = false
    @Published var compactColumn: NavigationSplitViewColumn = .sidebar
    // Start with the archive browser, not an empty detail-only iPad window.
    // SwiftUI still collapses these columns for compact phone widths.
    @Published var columnVisibility: NavigationSplitViewVisibility = .all
    @Published var isImporterPresented = false
    @Published var isBusy = false
    @Published var status = String(localized: "Ready")
    @Published var errorMessage: String?
    @Published var previewText: String?
    @Published var extractionSelection: Set<String> = []
    @Published var exportedURL: URL?
    @Published var exportedEntryPath: String?
    @Published var extractionLocation: String?
    @Published var diagnostics = LayoutDiagnostics()
    @Published var hingeStatus = "Unavailable"
    @Published var packingSources: [PackingSource] = []
    @Published var packingFormat: PackingFormat = .zip
    @Published var packingName = "Archive"
    @Published var packingReceipt: String?
    @Published var isPasswordPresented = false
    @Published var passwordError: String?
    let performance = PerformanceModel()
    let mediaPreview = MediaPreviewModel()
    var transferMetrics: OperationMetrics? { performance.transfer }
    private var passwordAction: PasswordAction?
    private var operation: Task<Void, Never>?
    private var previewOperation: Task<Void, Never>?
    private var resourceMonitor: Task<Void, Never>?
    private var progressMailbox: ProgressMailbox?
    private var transferMeter: TransferMeter?
    private var stoppedForMemory = false
    private var browserOperation: Task<Void, Never>?
    private var browserRevision = UUID()
    private var cachedFolder: String?
    private var cachedRows: [BrowserItem] = []
    // Keep only the current folder/selection, not a growing history of large
    // path sets. Re-rendering controls must not re-filter the entire archive.
    private var allExtractionAvailability: Bool?
    private var folderExtractionAvailability: (path: String, allowed: Bool)?
    private var itemsExtractionAvailability: (paths: Set<String>, allowed: Bool)?

    isolated deinit {
        resourceMonitor?.cancel(); operation?.cancel(); previewOperation?.cancel(); browserOperation?.cancel()
        for source in packingSources { try? FileManager.default.removeItem(at: source.snapshotDirectory) }
    }

    private func refreshSelection() {
        guard let path = navigation.selection else { selectedEntry = nil; return }
        selectedEntry = archive?.entries.first { $0.path == path }
    }
    private func refreshBrowser(debounce: Bool = false) {
        browserOperation?.cancel()
        let revision = UUID(); browserRevision = revision
        guard let archive else { browserItems = []; cachedRows = []; cachedFolder = nil; isListing = false; return }
        let entries = archive.entries, folder = navigation.folder, query = navigation.search
        let cached = cachedFolder == folder ? cachedRows : nil
        if cached == nil { browserItems = [] }
        isListing = true
        browserOperation = Task {
            do {
                if debounce { try await Task.sleep(for: .milliseconds(200)) }
                try Task.checkCancellation()
                let worker = Task.detached(priority: .userInitiated) {
                    let rows = try cached ?? ArchiveBrowser.folderItems(entries: entries, folder: folder)
                    return (rows, try ArchiveBrowser.search(rows, query: query))
                }
                let result = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                guard !Task.isCancelled, browserRevision == revision else { return }
                cachedFolder = folder; cachedRows = result.0; browserItems = result.1; isListing = false
            } catch {
                if browserRevision == revision { isListing = false }
            }
        }
    }

    func setForeground(_ active: Bool) {
        resourceMonitor?.cancel(); resourceMonitor = nil
        if !active { cancel(); return }
        resourceMonitor = Task { [weak self] in
            var sampler = ProcessSampler()
            while !Task.isCancelled {
                let sample = sampler.sample()
                self?.performance.process = sample
                self?.refreshTransfer()
                if MemoryPolicy.shouldStop(headroom: sample.headroomBytes) { self?.handleMemoryPressure() }
                do { try await Task.sleep(for: .seconds(1)) } catch { break }
            }
        }
    }

    func handleMemoryPressure() {
        browserOperation?.cancel(); browserRevision = UUID()
        if isListing { isListing = false }
        cachedRows = []; cachedFolder = nil
        previewOperation?.cancel()
        mediaPreview.reset()
        if previewText != nil { previewText = nil }
        if isBusy && !stoppedForMemory { stoppedForMemory = true; operation?.cancel() }
    }

    /// Cancel and drain the previous decoder before starting another worker.
    private func prepareOperation() -> Task<Void, Never>? {
        let preview = previewOperation
        preview?.cancel(); previewOperation = nil
        mediaPreview.reset()
        // Retain the already bounded text result in normal use. Only its
        // decoder needs draining; a memory warning releases the text as well.
        stoppedForMemory = false; performance.transfer = nil
        progressMailbox = nil; transferMeter = nil
        return preview
    }
    private func waitForPreview(_ task: Task<Void, Never>?) async -> Bool {
        await task?.value
        // Reserve room for a dictionary plus framework / I/O overhead before
        // starting a decoder. This is conservative, not an allocation grant.
        if !MemoryPolicy.allowsNewWork(headroom: MemoryPolicy.headroom()) { stoppedForMemory = true }
        if Task.isCancelled || stoppedForMemory { finish(CancellationError()); isBusy = false; return false }
        return true
    }
    private func startTransfer() -> ProgressMailbox {
        let mailbox = ProgressMailbox()
        progressMailbox = mailbox; transferMeter = TransferMeter()
        performance.transfer = OperationMetrics()
        return mailbox
    }
    private func refreshTransfer(finished: Bool = false, succeeded: Bool = false) {
        guard let mailbox = progressMailbox, var meter = transferMeter else { return }
        let sample = mailbox.read()
        performance.transfer = meter.sample(bytes: sample.bytes, total: sample.total, finished: finished, succeeded: succeeded)
        transferMeter = finished ? nil : meter
        if finished { progressMailbox = nil }
    }

    func importArchive(_ url: URL, alreadyPrivate: Bool = false, password: String? = nil) {
        guard !isBusy else { return }
        let priorPreview = prepareOperation()
        isBusy = true; status = String(localized: "Preparing file…")
        let mailbox = startTransfer()
        operation = Task {
            guard await waitForPreview(priorPreview) else { return }
            let worker = Task.detached(priority: .userInitiated) {
                let snapshot = alreadyPrivate ? url : try CoordinatedFileAccess.snapshot(of: url, progress: { mailbox.update($0, $1) })
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
                    refreshTransfer(finished: true)
                    requestPassword(.open(snapshot)); isBusy = false; return
                }
                previewOperation?.cancel()
                let previous = archive?.url
                archive = opened; navigation = ArchiveNavigation(); previewText = nil; exportedURL = nil
                extractionSelection = []
                exportedEntryPath = nil; extractionLocation = nil
                columnVisibility = .all
                compactColumn = .sidebar
                if let previous, previous != opened.url { try? FileManager.default.removeItem(at: previous.deletingLastPathComponent()) }
                status = String(localized: "Archive ready")
                refreshTransfer(finished: true, succeeded: true)
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
        compactColumn = path == nil ? .sidebar : .detail
        let priorPreview = previewOperation
        previewOperation?.cancel(); previewText = nil
        let generation = mediaPreview.reset()
        guard !isBusy, MemoryPolicy.allowsNewWork(headroom: MemoryPolicy.headroom()),
              let archive, let entry = selectedEntry else { return }
        guard !entry.isDirectory, let kind = ArchivePreviewKind.forPath(entry.path) else { return }
        if archive.requiresPassword(entry), password == nil {
            mediaPreview.lock()
            requestPassword(.preview(entry.path)); return
        }
        // Visible filenames are not proof of decryption. Unsupported encrypted
        // ZIP entries never reach extraction or any decoder, even after input.
        guard entry.isExtractable else {
            if entry.isEncrypted {
                mediaPreview.lock(String(localized: "Encrypted ZIP preview is not supported by this build. No content has been decoded."))
            } else {
                mediaPreview.fail(ArchiveFailure.unsupported(String(localized: "This archive entry uses an unsupported compression method.")), generation: generation)
            }
            return
        }
        if kind != .text { mediaPreview.preparing(kind) }
        previewOperation = Task {
            await priorPreview?.value
            guard !Task.isCancelled else { return }
            let media = mediaPreview
            let worker = Task.detached { () async throws -> String? in
                if kind == .text { return try archive.previewText(entry, password: password) }
                guard entry.uncompressedSize <= 512 * 1024 * 1024,
                      kind != .image || entry.uncompressedSize <= 32 * 1024 * 1024 else { throw MediaPreviewFailure.limit }
                let root = FileManager.default.temporaryDirectory.appendingPathComponent("ArchiveDesk-Media-\(UUID())", isDirectory: true)
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
                defer { try? FileManager.default.removeItem(at: root) }
                // Decode only after completed decryption and format integrity
                // checks. Selected-entry staging never extracts the whole pack.
                let output = try archive.extract(paths: [entry.path], outputRoot: root, password: password)
                let file = output.appendingPathComponent(try ArchiveSafety.outputPath(entry.path))
                try await MediaPreviewWorker.run(url: file, kind: kind, model: media, generation: generation)
                return nil
            }
            do {
                let text = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                try Task.checkCancellation()
                if navigation.selection == path { previewText = text }
            } catch is CancellationError { }
            catch {
                guard !Task.isCancelled else { return }
                if navigation.selection == path {
                    if case RARFailure.passwordOrDamage = error, archive.requiresPassword(entry) {
                        mediaPreview.lock(); requestPassword(.preview(entry.path), error: error.localizedDescription)
                    } else { mediaPreview.fail(error, generation: generation); errorMessage = error.localizedDescription }
                }
            }
        }
    }

    func enterFolder(_ path: String) { previewOperation?.cancel(); previewText = nil; mediaPreview.reset(); navigation.enter(path); compactColumn = .sidebar }
    func goUp() { previewOperation?.cancel(); previewText = nil; mediaPreview.reset(); navigation.goUp(); compactColumn = .sidebar }

    func extractSelected(to pickedFolder: URL? = nil, password: String? = nil) {
        guard !isBusy, let entry = selectedEntry, entry.isExtractable else { return }
        extract(scope: .entry(entry.path), to: pickedFolder, password: password)
    }

    func canExtract(_ scope: ArchiveExtractionScope) -> Bool {
        guard !isBusy, let archive else { return false }
        switch scope {
        case .all: if let cached = allExtractionAvailability { return cached }
        case .folder(let path): if folderExtractionAvailability?.path == path { return folderExtractionAvailability!.allowed }
        case .items(let paths): if itemsExtractionAvailability?.paths == paths { return itemsExtractionAvailability!.allowed }
        case .entry: break
        }
        let entries = scope.entries(in: archive.entries)
        let allowed = !entries.isEmpty && entries.allSatisfy(\.isExtractable)
        switch scope {
        case .all: allExtractionAvailability = allowed
        case .folder(let path): folderExtractionAvailability = (path, allowed)
        case .items(let paths): itemsExtractionAvailability = (paths, allowed)
        case .entry: break
        }
        return allowed
    }

    func extract(scope: ArchiveExtractionScope, to pickedFolder: URL? = nil, password: String? = nil) {
        guard !isBusy, let archive else { return }
        let entries = scope.entries(in: archive.entries)
        guard !entries.isEmpty, entries.allSatisfy(\.isExtractable) else {
            errorMessage = String(localized: "This selection contains unavailable entries or an empty folder."); return
        }
        let paths = Set(entries.map(\.path))
        let needsPassword = entries.contains(where: archive.requiresPassword)
        if needsPassword, password == nil { requestPassword(.extract(scope, pickedFolder)); return }
        let priorPreview = prepareOperation()
        let mailbox = startTransfer()
        isBusy = true; status = String(localized: "Extracting…"); exportedURL = nil
        exportedEntryPath = nil; extractionLocation = nil
        operation = Task {
            guard await waitForPreview(priorPreview) else { return }
            let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Extractions", isDirectory: true)
            let worker = Task.detached(priority: .userInitiated) {
                let progress: ArchiveProgress = { mailbox.update($0, $1) }
                if let pickedFolder { return try CoordinatedFileAccess.extract(archive, paths: paths, to: pickedFolder, password: password, progress: progress) }
                return ExtractionResult(directory: try archive.extract(paths: paths, outputRoot: root, password: password, progress: progress), destination: .appDocuments)
            }
            do {
                let result = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                if case .entry(let path) = scope {
                    exportedURL = result.directory.appendingPathComponent(try ArchiveSafety.outputPath(path))
                    exportedEntryPath = path
                } else { exportedURL = result.directory; exportedEntryPath = nil }
                if case .items = scope { extractionSelection = [] }
                // Display the receipt only; do not read the external URL after its grant ends.
                extractionLocation = (pickedFolder?.lastPathComponent ?? String(localized: "ArchiveDesk on this device"))
                    + "/" + result.directory.lastPathComponent
                status = String(localized: "Extraction complete")
                refreshTransfer(finished: true, succeeded: true)
            } catch {
                refreshTransfer(finished: true)
                if case RARFailure.passwordOrDamage = error, needsPassword { requestPassword(.extract(scope, pickedFolder), error: error.localizedDescription) }
                else { finish(error) }
            }
            isBusy = false
        }
    }

    func cancel() { operation?.cancel(); previewOperation?.cancel(); mediaPreview.reset(); cancelPassword() }

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
        case .extract(let scope, let folder): extract(scope: scope, to: folder, password: password)
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
        let priorPreview = prepareOperation()
        isBusy = true; status = String(localized: "Preparing files…")
        let mailbox = startTransfer()
        let existing = packingSources
        operation = Task {
            guard await waitForPreview(priorPreview) else { return }
            let worker = Task.detached(priority: .userInitiated) {
                var added: [PackingSource] = []
                var success = false
                defer { if !success { for source in added { try? FileManager.default.removeItem(at: source.snapshotDirectory) } } }
                var names = Set(existing.map(\.name))
                var copied: UInt64 = 0
                for url in urls {
                    try Task.checkCancellation()
                    let name = try PackingInput.uniqueName(url.lastPathComponent, used: names)
                    let priorBytes = copied
                    let source = try PackingInput.snapshot(url, name: name, progress: { bytes, _ in mailbox.update(priorBytes + bytes, 0) })
                    copied += source.bytes
                    added.append(source); names.insert(name)
                    _ = try ArchiveSafety.validate(entries: (existing + added).lazy.flatMap(\.items).map(\.entry), archiveBytes: 0)
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
                refreshTransfer(finished: true, succeeded: true)
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
        let priorPreview = prepareOperation()
        let mailbox = startTransfer()
        let sources = packingSources, format = packingFormat, name = packingName
        isBusy = true; status = String(localized: "Creating archive…")
        packingReceipt = nil
        operation = Task { [self] in
            guard await waitForPreview(priorPreview) else { return }
            let progress: ArchiveProgress = { mailbox.update($0, $1) }
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
                status = String(localized: "Archive created")
                refreshTransfer(finished: true, succeeded: true)
            } catch { finish(error) }
            isBusy = false
        }
    }

    private func finish(_ error: Error) {
        refreshTransfer(finished: true)
        if error is CancellationError {
            status = String(localized: "Cancelled")
            if stoppedForMemory {
                errorMessage = String(localized: "Stopped to protect app memory. Temporary output was rolled back. Try a smaller selection or an archive with a smaller dictionary.")
            }
        }
        else { errorMessage = error.localizedDescription; status = String(localized: "Failed") }
    }

    #if DEBUG
    func loadDebugArchiveIfRequested() {
        #if targetEnvironment(simulator)
        if let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--media-fixture-path=") }), archive == nil, !isBusy {
            importArchive(URL(fileURLWithPath: String(argument.dropFirst("--media-fixture-path=".count))))
            return
        }
        #endif
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

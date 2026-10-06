import XCTest

final class ArchiveDeskDuoUITests: XCTestCase {
    @MainActor
    func testAccessiblePreviewAndBackNavigation() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--demo-archive", "--accessibility-text", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let folder = app.descendants(matching: .any)["folder.Documents"].firstMatch
        XCTAssertTrue(folder.waitForExistence(timeout: 15)); folder.tap()
        let note = app.descendants(matching: .any)["entry.Documents/Notes.md"].firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 5)); note.tap()
        let extract = extractionAction(in: app)
        XCTAssertTrue(extract.isEnabled)
        capture(app, name: "Accessibility text — adaptive detail")
        XCUIDevice.shared.orientation = .landscapeLeft
        waitForLayout(app, size: nil)
        XCTAssertTrue(extractionAction(in: app).isEnabled)
        capture(app, name: "Landscape — selection retained")
        XCUIDevice.shared.orientation = .portrait
        let duoBack = app.buttons["BackButton"].firstMatch
        let back = duoBack.exists ? duoBack : app.navigationBars.buttons.element(boundBy: 0)
        // A wide iPad may retain the sidebar instead of displaying a back button.
        if !note.isHittable && back.exists && back.isHittable { back.tap() }
        XCTAssertTrue(note.waitForExistence(timeout: 5), app.debugDescription)
        let parent = app.buttons["parentFolder"].firstMatch
        if parent.isHittable { parent.tap(); XCTAssertTrue(folder.waitForExistence(timeout: 5)) }
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }
    @MainActor
    func testLargePackingMetrics() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--packing-fixtures", "--performance-fixture", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["packingSource.Performance.bin"].firstMatch.waitForExistence(timeout: 30))
        let create = app.buttons["createArchive"].firstMatch
        waitForStableHitTarget(create); create.tap()
        let local = app.buttons["ArchiveDesk on this device"].firstMatch
        XCTAssertTrue(local.waitForExistence(timeout: 5))
        waitForStableHitTarget(local); local.tap()
        let tasks = app.buttons["Tasks"].firstMatch
        waitForStableHitTarget(tasks); tasks.tap()
        assertMetrics(in: app)
        capture(app, name: "128 MiB packing performance")
        XCTAssertTrue(app.staticTexts["Archive created"].firstMatch.waitForExistence(timeout: 90), app.debugDescription)
        let progress = app.progressIndicators["operationProgress"].firstMatch
        XCTAssertTrue((progress.value as? String)?.contains("100") == true, app.debugDescription)
        XCTAssertFalse(app.alerts.firstMatch.exists)
        capture(app, name: "Packing committed — final average speed")
    }

    @MainActor
    func testExtractionMetrics() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--demo-archive", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let folder = app.descendants(matching: .any)["folder.Documents"].firstMatch
        XCTAssertTrue(folder.waitForExistence(timeout: 15)); folder.tap()
        let note = app.descendants(matching: .any)["entry.Documents/Notes.md"].firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 5)); note.tap()
        let extract = extractionAction(in: app)
        waitForStableHitTarget(extract); extract.tap()
        let local = app.buttons["ArchiveDesk on this device"].firstMatch
        XCTAssertTrue(local.waitForExistence(timeout: 5)); waitForStableHitTarget(local); local.tap()
        let tasks = app.buttons["Tasks"].firstMatch
        waitForStableHitTarget(tasks); tasks.tap()
        XCTAssertTrue(app.staticTexts["Extraction complete"].firstMatch.waitForExistence(timeout: 10), app.debugDescription)
        assertMetrics(in: app)
        let progress = app.progressIndicators["operationProgress"].firstMatch
        XCTAssertTrue((progress.value as? String)?.contains("100") == true, app.debugDescription)
        XCTAssertFalse(app.alerts.firstMatch.exists)
        capture(app, name: "Extraction performance — verified completion")
    }

    @MainActor
    private func assertMetrics(in app: XCUIApplication) {
        for identifier in ["cpuUsage", "ramUsage", "operationSpeed", "processedBytes", "operationProgress"] {
            let value = app.descendants(matching: .any)[identifier].firstMatch
            for _ in 0..<5 where !value.exists { app.collectionViews.firstMatch.swipeUp() }
            XCTAssertTrue(value.waitForExistence(timeout: 5), app.debugDescription)
        }
    }

    @MainActor
    func testArchiveActionIconsAndNavigation() throws {
        // Screenshots cover the distinct open/closed box template assets and
        // the native tab's selected rendering on the actual Duo runtime.
        let app = XCUIApplication()
        app.launchArguments = ["--demo-archive", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let folder = app.descendants(matching: .any)["folder.Documents"].firstMatch
        XCTAssertTrue(folder.waitForExistence(timeout: 15), app.debugDescription)
        folder.tap()
        let note = app.descendants(matching: .any)["entry.Documents/Notes.md"].firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 5), app.debugDescription)
        note.tap()
        let extract = extractionAction(in: app)
        XCTAssertTrue(extract.isEnabled, app.debugDescription)
        capture(app, name: "Extract action — open box")
        waitForStableHitTarget(extract); extract.tap()
        // Native confirmation popovers can omit Cancel on this display. Use
        // the verified local destination instead of assuming that button exists.
        let local = app.buttons["ArchiveDesk on this device"].firstMatch
        XCTAssertTrue(local.waitForExistence(timeout: 5), app.debugDescription)
        waitForStableHitTarget(local); local.tap()
        let receipt = app.descendants(matching: .any)["extractionReceipt"].firstMatch
        if !receipt.waitForExistence(timeout: 5) { app.swipeUp() }
        XCTAssertTrue(receipt.waitForExistence(timeout: 10), app.debugDescription)
        let packingTab = app.buttons["Create archive"].firstMatch
        XCTAssertTrue(packingTab.waitForExistence(timeout: 5), app.debugDescription)
        waitForStableHitTarget(packingTab); packingTab.tap()
        let create = app.buttons["createArchive"].firstMatch
        XCTAssertTrue(create.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(create.isEnabled, "No sources were added; icon change must not alter validation.")
        capture(app, name: "Create archive action — closed box")
    }

    @MainActor
    func testPackingPickerCancellationPreservesSources() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--packing-fixtures", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let source = app.descendants(matching: .any)["packingSource.SourceA"].firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 15), app.debugDescription)
        let add = app.buttons["addPackingSources"].firstMatch
        waitForStableHitTarget(add); add.tap()
        let cancel = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 30), app.debugDescription)
        waitForStableHitTarget(cancel); cancel.tap()
        XCTAssertTrue(source.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.descendants(matching: .any)["packingSource.other.txt"].firstMatch.exists)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    @MainActor
    func testPasswordPromptCancellationReturnsToBrowser() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--demo-archive", "--fixture-rar-headers", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.secureTextFields["archivePassword"].firstMatch.waitForExistence(timeout: 15))
        let cancel = app.buttons["Cancel"].firstMatch
        waitForStableHitTarget(cancel); cancel.tap()
        let open = app.buttons["openArchive"].firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(open.isEnabled)
        XCTAssertFalse(app.secureTextFields["archivePassword"].firstMatch.exists)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    @MainActor
    func testMultiSourceZIPAndTARCreation() throws {
        XCUIDevice.shared.orientation = .portrait
        for format in ["ZIP", "TAR"] {
            let app = XCUIApplication()
            app.launchArguments = ["--packing-fixtures", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
            app.launch()
            XCTAssertTrue(app.descendants(matching: .any)["packingSource.SourceA"].firstMatch.waitForExistence(timeout: 15), app.debugDescription)
            XCTAssertTrue(app.descendants(matching: .any)["packingSource.other.txt"].firstMatch.exists)
            let choice = app.segmentedControls["packingFormat"].buttons[format]
            for _ in 0..<5 where !choice.exists { app.collectionViews.firstMatch.swipeUp() }
            XCTAssertTrue(choice.waitForExistence(timeout: 5), app.debugDescription)
            choice.tap()
            let create = app.buttons["createArchive"].firstMatch
            waitForStableHitTarget(create); create.tap()
            let local = app.buttons["ArchiveDesk on this device"].firstMatch
            XCTAssertTrue(local.waitForExistence(timeout: 5))
            waitForStableHitTarget(local); local.tap()
            let receipt = app.descendants(matching: .any)["packingReceipt"].firstMatch
            for _ in 0..<5 {
                if receipt.waitForExistence(timeout: 1) { break }
                app.collectionViews.firstMatch.swipeUp()
            }
            XCTAssertTrue(receipt.waitForExistence(timeout: 10), app.debugDescription)
            // A visible Export header does not instantiate the following lazy
            // Form row on every viewport. Scroll to the actual output path.
            let outputPath = app.staticTexts.containing(NSPredicate(format: "label ENDSWITH %@", "." + format.lowercased())).firstMatch
            for _ in 0..<5 where !outputPath.exists { app.collectionViews.firstMatch.swipeUp() }
            XCTAssertTrue(outputPath.waitForExistence(timeout: 5), app.debugDescription)
            XCTAssertFalse(app.alerts.firstMatch.exists, app.debugDescription)
            capture(app, name: "Multi-source " + format + " creation")
            app.terminate()
        }
    }

    @MainActor
    func testPasswordRARHeadersRetryPreviewAndExtraction() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--demo-archive", "--fixture-rar-headers", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        try submitFixturePassword("wrong", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["passwordError"].firstMatch.waitForExistence(timeout: 10), app.debugDescription)
        try submitFixturePassword("password", in: app)
        let b = app.descendants(matching: .any)["entry.b.txt"].firstMatch
        XCTAssertTrue(b.waitForExistence(timeout: 15), app.debugDescription)
        b.tap()
        // Opening headers must not retain a password for the subsequent preview.
        try submitFixturePassword("password", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["textPreview"].firstMatch.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.staticTexts["This is from b.txt"].firstMatch.exists)
        let extract = extractionAction(in: app)
        waitForStableHitTarget(extract); extract.tap()
        let local = app.buttons["ArchiveDesk on this device"].firstMatch
        XCTAssertTrue(local.waitForExistence(timeout: 5)); waitForStableHitTarget(local); local.tap()
        // Extraction is another operation and asks again, without saved secrets.
        try submitFixturePassword("password", in: app)
        let receipt = app.descendants(matching: .any)["extractionReceipt"].firstMatch
        if !receipt.waitForExistence(timeout: 5) { app.swipeUp() }
        XCTAssertTrue(receipt.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.alerts.firstMatch.exists, app.debugDescription)
        capture(app, name: "RAR5 password retry, preview and extraction")
    }

    @MainActor
    private func submitFixturePassword(_ password: String, in app: XCUIApplication) throws {
        let field = app.secureTextFields["archivePassword"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 15), app.debugDescription)
        waitForStableHitTarget(field); field.tap(); field.typeText(password)
        let submit = app.buttons["submitArchivePassword"].firstMatch
        waitForStableHitTarget(submit); submit.tap()
    }

    @MainActor
    func testOpenSourceNoticesAreReadable() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--demo-archive", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["Information"].firstMatch.waitForExistence(timeout: 15))
        app.buttons["Information"].firstMatch.tap()
        let notices = app.buttons["Open-source notices"].firstMatch
        XCTAssertTrue(notices.waitForExistence(timeout: 5), app.debugDescription)
        notices.tap()
        let version = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "libarchive 3.8.9")).firstMatch
        XCTAssertTrue(version.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(version.isHittable, app.debugDescription)
        XCTAssertFalse(app.staticTexts["Open-source notices are unavailable."].firstMatch.exists)
        capture(app, name: "Readable bundled codec notices")
    }

    @MainActor
    func testNative7zPreviewAndExtraction() throws {
        try verifyCodecFixture("--fixture-7z")
    }

    @MainActor
    func testDeflatePreviewAndExtraction() throws {
        try verifyCodecFixture("--fixture-deflate")
        try verifyCodecFixture("--fixture-cp437")
    }

    @MainActor
    private func verifyCodecFixture(_ fixture: String) throws {
        let app = XCUIApplication()
        app.launchArguments = ["--demo-archive", fixture, "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let path = fixture == "--fixture-cp437" ? "éotes.md" : "Notes.md"
        let note = app.descendants(matching: .any)["entry." + path].firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 15), app.debugDescription)
        if fixture == "--fixture-7z" {
            XCTAssertTrue(app.descendants(matching: .any)["entry.中文.txt"].firstMatch.exists, app.debugDescription)
            XCTAssertTrue(app.descendants(matching: .any)["entry.日本語.txt"].firstMatch.exists, app.debugDescription)
        }
        note.tap()
        XCTAssertTrue(app.descendants(matching: .any)["textPreview"].firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "ArchiveDesk native codec verification.")).firstMatch.exists)
        let extract = extractionAction(in: app)
        waitForStableHitTarget(extract)
        extract.tap()
        let local = app.buttons["ArchiveDesk on this device"].firstMatch
        XCTAssertTrue(local.waitForExistence(timeout: 5))
        waitForStableHitTarget(local)
        local.tap()
        let receipt = app.descendants(matching: .any)["extractionReceipt"].firstMatch
        if !receipt.waitForExistence(timeout: 5) { app.swipeUp() }
        XCTAssertTrue(receipt.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.alerts.firstMatch.exists, app.debugDescription)
        capture(app, name: fixture + " verified preview and extraction")
    }

    @MainActor
    func testCoordinatedReadCreatesPreviewSnapshot() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--demo-archive", "--coordinated-read-fixture", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let folder = app.descendants(matching: .any)["folder.Documents"].firstMatch
        XCTAssertTrue(folder.waitForExistence(timeout: 15), app.debugDescription)
        folder.tap()
        let note = app.descendants(matching: .any)["entry.Documents/Notes.md"].firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        note.tap()
        XCTAssertTrue(app.descendants(matching: .any)["textPreview"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "A small UTF-8 preview.")).firstMatch.exists)
        XCTAssertFalse(app.alerts.firstMatch.exists)
        capture(app, name: "Verified coordinated-read snapshot")
    }

    @MainActor
    func testPreviewSelectionSurvivesRotation() throws {
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchArguments = ["--demo-archive", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let folder = app.descendants(matching: .any)["folder.Documents"].firstMatch
        XCTAssertTrue(folder.waitForExistence(timeout: 15), app.debugDescription)
        folder.tap()
        let note = app.descendants(matching: .any)["entry.Documents/Notes.md"].firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        note.tap()
        let preview = app.descendants(matching: .any)["textPreview"].firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "A small UTF-8 preview.")).firstMatch.exists)
        app.buttons["Information"].firstMatch.tap()
        let environment = app.descendants(matching: .any)["interfaceEnvironmentDiagnostic"].firstMatch
        // Additional format rows make Information taller. Scroll its native
        // collection rather than assuming one swipe reveals Debug diagnostics.
        for _ in 0..<5 {
            if environment.waitForExistence(timeout: 1) { break }
            app.collectionViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(environment.waitForExistence(timeout: 5), app.debugDescription)
        let environmentValue = try XCTUnwrap(environment.value as? String, app.debugDescription)
        XCTAssertTrue(["regularPhone", "standard"].contains(environmentValue))
        // Fully open Duo can report no reserved division. Its actual phone
        // regular/regular environment, not a division count, selects this check.
        let usesInnerDisplayEnvironment = environmentValue == "regularPhone"
        app.buttons["Files"].firstMatch.tap()
        capture(app, name: "Preview before rotation")
        let initialSize = app.windows.firstMatch.frame.size
        XCUIDevice.shared.orientation = .landscapeLeft
        waitForLayout(app, size: usesInnerDisplayEnvironment ? nil : CGSize(width: initialSize.height, height: initialSize.width))
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "A small UTF-8 preview.")).firstMatch.exists)
        capture(app, name: usesInnerDisplayEnvironment ? "Inner preview after physical rotation request" : "Preview landscape")
        XCUIDevice.shared.orientation = .portrait
        waitForLayout(app, size: usesInnerDisplayEnvironment ? nil : initialSize)
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "A small UTF-8 preview.")).firstMatch.exists)
        capture(app, name: "Preview portrait restored")
    }

    @MainActor
    func testSelectedStoredFileCanBeExtracted() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--demo-archive", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let folder = app.descendants(matching: .any)["folder.Documents"].firstMatch
        XCTAssertTrue(folder.waitForExistence(timeout: 15))
        folder.tap()
        let note = app.descendants(matching: .any)["entry.Documents/Notes.md"].firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        note.tap()
        let extract = extractionAction(in: app)
        XCTAssertTrue(extract.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(extract.isEnabled)
        waitForStableHitTarget(extract)
        extract.tap()
        let local = app.buttons["ArchiveDesk on this device"].firstMatch
        XCTAssertTrue(local.waitForExistence(timeout: 5), app.debugDescription)
        waitForStableHitTarget(local)
        local.tap()
        let receipt = app.descendants(matching: .any)["extractionReceipt"].firstMatch
        // The compact outer display virtualizes off-screen Form rows.
        if !receipt.waitForExistence(timeout: 5) { app.swipeUp() }
        XCTAssertTrue(receipt.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.buttons["Share extracted file"].firstMatch.exists)
        XCTAssertFalse(app.alerts.firstMatch.exists)
        capture(app, name: "Verified local extraction receipt")
    }

    @MainActor
    func testDestinationPickerCancellationRetainsPreview() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--demo-archive", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let folder = app.descendants(matching: .any)["folder.Documents"].firstMatch
        XCTAssertTrue(folder.waitForExistence(timeout: 15))
        folder.tap()
        let note = app.descendants(matching: .any)["entry.Documents/Notes.md"].firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        note.tap()
        var extract = extractionAction(in: app)
        XCTAssertTrue(extract.waitForExistence(timeout: 5), app.debugDescription)
        waitForStableHitTarget(extract)
        extract.tap()
        let choose = app.buttons["Choose folder in Files…"].firstMatch
        XCTAssertTrue(choose.waitForExistence(timeout: 5))
        waitForStableHitTarget(choose)
        choose.tap()
        let cancel = app.buttons["Cancel"].firstMatch
        let action = app.buttons["DOCPicker.actionButton"].firstMatch
        XCTAssertTrue(action.waitForExistence(timeout: 30), app.debugDescription)
        waitForStableHitTarget(action)
        capture(app, name: "System destination folder picker")
        if cancel.exists {
            waitForStableHitTarget(cancel)
            cancel.tap()
        } else {
            // The system's wide Duo presentation uses an outside-dismiss region
            // instead of a close button. Tap its visible left margin, not Files.
            let dismiss = app.descendants(matching: .any)["PopoverDismissRegion"].firstMatch
            XCTAssertTrue(dismiss.exists, app.debugDescription)
            dismiss.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5)).tap()
        }
        XCTAssertTrue(app.descendants(matching: .any)["textPreview"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "A small UTF-8 preview.")).firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any)["extractionReceipt"].firstMatch.exists)
        XCTAssertFalse(app.alerts.firstMatch.exists)

        // Re-open and select the actual system-authorized app Documents folder.
        // This exercises NSFileCoordinator on iOS, unlike the shortcut local path.
        extract = extractionAction(in: app)
        XCTAssertTrue(extract.waitForExistence(timeout: 5), app.debugDescription)
        waitForStableHitTarget(extract)
        extract.tap()
        XCTAssertTrue(choose.waitForExistence(timeout: 5), app.debugDescription)
        waitForStableHitTarget(choose)
        choose.tap()
        let openFolder = app.buttons["DOCPicker.actionButton"].firstMatch
        XCTAssertTrue(openFolder.waitForExistence(timeout: 30), app.debugDescription)
        waitForStableHitTarget(openFolder)
        openFolder.tap()
        let receipt = app.descendants(matching: .any)["extractionReceipt"].firstMatch
        if !receipt.waitForExistence(timeout: 5) { app.swipeUp() }
        XCTAssertTrue(app.descendants(matching: .any)["extractionReceipt"].firstMatch.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.alerts.firstMatch.exists, app.debugDescription)
        app.buttons["Tasks"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Saved folder"].firstMatch.waitForExistence(timeout: 5))
        capture(app, name: "Verified coordinated folder extraction")
    }

    @MainActor
    private func extractionAction(in app: XCUIApplication) -> XCUIElement {
        let direct = app.buttons["extractSelected"].firstMatch
        if direct.waitForExistence(timeout: 5) {
            waitForStableHitTarget(direct)
            return direct
        }
        let more = app.buttons["More"].firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 5), app.debugDescription)
        waitForStableHitTarget(more)
        more.tap()
        let action = app.buttons["Extract"].firstMatch
        if !action.waitForExistence(timeout: 3) {
            // In narrow regular windows, the file column overlays the detail.
            // The first tap can dismiss that column. Re-query the now-exposed
            // native More control; never tap Extract until its menu is present.
            XCTAssertTrue(more.exists, app.debugDescription)
            waitForStableHitTarget(more)
            more.tap()
        }
        XCTAssertTrue(action.waitForExistence(timeout: 5), app.debugDescription)
        return action
    }

    @MainActor
    private func waitForStableHitTarget(_ element: XCUIElement) {
        // The remote Files view can expose its button before the sheet finishes
        // expanding. Do not tap a stale accessibility frame during that animation.
        var previousFrame = CGRect.zero
        var stableSamples = 0
        let predicate = NSPredicate { _, _ in
            guard element.exists, element.isHittable else { stableSamples = 0; return false }
            let frame = element.frame
            stableSamples = frame == previousFrame && !frame.isEmpty ? stableSamples + 1 : 0
            previousFrame = frame
            return stableSamples >= 2
        }
        let ready = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
    }

    @MainActor
    private func waitForLayout(_ app: XCUIApplication, size: CGSize?) {
        var previousFrame = CGRect.zero
        var stableSamples = 0
        let predicate = NSPredicate { _, _ in
            let frame = app.windows.firstMatch.frame
            if let size {
                return abs(frame.width - size.width) < 1 && abs(frame.height - size.height) < 1
            }
            // Apple's Duo inner display uses division regions rather than
            // supported interface orientations. Check stable positive geometry
            // and retained content, without assuming the window must swap axes.
            stableSamples = frame == previousFrame && !frame.isEmpty ? stableSamples + 1 : 0
            previousFrame = frame
            return stableSamples >= 2
        }
        let ready = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
    }

    @MainActor
    private func capture(_ app: XCUIApplication, name: String) {
        // A matching accessibility frame can precede the rotation animation.
        Thread.sleep(forTimeInterval: 1)
        // On Duo, main-screen capture can be the inactive (black) outer panel.
        // Keep the app-scene capture as well; visually verify both attachments.
        let sceneAttachment = XCTAttachment(screenshot: app.screenshot())
        sceneAttachment.name = name + " — app scene"
        sceneAttachment.lifetime = .keepAlways
        add(sceneAttachment)
        // Full-screen capture also catches rotation cropping on one-display devices.
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

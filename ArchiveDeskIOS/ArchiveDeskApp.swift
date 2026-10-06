import SwiftUI

@main
struct ArchiveDeskApp: App {
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--accessibility-text") {
                RootView().dynamicTypeSize(.accessibility3)
            } else { RootView() }
            #else
            RootView()
            #endif
        }
    }
}

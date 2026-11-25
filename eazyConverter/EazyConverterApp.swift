import SwiftUI

@main
struct EazyConverterApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        #if os(macOS)
        .defaultSize(width: 900, height: 760)
        .commands {
            // There's no "New" document: the app never creates files of its own.
            CommandGroup(replacing: .newItem) {}
        }
        #endif
    }
}

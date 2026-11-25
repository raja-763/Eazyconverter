import SwiftUI

@main
struct EazyConverterApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        #if os(macOS)
        .defaultSize(width: 900, height: 760)
        #endif
        .commands {
            // There's no "New" document: the app never creates files of its own.
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Document") {
                DocumentMenu()
            }
        }
    }
}

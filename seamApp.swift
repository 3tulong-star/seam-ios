import SwiftUI

@main
struct seamApp: App {
    @State private var selectedMode: ConversationMode? = nil

    var body: some Scene {
        WindowGroup {
            Group {
                if let mode = selectedMode {
                    ContentView(mode: mode) {
                        selectedMode = nil
                    }
                } else {
                    ModeSelectionView(selectedMode: $selectedMode)
                }
            }
        }
    }
}

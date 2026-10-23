import SwiftUI

@main
struct CrossLinkApp: App {
    @StateObject private var link = MacLinkManager()

    var body: some Scene {
        MenuBarExtra {
            ContentView(link: link)
        } label: {
            // Template image from the asset catalog: the logo glyph, tinted by the menu bar
            Image("MenuBarIcon")
        }
        .menuBarExtraStyle(.window)
    }
}

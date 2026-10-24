import SwiftUI
import AppKit

@main
struct CrossLinkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            ContentView(link: delegate.link)
        } label: {
            // Template image from the asset catalog: the logo glyph, tinted by the menu bar
            Image("MenuBarIcon")
        }
        .menuBarExtraStyle(.window)
    }
}

/// Files reach the phone from Finder too: "Open With → CrossLink", a drop on the app icon, or
/// Services → "Отправить на телефон" (NSServices in Info.plist).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let link = MacLinkManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        link.sendFiles(urls.filter(\.isFileURL))
    }

    @objc func sendToPhone(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        link.sendFiles(urls)
    }
}

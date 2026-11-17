import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // "-appearance dark" or "-appearance light" on the command line overrides the system, for development.
        switch UserDefaults.standard.string(forKey: "appearance") {
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        default: break
        }
        model.start()
    }

    /// Opening Stash again while it is running, from Spotlight or Finder, shows the shelf.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        model.showPanel()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.willQuit()
    }
}

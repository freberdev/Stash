import Foundation
import ServiceManagement

/// Opening Stash when the user logs in.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    /// True when Stash runs from the Applications folder, as opposed to a build folder or a disk image.
    static var isInstalled: Bool {
        Bundle.main.bundlePath.hasPrefix("/Applications/")
    }
}

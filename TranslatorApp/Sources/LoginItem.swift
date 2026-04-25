import Foundation
import ServiceManagement

/// Thin wrapper around `SMAppService.mainApp` for "Launch at Login".
/// macOS 13+ replaced the old SMLoginItemSetEnabled / launchd-plist
/// dance with this one-liner — register the main app and the system
/// auto-starts it next login.
enum LoginItem {

    static var isRegistered: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    static func setRegistered(_ value: Bool) -> Bool {
        do {
            if value {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            NSLog("Skald: login-item update failed (%@): %@",
                  value ? "register" : "unregister",
                  String(describing: error))
            return false
        }
    }
}

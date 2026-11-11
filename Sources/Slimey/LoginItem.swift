import Foundation
import ServiceManagement

/// Launch at login via macOS Login Items (System Settings → General → Login Items).
enum LoginItem {
    static var status: SMAppService.Status { SMAppService.mainApp.status }

    static func setEnabled(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Slimey: login item change failed: \(error)")
        }
    }
}

import Foundation
import ServiceManagement

/// Starts the app when the user logs in (System Settings > General > Login Items).
enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Returns an error message the user can act on, or nil on success.
    @MainActor
    static func set(_ enabled: Bool) -> String? {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return nil
        } catch {
            return tr("Could not change the login item: \(error.localizedDescription). Move the app to the Applications folder and try again.",
                      "로그인 항목을 바꾸지 못했습니다: \(error.localizedDescription). 앱을 응용 프로그램 폴더로 옮긴 뒤 다시 시도하세요.")
        }
    }
}

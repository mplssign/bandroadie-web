import Cocoa
import FlutterMacOS
import UserNotifications

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  // Clear badge count whenever the app comes to the foreground
  override func applicationDidBecomeActive(_ notification: Notification) {
    NSApplication.shared.dockTile.badgeLabel = nil
    UNUserNotificationCenter.current().removeAllDeliveredNotifications()
  }
}

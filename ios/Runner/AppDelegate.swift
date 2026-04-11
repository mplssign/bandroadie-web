import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // Push notification permission and APNS registration are handled by the
    // firebase_messaging Flutter plugin. Calling requestAuthorization() or
    // registerForRemoteNotifications() here races Firebase initialization and
    // causes the APNS token to be lost.
    //
    // Flow:
    // 1. Firebase.initializeApp() runs in Dart main()
    // 2. Firebase sets up APNS method swizzling
    // 3. PushNotificationService.requestPermission() triggers the iOS dialog
    // 4. Firebase plugin calls registerForRemoteNotifications() and captures
    //    the APNS token via swizzling

    // MethodChannel for clearing app icon badge from Flutter
    let controller = window?.rootViewController as! FlutterViewController
    let badgeChannel = FlutterMethodChannel(
      name: "com.bandroadie/badge",
      binaryMessenger: controller.binaryMessenger
    )
    badgeChannel.setMethodCallHandler { (call, result) in
      if call.method == "clearBadge" {
        if #available(iOS 16.0, *) {
          UNUserNotificationCenter.current().setBadgeCount(0) { error in
            if let error = error {
              result(FlutterError(code: "BADGE_ERROR", message: error.localizedDescription, details: nil))
            } else {
              result(nil)
            }
          }
        } else {
          application.applicationIconBadgeNumber = 0
          result(nil)
        }
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

import UIKit
import Flutter
import GoogleSignIn

@main
class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    
    // Handle custom URL scheme on launch
    if let url = launchOptions?[UIApplication.LaunchOptionsKey.url] as? URL {
      handleIncomingURL(url)
    }
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  // Handle custom URL schemes when app is already running
  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey : Any] = [:]
  ) -> Bool {
    // Handle Google Sign-in
    if GIDSignIn.sharedInstance.handle(url) {
      return true
    }
    
    // Handle your custom scheme (ratedly://)
    if url.scheme == "ratedly" {
      handleIncomingURL(url)
      return true
    }
    
    return super.application(app, open: url, options: options)
  }
  
  // Helper method to handle incoming URLs
  func handleIncomingURL(_ url: URL) {
    // The uni_links plugin should automatically pick up this URL
    print("AppDelegate handled URL: \(url.absoluteString)")
    
    // You can also post a notification if needed
    NotificationCenter.default.post(
      name: NSNotification.Name("IncomingURL"),
      object: nil,
      userInfo: ["url": url.absoluteString]
    )
  }
}

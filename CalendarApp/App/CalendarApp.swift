import SwiftUI
import GoogleSignIn
import UIKit

@main
struct CalendarApp: App {
    @UIApplicationDelegateAdaptor(CalendarAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            CalendarRootView()
                .onOpenURL { url in
                    CalendarAppDelegate.handleGoogleSignInURL(url)
                }
        }
    }
}

final class CalendarAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        CalendarAppDelegate.handleGoogleSignInURL(url)
    }

    static func handleGoogleSignInURL(_ url: URL) -> Bool {
        let handled = GIDSignIn.sharedInstance.handle(url)
        NotificationCenter.default.post(name: .googleSignInCallbackHandled, object: nil)
        return handled
    }
}

extension Notification.Name {
    static let googleSignInCallbackHandled = Notification.Name("googleSignInCallbackHandled")
}

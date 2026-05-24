import SwiftUI
import GoogleSignIn

@main
struct CalendarApp: App {
    var body: some Scene {
        WindowGroup {
            CalendarRootView()
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}

// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import FirebaseCore
import GoogleSignIn
import SwiftUI

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()
        return true
    }
}

@main
struct MCATSpeedrunApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var app = AppState()
    @StateObject private var auth = AuthManager()
    @StateObject private var sync = SyncManager()
    @StateObject private var progress = ProgressStore()

    var body: some Scene {
        WindowGroup {
            Group {
                if auth.user != nil {
                    RootView()
                } else {
                    AuthView()
                }
            }
            .environmentObject(app)
            .environmentObject(auth)
            .environmentObject(sync)
            .environmentObject(progress)
            .preferredColorScheme(app.darkMode ? .dark : .light)
            .onOpenURL { url in
                GIDSignIn.sharedInstance.handle(url)
            }
            .onChange(of: auth.user?.uid) { _, uid in
                if let uid {
                    sync.attach(app: app, progress: progress)
                    sync.start(uid: uid, name: auth.user?.displayName, email: auth.user?.email)
                } else {
                    sync.stop()
                }
            }
            .task {
                if let user = auth.user {
                    sync.attach(app: app, progress: progress)
                    sync.start(uid: user.uid, name: user.displayName, email: user.email)
                }
            }
        }
    }
}

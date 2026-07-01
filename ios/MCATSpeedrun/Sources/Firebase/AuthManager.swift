// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
//
// Firebase Authentication wrapper (email/password + Google), exposed as an
// ObservableObject so the app can gate on sign-in state.

import FirebaseAuth
import FirebaseCore
import GoogleSignIn
import SwiftUI

@MainActor
final class AuthManager: ObservableObject {
    @Published var user: User?
    @Published var errorMessage: String?
    @Published var working = false

    private var handle: AuthStateDidChangeListenerHandle?

    init() {
        user = Auth.auth().currentUser
        handle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            self?.user = user
        }
    }

    func signUp(email: String, password: String, name: String) async {
        working = true; errorMessage = nil
        do {
            _ = try await Auth.auth().createUser(withEmail: email, password: password)
            if !name.isEmpty, let user = Auth.auth().currentUser {
                let change = user.createProfileChangeRequest()
                change.displayName = name
                try? await change.commitChanges()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        working = false
    }

    func signIn(email: String, password: String) async {
        working = true; errorMessage = nil
        do {
            _ = try await Auth.auth().signIn(withEmail: email, password: password)
        } catch {
            errorMessage = error.localizedDescription
        }
        working = false
    }

    func signInWithGoogle() async {
        working = true; errorMessage = nil
        defer { working = false }
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            errorMessage = "Missing Google client ID"
            return
        }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        guard let root = Self.rootViewController() else {
            errorMessage = "No window to present sign-in"
            return
        }
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: root)
            guard let idToken = result.user.idToken?.tokenString else {
                errorMessage = "Google sign-in returned no token"
                return
            }
            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: result.user.accessToken.tokenString
            )
            _ = try await Auth.auth().signIn(with: credential)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() {
        try? Auth.auth().signOut()
        GIDSignIn.sharedInstance.signOut()
    }

    private static func rootViewController() -> UIViewController? {
        guard
            let scene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
                ?? UIApplication.shared.connectedScenes.first as? UIWindowScene,
            let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
                ?? scene.windows.first?.rootViewController
        else { return nil }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        return top
    }
}

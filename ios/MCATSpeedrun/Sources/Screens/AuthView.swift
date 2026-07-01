// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
//
// Login / sign-up gate. Shown when no Firebase user is signed in.

import SwiftUI

struct AuthView: View {
    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject var app: AppState
    @EnvironmentObject var sync: SyncManager

    @State private var isSignUp = true
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Spacer(minLength: 40)
                VStack(spacing: 6) {
                    Text("MCAT Speedrun")
                        .font(Theme.font(32, .heavy)).foregroundStyle(Theme.text)
                    Text("Memory · Performance · Readiness")
                        .font(Theme.font(15, .semibold)).foregroundStyle(Theme.muted)
                }

                VStack(spacing: 12) {
                    if isSignUp {
                        field("Name", text: $name, secure: false, email: false)
                    }
                    field("Email", text: $email, secure: false, email: true)
                    field("Password", text: $password, secure: true)

                    if let e = auth.errorMessage {
                        Text(e).font(Theme.font(13, .semibold)).foregroundStyle(Theme.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button(isSignUp ? "Create account" : "Log in") {
                        Task {
                            if isSignUp {
                                await auth.signUp(
                                    email: email, password: password, name: name)
                                if auth.errorMessage == nil {
                                    app.profileName = name.trimmingCharacters(in: .whitespaces)
                                    sync.pushLocal()
                                }
                            } else {
                                await auth.signIn(email: email, password: password)
                            }
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(
                        auth.working || email.isEmpty || password.isEmpty
                            || (isSignUp && name.isEmpty))

                    Button {
                        Task { await auth.signInWithGoogle() }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "g.circle.fill")
                            Text("Continue with Google")
                        }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(auth.working)

                    Button(isSignUp ? "I already have an account" : "Create an account") {
                        isSignUp.toggle()
                        auth.errorMessage = nil
                    }
                    .font(Theme.font(14, .semibold))
                    .foregroundStyle(Theme.accent)
                    .padding(.top, 2)
                }
                .cardStyle()

                if auth.working { ProgressView().tint(Theme.accent) }
            }
            .padding(20)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .screenBackground()
    }

    @ViewBuilder
    private func field(
        _ placeholder: String, text: Binding<String>, secure: Bool, email: Bool = true
    ) -> some View {
        Group {
            if secure {
                SecureField(placeholder, text: text)
            } else if email {
                TextField(placeholder, text: text)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } else {
                TextField(placeholder, text: text)
                    .textInputAutocapitalization(.words)
            }
        }
        .font(Theme.font(16))
        .foregroundStyle(Theme.text)
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 11).fill(Theme.surface2))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(Theme.border, lineWidth: 1))
    }
}

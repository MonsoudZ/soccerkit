import AuthenticationServices
import SwiftUI

/// The first-run gate. Signing in with Apple is what makes a coach's data follow
/// them between devices — it is not what makes the app work, so it can also be
/// skipped.
struct LoginView: View {
    @EnvironmentObject private var auth: AuthController
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: Spacing.xxl) {
            Spacer()

            VStack(spacing: Spacing.lg) {
                Image(systemName: "soccerball.inverse")
                    .font(.system(size: 68))
                    .foregroundStyle(.tint)
                Text("SoccerCoachKit")
                    .font(AppFont.display)
                Text("Your roster, game day, training, and season — all in one place.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.xl)
            }

            Spacer()

            VStack(spacing: Spacing.md) {
                SignInWithAppleButton(.signIn) { request in
                    auth.configure(request)
                } onCompletion: { result in
                    auth.handle(result)
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 50)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small, style: .continuous))

                if let authError = auth.authError {
                    Label(authError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.critical)
                        .multilineTextAlignment(.center)
                }

                Button("Continue without an account") {
                    auth.continueAsGuest()
                }
                .font(.subheadline)
                .padding(.top, Spacing.xs)

                Text("Signing in keeps your teams backed up and in sync across your devices. Without it everything still works — it just stays on this device, and it comes with you if you sign in later.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.bottom, Spacing.xxl)
        }
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
    }
}

import AuthenticationServices
import SwiftUI

/// The sign-in gate shown until the coach authenticates with Apple.
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
                Text("Your roster, game day, training, and season — signed in and ready.")
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

                Text("We only use your Apple ID to sign you in. Your team data stays on your device.")
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

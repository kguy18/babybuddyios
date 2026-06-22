import SwiftUI

/// Top-level router: shows onboarding until a server + token are validated, then the app.
struct RootView: View {
    @Environment(AppSession.self) private var session
    @Environment(AppLockManager.self) private var lock

    var body: some View {
        ZStack {
            switch session.state {
            case .unauthenticated:
                OnboardingView()
            case .authenticated:
                MainTabView()
            }
            if lock.isLocked {
                LockView().transition(.opacity)
            }
        }
    }
}

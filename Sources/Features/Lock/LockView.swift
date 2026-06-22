import SwiftUI

/// Full-screen lock shown when ``AppLockManager`` has locked the app. Auto-prompts for
/// biometrics on appear and offers a retry button if the user cancels.
struct LockView: View {
    @Environment(AppLockManager.self) private var lock

    var body: some View {
        ZStack {
            Rectangle().fill(.background).ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "lock.fill").font(.system(size: 48)).foregroundStyle(.tint)
                Text("Baby Buddy is locked").font(.headline)
                Button("Unlock") { Task { await lock.unlock() } }
                    .buttonStyle(.borderedProminent)
            }
        }
        .task { await lock.unlock() }
    }
}

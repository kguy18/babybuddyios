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
                    .accessibilityHidden(true)
                Text("Baby Buddy is locked").font(.headline)
                Button("Unlock") { Task { await lock.unlock() } }
                    .buttonStyle(.borderedProminent)
            }
        }
        // A full-screen modal barrier so VoiceOver stays within the lock screen — `.contain` first,
        // or the trait lands on a view that isn't an accessibility container and does nothing: the
        // Dashboard behind the lock stayed readable, which is the whole point of locking.
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        // …and announces why the app's content just disappeared.
        .onAppear { AccessibilityNotification.Announcement(String(localized: "Baby Buddy is locked")).post() }
        .task { await lock.unlock() }
    }
}

import SwiftUI

/// Modal that offers the local 14-day free trial of premium features.
///
/// This view holds **no business logic** — it reads trial state from ``TrialManager`` and, only when
/// the user taps "Start Free Trial", calls ``TrialManager/startTrial()``. Simply presenting this
/// modal never starts the trial (there is no `onAppear` side effect). If the trial has already been
/// started (whether active or expired), the start option is not shown again — the modal falls back
/// to an informational state — which upholds the one-shot, no-restart guarantee.
///
/// Present it with `.sheet`; the layout is designed for a bottom-sheet / card presentation.
struct TrialOfferView: View {
    @Environment(TrialManager.self) private var trial
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            Capsule()
                .fill(.tertiary)
                .frame(width: 36, height: 5)
                .padding(.top, 10)

            icon

            if trial.hasStartedTrial {
                alreadyUsedContent
            } else {
                offerContent
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity)
        .background(BBColor.surface.ignoresSafeArea())
    }

    private var icon: some View {
        Image(systemName: "gift.fill")
            .font(.system(size: 52))
            .foregroundStyle(BBColor.brand)
            .accessibilityHidden(true)
    }

    // MARK: Offer (trial not yet started)

    private var offerContent: some View {
        VStack(spacing: 24) {
            VStack(spacing: 10) {
                Text("Try Premium free for 14 days")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text("Unlock every premium feature for two weeks. No subscription required, nothing is charged, and it won't auto-renew — the trial simply ends.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                Button("Start Free Trial") {
                    trial.startTrial()
                    dismiss()
                }
                .buttonStyle(.bbPrimary)

                Button("Not Now") {
                    Analytics.trialDeclined()
                    dismiss()
                }
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
        // Only the offerable state counts as an "offer viewed" — the already-used/expired state
        // (`alreadyUsedContent`) is informational and must not inflate the trial-offer denominator.
        .onAppear { Analytics.trialOfferViewed() }
    }

    // MARK: Already started / expired

    private var alreadyUsedContent: some View {
        VStack(spacing: 24) {
            VStack(spacing: 10) {
                Text(trial.isTrialActive ? "Your free trial is active" : "Your free trial has ended")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text(alreadyUsedMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button("Done") { dismiss() }
                .buttonStyle(.bbPrimary)
        }
    }

    private var alreadyUsedMessage: String {
        if trial.isTrialActive {
            let days = trial.daysRemaining
            return "You have \(days) day\(days == 1 ? "" : "s") of premium features remaining. Enjoy!"
        } else {
            return "Your 14-day trial is over. Upgrade to Premium any time to keep your premium features."
        }
    }
}

#Preview("Offer") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            TrialOfferView()
                .environment(TrialManager())
                .presentationDetents([.medium])
        }
}

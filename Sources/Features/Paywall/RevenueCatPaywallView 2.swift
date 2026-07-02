import SwiftUI
#if canImport(RevenueCatUI)
import RevenueCatUI
#endif

/// The single UI boundary allowed to reference `RevenueCatUI` — the presentation-layer analog of
/// ``PurchaseManager`` for the core SDK.
///
/// When the optional `RevenueCatUI` package is linked, this renders RevenueCat's prebuilt,
/// remotely-configured `PaywallView`; otherwise it renders `fallback` (the app's hand-built paywall).
/// Keeping the `#if canImport(RevenueCatUI)` here means no feature view — including ``PremiumScreen``
/// — has to import or name a RevenueCat type.
struct RevenueCatPaywallView<Fallback: View>: View {
    @ViewBuilder var fallback: () -> Fallback

    var body: some View {
        #if canImport(RevenueCatUI)
        PaywallView()
        #else
        fallback()
        #endif
    }
}

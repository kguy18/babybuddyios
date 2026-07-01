import SwiftUI

/// Small badge indicating a record's sync state. Hidden when fully synced.
struct SyncStateBadge: View {
    let state: SyncState

    var body: some View {
        switch state {
        case .synced:
            EmptyView()
        case .pendingCreate, .pendingUpdate, .pendingDelete:
            // Darker-than-system orange clears the 3:1 non-text contrast bar; the distinct symbol
            // (vs. the conflict triangle) means state isn't conveyed by color alone.
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(BBColor.restart)
                .help("Waiting to sync")
                .accessibilityLabel("Waiting to sync")
        case .conflicted:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(BBColor.danger)
                .help("Sync conflict — tap to resolve")
                .accessibilityLabel("Sync conflict")
        }
    }
}

/// Reusable dashboard card container.
struct DashboardCard<Icon: View, Content: View>: View {
    let title: String
    let icon: Icon
    let content: Content

    init(title: String, @ViewBuilder icon: () -> Icon, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                icon
                Text(title)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
    }
}

extension DashboardCard where Icon == Image {
    /// Convenience for SF Symbol chrome cards (these auto-size to the font).
    init(title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.init(title: title, icon: { Image(systemName: systemImage) }, content: content)
    }
}

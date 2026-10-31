import SwiftUI

/// Where the panes go on iPhone Duo's open display: one pane each side of the fold, nothing on it.
enum FoldLayout {
    /// The narrowest pane worth splitting for. Right of the fold the open display leaves 372 pt
    /// before the rail, close to the front display's 382, so a phone layout fits in either pane.
    static let minPane: CGFloat = 360
    /// The fold's width when the system doesn't report it: 40 pt on iPhone Duo.
    static let assumedFold: CGFloat = 40

    struct Panes: Equatable {
        /// The pane left of the fold, the fold itself, and the pane right of it.
        var side: CGFloat, fold: CGFloat, main: CGFloat
    }

    /// The panes for a container `width` wide, or nil when one pane is all that fits. `fold` is
    /// the division's frame in the container's own coordinates when the system reports one; with
    /// none, the fold is assumed to sit in the middle.
    static func panes(width: CGFloat, fold: CGRect?) -> Panes? {
        let start = fold.map { max($0.minX, 0) } ?? (width - assumedFold) / 2
        let end = fold.map { min($0.maxX, width) } ?? start + assumedFold
        let panes = Panes(side: start, fold: end - start, main: width - end)
        return min(panes.side, panes.main) >= minPane ? panes : nil
    }
}

/// Two panes either side of the fold when there's room for both, and only `main` otherwise.
/// `main` keeps its place in the view tree across the change, so folding or unfolding the phone
/// resizes it rather than rebuilding it: its scroll position and the sheets above it stay put.
/// `main` is told whether the side pane is showing, for content that moves between the two.
struct FoldSplitView<Side: View, Main: View>: View {
    @ViewBuilder var side: () -> Side
    @ViewBuilder var main: (_ split: Bool) -> Main

    var body: some View {
        GeometryReader { geo in
            let panes = FoldLayout.panes(width: geo.size.width, fold: Self.fold(in: geo))
            HStack(spacing: 0) {
                if let panes {
                    side().frame(width: panes.side)
                    Color.clear.frame(width: panes.fold).accessibilityHidden(true)
                }
                main(panes != nil).frame(width: panes?.main ?? geo.size.width)
            }
        }
    }

    /// The fold, from the system's reserved regions. Inactive ones count too: the fold is only
    /// reserved in the book pose, but nothing is drawn across it laid flat either.
    private static func fold(in geo: GeometryProxy) -> CGRect? {
        // ReservedRegion is in the iOS 27.1 SDK (Xcode 27.1, Swift 6.4) and later. Xcode 26 lacks
        // it, so builds made with it fall back to a centred fold.
        #if compiler(>=6.4)
        if #available(iOS 27.1, *) {
            return geo.reservedRegions(kind: .division, options: .includeInactive)
                .first { $0.frame.height > $0.frame.width }?.frame
        }
        #endif
        return nil
    }
}

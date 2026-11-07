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
        return (forced || min(panes.side, panes.main) >= minPane) ? panes : nil
    }

    /// `BB_FOLD=1` (DEBUG) lays out every screen and sheet as the open display does, however narrow
    /// the window, so UI tests reach those layouts on any simulator: XCUITest can't unfold an
    /// iPhone Duo.
    static let forced: Bool = {
        #if DEBUG
        ProcessInfo.processInfo.environment["BB_FOLD"] == "1"
        #else
        false
        #endif
    }()

    /// The narrowest sheet that takes two columns. The open display centres a sheet 653 pt wide,
    /// across the fold, so a sheet can't split at the fold the way a screen does. A phone's sheet
    /// is at most 440 pt wide and the front display's 382 pt, and both keep one column.
    static let wideSheet: CGFloat = 600

    static func isWide(_ width: CGFloat) -> Bool { forced || width >= wideSheet }
}

extension View {
    /// Writes whether this view is at least ``FoldLayout/wideSheet`` wide to `wide`, as it changes.
    func trackingWide(_ wide: Binding<Bool>) -> some View {
        onGeometryChange(for: Bool.self) { FoldLayout.isWide($0.size.width) } action: { wide.wrappedValue = $0 }
    }
}

/// A sheet's content in two columns side by side when `wide`, and one above the other otherwise,
/// in the order given. At accessibility text sizes it is always one column: the two are 290 pt each.
/// The gap is the fold's width, because the open display centres a sheet on the fold. The columns
/// keep their views across the change, so folding the phone with the sheet open keeps what's typed.
struct SheetColumns<Leading: View, Trailing: View>: View {
    let wide: Bool
    var spacing: CGFloat = 18
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = wide && !typeSize.isAccessibilitySize
            ? AnyLayout(HStackLayout(alignment: .top, spacing: FoldLayout.assumedFold))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: spacing))
        layout {
            VStack(alignment: .leading, spacing: spacing, content: leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: spacing, content: trailing)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
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

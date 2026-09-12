import SwiftUI
import PromptCamCore

/// Rectangles the layout must keep important controls away from.
struct ReservedRegionSet: Equatable {
    /// Hinge / division regions — where the display is split.
    var division: [CGRect] = []
    /// Occlusion regions — where something covers the display.
    var occlusion: [CGRect] = []

    var isEmpty: Bool { division.isEmpty && occlusion.isEmpty }

    var all: [CGRect] { division + occlusion }

    /// Whether `rect` overlaps anything reserved.
    ///
    /// Used to decide whether a control group needs to move, not to move it
    /// pixel by pixel — standard adaptive containers do the real work.
    func intersects(_ rect: CGRect) -> Bool {
        all.contains { $0.intersects(rect) }
    }

    /// The largest contiguous horizontal band of `bounds` that avoids every
    /// reserved region.
    ///
    /// PromptCam uses this for one specific purpose: choosing which side of a
    /// division region to place the recording controls on, so the record button
    /// never straddles the hinge.
    func largestSafeBand(in bounds: CGRect) -> CGRect {
        guard !all.isEmpty else { return bounds }

        // Split `bounds` vertically at every reserved region, then keep the
        // tallest surviving slice.
        var candidates: [CGRect] = []
        let sorted = all
            .filter { $0.intersects(bounds) }
            .sorted { $0.minY < $1.minY }

        var cursor = bounds.minY
        for region in sorted {
            if region.minY > cursor {
                candidates.append(
                    CGRect(x: bounds.minX, y: cursor, width: bounds.width, height: region.minY - cursor)
                )
            }
            cursor = max(cursor, region.maxY)
        }
        if cursor < bounds.maxY {
            candidates.append(
                CGRect(x: bounds.minX, y: cursor, width: bounds.width, height: bounds.maxY - cursor)
            )
        }

        return candidates.max { $0.height < $1.height } ?? bounds
    }
}

/// Reads reserved regions from a `GeometryProxy`.
///
/// ## Status: REQUIRES_MAC, then REQUIRES_DUO_SIMULATOR
///
/// REQUIRES_MAC_VALIDATION — confirm that `GeometryProxy.reservedRegions(kind:)`
/// exists with that spelling, that the kinds are `.division` and `.occlusion`,
/// that each region exposes `.frame`, and whether an `.includeInactive` option
/// is needed. Nothing outside this file touches those symbols.
enum ReservedRegionReader {

    static func regions(from proxy: GeometryProxy) -> ReservedRegionSet {
        #if PROMPTCAM_DUO
        // REQUIRES_MAC_VALIDATION — supplied API surface, never compiled.
        var set = ReservedRegionSet()
        set.division = proxy.reservedRegions(kind: .division).map(\.frame)
        set.occlusion = proxy.reservedRegions(kind: .occlusion).map(\.frame)
        return set
        #else
        // Baseline build: an ordinary iPhone has no hinge and no occlusion, so
        // an empty set is the truthful answer rather than a guess.
        _ = proxy
        return ReservedRegionSet()
        #endif
    }
}

/// A layout container for the director interface's primary and secondary areas.
///
/// ## Status: REQUIRES_MAC
///
/// The supplied guidance introduces `ArrangementView` for adaptive primary and
/// secondary content, with `.split` and `.overlay` styles, and warns against
/// adopting it for novelty. PromptCam has a genuine need: the camera preview
/// and the question console must sit side by side when the inner display is
/// open and stack when it is not.
///
/// However, standard adaptive containers already handle this, and the guidance
/// says to prefer them unless there is a demonstrated need. So the **default**
/// implementation here is a plain size-class-driven layout that works on every
/// device today, and `ArrangementView` is behind the flag as an upgrade to
/// evaluate on a Mac — not a dependency.
///
/// REQUIRES_MAC_VALIDATION — confirm `ArrangementView`'s initialiser label
/// (`secondary:`), the `arrangementViewStyle(_:)` modifier and the `.split` /
/// `.overlay` style values, then compare the result against the size-class
/// layout below and keep whichever is actually better.
struct DirectorArrangement<Primary: View, Secondary: View>: View {
    /// True when there is room to show both areas side by side.
    let prefersSideBySide: Bool
    @ViewBuilder let primary: () -> Primary
    @ViewBuilder let secondary: () -> Secondary

    var body: some View {
        #if PROMPTCAM_DUO && PROMPTCAM_USE_ARRANGEMENT_VIEW
        // REQUIRES_MAC_VALIDATION — supplied API surface, never compiled.
        // Behind a second flag so it can be trialled without disturbing the
        // rest of the Duo path.
        ArrangementView {
            primary()
        } secondary: {
            secondary()
        }
        .arrangementViewStyle(prefersSideBySide ? .split : .overlay)
        #else
        // Portable layout that behaves correctly on every device, including an
        // open inner display reporting regular size classes.
        if prefersSideBySide {
            HStack(spacing: 0) {
                primary()
                secondary()
            }
        } else {
            VStack(spacing: 0) {
                primary()
                secondary()
            }
        }
        #endif
    }
}

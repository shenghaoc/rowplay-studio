import Foundation

/// Human-scale SkiErg proportions and grip contract ported from RowPlay
/// `skiEquipment.ts`.  Readable proportions for a chase-camera replay — not
/// literal FIS millimetres and not toy planks.  Ski and pole length derive
/// from the measured 1.64 m rig into the classic bands: skis ~116%
/// (112–117% band) and poles ~83.5% (83–84% band).
public enum ReplaySkiGripContract {
    public struct AthleteProportions: Sendable {
        /// Measured rest-pose stature of the shipped V4 athlete.
        public let standingHeight = 1.64
        public let shoulderHalfWidth = 0.25
        public let hipHalfWidth = 0.12
        /// Contact-safe limb lengths retained so the V4 silhouette and the
        /// procedural hand/pole and knee/ski closures share one reach
        /// envelope.
        public let upperArmLength = 0.49
        public let forearmLength = 0.47
        public let thighLength = 0.4
        public let shinLength = 0.39
        /// Half of ski centre-to-centre (~0.30 m stance, slightly outside
        /// the hips).
        public let skiCenterOffset = 0.15
        /// Runner length: 1.64 m × 1.16 ≈ 1.90 m.
        public let skiLength = 1.9
        /// Maximum shovel width — a readable needle (~72 mm).
        public let skiWidth = 0.072
        /// Double-pole length: 1.64 m × 0.835 ≈ 1.37 m.  The rigid
        /// hand↔basket link and the plant solver read this value.
        public let poleLength = 1.37
        /// Basket plant just outside the ski pair for a compact double-pole
        /// press.
        public let polePlantLateralOffset = 0.46
        /// How far ahead of the athlete's centre the basket plants.  With
        /// 1.37 m of pole, planting 0.24 m forward keeps the taut margin
        /// (~0.23 m) while the shaft still slants backward at impact.
        public let polePlantForwardOffset = 0.24
    }

    public static let athleteProportions = AthleteProportions()

    /// The palm rides this far down the shaft from the grip top, so the
    /// contact solver targets a point inside the 0.15 m grip capsule rather
    /// than its rim.
    public static let gripShift = 0.042

    /// Physical radius of the rendered pole-grip capsule.  The pole grip is
    /// the equipment the shipped hand's fist channel was calibrated against,
    /// so this *is* the reference grip radius — resizing the rubber without
    /// re-fitting the channel silently moves every solved grip on all three
    /// sports.
    public static let poleGripRadius = ReplayGripGeometry.handFistReferenceGripRadius

    /// Thumb opposition that closes the fist onto the pole grip, in the thumb
    /// root's bone frame — fitted against the shipped rig.
    public static let poleThumbOppose = 1.75

    /// Grip closure options for one SkiErg hand: sequential first-contact
    /// closure on the continuous pole shaft.
    public static func gripClosureOptions(side: ReplayHandSide) -> ReplayHandGripClosureOptions {
        ReplayHandGripClosureOptions(
            side: side,
            surface: ReplayHandGripSurface(radius: poleGripRadius),
            thumbOppose: poleThumbOppose
        )
    }

    /// Equipment is progressive in geometry, not only in pixel density.  Low
    /// keeps a complete, credible silhouette; Medium adds functional
    /// hardware; High and Ultra spend additional geometry on edges, closures,
    /// and grip details.
    public struct EquipmentDetail: Equatable, Sendable {
        /// Radial resolution for the visible hard-surface fallback.
        public let radialSegments: Int
        /// Detail that earns geometry only when the tier can display it.
        public let topSheet: Bool
        public let metalEdges: Bool
        public let bindingRails: Bool
        public let bootClosures: Bool
        public let gripStraps: Bool
        public let basketRibs: Bool
    }

    public static func equipmentDetail(for quality: ReplayRenderQuality) -> EquipmentDetail {
        switch quality {
        case .low:
            EquipmentDetail(
                radialSegments: 8,
                topSheet: false,
                metalEdges: false,
                bindingRails: false,
                bootClosures: false,
                gripStraps: false,
                basketRibs: false
            )
        case .medium:
            EquipmentDetail(
                radialSegments: 12,
                topSheet: true,
                metalEdges: false,
                bindingRails: true,
                bootClosures: true,
                gripStraps: true,
                basketRibs: false
            )
        case .high:
            EquipmentDetail(
                radialSegments: 16,
                topSheet: true,
                metalEdges: true,
                bindingRails: true,
                bootClosures: true,
                gripStraps: true,
                basketRibs: true
            )
        case .ultra:
            EquipmentDetail(
                radialSegments: 20,
                topSheet: true,
                metalEdges: true,
                bindingRails: true,
                bootClosures: true,
                gripStraps: true,
                basketRibs: true
            )
        }
    }
}

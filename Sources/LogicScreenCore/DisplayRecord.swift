import Foundation
import CoreGraphics

/// All rectangles use Quartz global coordinates, in points, with the origin at the top left.
public struct DisplayRecord: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let displayID: UInt32
    public let name: String
    public let frame: CGRect
    public let visibleFrame: CGRect
    public let isMain: Bool
    public let isBuiltIn: Bool
    public let isActive: Bool
    public let isMirrored: Bool

    public init(id: String, displayID: UInt32, name: String, frame: CGRect, visibleFrame: CGRect,
                isMain: Bool, isBuiltIn: Bool, isActive: Bool, isMirrored: Bool = false) {
        self.id = id
        self.displayID = displayID
        self.name = name
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.isMain = isMain
        self.isBuiltIn = isBuiltIn
        self.isActive = isActive
        self.isMirrored = isMirrored
    }
}

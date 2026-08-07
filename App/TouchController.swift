import UIKit

/// Assigns roles to touches by where they START: inside the steering zone the
/// touch drives the virtual joystick; anywhere else it fires the laser. Roles
/// are fixed at touch-down; UITouch objects are never retained (Apple's rule)
/// — only their identities.
final class TouchController {
    enum Role {
        case joystick
        case laser
    }

    private var joystickID: ObjectIdentifier?
    private var laserID: ObjectIdentifier?

    /// Returns the role assigned to a newly began touch, or nil if that role
    /// is already taken (extra fingers are ignored).
    func began(_ touch: UITouch, inSteeringZone: Bool) -> Role? {
        let id = ObjectIdentifier(touch)
        if inSteeringZone {
            guard joystickID == nil else { return nil }
            joystickID = id
            return .joystick
        }
        guard laserID == nil else { return nil }
        laserID = id
        return .laser
    }

    func role(of touch: UITouch) -> Role? {
        let id = ObjectIdentifier(touch)
        if id == joystickID { return .joystick }
        if id == laserID { return .laser }
        return nil
    }

    /// Clears and returns the touch's role. Call for both ended and cancelled.
    @discardableResult
    func ended(_ touch: UITouch) -> Role? {
        let id = ObjectIdentifier(touch)
        if id == joystickID {
            joystickID = nil
            return .joystick
        }
        if id == laserID {
            laserID = nil
            return .laser
        }
        return nil
    }
}

import UIKit

/// Assigns roles to touches by identity: the first active touch steers the
/// player, any additional touch drives the laser. Roles are fixed at touch-down;
/// UITouch objects are never retained (Apple's rule) — only their identities.
final class TouchController {
    enum Role {
        case movement
        case laser
    }

    private var movementID: ObjectIdentifier?
    private var laserID: ObjectIdentifier?

    /// Returns the role assigned to a newly began touch, or nil if both roles
    /// are taken (extra fingers are ignored).
    func began(_ touch: UITouch) -> Role? {
        let id = ObjectIdentifier(touch)
        if movementID == nil {
            movementID = id
            return .movement
        }
        if laserID == nil {
            laserID = id
            return .laser
        }
        return nil
    }

    func role(of touch: UITouch) -> Role? {
        let id = ObjectIdentifier(touch)
        if id == movementID { return .movement }
        if id == laserID { return .laser }
        return nil
    }

    /// Clears and returns the touch's role. Call for both ended and cancelled.
    @discardableResult
    func ended(_ touch: UITouch) -> Role? {
        let id = ObjectIdentifier(touch)
        if id == movementID {
            movementID = nil
            return .movement
        }
        if id == laserID {
            laserID = nil
            return .laser
        }
        return nil
    }
}

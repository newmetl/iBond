import UIKit

/// Assigns roles to touches by which control zone they START in: the steering
/// zone drives the virtual joystick, the fire zone drives the laser button.
/// Touches elsewhere are ignored. Roles are fixed at touch-down; UITouch
/// objects are never retained (Apple's rule) — only their identities.
final class TouchController {
    enum Role {
        case joystick
        case fire
    }

    private var joystickID: ObjectIdentifier?
    private var fireID: ObjectIdentifier?

    /// Claims the role for a newly began touch. Returns false when that role
    /// is already held by another finger (the extra touch is ignored).
    func began(_ touch: UITouch, as role: Role) -> Bool {
        let id = ObjectIdentifier(touch)
        switch role {
        case .joystick:
            guard joystickID == nil else { return false }
            joystickID = id
        case .fire:
            guard fireID == nil else { return false }
            fireID = id
        }
        return true
    }

    func role(of touch: UITouch) -> Role? {
        let id = ObjectIdentifier(touch)
        if id == joystickID { return .joystick }
        if id == fireID { return .fire }
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
        if id == fireID {
            fireID = nil
            return .fire
        }
        return nil
    }
}

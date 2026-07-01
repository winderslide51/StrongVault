import Foundation

/// Décide s'il faut reverrouiller une base ouverte. Logique pure (testable sans device) :
/// la couche App branche les évènements réels (passage en arrière-plan, minuterie) et
/// exécute la purge des secrets déchiffrés lorsque `shouldLock` renvoie `true`.
public struct AutoLockPolicy: Sendable, Equatable {
    /// Délai d'inactivité avant verrouillage. `nil` = jamais sur timeout.
    public var timeout: TimeInterval?
    /// Verrouiller dès le passage en arrière-plan.
    public var lockOnBackground: Bool

    public init(timeout: TimeInterval? = 60, lockOnBackground: Bool = true) {
        self.timeout = timeout
        self.lockOnBackground = lockOnBackground
    }

    /// - Parameters:
    ///   - lastActivity: date de la dernière interaction.
    ///   - now: instant courant.
    ///   - didEnterBackground: la base a-t-elle été mise en arrière-plan depuis l'ouverture.
    public func shouldLock(lastActivity: Date, now: Date, didEnterBackground: Bool) -> Bool {
        if lockOnBackground && didEnterBackground {
            return true
        }
        if let timeout, now.timeIntervalSince(lastActivity) >= timeout {
            return true
        }
        return false
    }
}

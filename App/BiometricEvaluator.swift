import LocalAuthentication

/// Abstraction injectable au-dessus de `LAContext` : permet à l'UI de savoir si la biométrie
/// est disponible et de l'étiqueter, sans coupler les vues à `LocalAuthentication` (et donc de
/// rester compilables/testables sans vrai prompt).
protocol BiometricEvaluator: Sendable {
    var isAvailable: Bool { get }
    /// Libellé humain du facteur biométrique (« Face ID », « Touch ID »).
    var label: String { get }
}

struct SystemBiometricEvaluator: BiometricEvaluator {
    var isAvailable: Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    var label: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Biométrie"
        }
    }
}

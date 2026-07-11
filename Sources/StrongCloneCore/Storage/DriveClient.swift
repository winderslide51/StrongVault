import Foundation

/// Abstraction **injectable** de l'accès à Google Drive, côté Core. Garde le Core sans
/// dépendance au SDK Drive (ni réseau) : `GoogleDriveProvider` et ses tests s'écrivent contre
/// ce protocole, l'implémentation réelle (SDK `swift-google-drive-client` + OAuth) vit dans
/// la couche App (`GoogleDriveClientLive`). C'est ce qui rend la feature **testable en CI**
/// avec un `FakeDriveClient`, la connexion réelle restant device/manuel.
public protocol DriveClient: Sendable {
    /// Métadonnées d'un fichier Drive : `identifier` = `fileId`, `displayName` = nom,
    /// `modifiedAt` = date de modification. Drive n'expose pas la taille sur ce chemin
    /// (`sizeBytes` reste `nil`).
    func metadata(fileId: String) async throws -> StorageMetadata

    /// Télécharge les octets bruts du fichier Drive.
    func download(fileId: String) async throws -> Data
}

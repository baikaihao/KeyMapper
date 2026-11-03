import Foundation
import Testing
@testable import KeyMapperCore

@Suite @MainActor
struct BackupManagerTests {
    private func withDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }

    private func request(directory: URL, limit: Int = 5) -> BackupManager.BackupRequest {
        BackupManager.BackupRequest(
            configuration: MappingStore.makeConfiguration(
                mappings: [MyMap(fCode: 0, fFlags: 0, tCode: 1, tFlags: 0,
                                 appFilterMode: .whitelist, appWhitelist: ["test.allowed"])],
                blacklist: ["test.blocked"],
                pauseHotkey: MappingStore.defaultPauseHotkey
            ),
            directory: directory,
            maximumBackupCount: limit
        )
    }

    @Test
    func backupWritesACompleteImportableConfiguration() throws {
        try withDirectory { directory in
            let nested = directory.appendingPathComponent("backups")
            let result = try BackupManager.writeBackup(request(directory: nested))
            let restored = try MappingStore.decodeAndValidateConfiguration(at: result.url)
            #expect(result.url.deletingLastPathComponent().path == nested.path)
            #expect(restored.mappings.count == 1)
            #expect(restored.mappings[0].appFilterMode == .whitelist)
            #expect(restored.mappings[0].appWhitelist == ["test.allowed"])
            #expect(restored.blacklist == ["test.blocked"])
        }
    }

    @Test
    func consecutiveBackupsKeepDistinctFilesAndRespectRetention() throws {
        try withDirectory { directory in
            let unrelated = directory.appendingPathComponent("notes.json")
            let noteData = Data("keep".utf8)
            try noteData.write(to: unrelated)
            let backupRequest = request(directory: directory, limit: 3)
            var destinations = Set<URL>()
            for _ in 0..<10 {
                let result = try BackupManager.writeBackup(backupRequest)
                #expect(destinations.insert(result.url).inserted)
                _ = try MappingStore.decodeAndValidateConfiguration(at: result.url)
            }
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            let backups = files.filter { $0.lastPathComponent.hasPrefix("keymapper_backup_") }
            #expect(backups.count == 3)
            for backup in backups { _ = try MappingStore.decodeAndValidateConfiguration(at: backup) }
            #expect(try Data(contentsOf: unrelated) == noteData)
        }
    }

    @Test
    func unwritableDestinationThrowsWithoutDamagingExistingFile() throws {
        try withDirectory { directory in
            let file = directory.appendingPathComponent("file")
            let original = Data("existing content".utf8)
            try original.write(to: file)
            #expect(throws: (any Error).self) {
                try BackupManager.writeBackup(request(directory: file.appendingPathComponent("backups")))
            }
            #expect(try Data(contentsOf: file) == original)
        }
    }
}

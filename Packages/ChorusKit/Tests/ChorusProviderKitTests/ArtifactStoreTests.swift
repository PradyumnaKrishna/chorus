import CryptoKit
import Foundation
import XCTest
@testable import ChorusProviderKit

final class ArtifactStoreTests: XCTestCase {
    func testInstallRejectsInvalidRepairBeforeReplacingExistingArtifacts() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("chorus-artifact-store-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        let original = Data("original-model".utf8)
        let replacement = Data("repaired-model".utf8)
        let originalArtifact = artifact(identifier: "model", path: "Models/model.onnx", data: original)
        let replacementArtifact = artifact(identifier: "model", path: "Models/model.onnx", data: replacement)

        let originalStore = ArtifactStore(rootDirectory: root, artifacts: [originalArtifact])
        let firstDownload = root.appendingPathComponent("first.download")
        try original.write(to: firstDownload)
        try originalStore.install([StagedArtifact(descriptor: originalArtifact, fileURL: firstDownload)])
        XCTAssertTrue(originalStore.isInstalled())

        let replacementStore = ArtifactStore(rootDirectory: root, artifacts: [replacementArtifact])
        let invalidRepair = root.appendingPathComponent("invalid.download")
        try Data("incorrect-data".utf8).write(to: invalidRepair)
        XCTAssertThrowsError(
            try replacementStore.install([
                StagedArtifact(descriptor: replacementArtifact, fileURL: invalidRepair)
            ])
        )
        XCTAssertEqual(try Data(contentsOf: originalStore.destination(for: originalArtifact)), original)

        let validRepair = root.appendingPathComponent("repair.download")
        try replacement.write(to: validRepair)
        try replacementStore.install([
            StagedArtifact(descriptor: replacementArtifact, fileURL: validRepair)
        ])
        XCTAssertEqual(
            try Data(contentsOf: replacementStore.destination(for: replacementArtifact)),
            replacement
        )

        try replacementStore.uninstall()
        XCTAssertFalse(replacementStore.isInstalled())
    }

    func testMultipleArtifactsMustBeCompleteBeforeInstallation() throws {
        let first = Data("first".utf8)
        let second = Data("second".utf8)
        let artifacts = [
            artifact(identifier: "first", path: "Payload/first.bin", data: first),
            artifact(identifier: "second", path: "Payload/second.bin", data: second)
        ]
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("chorus-artifact-set-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let download = root.appendingPathComponent("first.download")
        try first.write(to: download)

        XCTAssertThrowsError(
            try ArtifactStore(rootDirectory: root, artifacts: artifacts).install([
                StagedArtifact(descriptor: artifacts[0], fileURL: download)
            ])
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Payload/first.bin").path))
    }

    func testDescriptorRejectsDestinationsOutsideItsArtifactRoot() throws {
        let data = Data("model".utf8)
        for path in ["", ".", "../model.onnx", "/tmp/model.onnx"] {
            let descriptor = ProviderDescriptor(
                identifier: "test",
                displayName: "Test",
                summary: "Test provider",
                iconName: "Test",
                backgroundColor: "#ffffff",
                accentColor: "#000000",
                artifacts: [artifact(identifier: "model", path: path, data: data)]
            )
            let manifest = FileManager.default.temporaryDirectory
                .appendingPathComponent("chorus-provider-\(UUID().uuidString).json")
            defer { try? FileManager.default.removeItem(at: manifest) }
            try JSONEncoder().encode(descriptor).write(to: manifest)

            XCTAssertThrowsError(try ProviderDescriptor.load(from: manifest), "Accepted path: \(path)")
        }
    }

    func testPresenceSeparatesAnOutdatedInstallationFromAMissingOne() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("chorus-artifact-presence-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        let installed = Data("installed-model".utf8)
        let declared = artifact(identifier: "model", path: "Models/model.onnx", data: installed)
        let store = ArtifactStore(rootDirectory: root, artifacts: [declared])
        XCTAssertEqual(store.presence(), .absent)

        let download = root.appendingPathComponent("model.download")
        try installed.write(to: download)
        try store.install([StagedArtifact(descriptor: declared, fileURL: download)])
        XCTAssertEqual(store.presence(), .installed)

        // A release that declares a different model finds the old one in its place.
        let successor = artifact(identifier: "model", path: "Models/model.onnx",
                                 data: Data("a-larger-successor-model".utf8))
        let upgraded = ArtifactStore(rootDirectory: root, artifacts: [successor])
        XCTAssertEqual(upgraded.presence(), .outdated)
        XCTAssertFalse(upgraded.isInstalled())

        try upgraded.uninstall()
        XCTAssertEqual(upgraded.presence(), .absent)
    }

    private func artifact(identifier: String, path: String, data: Data) -> ArtifactDescriptor {
        ArtifactDescriptor(
            identifier: identifier,
            source: URL(string: "https://example.com/\(identifier)")!,
            relativePath: path,
            expectedByteCount: Int64(data.count),
            sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        )
    }
}

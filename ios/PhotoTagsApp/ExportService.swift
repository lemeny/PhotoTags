import Foundation
import Photos
import UniformTypeIdentifiers

struct ExportItemMetadata: Codable {
    let source_id: String
    let filename: String
    let tags: [String]
    let annotated_at: String
}

final class ExportService {
    private let iso = ISO8601DateFormatter()

    init() {
        iso.formatOptions = [.withInternetDateTime]
    }

    func export(
        assets: [PHAsset],
        tagsByID: [String: [String]],
        annotatedAtByID: [String: Date?]
    ) async throws -> URL {
        let batchName = "Export_Batch_\(dateStamp())"
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(batchName, isDirectory: true)
        try? FileManager.default.removeItem(at: base)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        for asset in assets {
            let resource = bestResource(for: asset)
            let originalName = resource.originalFilename
            let ext = (originalName as NSString).pathExtension.lowercased()
            let baseName = ((originalName as NSString).deletingPathExtension).isEmpty
                ? asset.localIdentifier.replacingOccurrences(of: "/", with: "_")
                : (originalName as NSString).deletingPathExtension
            let fileName = "\(baseName).\(ext.isEmpty ? "heic" : ext)"
            let imageURL = base.appendingPathComponent(fileName)
            try await writeResource(resource, to: imageURL)

            let metadata = ExportItemMetadata(
                source_id: asset.localIdentifier,
                filename: fileName,
                tags: tagsByID[asset.localIdentifier] ?? [],
                annotated_at: iso.string(from: annotatedAtByID[asset.localIdentifier] ?? Date())
            )
            let json = try JSONEncoder.pretty.encode(metadata)
            let jsonURL = base.appendingPathComponent("\(baseName).json")
            try json.write(to: jsonURL, options: .atomic)
        }

        return base
    }

    private func bestResource(for asset: PHAsset) -> PHAssetResource {
        let resources = PHAssetResource.assetResources(for: asset)
        return resources.first(where: { $0.uniformTypeIdentifier == UTType.heic.identifier }) ?? resources.first!
    }

    private func writeResource(_ resource: PHAssetResource, to destination: URL) async throws {
        try await withCheckedThrowingContinuation { continuation in
            PHAssetResourceManager.default().writeData(for: resource, toFile: destination, options: nil) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func dateStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: Date())
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

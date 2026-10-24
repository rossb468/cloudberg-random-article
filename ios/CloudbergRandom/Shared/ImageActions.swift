import Photos
import SwiftUI
import UniformTypeIdentifiers

/// Saving, copying and sharing an article image, keeping the original bytes so
/// animated images stay animated.
enum ImageActions {
    static func save(id: String) async -> Bool {
        guard let loaded = try? await ImageLoader.shared.load(id: id) else { return false }
        if let data = loaded.animationData {
            return await PhotoLibrarySaver.save(data: data)
        }
        return await PhotoLibrarySaver.save(loaded.image)
    }

    static func copy(id: String) async {
        guard let loaded = try? await ImageLoader.shared.load(id: id) else { return }
        if let data = loaded.animationData {
            UIPasteboard.general.setData(data, forPasteboardType: UTType.gif.identifier)
        } else {
            UIPasteboard.general.image = loaded.image
        }
    }
}

/// An animated image shared as-is, so it still moves wherever it lands.
struct ShareableAnimatedImage: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .gif) { $0.data }
    }
}

extension PhotoLibrarySaver {
    /// Saves the original file rather than a flattened image, which is what
    /// keeps a GIF animated in Photos.
    static func save(data: Data) async -> Bool {
        guard await PHPhotoLibrary.requestAuthorization(for: .addOnly) != .denied else { return false }
        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
            } completionHandler: { success, _ in
                continuation.resume(returning: success)
            }
        }
    }
}

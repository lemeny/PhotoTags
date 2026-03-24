import Foundation
import Photos
import UIKit

final class PhotoProvider {
    let imageManager = PHCachingImageManager()

    func requestPhotoPermission() async -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized, .limited:
            return true
        case .notDetermined:
            let granted = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            return granted == .authorized || granted == .limited
        default:
            return false
        }
    }

    func loadAssets() -> [PHAsset] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(with: .image, options: options)

        var assets: [PHAsset] = []
        assets.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }
        return assets
    }

    func startCaching(assets: [PHAsset], targetSize: CGSize = CGSize(width: 360, height: 360)) {
        imageManager.stopCachingImagesForAllAssets()
        imageManager.startCachingImages(
            for: assets,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: nil
        )
    }
}

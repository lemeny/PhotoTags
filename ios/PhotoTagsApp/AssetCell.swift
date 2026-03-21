import SwiftUI
import Photos

struct AssetCell: View {
    let asset: PHAsset
    let tags: [String]
    let selected: Bool
    let imageManager: PHCachingImageManager
    let onTap: () -> Void

    @State private var image: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Rectangle().fill(Color.gray.opacity(0.2))
                    }
                }
                .frame(width: 110, height: 110)
                .clipShape(RoundedRectangle(cornerRadius: 10))

                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.white, .blue)
                        .padding(6)
                }
            }

            Text(tags.joined(separator: ", "))
                .font(.caption2)
                .lineLimit(2)
                .frame(maxWidth: 110, alignment: .leading)
        }
        .onTapGesture(perform: onTap)
        .task {
            loadThumbnail()
        }
    }

    private func loadThumbnail() {
        let size = CGSize(width: 220, height: 220)
        imageManager.requestImage(
            for: asset,
            targetSize: size,
            contentMode: .aspectFill,
            options: nil
        ) { image, _ in
            self.image = image
        }
    }
}

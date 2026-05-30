import AppKit
import Foundation
import SwiftUI

enum AvatarImageData {
    static func dataURL(from imageURL: URL, maxPixelSize: CGFloat = 160, compression: CGFloat = 0.78) -> String? {
        guard let image = NSImage(contentsOf: imageURL),
              let resized = resizedImage(image, maxPixelSize: maxPixelSize),
              let tiffData = resized.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: compression]) else {
            return nil
        }

        return "data:image/jpeg;base64,\(jpegData.base64EncodedString())"
    }

    static func nsImage(from dataURL: String?) -> NSImage? {
        guard let dataURL,
              let commaIndex = dataURL.firstIndex(of: ",") else {
            return nil
        }

        let encoded = String(dataURL[dataURL.index(after: commaIndex)...])
        guard let data = Data(base64Encoded: encoded) else {
            return nil
        }
        return NSImage(data: data)
    }

    private static func resizedImage(_ image: NSImage, maxPixelSize: CGFloat) -> NSImage? {
        let originalSize = image.size
        guard originalSize.width > 0, originalSize.height > 0 else {
            return nil
        }

        let scale = min(maxPixelSize / originalSize.width, maxPixelSize / originalSize.height, 1)
        let targetSize = NSSize(width: originalSize.width * scale, height: originalSize.height * scale)
        let resized = NSImage(size: targetSize)

        resized.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: targetSize), from: .zero, operation: .copy, fraction: 1)
        resized.unlockFocus()
        return resized
    }
}

struct AvatarView: View {
    let handle: String
    let avatarDataURL: String?
    var size: CGFloat = 42

    var body: some View {
        ZStack {
            if let image = AvatarImageData.nsImage(from: avatarDataURL) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: [Color.accentColor.opacity(0.85), Color.orange.opacity(0.75)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Text(initials)
                    .font(.system(size: max(12, size * 0.34), weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.white.opacity(0.55), lineWidth: 1))
        .shadow(color: .black.opacity(0.10), radius: 5, x: 0, y: 3)
    }

    private var initials: String {
        let cleaned = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(cleaned.prefix(2)).uppercased()
    }
}

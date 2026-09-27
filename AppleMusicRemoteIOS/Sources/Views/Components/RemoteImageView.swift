import SwiftUI

public struct RemoteImageView: View {
    let urlString: String?
    let cornerRadius: CGFloat
    let placeholderIcon: String

    public init(urlString: String?, cornerRadius: CGFloat = 12, placeholderIcon: String = "music.note") {
        self.urlString = urlString
        self.cornerRadius = cornerRadius
        self.placeholderIcon = placeholderIcon
    }

    public var body: some View {
        Group {
            if let urlStr = urlString, !urlStr.isEmpty {
                if urlStr.hasPrefix("data:image/"),
                   let commaIndex = urlStr.firstIndex(of: ","),
                   let data = Data(base64Encoded: String(urlStr[urlStr.index(after: commaIndex)...])),
                   let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    let fullUrlString: String = {
                        if urlStr.hasPrefix("/") {
                            let host = PlayerStore.shared.currentServer?.ipAddress ?? "127.0.0.1"
                            let cleanHost = host.contains(" ") ? "127.0.0.1" : host
                            let port = PlayerStore.shared.currentServer?.port ?? 8080
                            return "http://\(cleanHost):\(port)\(urlStr)"
                        }
                        return urlStr
                    }()

                    if let url = URL(string: fullUrlString) {
                        AsyncImage(url: url) { phase in
                            if let img = phase.image {
                                img.resizable()
                                   .aspectRatio(contentMode: .fill)
                            } else {
                                placeholder
                            }
                        }
                    } else {
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [Color.amrSurfaceGlass, Color.white.opacity(0.04)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: placeholderIcon)
                .font(.system(size: 24, weight: .light))
                .foregroundColor(.white.opacity(0.35))
        }
    }
}

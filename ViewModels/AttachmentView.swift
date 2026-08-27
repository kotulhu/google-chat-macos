import SwiftUI

/// A compact attachment card: an inline image preview with lazy loading,
/// or a file row with icon, name, size and a download button.
struct AttachmentView: View {
    let attachment: Attachment
    @State private var imageData: Data?
    @State private var downloadProgress: Double?
    
    var body: some View {
        Group {
            if attachment.isImage {
                if let imageData, let nsImage = NSImage(data: imageData) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 200)
                        .cornerRadius(8)
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 150)
                        .overlay {
                            ProgressView()
                                .controlSize(.small)
                        }
                        .task {
                            await loadImage()
                        }
                }
            } else {
                HStack {
                    Image(systemName: "doc")
                        .font(.title2)
                    VStack(alignment: .leading) {
                        Text(attachment.name)
                            .font(.caption)
                        Text(formatBytes(attachment.size))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(L.str("download")) {
                        if let url = attachment.url {
                            downloadFile(url)
                        }
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
                .padding(8)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            }
        }
    }

    /// Loads the preview image from its thumbnail (or full) URL.
    private func loadImage() async {
        guard let loadURL = attachment.thumbnailURL ?? attachment.url else {
            print("No URL to load")
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: loadURL)
            imageData = data
        } catch {
            print("Failed to load image: \(error)")
        }
    }

    /// Presents a save panel and writes the downloaded file to disk.
    private func downloadFile(_ url: URL) {
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = attachment.name
        savePanel.begin { response in
            if response == .OK, let saveURL = savePanel.url {
                Task {
                    do {
                        let (data, _) = try await URLSession.shared.data(from: url)
                        try data.write(to: saveURL)
                    } catch {
                        print("Failed to save: \(error)")
                    }
                }
            }
        }
    }

    /// Formats a byte count using the system file-size formatter.
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

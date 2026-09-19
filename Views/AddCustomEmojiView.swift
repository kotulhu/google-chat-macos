import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Sheet for uploading a new custom emoji to the organization: pick or drop an
/// image (png/jpg/gif pass through, other formats and animations are converted),
/// choose a `:name:` and upload via `customEmojis.create`.
struct AddCustomEmojiView: View {
    @ObservedObject var chatVM: ChatViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedURL: URL?
    @State private var previewImage: NSImage?
    @State private var isAnimated = false
    @State private var emojiName = ""
    @State private var isUploading = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var isDropTargeted = false
    
    private let allowedTypes: [UTType] = [
        .png, .jpeg, .gif, .webP, .heic, .heif, .bmp, .tiff, .ico
    ]
    
    var body: some View {
        VStack(spacing: 14) {
            Text(L.str("add.custom.icon.title"))
                .font(.headline)
                .padding(.top, 16)
            
            dropZone
            
            HStack(spacing: 6) {
                Text(L.str("add.custom.icon.name"))
                    .font(.callout)
                    .foregroundColor(.secondary)
                TextField("", text: $emojiName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.callout, design: .monospaced))
            }
            .padding(.horizontal, 20)
            
            if let statusMessage {
                Label(statusMessage, systemImage: "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundColor(.green)
                    .padding(.horizontal, 20)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
            }
            
            HStack(spacing: 12) {
                Button(L.str("close")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                if isUploading {
                    ProgressView()
                        .controlSize(.small)
                }
                
                Button {
                    upload()
                } label: {
                    Text(isUploading ? L.str("add.custom.icon.uploading") : L.str("add.custom.icon.upload"))
                        .frame(minWidth: 120)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isUploading || selectedURL == nil)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(width: 420)
    }
    
    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6]))
                .foregroundColor(isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.5))
            
            VStack(spacing: 8) {
                if let previewImage {
                    Image(nsImage: previewImage)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 96, height: 96)
                } else {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary)
                }
                
                Text(L.str("add.custom.icon.drop"))
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                if let selectedURL {
                    Text(selectedURL.lastPathComponent)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                if previewImage != nil, isAnimated {
                    Text(L.str("add.custom.icon.animated"))
                        .font(.caption2)
                        .foregroundColor(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15))
                        .cornerRadius(4)
                }
                
                Button(L.str("add.custom.icon.choose")) {
                    chooseFile()
                }
                .font(.callout)
            }
            .padding(24)
        }
        .frame(height: 196)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .contentShape(Rectangle())
        .onTapGesture {
            chooseFile()
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            guard let provider = providers.first else { return false }
            let _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url, url.isFileURL {
                    DispatchQueue.main.async {
                        load(url: url)
                    }
                }
            }
            return true
        }
    }
    
    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = allowedTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            load(url: url)
        }
    }
    
    private func load(url: URL) {
        guard let image = NSImage(contentsOf: url) else {
            errorMessage = L.str("add.custom.icon.error.invalid")
            return
        }
        previewImage = image
        selectedURL = url
        isAnimated = CustomEmojiConverter.info(at: url).isAnimated
        emojiName = CustomEmojiConverter.suggestedName(from: url)
        statusMessage = nil
        errorMessage = nil
    }
    
    private func upload() {
        guard let url = selectedURL else {
            errorMessage = L.str("add.custom.icon.error.pick")
            return
        }
        let name = emojiName.isEmpty
            ? CustomEmojiConverter.suggestedName(from: url)
            : CustomEmojiConverter.sanitize(emojiName)
        isUploading = true
        statusMessage = nil
        errorMessage = nil
        
        Task {
            do {
                let granted = await chatVM.ensureCustomEmojiScope()
                guard granted else {
                    throw NSError(
                        domain: "CustomEmoji",
                        code: 0,
                        userInfo: [NSLocalizedDescriptionKey: L.str("add.custom.icon.scope.failed")]
                    )
                }
                let converted = try CustomEmojiConverter.convert(url: url)
                let created = try await chatVM.createCustomEmoji(
                    emojiName: name,
                    data: converted.data,
                    filename: converted.filename
                )
                let createdName = created?.emojiName ?? name
                statusMessage = L.str("add.custom.icon.success") + " — \(createdName)"
            } catch {
                let nsError = error as NSError
                let serverBody = nsError.localizedDescription.isEmpty ? "\(error)" : nsError.localizedDescription
                let lowered = serverBody.lowercased()
                if lowered.contains("duplicate") || lowered.contains("already exists") {
                    errorMessage = L.str("add.custom.icon.error.duplicate") + "\n" + serverBody
                } else {
                    errorMessage = serverBody
                }
            }
            isUploading = false
        }
    }
}
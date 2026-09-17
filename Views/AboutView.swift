import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    
    private let appName: String = {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Google Chat"
    }()
    private let appVersion: String = {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }()
    private let buildVersion: String = {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }()
    
    /// The "About" sheet: a background image, app icon, version/build numbers,
    /// developer contact, the Gogol tribute and a disclaimer that this is an
    /// unofficial client. A scrim keeps the text readable on any artwork.
    var body: some View {
        ZStack {
            Image("AboutBackground")
                .resizable()
                .scaledToFill()
                .frame(width: 320, height: 360)
                .clipped()
            
            LinearGradient(
                colors: [
                    Color(NSColor.windowBackgroundColor).opacity(0.55),
                    Color.black.opacity(0.45)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            
            VStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 72, height: 72)
                    .padding(4)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                
                Text(appName)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                Text(L.str("version.format", appVersion, buildVersion))
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.85))
                
                Spacer()
                
                VStack(spacing: 6) {
                    LabeledContent(L.str("developer")) {
                        Text("Vitalii D.")
                    }
                    LabeledContent(L.str("contact")) {
                        Text("speranza.ua@gmail.com")
                    }
                }
                .font(.body)
                .foregroundColor(.white)
                .frame(maxWidth: 220)
                .padding(10)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                
                Text(L.str("about.gogol.note"))
                    .font(.caption)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                
                Text(L.str("unofficial.client.note"))
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                
                Spacer()
                
                Button(L.str("close")) {
                    dismiss()
                }
                .keyboardShortcut(.escape)
            }
            .padding(24)
            .frame(width: 320, height: 360)
        }
        .frame(width: 320, height: 360)
    }
}
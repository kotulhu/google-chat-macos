import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    
    private let appVersion: String = {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }()
    private let buildVersion: String = {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }()
    
    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 80, height: 80)
            
            Text("Google Chat Client")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Версия \(appVersion) (сборка \(buildVersion))")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Divider()
                .padding(.horizontal, 40)
            
            VStack(spacing: 6) {
                LabeledContent("Разработчик") {
                    Text("Vitalii D.")
                }
                LabeledContent("Контакт") {
                    Text("speranza.ua@gmail.com")
                }
            }
            .font(.body)
            .frame(maxWidth: 220)
            
            Text("Неофициальный клиент Google Chat для macOS")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            
            Spacer()
            
            Button("Закрыть") {
                dismiss()
            }
            .keyboardShortcut(.escape)
        }
        .padding(24)
        .frame(width: 320, height: 360)
    }
}

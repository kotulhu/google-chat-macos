import SwiftUI

struct SettingsView: View {
    @ObservedObject private var config = ConfigManager.shared
    
    var body: some View {
        Form {
            TextField("OAuth Client ID", text: $config.clientID)
                .textFieldStyle(.roundedBorder)

            TextField("Reversed Client ID", text: $config.reversedClientID)
                .textFieldStyle(.roundedBorder)
            
            TextField("Отображаемое имя", text: $config.localDisplayName)
                .textFieldStyle(.roundedBorder)
            
            Text("OAuth Client ID используется при входе. Reversed Client ID должен совпадать с GOOGLE_REVERSED_CLIENT_ID в локальном GoogleChat.local.xcconfig, потому что macOS регистрирует callback из Info.plist при сборке приложения.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(width: 480)
    }
}

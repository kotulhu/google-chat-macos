import SwiftUI

struct SettingsView: View {
    @ObservedObject private var config = ConfigManager.shared
    
    /// The Settings window: editable OAuth client IDs and a local display name,
    /// persisted through `ConfigManager`.
    var body: some View {
        Form {
            TextField("OAuth Client ID", text: $config.clientID)
                .textFieldStyle(.roundedBorder)

            TextField("Reversed Client ID", text: $config.reversedClientID)
                .textFieldStyle(.roundedBorder)
            
            TextField(L.str("display.name"), text: $config.localDisplayName)
                .textFieldStyle(.roundedBorder)
            
            Text(L.str("settings.oauth.note"))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(width: 480)
    }
}

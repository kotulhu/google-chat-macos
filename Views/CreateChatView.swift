import SwiftUI

struct CreateChatView: View {
    @ObservedObject var chatVM: ChatViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var name = ""
    @State private var selectedType: ChatSpace.SpaceType = .channel
    @State private var isCreating = false
    
    /// Sheet for creating a new channel or group chat.
    ///
    /// Collects a name and a space type, then delegates the creation to the
    /// shared `ChatViewModel`.
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L.str("new.chat.title"))
                .font(.headline)
            
            TextField(L.str("name"), text: $name)
                .textFieldStyle(.roundedBorder)
            
            Picker("", selection: $selectedType) {
                Text(L.str("channel")).tag(ChatSpace.SpaceType.channel)
            }
            .pickerStyle(.segmented)
            
            HStack {
                Spacer()
                Button(L.str("cancel")) {
                    dismiss()
                }
                Button(isCreating ? L.str("creating") : L.str("create")) {
                    Task {
                        isCreating = true
                        let created = await chatVM.createSpace(name: name, type: selectedType)
                        isCreating = false
                        if created {
                            dismiss()
                        }
                    }
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreating)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 360)
    }
}

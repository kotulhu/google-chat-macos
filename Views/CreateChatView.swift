import SwiftUI

struct CreateChatView: View {
    @ObservedObject var chatVM: ChatViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var name = ""
    @State private var selectedType: ChatSpace.SpaceType = .channel
    @State private var isCreating = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Новый чат")
                .font(.headline)
            
            TextField("Название", text: $name)
                .textFieldStyle(.roundedBorder)
            
            Picker("Тип", selection: $selectedType) {
                Text("Канал").tag(ChatSpace.SpaceType.channel)
                Text("Групповой чат").tag(ChatSpace.SpaceType.group)
            }
            .pickerStyle(.segmented)
            
            HStack {
                Spacer()
                Button("Отмена") {
                    dismiss()
                }
                Button(isCreating ? "Создание..." : "Создать") {
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

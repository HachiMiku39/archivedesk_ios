import SwiftUI

struct ArchivePasswordView: View {
    @ObservedObject var model: WorkspaceModel
    @State private var password = ""
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Password", text: $password)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("archivePassword")
                    Text("The password is used only for this operation. It is not saved in settings, history, or logs.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let error = model.passwordError { Text(verbatim: error).foregroundStyle(.red).accessibilityIdentifier("passwordError") }
                }
                Button("Continue") {
                    let current = password
                    password = ""
                    model.submitPassword(current)
                }.disabled(model.isBusy).accessibilityIdentifier("submitArchivePassword")
            }
            .navigationTitle("Password required")
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", role: .cancel) { password = ""; model.cancelPassword() }
            } }
        }
        .onDisappear { password = "" }
        .presentationDetents([.medium, .large])
    }
}

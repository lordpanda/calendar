import SwiftUI

struct InviteesEditView: View {
    @Binding var invitees: [String]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language
    @State private var email = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("email@example.com", text: $email)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                        Button(L.tr("Add", language: language)) {
                            addInvitee()
                        }
                        .disabled(normalizedEmail.isEmpty)
                    }
                }

                Section(L.tr("Invitees", language: language)) {
                    if invitees.isEmpty {
                        Text(L.tr("No invitees", language: language))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(invitees, id: \.self) { invitee in
                            Text(invitee)
                        }
                        .onDelete { indices in
                            invitees.remove(atOffsets: indices)
                        }
                    }
                }
            }
            .navigationTitle(L.tr("Invitees", language: language))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.tr("Done", language: language)) {
                        dismiss()
                    }
                }
            }
        }
    }

    private var normalizedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func addInvitee() {
        let value = normalizedEmail
        guard !value.isEmpty, !invitees.contains(value) else { return }
        invitees.append(value)
        email = ""
    }
}

struct AttachmentEditView: View {
    @Binding var attachmentURL: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://...", text: $attachmentURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                } footer: {
                    Text(L.tr("Use a web or file URL. Providers may reject attachments they cannot access.", language: language))
                }

                if !attachmentURL.isEmpty {
                    Section {
                        Button(L.tr("Remove Attachment", language: language), role: .destructive) {
                            attachmentURL = ""
                        }
                    }
                }
            }
            .navigationTitle(L.tr("Attachment", language: language))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.tr("Done", language: language)) {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct VideoCallEditView: View {
    @Binding var videoCallURL: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://...", text: $videoCallURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                } footer: {
                    Text(L.tr("Use a video meeting URL.", language: language))
                }

                if !videoCallURL.isEmpty {
                    Section {
                        Button(L.tr("Remove Video Call", language: language), role: .destructive) {
                            videoCallURL = ""
                        }
                    }
                }
            }
            .navigationTitle(L.tr("Video Call", language: language))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.tr("Done", language: language)) {
                        dismiss()
                    }
                }
            }
        }
    }
}

import SwiftUI
import PhotosUI
import DisciplineCore

/// The developer profile (photo + name) and the enrolled signatures ("key signs") the rings must match.
struct KeysView: View {
    @EnvironmentObject var model: OuijaModel
    @State private var photo: PhotosPickerItem?
    @State private var newName = ""
    @State private var newKey = ""
    @State private var message = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 16) {
                        ProfileAvatar(size: 64)
                        VStack(alignment: .leading, spacing: 6) {
                            TextField("Your name", text: $model.settings.profileName)
                                .font(.headline)
                                .textContentType(.name)
                                .accessibilityIdentifier("keys.name")
                            let photoLabel = model.profileImage == nil ? "Add photo" : "Change photo"
                            PhotosPicker(selection: $photo, matching: .images) {
                                Text(photoLabel).font(.subheadline)
                            }
                            .accessibilityIdentifier("keys.photo")
                        }
                    }
                    .padding(.vertical, 4)
                } header: { Text("Developer profile") } footer: {
                    Text("Shown on the Agreement slider, in sign-in requests and in the Dynamic Island. Without a photo, your initials are used.")
                }

                Section {
                    if model.settings.enrolled.isEmpty {
                        Text("No computers enrolled yet. Add the key your computer's ring page shows.")
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("keys.empty")
                    }
                    ForEach(model.settings.enrolled) { k in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(k.name).font(.headline)
                            Text("Key sign \(k.fingerprint)").font(.footnote.monospaced()).foregroundStyle(.secondary)
                            Text("Added \(k.added.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.tertiary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("keys.enrolled.\(k.fingerprint)")
                    }
                    .onDelete { model.settings.enrolled.remove(atOffsets: $0) }
                } header: { Text("Enrolled signatures") } footer: {
                    Text("The rings are accepted only when they carry a valid Ed25519 signature from one of these keys. Each key also sets its own ring dance.")
                }

                Section("Add a computer") {
                    TextField("Name (e.g. Studio Mac)", text: $newName).accessibilityIdentifier("keys.newName")
                    TextField("NCOMKEY1.…", text: $newKey, axis: .vertical)
                        .font(.footnote.monospaced())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("keys.newKey")
                    Button("Enroll key") {
                        message = model.enroll(name: newName, keyText: newKey) ?? "Enrolled."
                        if message == "Enrolled." { newName = ""; newKey = "" }
                    }
                    .disabled(newKey.isEmpty)
                    .accessibilityIdentifier("keys.enroll")
                    if !message.isEmpty {
                        Text(message).font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("keys.message")
                    }
                }

                Section {
                    LabeledContent("Ouija key", value: model.deviceFingerprint)
                    if let at = model.settings.agreedAt {
                        LabeledContent("Agreement signed", value: at.formatted(date: .abbreviated, time: .standard))
                            .accessibilityIdentifier("keys.agreedAt")
                    }
                    ForEach(model.settings.approvals.prefix(5)) { a in
                        LabeledContent(a.client, value: "\(a.at.formatted(date: .omitted, time: .shortened)) · \(a.how == "island" ? "Island" : "slide")")
                    }
                } header: { Text("This iPhone") } footer: {
                    Text("Apps that use Sign in with Ouija pin this key the first time and refuse any other.")
                }
            }
            .navigationTitle("Keys")
            .onChange(of: photo) { _, item in
                Task {
                    let data = try? await item?.loadTransferable(type: Data.self)
                    model.setProfilePhoto(data)
                }
            }
        }
    }
}

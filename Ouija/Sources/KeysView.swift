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
    @State private var nameDraft = ""
    @State private var nameProblem = ""
    @State private var showCard = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 16) {
                        ProfileAvatar(size: 64)
                        VStack(alignment: .leading, spacing: 6) {
                            TextField("Your name", text: $nameDraft)
                                .font(.headline)
                                .textContentType(.name)
                                .submitLabel(.done)
                                .onSubmit {
                                    nameProblem = model.createAccount(name: nameDraft, kind: model.account?.kind ?? .local) ?? ""
                                    if !nameProblem.isEmpty { nameDraft = model.displayName }
                                }
                                .onAppear { nameDraft = model.displayName }
                                .accessibilityIdentifier("keys.name")
                            let photoLabel = model.profileImage == nil ? "Add photo" : "Change photo"
                            PhotosPicker(selection: $photo, matching: .images) {
                                Text(photoLabel).font(.subheadline)
                            }
                            .accessibilityIdentifier("keys.photo")
                        }
                    }
                    .padding(.vertical, 4)
                    LabeledContent("Account kept in", value: model.accountStore)
                        .font(.footnote)
                        .accessibilityIdentifier("keys.accountStore")
                    if !nameProblem.isEmpty { Text(nameProblem).font(.footnote).foregroundStyle(OuijaStyle.bad) }
                } header: { Text("Your account") } footer: {
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

                Section {
                    if let dev = model.settings.developer {
                        LabeledContent("Developer", value: "\(dev.ownerName) · card \(dev.cardID)")
                            .accessibilityIdentifier("keys.developer")
                    } else {
                        Text("Not signed in with an NCOM ID card.").foregroundStyle(.secondary).accessibilityIdentifier("keys.developer")
                    }
                    Button("Tap NCOM ID card") { showCard = true }.accessibilityIdentifier("keys.devCard")
                    TextField("NCOM verifier address (https://…)", text: $model.settings.verifierURL)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                        .font(.footnote.monospaced())
                        .accessibilityIdentifier("keys.verifierURL")
                    TextField("NCOM Dev public key", text: $model.settings.ncomDevKey)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().font(.footnote.monospaced())
                    TextField("GlassVault public key", text: $model.settings.glassVaultKey)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().font(.footnote.monospaced())
                    LabeledContent("This iPhone's card key", value: "\(model.magicKey.fingerprint) · \(model.magicKey.kind)")
                        .font(.footnote)
                    if !model.settings.securityReports.isEmpty {
                        ForEach(model.settings.securityReports.prefix(5)) { r in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.detail).font(.footnote)
                                Text("\(r.at.formatted(date: .abbreviated, time: .shortened)) · \(r.kind)\(r.reportedToIT ? " · reported to IT" : "")")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: { Text("Developer card") } footer: {
                    Text("The NCOM ID card signs you in as a developer only when NCOM Dev, GlassVault and this iPhone all agree. Give NCOM this iPhone's card key to register it.")
                }
            }
            .navigationTitle("Keys")
            .sheet(isPresented: $showCard) { DevCardSheet().presentationDetents([.large]) }
            .onChange(of: photo) { _, item in
                Task {
                    let data = try? await item?.loadTransferable(type: Data.self)
                    model.setProfilePhoto(data)
                }
            }
        }
    }
}

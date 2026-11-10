import SwiftUI
import Charts

/// Create / edit a profile: drag points on the chart or edit them numerically.
/// Save via the `/storage` WebSocket (`force` to overwrite the existing name).
struct ProfileEditorView: View {
    @Environment(KilnClient.self) private var client
    @Environment(\.dismiss) private var dismiss

    @State private var profile: Profile
    @State private var originalName: String
    @State private var originalData: [Profile.Point]
    @State private var originalUnits: String
    @State private var isSaving = false
    @State private var saveMessage: String?
    @State private var showReplaceConfirm = false

    private let isNew: Bool

    init(profile: Profile, isNew: Bool = false) {
        _profile = State(initialValue: profile)
        _originalName = State(initialValue: profile.name)
        _originalData = State(initialValue: profile.data)
        _originalUnits = State(initialValue: profile.tempUnits)
        self.isNew = isNew
    }

    /// True when the user has edited points, name, or units since last save.
    private var hasUnsavedChanges: Bool {
        profile.name != originalName
            || profile.tempUnits != originalUnits
            || profile.data != originalData
    }

    var body: some View {
        Form {
            // Saved-file status at the top.
            Section {
                if isSaving {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Saving…")
                    }
                } else if let saveMessage {
                    Label(saveMessage, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else if hasUnsavedChanges {
                    Label("Unsaved changes", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                } else {
                    Label("All changes saved", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Profile") {
                TextField("Name", text: $profile.name)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Picker("Units", selection: $profile.tempUnits) {
                    Text("Celsius").tag("c")
                    Text("Fahrenheit").tag("f")
                }
            }

            Section {
                ProfileChart(points: $profile.data, tempUnits: profile.tempUnits)
                    .frame(height: 290)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            } header: {
                HStack {
                    Spacer()
                    Text("Schedule")
                    Spacer()
                }
            } footer: {
                Text("Drag points to set time and temperature. Keep two points minimum; they're sorted by time on save.")
            }

            Section("Points") {
                ProfilePointList(points: $profile.data)
            }

            Section {
                LabeledContent("Peak temp", value: "\(Int(profile.peakTemp))°")
                LabeledContent("Duration", value: Format.clock(profile.totalDuration))
            } header: {
                Text("Summary")
            }
        }
        .navigationTitle(isNew ? "New Profile" : profile.name)
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.immediately)
        .toolbar {
            if isNew {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task { await save(force: false) }
                } label: {
                    if isSaving { ProgressView() } else { Text("Save") }
                }
                .disabled(profile.name.isEmpty || profile.data.count < 2 || isSaving || !hasUnsavedChanges)
            }
        }
        .confirmationDialog(
            "A profile named “\(profile.name)” already exists. Replace it?",
            isPresented: $showReplaceConfirm,
            titleVisibility: .visible
        ) {
            Button("Replace", role: .destructive) {
                Task { await save(force: true) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func save(force: Bool) async {
        guard !profile.name.isEmpty else { return }
        // Always store in celsius internally on the server; convert f->c for save if needed.
        var toSave = profile
        toSave.name = safeName(profile.name)
        toSave.data = profile.data.sorted { $0.time < $1.time }
        if profile.tempUnits.lowercased() == "f" {
            toSave.tempUnits = "c"
            toSave.data = toSave.data.map { .init(time: $0.time, temp: ($0.temp - 32) * 5 / 9) }
        }

        isSaving = true
        // Server refuses to overwrite an existing profile file unless force=true.
        // So: overwriting a *different* profile asks the user first; editing this
        // profile in place (same name) is always an intended overwrite.
        let overwriteOther = client.profiles.contains { $0.name == toSave.name && $0.name != originalName }
        if overwriteOther && !force {
            isSaving = false
            showReplaceConfirm = true
            return
        }
        let forceWrite = force || overwriteOther || client.profiles.contains { $0.name == toSave.name }
        var didWrite = false
        client.saveProfile(toSave, force: forceWrite) { ok in didWrite = ok }
        // Give the server a beat to push the updated list, then refresh.
        try? await Task.sleep(nanoseconds: 400_000_000)
        client.refreshStorage()
        try? await Task.sleep(nanoseconds: 300_000_000)
        isSaving = false
        if client.profiles.contains(where: { $0.name == toSave.name }) {
            saveMessage = "Saved."
            // Update the baseline so hasUnsavedChanges resets to false.
            originalName = toSave.name
            originalUnits = profile.tempUnits
            originalData = profile.data
            if isNew {
                dismiss()
            }
        } else if didWrite {
            saveMessage = "Sent. Verify in the list."
        } else {
            saveMessage = "Save failed."
        }
    }

    /// Map an arbitrary name to a filesystem-safe one (the server uses `<name>.json`).
    private func safeName(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        return raw
            .replacingOccurrences(of: " ", with: "_")
            .components(separatedBy: allowed.inverted)
            .joined()
    }
}

import AppKit
import SwiftUI
import SottoCore
import SottoViewModels
import UniformTypeIdentifiers

struct GoogleDriveBackupSheet: View {
    var sources: (@Sendable () async throws -> [MeetingDriveBackupSource])? = nil
    @State private var automaticStatus: GoogleDriveAutomaticBackup.Status?
    @State private var automaticError: String?
    @State private var confirmsAutomaticBackup = false
    @State private var model = GoogleDriveBackupViewModel()
    @State private var folderName = "Sotto Meetings"
    @State private var signIn = GoogleDriveSignIn()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(sources == nil ? "Google Drive backups" : "Back up to Google Drive")
                .font(.title2.weight(.semibold))
            if sources != nil {
                Text(
                    "Review the files below before uploading. Google will store this copy in your Drive, including any retained audio and meeting metadata."
                )
                .foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    accountControls
                    if model.identity != nil { destinationControls }
                    Divider()
                    if sources == nil {
                        automaticControls
                    } else {
                        preview
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let error = model.errorMessage {
                Text(error).foregroundStyle(.red).textSelection(.enabled)
                    .accessibilityLabel("Backup error: \(error)")
            }
            if let status = model.statusMessage { Text(status).foregroundStyle(.secondary) }
            if let progress = model.progress {
                ProgressView(value: Double(progress.uploadedBytes), total: Double(max(1, progress.totalBytes))) {
                    Text(progress.path).lineLimit(1)
                }
            } else if model.isBusy {
                ProgressView().controlSize(.small)
            }
            HStack {
                if model.isBusy {
                    Button("Cancel") { model.cancel() }.sottoAction(.secondary)
                }
                Spacer()
                Button("Close") { dismiss() }.sottoAction(.secondary).disabled(model.isBusy)
                if sources != nil {
                    Button(model.failures.isEmpty ? "Upload" : "Retry failed uploads") { model.upload() }
                        .sottoAction(.primary)
                        .disabled(
                            model.isBusy || model.identity == nil || model.snapshots.isEmpty
                                || model.completed.count == model.snapshots.count)
                }
            }
        }
        .padding(24)
        .frame(width: 620, height: 700)
        .interactiveDismissDisabled(model.isBusy)
        .task {
            model.prepare(sources: sources ?? { [] })
            guard sources == nil else { return }
            while !Task.isCancelled {
                await refreshAutomaticStatus()
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }
        .alert("Enable automatic Drive backups?", isPresented: $confirmsAutomaticBackup) {
            Button("Cancel", role: .cancel) {}
            Button("Enable") {
                guard let identity = model.identity else { return }
                let destination = model.destination
                changeAutomaticBackup { backup in
                    try await backup.enable(identity: identity, destination: destination)
                }
            }
        } message: {
            Text(
                "While Sotto is running, new and changed meetings will upload to \(model.destination.name) in \(model.identity?.email ?? "the selected account"). This includes transcripts, notes, prompt results, saved calendar context, local artifact paths, and retained audio. Changing the destination clears the previous local queue."
            )
        }
        .onDisappear { Task { await model.close() } }
    }

    private var automaticControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Automatic backup").font(.headline)
            if let configuration = automaticStatus?.configuration {
                Text(
                    "\(configuration.paused ? "Paused" : "On") · \(configuration.identity.email) · \(configuration.destination.name)"
                )
                .foregroundStyle(.secondary)
                if model.identity != configuration.identity {
                    Text("Uploads are held until \(configuration.identity.email) is connected.")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button(configuration.paused ? "Resume" : "Pause") {
                        changeAutomaticBackup { try await $0.setPaused(!configuration.paused) }
                    }.sottoAction(.secondary)
                    Button("Turn off") {
                        changeAutomaticBackup { try await $0.disable() }
                    }.sottoAction(.secondary)
                }
            } else {
                Text("Off. New and changed meetings can be uploaded while Sotto runs.")
                    .foregroundStyle(.secondary)
            }
            if let identity = model.identity {
                let config = automaticStatus?.configuration
                if config?.identity != identity || config?.destination.id != model.destination.id {
                    Button(config == nil ? "Enable for this folder…" : "Use this folder for automatic backup…") {
                        confirmsAutomaticBackup = true
                    }
                    .sottoAction(.primary)
                    .disabled(model.isBusy)
                }
            }
            if let automaticError {
                Text(automaticError).foregroundStyle(.red)
            }
            ForEach(automaticStatus?.entries ?? []) { entry in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.candidate.title)
                        Text(backupStatus(entry)).font(.caption).foregroundStyle(.secondary)
                        if let message = entry.message {
                            Text(message).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if entry.phase == .failed || entry.phase == .signInRequired {
                        Button("Retry") {
                            let id = entry.id
                            changeAutomaticBackup { try await $0.retry(id) }
                        }
                        .sottoAction(.secondary)
                    }
                }
            }
        }
    }

    private func backupStatus(_ entry: GoogleDriveAutomaticBackup.Entry) -> String {
        switch entry.phase {
        case .pending: "Pending"
        case .uploaded: "Uploaded"
        case .signInRequired: "Sign-in required"
        case .failed: "Failed"
        }
    }

    private static let automaticReadError = "Could not read the automatic backup queue."

    private func refreshAutomaticStatus() async {
        do {
            automaticStatus = try await GoogleDriveAutomaticBackup.shared.status()
            if automaticError == Self.automaticReadError { automaticError = nil }
        } catch {
            automaticError = Self.automaticReadError
        }
    }

    private func changeAutomaticBackup(
        _ change: @escaping @Sendable (GoogleDriveAutomaticBackup) async throws -> Void
    ) {
        Task {
            do {
                try await change(.shared)
                automaticError = nil
                await refreshAutomaticStatus()
            } catch {
                automaticError = "Could not update the automatic backup queue."
            }
        }
    }

    @ViewBuilder
    private var accountControls: some View {
        if let identity = model.identity {
            HStack {
                Label(identity.email, systemImage: "person.crop.circle")
                Spacer()
                Button("Disconnect") { model.disconnect() }.sottoAction(.secondary).disabled(model.isBusy)
            }
        } else {
            if !model.hasClient {
                Text(
                    "For this personal app, enable the Google Drive API in your Google Cloud project, create a Desktop app OAuth client, and import its downloaded JSON. Credentials are stored in this Mac’s Keychain."
                )
                .font(.callout).foregroundStyle(.secondary)
                Link(
                    "Open Google Cloud credentials",
                    destination: URL(string: "https://console.cloud.google.com/apis/credentials")!)
            }
            HStack {
                Button(model.hasClient ? "Change OAuth client…" : "Import OAuth client JSON…") { importClient() }
                    .sottoAction(.secondary)
                if model.hasClient {
                    Button("Connect Google account…") {
                        model.connect { try await signIn.connect(account: .shared) }
                    }.sottoAction(.primary)
                }
            }.disabled(model.isBusy)
        }
    }

    private var destinationControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Destination: \(model.path.map(\.name).joined(separator: " / "))").font(.headline)
            Text(
                "Only folders created by or explicitly opened with Sotto are visible with its limited Google permissions. Choose My Drive or create a backup folder here."
            )
            .font(.caption).foregroundStyle(.secondary)
            if model.path.count > 1 {
                Button("Back to parent folder") { model.goBack() }.sottoAction(.secondary)
            }
            ForEach(model.folders) { folder in
                Button {
                    model.openFolder(folder)
                } label: {
                    Label(folder.name, systemImage: "folder")
                }.sottoAction(.secondary)
            }
            HStack {
                TextField("New folder name", text: $folderName)
                Button("Create and use folder") { model.createFolder(name: folderName) }
                    .sottoAction(.secondary).disabled(
                        folderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.disabled(model.isBusy)
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Files to upload").font(.headline)
            Text(
                "The copy includes transcript text, notes, prompt results, local artifact paths and any saved calendar context. Repeating an upload updates Sotto’s existing copy in this destination."
            )
            .font(.caption).foregroundStyle(.secondary)
            ForEach(model.snapshots) { snapshot in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(snapshot.title).font(.headline)
                        Spacer()
                        if model.completed.contains(snapshot.id) { Label("Uploaded", systemImage: "checkmark.circle") }
                    }
                    ForEach(snapshot.files) { file in
                        HStack {
                            Text(file.relativePath).textSelection(.enabled)
                            Spacer()
                            Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                                .foregroundStyle(.secondary)
                        }.font(.caption)
                    }
                    if let failure = model.failures[snapshot.id] { Text(failure).font(.callout).foregroundStyle(.red) }
                }
            }
        }
    }

    private func importClient() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do {
                let data = try await Task.detached {
                    guard try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0 <= 65_536 else {
                        throw GoogleDriveError.message("Choose the small OAuth JSON downloaded from Google Cloud.")
                    }
                    return try Data(contentsOf: url)
                }.value
                model.importClient(data)
            } catch { model.errorMessage = error.localizedDescription }
        }
    }
}

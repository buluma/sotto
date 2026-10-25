import AppKit
import SwiftUI
import SottoCore
import SottoViewModels
import UniformTypeIdentifiers

struct GoogleDriveBackupSheet: View {
    let sources: @Sendable () async throws -> [MeetingDriveBackupSource]
    @State private var model = GoogleDriveBackupViewModel()
    @State private var folderName = "Sotto Meetings"
    @State private var signIn = GoogleDriveSignIn()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Back up to Google Drive").font(.title2.weight(.semibold))
            Text(
                "Review the files below before uploading. Google will store this copy in your Drive, including any retained audio and meeting metadata."
            )
            .foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    accountControls
                    if model.identity != nil { destinationControls }
                    Divider()
                    preview
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
                Button(model.failures.isEmpty ? "Upload" : "Retry failed uploads") { model.upload() }
                    .sottoAction(.primary)
                    .disabled(
                        model.isBusy || model.identity == nil || model.snapshots.isEmpty
                            || model.completed.count == model.snapshots.count)
            }
        }
        .padding(24)
        .frame(width: 620, height: 700)
        .interactiveDismissDisabled(model.isBusy)
        .task { [sources] in model.prepare(sources: sources) }
        .onDisappear { Task { await model.close() } }
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

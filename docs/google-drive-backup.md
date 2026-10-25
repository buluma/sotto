# Google Drive meeting backup

SOT-9 adds explicit Google Drive uploads from the Library. Choose **Back up to Google Drive…** from a saved meeting’s menu, or select multiple saved meetings and choose **Google Drive…**. Review the complete file list and destination, then click **Upload**. Drive for desktop is not required.

## Connect this personal fork

This fork does not ship someone else’s Google OAuth credentials. In your Google Cloud project, enable the Google Drive API, configure the OAuth consent screen, and create an OAuth client of type **Desktop app**. Download its client JSON and import it in the backup sheet. If the OAuth project is in Testing, add your Google account as a test user; Google may expire testing-mode refresh tokens after seven days, requiring another connection. The client configuration, access token, and refresh token are stored in a dedicated, non-synchronizing, device-only Keychain service, `com.sotto.google-drive`.

Click **Connect Google account…** and finish authorization in your default browser. Sotto requests only `https://www.googleapis.com/auth/drive.file`. It uses authorization-code exchange with PKCE and a short-lived listener bound to `127.0.0.1` on a dynamically assigned port. Authorization times out after three minutes. Neither the client secret nor access/refresh tokens are included in backup files or logs.

The native destination browser shows My Drive and folders available under `drive.file`: folders created by Sotto or explicitly granted to this OAuth application. It does not enumerate every pre-existing folder in your account. Use **Create and use folder** to create a dedicated destination without granting access to your whole Drive. No Google Picker browser integration or broader Drive permission is used.

## What leaves this Mac

The sheet stages a private copy before previewing it. It regenerates the standard meeting artifact views from saved transcript corrections, notes, classification, and prompt results, preserving the local originals. It includes retained raw/cleaned/playback audio and `meeting-recording-metadata.json` when present. It excludes recovery locks, scratch files, database files, downloaded models, unrelated folder contents, and symbolic links. Audio already removed by local retention is not reconstructed.

These are full meeting artifacts, not a redacted share: transcripts, notes, prompt results, calendar attendees/organizer information when saved, and artifact paths may be present. Google stores the selected copy under your account’s normal Drive permissions. Sotto does not create public links, modify sharing permissions, or add application-level encryption. The local Library remains authoritative. The staging copy is removed on ordinary sheet dismissal; an abrupt process termination can leave private temporary files for the operating system to clean up.

## Retry and update behavior

The account shown in the preview is bound to every folder and upload request; an account change in another app instance is rejected. Root destinations resolve My Drive’s actual ID, and existing backup items must still belong to their expected parent before updates or cleanup. Each meeting gets a folder named with its title and UUID. Per-account, per-destination Drive IDs are reserved in `google-drive-backup-ids.json` under Sotto’s Application Support directory before remote creates. Ledger reservation transactions reload and merge under an OS file lock across app instances; a separate nonblocking lease permits only one active upload batch in this app state directory. Keep this local ledger to preserve the identity of existing backups across app restarts. It contains opaque remote IDs, not tokens or transcript content. Deleting the ledger or using another Mac can create a separate backup copy.

Uploads send one-megabyte chunks, probe the confirmed position after an interrupted response, and keep active resumable sessions for retries in the same preview. A newly prepared preview starts a new upload session so bytes from different snapshots cannot be mixed. A retry after app restart reuses reserved remote IDs and starts the affected file again. Progress is per meeting; **Retry failed uploads** skips meetings already confirmed complete in this sheet.

Repeating a backup updates the existing Sotto-managed files in the chosen destination. Once its current files are uploaded, obsolete files tracked by Sotto are moved to Drive’s Trash; unrelated remote files remain untouched. Remote updates are not atomic: cancelling or losing a connection can leave a partial remote copy. The sheet marks a meeting uploaded only when the entire operation succeeds. Move a backup item back if it was manually moved in Drive before retrying; a permanently deleted reserved ID can require a new destination. All failure/cancellation/disconnect outcomes preserve local meetings and audio.

**Disconnect** clears local tokens before attempting Google revocation. If revocation cannot be confirmed, the sheet directs you to remove Sotto access in Google account settings. Disconnecting preserves existing Drive files and the local ID ledger.

## Scope and verification

V1 has no automatic uploads, scheduled processing, database synchronization, or Drive-to-Library restore. SOT-10 tracks optional automatic backup separately. The backup sheet must remain open during upload; closing the Library cancels its operation. Core recording, transcription, local retention, and deletion retain their existing behavior.

Focused tests cover preview isolation and allowlisting, OAuth state/PKCE/scope, credential clearing, ID reuse after reopening or uncertain creates, and confirmed-offset resumable uploads. Live acceptance requires the owner’s Google Cloud client and account: connect, create/select a destination, upload one and several meetings including retained audio, inspect the files in Drive, interrupt/retry a large upload, repeat without duplicate folders, and disconnect. Source/unit evidence does not establish that live account acceptance.

Google references: [native application OAuth](https://developers.google.com/identity/protocols/oauth2/native-app), [Drive authorization scopes](https://developers.google.com/workspace/drive/api/guides/api-specific-auth), and [resumable uploads](https://developers.google.com/workspace/drive/api/guides/manage-uploads).

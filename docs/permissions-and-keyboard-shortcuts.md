# macOS Permissions and Keyboard Shortcuts

Use this guide when Sotto can dictate from its on-screen control but a global keyboard shortcut, especially Fn, does not start dictation.

## Permissions Sotto Uses

| macOS permission | What Sotto uses it for | Where to check |
|---|---|---|
| Microphone | Dictation and microphone-backed meetings | System Settings → Privacy & Security → Microphone |
| Input Monitoring | Receiving Fn and other keyboard events globally for dictation and other hotkeys | System Settings → Privacy & Security → Input Monitoring |
| Accessibility (shown as Device Control and Data Access on some macOS versions) | Sending the paste keystroke and accessibility-assisted text operations | System Settings → Privacy & Security → Accessibility or Device Control and Data Access |
| Screen & System Audio Recording | Capturing system audio in meeting modes that include it | System Settings → Privacy & Security → Screen & System Audio Recording |

Input Monitoring and Accessibility are separate permissions. Enabling Sotto under Device Control and Data Access does not enable Input Monitoring. Sotto's Permissions card may show Accessibility as granted while the global hotkey still cannot receive keyboard events because Input Monitoring is off.

## Fn Does Not Start Dictation

1. Open **System Settings → Privacy & Security → Input Monitoring** and enable the exact Sotto app you run.
2. Quit and reopen Sotto so the event listener starts again with the grant in place.
3. Confirm **System Settings → Privacy & Security → Accessibility** (or **Device Control and Data Access**) also has the same Sotto app enabled; this is used for auto-paste.
4. In **System Settings → Keyboard**, set **Press fn key to** to **Do Nothing** if macOS Dictation is assigned to Fn. The Fn key can otherwise invoke macOS Dictation instead of Sotto's hold or double-tap gesture.
5. In Sotto, verify the dictation shortcuts are enabled and try the configured gesture again. The default shared Fn gesture is hold Fn for push-to-talk or double-tap Fn for hands-free dictation.

If the on-screen dictation button works but Fn does not, microphone access and speech recognition can work while global keyboard monitoring is still blocked. Check Input Monitoring first.

## If the Permission Toggle Looks Enabled but Sotto Reports It Missing

macOS permissions are attached to an app identity. After replacing or re-signing a local build, remove that app from the relevant privacy list, add the current `.app` from Applications again, enable it, then quit and reopen Sotto. Grant permissions separately to Sotto and Sotto-Dev; they have different bundle identifiers and state directories.

Resetting TCC permissions removes grants and requires them to be granted again. For the installed stable app, quit Sotto and run `tccutil reset All com.sotto.Sotto` in Terminal. The development build uses `com.sotto.dev` instead. Re-add the app in System Settings if the expected prompt or grant does not appear.

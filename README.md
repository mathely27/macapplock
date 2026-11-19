# AppLocker for macOS

Native menu bar app that asks for Touch ID or the current Mac user's password when you enter a protected app. Requires macOS 13 or later.

## Build and run

1. Open `AppLocker.xcodeproj` in Xcode and use **Sign to Run Locally** (or your development team).
2. Build and run the AppLocker scheme.
3. Grant **System Settings → Privacy & Security → Accessibility** to this exact copy of AppLocker. Protected apps remain locked until this permission is granted. Window close/reopen detection requires it.
4. Add WhatsApp or another app using **+**.
5. Turn on **Launch at Login** for protection after signing in. If macOS requests approval, enable AppLocker under **General → Login Items**. Keep the app in a stable location before enabling this setting.

Closing AppLocker's dashboard leaves protection running in the menu bar. Quitting AppLocker, removing an app, disabling protection, and disabling login protection require authentication when applicable. Settings failures are shown in the dashboard.

## Lock behavior

- Each foreground visit shows an explicit lock screen. Click **Unlock with Touch ID or Mac Password** (or press Return) to start fresh native authentication. Switching away, hiding the app, closing/minimizing its last window, quitting, sleep, and screen lock revoke the unlock.
- Closing and reopening WhatsApp uses the same process on macOS. Accessibility window notifications handle this directly; a 250 ms reconciliation timer and WindowServer window IDs back up workspace events. An empty accessibility window list cannot bypass a visible protected app.
- Cancel on the lock screen hides the protected app. Canceling the native authentication keeps the lock screen visible so you can retry.
- Prompts are serialized. A second protected app opened during a prompt stays hidden and locked.
- Existing processes are hidden behind an opaque shield during authentication. Apps are not force-quit or relaunched, preserving unsaved work and background activity.
- Unlocks are bound to process identity and a unique request. Late callbacks cannot unlock a replacement process or a session invalidated by sleep/termination. Fresh `LAContext` instances use no Touch ID reuse interval.

This is a user-session privacy utility. macOS delivers app/window notifications after events; AppLocker cannot guarantee that content never appears briefly. Accessibility permission is needed for reliable same-process window reopen detection. It must remain running; Force Quit, a crash, or an administrator can stop protection. Hidden apps continue background processing, notifications, and network activity. This is not an OS security boundary.

## Verification

Run `swift test` (with Xcode selected, or `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`). Core regression tests cover window detection fallback, explicit open intent, and rapid same-process reopen, duplicate events, cancellation/retry, stale callbacks, PID reuse, and process-bound authorization.

Manual checks on the signed running app:

- Unlock WhatsApp, switch to Finder, then return immediately: fresh prompt.
- Close its last window with the red button, reopen from Dock within 2–3 seconds: fresh prompt.
- Minimize its last window and restore it: fresh prompt.
- Cancel and reopen: fresh prompt, with no killed process.
- Quit/relaunch WhatsApp: fresh prompt.
- Close AppLocker's dashboard and repeat: monitoring continues.
- Open two protected apps during authentication: neither receives an unrelated unlock.
- Sleep/wake or lock/unlock the Mac: previous authorization is revoked.
- Disable/remove protection or quit AppLocker: authentication is required.
- Enable Launch at Login, sign out/in, verify the menu bar icon and prompt.

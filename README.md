# AppLocker for macOS

Automatically ask for Touch ID or your Mac password when you open a protected app. No initial Unlock click is required. Closing the dashboard keeps the menu bar guard running.

## Download

### [Download AppLocker for Apple Silicon](https://github.com/mathely27/macapplock/releases/latest/download/AppLocker-macOS-AppleSilicon.zip)

**Requires an Apple Silicon (M-series) Mac running macOS 13 or later.** This prebuilt download does not support Intel Macs or Windows. Xcode, Python, and Homebrew are not needed to use it.

The ZIP contains:

- `AppLocker.app` — the ready-to-run app.
- `EnableBackground.command` — sets up automatic background protection for your Mac account.
- `START_HERE.md` — the installation instructions below.

[All releases and checksums](https://github.com/mathely27/macapplock/releases/latest)

## Install and set up

1. Download the ZIP above and extract it.
2. Move **AppLocker.app** into **Applications**. Keep it there; run this installed copy rather than the copy in Downloads.
3. Open AppLocker normally. This is a locally signed, unnotarized build. If macOS blocks the first launch, review the download source and follow [Apple's instructions for opening a trusted app](https://support.apple.com/en-us/102445). The setup script does not disable Gatekeeper or remove quarantine protections.
4. In **System Settings → Privacy & Security → Accessibility**, enable the installed AppLocker. If it is missing, click **+** and choose `/Applications/AppLocker.app`.
5. In AppLocker, click **+** and select the apps you want to protect. Opening a protected app now starts native Touch ID or Mac password authentication automatically.
6. Double-click **EnableBackground.command** from the extracted folder. It opens Terminal and installs only AppLocker's per-user login agent. No administrator password is required by the script.
7. **Sign out and back in once** to activate the supervised background service. If macOS asks, allow AppLocker under **General → Login Items**. Until that login, the normally opened app continues monitoring when its dashboard is closed, but its process is not yet supervised for automatic restart.

After setup, use the menu bar shield → **Open AppLocker** to manage protection. Each Mac uses its own user's Touch ID or Mac password. The download does not include the developer's protected-app list or credentials.

### Already have the app?

Download the same ZIP and use its included `EnableBackground.command` ([view the setup script](Service/EnableBackground.command)). Run it only after placing AppLocker in Applications and opening that copy once. Sign out/in once after setup. The script preserves existing app settings and does not terminate running applications.

### Permission or startup trouble

- **Grant Access still appears after an update:** locally signed builds have different signatures. Remove only the stale AppLocker entry from Accessibility, then add `/Applications/AppLocker.app` again and allow it. Approve the macOS authorization prompt yourself.
- **Background protection does not start:** make sure the app remains in Applications, run `EnableBackground.command`, and sign out/in once. Check **General → Login Items** for an approval request.
- **Native authentication was cancelled:** the app remains locked with a retry button. No protected app is force-quit.

## Background protection

Closing the dashboard, Cmd+Q, and Dock Quit dismiss the dashboard and remove the Dock icon. The menu bar guard continues monitoring all enabled protected apps and can display lock and authentication panels independently of the dashboard.

The installed per-user launchd service `com.applock.AppLocker.guard` runs `/Applications/AppLocker.app/Contents/MacOS/AppLocker --background`, starts at login, and restarts the guard after an unexpected process exit. Background startup creates no dashboard. The service plist lives at `~/Library/LaunchAgents/com.applock.AppLocker.guard.plist`. Keep the installed app in `/Applications`.

Use the menu bar's **Open AppLocker** to manage protected apps. **Stop Protection Until Login…** requires native authentication and unloads the service for the current login session. Its installed plist restores protection at the next login. Shut down, restart, and logout are allowed normally. An administrator can still disable or uninstall the service; this is a user-session privacy utility, not an OS security boundary. Restarting after a crash has a short interruption.

Accessibility permission must be enabled for this installed copy in System Settings → Privacy & Security → Accessibility. After a locally signed update, macOS may keep an enabled entry bound to the old binary signature. In that case remove only the AppLocker entry, then use + to add `/Applications/AppLocker.app` again. Merely toggling the old entry may retain its obsolete code requirement. Approve the normal macOS authorization prompt when requested. Without it, protected apps stay hidden and the dashboard explains the setup requirement.

## Build and verify

Build the AppLocker scheme with Xcode, using Sign to Run Locally. Run core tests with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`.

The guard preserves the existing window-lifecycle behavior: switching away, hiding, closing/minimizing the last window, sleep, screen lock, and process termination revoke authorization. Cancellation keeps apps locked without killing their processes or losing unsaved work. Lock panels serialize authentication requests, and stale callbacks cannot unlock another process.

Verify on the installed app:

- Start with no dashboard: protected apps still display their lock panels.
- Close the dashboard with its red button, reopen it, then Cmd+Q: background monitoring remains active in both cases.
- Terminate the guard process: launchd starts a fresh guard with no saved authorization.
- Visit each configured protected app after closing the dashboard: each requires authentication.
- Cancel authentication and retry: the lock panel stays usable.
- Sign out/in: the service starts automatically, without opening the dashboard.

macOS reports app/window changes after they happen, so a brief content flash cannot be ruled out. Hidden apps retain their normal background activity and notifications.

launchd design reference: https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html

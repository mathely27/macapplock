# AppLocker for macOS

Automatically ask for Touch ID or your Mac password when you open a protected app. No initial Unlock click is required. Closing the dashboard keeps the menu bar guard running.

## Download

### [Download AppLocker 1.2 — Universal DMG](https://github.com/mathely27/macapplock/releases/latest/download/AppLocker-Universal.dmg)

**Intel and Apple Silicon (M-series), macOS 13 or later.** One universal app includes native `x86_64` and `arm64` code. Xcode, Python, and Homebrew are not needed to use it. Macs running macOS 12 or earlier are not supported.

The disk image includes the app with its new icon embedded, an Applications shortcut, and a **Setup & Help** folder containing background setup and troubleshooting.

**Signing status:** this is a locally signed, unnotarized build. A DMG is an installation container and does not grant Apple trust. First-open approval may still be required. See [Apple's guide](https://support.apple.com/en-us/102445). Seamless Gatekeeper approval requires a Developer ID certificate and Apple notarization; these are not present in this release.

[Release notes and SHA-256 checksum](https://github.com/mathely27/macapplock/releases/latest)

## Install

1. Download and open **AppLocker-Universal.dmg**.
2. Drag **AppLocker** onto the **Applications** shortcut. If an old AppLocker process is stuck, stop that process in Activity Monitor before replacing its app. Do not delete your preferences.
3. Eject the disk image and open **AppLocker from Applications**. Run this installed copy rather than the copy inside the DMG or Downloads. Review the source and follow Apple's first-open approval instructions if macOS blocks it.
4. Enable the installed app in **System Settings → Privacy & Security → Accessibility**. If needed, click **+** and choose `/Applications/AppLocker.app`.
5. Click **+** in AppLocker to choose apps to protect. Their native Touch ID/Mac password prompt opens automatically.
6. To set up automatic startup and restart, run **Setup & Help → EnableBackground.command** from the disk image (or copy the folder before ejecting). It installs only the current user's login agent; it does not stop apps, change Accessibility, or bypass Gatekeeper.
7. **Sign out and back in once** to activate the supervised guard. Allow AppLocker under **General → Login Items** if macOS requests it. Until that login, the normally opened app keeps monitoring when its dashboard closes, but automatic process restart is not yet supervised.

Use the menu bar shield → **Open AppLocker** to manage protection. Each Mac uses its own user's Touch ID/Mac password. The download contains no protected-app list or credentials from the developer.

## Upgrading from the old ZIP

- Download the new universal DMG above. The old release was Apple Silicon only and its icon depended on Finder custom-icon metadata.
- Stop a stuck old AppLocker process using Activity Monitor, replace the app in Applications, and open the installed copy. Avoid multiple running copies.
- If the icon remains stale, remove the old Dock shortcut and drag the installed app back to the Dock. The 1.2 icon is compiled inside the app itself.
- If **Grant Access** remains after an update, remove only the stale AppLocker Accessibility entry and add the new installed copy again. Approve the normal macOS authorization prompt yourself.
- If it still reports **not responding**, report the exact macOS version, chip, and error text in [an issue](https://github.com/mathely27/macapplock/issues). A screenshot alone cannot establish the cause.

## Verification scope

The universal binary, embedded icon, clean strict code signature, DMG checksum, and copy-out from the mounted image were verified locally. Fresh-profile Apple Silicon startup and the Intel slice running under Rosetta both opened the dashboard; the Intel test also used a seeded protected-app list with no Accessibility permission. All 11 core regression tests passed.

Physical Intel hardware and each supported older macOS version have not been tested. This release also defers monitoring until after singleton initialization to avoid a re-entrant startup deadlock when permission handling opens the dashboard.

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

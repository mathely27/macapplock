# AppLocker for macOS 13+

AppLocker asks for fresh Touch ID or the Mac user's password on each protected-app visit. Existing protected-app settings are preserved.

## Background protection

Closing the dashboard, Cmd+Q, and Dock Quit dismiss the dashboard and remove the Dock icon. The menu bar guard continues monitoring all enabled protected apps and can display lock and authentication panels independently of the dashboard.

The installed per-user launchd service `com.applock.AppLocker.guard` runs `/Applications/AppLocker.app/Contents/MacOS/AppLocker --background`, starts at login, and restarts the guard after an unexpected process exit. Background startup creates no dashboard. The service plist lives at `~/Library/LaunchAgents/com.applock.AppLocker.guard.plist`. Keep the installed app in `/Applications`.

Use the menu bar's **Open AppLocker** to manage protected apps. **Stop Protection Until Login…** requires native authentication and unloads the service for the current login session. Its installed plist restores protection at the next login. Shut down, restart, and logout are allowed normally. An administrator can still disable or uninstall the service; this is a user-session privacy utility, not an OS security boundary. Restarting after a crash has a short interruption.

Accessibility permission must be enabled for this installed copy in System Settings → Privacy & Security → Accessibility. A changed local code signature can require re-enabling that existing permission after an update. Without it, protected apps stay hidden and the dashboard explains the setup requirement.

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

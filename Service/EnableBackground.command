#!/bin/zsh
# Installs only the current user's AppLocker login agent. It does not stop apps,
# alter Accessibility permissions, or bypass macOS security checks.
set -euo pipefail

app_path='/Applications/AppLocker.app'
agent_label='com.applock.AppLocker.guard'
agent_dir="$HOME/Library/LaunchAgents"
agent_path="$agent_dir/$agent_label.plist"

finish() {
    print
    read -r '?Press Return to close this window. '
}
fail() {
    print -u2 -- "$1"
    finish
    exit 1
}

os_version="$(/usr/bin/sw_vers -productVersion)"
[[ "${os_version%%.*}" -ge 13 ]] || fail 'AppLocker requires macOS 13 or later.'
[[ -x "$app_path/Contents/MacOS/AppLocker" ]] || fail 'First move AppLocker.app into Applications and open it once, then run this setup again.'
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_path/Contents/Info.plist")"
[[ "$bundle_id" == 'com.applock.AppLocker' ]] || fail 'The installed application is not AppLocker.'
/usr/bin/codesign --verify --deep "$app_path" || fail 'AppLocker could not be verified. Download a fresh copy from the repository release.'

/bin/mkdir -p "$agent_dir"
staged_path="$(/usr/bin/mktemp "$agent_dir/.applocker.XXXXXX")"
trap '/bin/rm -f "$staged_path"' EXIT
/bin/cat > "$staged_path" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>com.applock.AppLocker.guard</string>
    <key>ProgramArguments</key><array>
        <string>/Applications/AppLocker.app/Contents/MacOS/AppLocker</string>
        <string>--background</string>
    </array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>LimitLoadToSessionType</key><string>Aqua</string>
    <key>ProcessType</key><string>Interactive</string>
    <key>ThrottleInterval</key><integer>3</integer>
    <key>AssociatedBundleIdentifiers</key><array><string>com.applock.AppLocker</string></array>
</dict>
</plist>
PLIST
/usr/bin/plutil -lint "$staged_path" >/dev/null
/bin/chmod 644 "$staged_path"
if [[ -e "$agent_path" ]] && ! /usr/bin/cmp -s "$staged_path" "$agent_path"; then
    /bin/cp -p "$agent_path" "$agent_path.backup.$(/bin/date +%Y%m%d%H%M%S)"
fi
/bin/mv -f "$staged_path" "$agent_path"

# Do not bootstrap a second instance alongside the normally launched app.
# macOS loads this LaunchAgent on the next login and owns its restart policy.
if ! /bin/launchctl enable "gui/$(/usr/bin/id -u)/$agent_label"; then
    print -u2 'The login agent was installed, but macOS did not enable it. Check System Settings > General > Login Items.'
    finish
    exit 1
fi
print 'AppLocker background setup is installed for your account.'
print 'Sign out and back in once to activate supervised background protection.'
print 'Keep AppLocker.app in Applications. Allow it in Login Items if macOS asks.'
print 'Your protected-app list and Accessibility permissions were not changed.'
finish

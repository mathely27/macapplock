# AppLocker for macOS 🔐

AppLocker is a lightweight, native macOS utility that allows you to protect your applications using Touch ID or your Mac's administrator password.

## 🌟 Features
- **Native Security:** Leverages macOS `LocalAuthentication` to use Touch ID and standard Mac passwords.
- **Immediate Protection:** Terminates protected applications instantly upon launch until authenticated.
- **Launch at Login:** Option to run silently in the background automatically when you start your Mac.
- **Clean Architecture:** Built using SwiftUI and follows a clean MVVM folder architecture.
- **Lightweight UI:** Native gray/black styling utilizing standard macOS components (`List`, `Form`, `Toggle`).

## 📁 Architecture
The project is strictly organized using the following folder architecture:
- `AppLocker/Models` - Contains the `ProtectedApp` data model.
- `AppLocker/Managers` - Core logic (`AppLockManager`) for app lifecycle monitoring, persistence, and LocalAuthentication.
- `AppLocker/Views` - SwiftUI views for the dashboard, app lists, and adding apps.
- `AppLocker/App` - The application entry point and AppDelegate.

## 🚀 How to Run Locally

### Requirements
- macOS 13.0 or later
- Xcode 14.0 or later

### Setup
1. Clone the repository.
2. Open `AppLocker.xcodeproj` in Xcode.
3. Select the `AppLocker` target.
4. Go to **Signing & Capabilities** and select your Team (or choose "Sign to Run Locally").
5. Press `Cmd + R` to build and run.

*Note: The app requires "Accessibility" permissions to monitor the launch of other applications effectively. You will be prompted to allow this on first launch.*

## 💻 Usage
1. Open **AppLocker**.
2. Click **Add App** and select the applications you want to protect (e.g., WhatsApp, Mail, Photos).
3. Toggle the **Launch at Login** switch to enable background protection automatically.
4. Close the AppLocker window; it will continue running seamlessly in the background.

Whenever you open a protected app, AppLocker will intercept it and present a native Touch ID/Password prompt!

## 📜 License
MIT License. Feel free to fork and improve!
# macapplock

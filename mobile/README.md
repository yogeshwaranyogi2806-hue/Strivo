# Strivo Mobile

Flutter app source for the Android-first coach product. The existing files in the workspace root are a browser prototype and remain separate from this app.

## Prerequisites

- Flutter stable with Dart 3.4 or newer
- Android Studio with an Android SDK and emulator, or a USB-connected Android device
- A Supabase project for authentication and database access

Install Android Studio and its Android SDK, then run `flutter doctor` and resolve any Android toolchain issues. The Android project wrapper is already included in this directory.

```powershell
flutter doctor --android-licenses
flutter doctor
```

From this directory, fetch dependencies and launch on a connected Android device:

```powershell
flutter pub get
flutter run --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co --dart-define=SUPABASE_ANON_KEY=YOUR_SUPABASE_PUBLISHABLE_KEY
```

To create a debug APK for sideloading, run `flutter build apk --debug`. The APK will be at `build/app/outputs/flutter-apk/app-debug.apk`.

Use the Supabase publishable/anon key in the mobile client, never a service-role key. Database access is protected by row-level security. Apply the SQL migration in `../supabase/migrations` before signing in. Phone OTP also requires configuring an SMS provider in Supabase.

## Checks

```powershell
dart format --set-exit-if-changed .
flutter analyze
flutter test
```

## Structure

- `lib/app/` app theme and navigation
- `lib/core/` environment configuration and shared providers
- `lib/features/auth/` email/password and phone OTP sign-in
- `lib/features/dashboard/` authenticated coach shell and workspace setup
- `test/` focused app configuration tests
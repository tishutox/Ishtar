# Ishtar

Cross-platform foundation for an Amino-inspired community hub.

## Goals

- One codebase for Android, iOS, Web, and Desktop (Windows, macOS, Linux)
- Responsive layouts for phone, tablet, and large screens
- Modular structure for future features like feed, chat, communities, and profiles

## Projektstruktur

```text
lib/
	app/
	core/
		responsive/
		theme/
	features/
		home/
		communities/
		profile/
	widgets/
```

## Requirements

- Flutter SDK (stable)
- Android Studio for Android build tools
- Xcode (macOS only) for iOS build tools

## Run

```bash
flutter pub get
flutter run
```

Supabase is configured at runtime so client configuration is not committed:

```powershell
flutter run -d windows `
  --dart-define=SUPABASE_URL=https://lclcpnecbejxzbbzygwt.supabase.co `
  --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
```

Before profile image uploads can be used, run
`supabase/avatar_storage.sql` once in the Supabase SQL Editor.

For public profiles, banners, bios, links and people tags, run
`supabase/profiles.sql` once in the Supabase SQL Editor. Public profile URLs use
`https://tishutox.github.io/Ishtar/app/u/username` and the app scheme
`lumiiquest://u/username`.

If `supabase/profiles.sql` changes after the initial setup, run the complete
file again. The migration is idempotent and adds new profile fields safely.

For the private notifications inbox and friend requests, run
`supabase/notifications.sql` in the Supabase SQL Editor. Run the complete file
again whenever it changes; the migration preserves existing notifications.

Voice and video calls use Supabase Realtime for signaling and WebRTC for media.
Keep Realtime enabled in the Supabase project. Calls request microphone access;
video calls also request camera access. On web, serve the app from HTTPS or
localhost so the browser can grant media-device access. Audio output follows
the system's connected headset by default; the in-call audio-device control
lets users select another available output.

## Run By Platform

```bash
flutter run -d windows
flutter run -d chrome
flutter run -d android
flutter run -d ios
```

## Suggested Next Steps

- Authentication (Email, OAuth)
- Backend (for example Supabase/Firebase or your own API)
- Data models for community, post, comment, and chat
- State management (Riverpod or Bloc)

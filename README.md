# Secure Chat (Flutter)

A WhatsApp-style mobile chat client built with Flutter as a portfolio project.

The app demonstrates end-to-end product thinking: authentication flow, chat list, real-time-like messaging UX, media sharing, voice messages, API integration, and error handling.

## Why this project

This project was built to show practical Flutter engineering skills in a realistic messaging app scenario:

- Clean feature-based structure (`auth`, `chat`, `core`, `service`)
- API-first implementation with a mock fallback for demos
- Stateful UI with BLoC and robust async/error states
- Mobile-native features (camera, gallery, file picker, microphone, audio playback)

## Key Features

- Authentication: login with validation (username, full name, user ID, password)
- Session management: token persistence with `SharedPreferences`
- Chat list: search, unread filter, pin/unpin (up to 3), swipe-to-archive
- New conversation: start chat by phone number
- Messaging: send text, image, file, and voice messages
- Media flow: gallery picker, camera capture, and file picker integration
- Voice UX: record, send, and play audio messages in-app
- Message actions: edit and delete messages
- Chat actions: delete conversation
- Reliability: pull-to-refresh + user-friendly error states
- Permissions: guided access flow for camera, microphone, and media library

## Tech Stack

- Flutter (Dart)
- `flutter_bloc` + `equatable`
- `dio` for HTTP layer
- `shared_preferences` for local persistence
- `image_picker`, `file_picker`
- `record`, `audioplayers`
- `permission_handler`
- `google_fonts` (Urbanist)

## Architecture

The codebase follows a layered, feature-first approach:

- `presentation`: pages, widgets, BLoC state management
- `domain`: entities, repository contracts, use cases
- `data`: remote data sources, repository implementations, DTO mapping
- `service`: API client, storage service, interceptors, error mapping
- `core`: theme, constants, shared UI components

## Project Structure

```text
lib/
  core/
    constants/
    theme/
    widgets/
  features/
    auth/
      data/
      domain/
      presentation/
    chat/
      data/
      domain/
      presentation/
  service/
    api_service.dart
    db_service.dart
    utils/
  app.dart
  main.dart
```

## Getting Started

### 1) Install dependencies

```bash
flutter pub get
```

### 2) Configure API

Update `lib/core/constants/api_constants.dart`:

- `baseUrl`
- `apiToken` (optional, if your backend requires it)

### 3) Run the app

```bash
flutter run
```

## Demo Mode (No Backend Required)

You can run login in demo mode using a mock auth repository:

```bash
flutter run --dart-define=USE_MOCK_AUTH=true
```

This is useful for portfolio demos when the backend is unavailable.

## Backend Endpoints Used

- `POST /api/auth/login`
- `GET /api/chats`
- `POST /api/chats/start`
- `GET /api/chats/{chatId}/messages`
- `POST /api/chats/{chatId}/send/text`
- `POST /api/chats/{chatId}/send/media`
- `POST /api/files/upload-{kind}`
- `PATCH /api/chats/{chatId}/messages/{messageRef}`
- `DELETE /api/chats/{chatId}/messages/{messageRef}`
- `DELETE /api/chats/{chatId}`

## What this portfolio project demonstrates

- Building non-trivial Flutter UI with polished interactions
- Integrating with REST APIs and mapping inconsistent payloads safely
- Managing async state and failures with predictable UX
- Working with platform permissions and native device capabilities
- Organizing code for scalability and maintainability

---

If you are reviewing this as part of my portfolio, I can also provide a short architecture walkthrough and a live demo flow.
# sss_stream_crm

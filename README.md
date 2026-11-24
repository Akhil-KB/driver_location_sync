# Driver Location Sync

Flutter app for driver GPS tracking with offline storage and sync when connectivity returns.

## Features

- Start / stop location tracking (simulated GPS or device GPS)
- Save location points locally when offline
- Keep pending points after app restart
- Auto-sync to a mock REST API with retries
- Avoid duplicate uploads with stable record IDs
- Cubit-based structure: UI, sync logic, local storage, and API kept separate

## Setup

```bash
flutter pub get
flutter test
flutter run
```

```bash
flutter run -d macos   # simulated GPS works well on desktop
flutter run            # Android / iOS device or emulator
```

## Usage

1. Open the app (simulated GPS is selected by default).
2. Tap **Start** to begin capturing points.
3. Turn on airplane mode to verify offline storage.
4. Close and reopen the app — pending points should still be there.
5. Go online again and tap **Sync** (or wait for automatic sync).

## Structure

```text
lib/
  models/
  data/
    local/           # JSON persistence
    remote/          # mock REST client
    location/        # device + simulated GPS
    connectivity/
  domain/            # sync / retry logic
  presentation/
    cubit/
    pages/
```

## Architecture

- `TrackingCubit` handles UI state
- `LocationSyncService` handles ingest, persist, sync, and retries
- Local store is a JSON file for simplicity
- Mock uploads go to `https://httpbin.org/post` and fail randomly so retry behavior is easy to see
- Each captured point gets a UUID that stays the same across retries

## Background location tracking

Background service code is not included in this sample. Approach for production:

### Android

- Request fine location, then background location on Android 10+
- Keep a foreground service with a persistent notification during an active trip
- Write every point to local storage first, then upload when online
- After process death, restore from the local queue and restart tracking when the driver opens the app
- Limits: background access is restricted without a foreground service; OEM battery savers can still throttle updates

### iOS

- Start with When In Use, request Always only if continuous background tracking is required
- Enable `UIBackgroundModes = location`
- Persist locally first; sync when the network is available
- If the user force-closes the app, continuous updates stop until relaunch (significant-change / region monitoring can help wake the app)
- Limits: Always permission is reviewed carefully; iOS may coalesce updates to save power

### Shared approach

1. Capture locations in a long-running background capability
2. Append to a local queue with stable IDs
3. Sync over REST when online
4. Mark synced only after a successful response
5. Retry with backoff using the same ID

## Limitations

- Simulated GPS is the default path
- Local storage is a single JSON file
- No map UI or auth layer in this sample

## Tests

```bash
flutter test
```

# Driver Location Sync

Flutter sample for driver GPS tracking with offline-first storage and reliable sync.

Focus areas: architecture, offline reliability, synchronization, and testable problem-solving.

## What it does

- Start / stop tracking (simulated GPS or device GPS)
- Persist every location point locally before any upload attempt
- Keep pending points across app restarts
- Auto-sync when connectivity returns
- Retry failed uploads with backoff
- Block duplicate uploads with stable record IDs (`Idempotency-Key`)

## Demo

Screen recording (Android emulator) with captions:

[docs/demo.mp4](docs/demo.mp4)

Shows simulated GPS tracking, offline pending queue, and sync drain when connectivity returns.

## Setup

```bash
flutter pub get
flutter test
flutter run
```

```bash
flutter run -d macos
flutter run
```

## Architecture

```text
presentation/   TrackingCubit + UI
domain/         LocationSyncService (offline queue + sync rules)
data/
  local/        atomic JSON persistence
  remote/       mock REST client
  location/     device / simulated GPS
  connectivity/ online-offline signals
```

Design choices:

- **UI does not talk to storage or HTTP directly.** Cubit only starts GPS and forwards points into the sync service.
- **Offline-first write path.** `ingest()` always writes disk first. Upload happens only after persistence succeeds.
- **Single-flight sync.** Concurrent sync requests share one in-flight job. Points that arrive mid-sync mark the queue dirty and get drained before sync exits.
- **Crash recovery.** Records left in `syncing` are reset to `pending` on startup so an interrupted upload is retried with the same id.
- **Idempotent uploads.** The client UUID is reused for every retry and sent as `Idempotency-Key`.
- **Typed failures.** Network loss stops the batch; transient server failures retry with exponential backoff.

## Offline + sync flow

1. Capture location point with a stable UUID
2. Append/upsert into local store
3. If offline, leave as `pending`
4. When online, upload oldest pending first
5. Mark `synced` only after a successful response
6. On failure, store error + retry count and try again later

## Tests

```bash
flutter test
```

Covered cases:

- offline persistence across restart
- interrupted `syncing` recovery
- retry after transient failure
- duplicate id prevention
- connectivity loss during a sync batch
- points ingested while sync is running

## Background location notes

Background service implementation is not part of this sample.

**Android:** foreground service + notification for active trips; persist locally first; sync when network returns; OEM battery savers can still throttle updates.

**iOS:** When In Use first, Always only if required; `UIBackgroundModes = location`; force-quit stops continuous updates until relaunch.

Shared rule: local queue with stable ids is the source of truth; network sync is eventual.

## Limitations

- Simulated GPS is the default path
- Local store is a JSON file (good enough for this sample size)
- Mock API randomly fails so retry behavior is visible

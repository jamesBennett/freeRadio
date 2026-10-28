# Free Radio — build plan

Status (2026-10-22): steps 1–6 implemented. App builds; 24 unit tests pass on the iOS simulator. Simulator flow verified: fresh-install empty state, search, pin, live playback, pause, relaunch restores pin and selection without autoplay, now-playing titles on an ICY music stream. MusicBrainz contact configured; live MusicBrainz/Cover Art Archive lookup verified for well-known tracks. Physical iPhone (iPhone 17 Pro Max) verified by the user: streaming, lock-screen controls, wired headphones, phone-call interruption, relaunch without autoplay, larger text. Bluetooth (AirPods Max) failed once and then worked; cause not reproduced, so watch for it. Stations that send an empty ICY `StreamTitle` (e.g. found via search: KCRW Eclectic 24) show the station-art fallback by design. Remaining: ʻOpihi 107.7 is absent from Radio Browser (directory coverage, Q17); long two-line titles push the Player transport below the tab bar.

User-requested UI changes (2026-10-22): Player has a pin toggle; the in-app transport is a single Play/Stop control (no Pause; lock-screen controls keep the system play/pause); a horizontal swipe on Player returns to Stations, ignoring drags on the volume slider. The signing team comes from the gitignored `Config/Local.xcconfig` (included by `Config/Signing.xcconfig`), so regeneration keeps device signing and no team ID is committed.

Native-metadata finding: AVFoundation never sends `Icy-MetaData: 1` for progressive streams, so it receives no ICY titles. `ICYTitlePoller` (generic, not station-specific) opens a short side connection about every 20 seconds, reads one `StreamTitle` and disconnects (roughly 15–20% extra data on a 128 kbps stream). HLS streams still use AVFoundation timed metadata. Ad-inserting servers (seen on a StreamOn/AdsWizz stream) open every new connection with a placeholder title such as "THIS STATION WILL CONTINUE AFTER THIS BREAK", then send the real title one slot later, so the poller reads two metadata slots and keeps the latest title.

## Product contract

Native iPhone app, iOS 18+, SwiftUI and AVFoundation, two tabs (Stations and Player), approved Grid layout with navy #173B67 accents and bold Helvetica-style typography. No login, app-added advertising or operated backend.

Fresh install: no pins and no selected station. Stations shows search and an empty-state invitation to pin results. Player prompts the listener to choose a station until one is selected. No real station names, stream URLs, curated catalog, station-specific logic or sample stations ship in the app. Directory responses and user actions supply station content.

Tap a result to play it and open Player. Pinning is a separate action; pins can be reordered. Unpinning does not stop playback. Persist pins, order and last-selected station locally; a cold launch restores them without autoplay. The user examples are manual external search checks, not fixtures or fixed station integrations.

## Implementation sequence

1. **Project and feasibility.** Create a standard Xcode iOS app and test target. Use the installed Xcode explicitly without changing global developer settings. Resolve license/signing/device setup with the user when needed. Probe directory search and AVFoundation playback/metadata using runtime-selected results; do not encode specific broadcasters into the project. If a named manual search example is absent, report it as a directory coverage issue.
2. **Directory and local library.** Implement a Radio Browser client with server discovery/failover, descriptive User-Agent, cancellable search and pagination. Search by name/call sign, with genre filtering. Use directory UUIDs as identity and persist a station snapshot including the last resolved stream URL for pins and selection. Do not merge distinct stations by display name. Persist an ordered library atomically in Application Support with a versioned Codable file; keep transient caches separate. Missing/changed directory results never silently remove pins.
3. **Playback session.** One app-scoped AVPlayer owner handles selection, loading, playing, paused, stopped, reconnecting and failed states. Configure the playback audio session, background audio, system now-playing information and remote controls. In-app control is Play/Stop (user change, 2026-10-22); system Pause/resume returns to live; Stop ends the session and retains selection. Present native system volume. Wi-Fi and cellular are allowed.
4. **Reliability.** Retry transient failures within a 30-second budget, then expose Retry. Pause/Stop and station changes cancel obsolete work. A headphone/Bluetooth output disconnection pauses. A phone-call interruption resumes only when previously playing, allowed by the system and not overridden by a user action. A directory outage preserves local pins; playback from saved URLs remains possible if the stream/network is available.
5. **Metadata and artwork.** Consume AVFoundation timed metadata, preserve raw display text and conservatively normalize artist/title. No broadcaster-specific metadata endpoint. Match via MusicBrainz and retrieve associated artwork through Cover Art Archive. Throttle MusicBrainz requests, cache hits/misses and reject responses for an outdated station/track. Clear old track artwork on a track change and show directory station artwork or a neutral placeholder during unavailable/uncertain metadata. Playback never waits for enrichment. No recognition uploads or biography UI.
6. **Grid UI and device verification.** Build the station list, search states, pin controls, mini player and full Player using the approved theme. Handle long names, Dynamic Type and VoiceOver. Show loading, empty, unavailable metadata, stopped and error states clearly. Verify the whole flow on the user's physical iPhone.

## Module boundaries

- `StationDirectory`: remote discovery and station refresh; returns provider-neutral station values with source identity.
- `StationLibrary`: ordered user pins and last selection; no networking or player ownership.
- `PlaybackSession`: audio lifecycle, route/interruption handling and system controls; publishes playback/metadata state.
- `ArtworkResolver`: catalog matching, throttling, caches and cancellation; has no authority to change playback.
- SwiftUI screens: render those states and send user intents; do not duplicate playback or persistence logic.

These are internal modules in one app target initially. Add dependencies or packages only when an actual need appears.

## Validation

- Deterministic tests with neutral synthetic station values: empty install; save/reorder/unpin/restore; selection independent of pin membership; persistence errors do not overwrite good data silently.
- Playback state tests focus on cancellation, bounded reconnect, explicit-user-action precedence and stale events rather than replaying framework implementation.
- Metadata tests cover ambiguous text, talk/program labels, missing artwork and a delayed response arriving after a track/station change. Tests do not require live external services.
- Manual physical-device checks cover search, pinning, relaunch without autoplay, streaming, lock/background playback, hardware/system controls, interruptions, route loss, network loss and accessibility.
- Check the user's station examples by typing them into generic search. Listing absence is an unresolved acceptance dependency, not proof that search works as desired and not justification for hardcoding.

## Directory coverage and setup dependencies

Q17 accepted: verified missing station listings are addressed in Radio Browser's shared directory, outside the app. Prepare and validate each concrete listing for review before any public submission. No submission has been performed. Directory coverage remains an external acceptance dependency; the app stays generic regardless of submission outcome.

The earlier environment check found an unaccepted Xcode license. License acceptance and physical-device signing/setup may require user action; report the exact step when needed. These are setup dependencies, not open product-design choices.

## Completion criteria

The implementation is complete when the app builds, focused automated checks pass, and the documented on-device acceptance flow has been verified. Clearly report any checks that cannot run because of signing, device access, service availability or directory coverage; never mark unverified device behavior as passed.

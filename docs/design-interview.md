# Free Radio — design interview

Status: design interview decisions resolved through Q17. Final build plan is ready for shared-understanding confirmation before implementation.

## Settled requirements

- Native iOS app for listening to free radio streams.
- Two primary pages: Stations and Player.
- Stations includes search and pinned stations.
- Pinned stations are saved locally. No login for this version.
- Player includes Play, Pause, Stop, and volume controls.
- Player displays station name, band/artist and song name, and album artwork when available.
- Approved visual direction: A / Grid with dark blue accents; target accent #173B67. Reference: ../design/mockups/a-grid-navy.png.
- Large, bold Helvetica-style typography inspired by DIRT title cards.
- User is a software engineer and welcomes high-level technical questions.
- Personal iPhone use is the first release goal; public App Store distribution is much later.
- The app must never introduce advertising. Broadcaster audio plays unchanged, including any embedded commercials or sponsorships (Q4 accepted).
- Use free public internet radio through generic Radio Browser search. The user's examples (ʻOpihi 107.7, KCBX, national NPR) are external search-validation queries, not bundled content or specially supported stations.
- Explicit correction superseding Q5 and the original Q11 proposal: no default pins, bundled/curated station catalog, hardcoded station names/URLs, station-specific metadata adapters, or special-case behavior. Station information enters the app through directory responses and user selections only.
- First launch has an empty pin list and no selected station. Pins are created only by the user.
- Include background playback and lock-screen/headphone controls in v1.
- Accepted stack: SwiftUI + AVFoundation, iPhone first, iOS 18+, no backend operated by us.
- Accepted playback semantics: Pause resumes at the current live broadcast; Stop ends the playback session while retaining station selection. No recording or time shifting in v1.
- Accepted metadata pipeline: Radio Browser → stream-provided metadata through AVFoundation → MusicBrainz matching → Cover Art Archive artwork. Station branding is the fallback. Audio recognition is deferred.
- Accepted volume behavior: native system output volume, consistent with hardware buttons.

## Design tree

- Approved product and visual scope
  - Release target and audience: settled — personal iPhone first
    - Deployment baseline: iPhone, iOS 18+, personal installation first
    - Acceptance criteria: generic search/player, persistence, background controls and metadata fallback, with user examples checked through search
    - Physical-device signing/setup: implementation prerequisite
  - Radio source intent: generic free public internet radio
    - Provider selection: Radio Browser; no bundled catalog or station-specific integration
    - Directory coverage of user examples: external dependency; Q17 accepts corrections in the shared directory outside the app
    - Search, pin persistence, unavailable stations and service failures: accepted in round 3
  - Background and system playback scope: settled — background, lock-screen and headphone controls included
    - Pause/Stop semantics and system volume: accepted
    - Interruption, route-change and reconnection policies: accepted in round 3
  - Metadata/artwork direction: stream metadata plus external music-database enrichment accepted
    - MusicBrainz/Cover Art Archive and station fallback: accepted
    - Metadata matching and stale-response handling: specified below; validate during implementation
  - Local development toolchain: Xcode installed, license acceptance blocks simulator enumeration
    - App architecture: SwiftUI + AVFoundation, no operated backend
    - Project setup and validation approach: pending

## Round 1 — accepted

1. Personal iPhone MVP; public App Store release much later. User additionally requires no ads ever.
2. Free public internet radio. User specifically wants ʻOpihi 107.7 or NPR. Provider selection awaits targeted station verification.
3. Background playback and lock-screen/headphone controls in v1.

## Technical findings

- Radio Browser is a candidate free station directory with station UUIDs, resolved stream URLs, search and station logos. It does not supply current artist/song/album artwork and does not guarantee uptime. [API](https://docs.radio-browser.info/)
- Stream-carried metadata can be consumed through Apple's timed-metadata APIs, subject to what a broadcaster sends. [Apple](https://developer.apple.com/documentation/avfoundation/avplayeritemmetadataoutput)
- Background playback and system controls are supported by native audio APIs. [Background audio](https://developer.apple.com/documentation/avfoundation/configuring-your-app-for-media-playback), [Now Playing info](https://developer.apple.com/documentation/mediaplayer/mpnowplayinginfocenter)
- Local exploration found Xcode 27.1 at /Applications/Xcode.app. The active developer directory points at CommandLineTools. A per-command DEVELOPER_DIR override finds Xcode, but the unaccepted license blocks simulator enumeration. No license was accepted and no system settings were changed.
- The [official station owner](https://hawaiiradio.com/) links ʻOpihi 107.7 to its [KOPI online player](https://listen.streamon.fm/kopi). That player's public configuration exposes an HLS stream and metadata endpoint. Native playback has not yet been tested.
- A preliminary Radio Browser query for `opihi` returned no matches on one server; this does not establish absence across all aliases or servers. App-local fallback entries are now explicitly excluded. Discovery of a missing station requires a directory correction or a future provider decision.
- The [NPR Program Stream explanation](https://www.vpm.org/npr-news/2016-04-05/npr-program-stream/) distinguishes its repeating recent-program feed from member stations' live broadcasts. User requires both national NPR and local member stations, specifically KCBX.
- KCBX documents official online listening on its [Ways to Listen page](https://www.kcbx.org/streaming-kcbx). This verifies streaming availability, not successful native playback or directory coverage.

## Round 2 — accepted

- Q4 resolved: no app-added advertising; broadcaster audio remains unchanged.
- Q7 accepted: SwiftUI and AVFoundation, iPhone first, iOS 18+, no operated backend.
- Q8 accepted: resume at current live broadcast after Pause; Stop ends the session but retains station selection. No recording/time shifting.
- Q9 revised and accepted: MusicBrainz + Cover Art Archive for best-effort artwork enrichment, with station branding fallback. Audio recognition deferred.
- Q10 accepted: system output volume.
- Q5 superseded by round 3: Radio Browser search only, without an app-maintained station catalog or station-specific code.
- Q6 clarified by round 3: support finding both national and local stations through generic search; named stations are user-supplied examples only.
- User explicitly answered yes to all Q7–Q10 recommendations on 2026-10-22.
- Provider follow-up: alternative directories list ʻOpihi, but no alternative free supported API returning it has been verified. Radio Browser does return KCBX. See [directory research](radio-directory-alternatives.md). Q17 accepts community-directory corrections outside the app, with a concrete submission prepared for review first. None has been submitted.

## Accepted metadata pipeline — 2026-10-22

User has selected the overall direction: discover a station, read its now-playing text, and enrich identified tracks with artwork. See [primary-source research](metadata-pipeline-research.md).

Native flow: Radio Browser stream URL → AVFoundation playback/timed metadata → conservative track normalization → MusicBrainz recording/release matching → Cover Art Archive artwork → player and system now-playing display.

MusicBrainz and Cover Art Archive are accepted dependencies. Prefer structured metadata/artwork carried by a stream when available. Validate native delivery on representative streams found through directory search before deciding whether a generic protocol fallback is needed. No station-specific metadata endpoints or adapters. Do not assume all streams carry ICY, or that every stream sends a usable artist/title.

Reliability behavior: audio continues independently of enrichment; retain raw broadcaster text, avoid treating talk/program text as a song, clear previous artwork when the item changes, reject stale lookup responses, cache results, and throttle MusicBrainz to its documented rate. When identification or artwork is unavailable, show station branding. Recognition uploads, biographies, genre and release-year UI are outside v1.

## Round 3 — accepted with corrections

- Q11 rejected and replaced: start with no pinned or selected stations. No specific-station references in app source, resources, defaults, migration rules, live test fixtures or metadata handling. Dynamic directory data and user-saved stations are allowed. No curated fallback catalog. Community submissions remain external, separate and unperformed.
- Q12, station interactions: search by name/call sign with genre filters; tapping a station starts it and opens Player; pin/unpin is a separate action. Support drag-to-reorder pins. Unpinning the playing station does not stop audio.
- Q13, persistence and launch: retain pins/order and last-selected station locally across launches. Cold launch restores context without autoplay. These local preferences do not mean downloaded or offline audio.
- Q14, connection failures: allow cellular and Wi-Fi; show buffering/reconnecting state, retry transient failures for up to 30 seconds while playback remains requested, then show Retry. Explicit Pause/Stop cancels reconnect. Preserve pins during directory outages; cached stream URLs can still be attempted when networking works.
- Q15, interruptions: pause on headphone/Bluetooth disconnection; after a phone-call interruption, resume only if playback was active, the system permits it, and the user has not paused/stopped meanwhile.
- Q16 corrected: user can search for stations, including the examples they gave, through the directory. No fixed set of required station integrations. Generic search, selected-stream playback, background/system controls, persistence, metadata/artwork enrichment and fallbacks, network/route-change behavior, and Grid/navy UI with larger text and VoiceOver form the milestone. No CarPlay-specific UI, recording, sleep timer or cross-device sync in v1.

## Round 4 — accepted

Q17 accepted: handle verified missing entries through Radio Browser's shared directory, outside this app. Prepare and validate any concrete public submission for review before sending. No submission has been performed. App behavior for missing results is an honest empty state with spelling/retry guidance, never a hidden station-specific fallback.

Design frontier is empty. Build plan: [implementation sequence](build-plan.md). Await final shared-understanding confirmation before implementing, per the invoked grilling skill. Environment prerequisites and external directory coverage are tracked as build dependencies rather than unanswered design choices.

## Interview procedure

Resolve independent decisions in rounds, document accepted answers, and advance dependent questions only after prerequisites settle. Create ADRs only for consequential trade-offs that merit one. Confirm shared understanding before implementing.

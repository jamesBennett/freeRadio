# Metadata configuration

MusicBrainz requires each application request to include a descriptive User-Agent with enough information to contact the application maintainer. The app target's Info.plist sets `FreeRadioMusicBrainzContact` to the maintainer's MusicBrainz profile, https://musicbrainz.org/user/freeRadioMusic. Use a real maintainer email address or support/project URL; do not ship a placeholder.

When this key is missing, blank, too long, or contains control characters, Free Radio skips MusicBrainz searches. Station artwork URLs continue to work as the fallback. Once configured, requests identify the app as `FreeRadio/0.1 (iOS; contact: <configured value>)` and share a one-request-per-second limiter.

The image and MusicBrainz response bodies are streamed with size caps. Artwork cache entries are bounded to 40 keys and 20 MB total, with successful values and misses cached separately by key.

See the [MusicBrainz API rate limiting guidance](https://musicbrainz.org/doc/MusicBrainz_API/Rate_Limiting) for the current User-Agent and request-rate requirements.

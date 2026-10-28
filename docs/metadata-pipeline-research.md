# Metadata and artwork enrichment research

Checked 2026-10-22 against primary sources. Research only; pipeline direction accepted, but provider selection, recognition opt-in, and fallback behavior remain pending. No credentials created, audio uploaded, or implementation performed.

## What the proposed pipeline does

Once a stream supplies usable artist/title text, MusicBrainz can search its **recording** catalog. A recording may appear as tracks on multiple **releases**; a release is a particular edition, while a release group groups editions. Cover Art Archive (CAA) then retrieves art by **release or release-group MBID**, not recording MBID. Sources: [search API](https://musicbrainz.org/doc/MusicBrainz_API/Search), [recording model](https://musicbrainz.org/doc/Recording), [release model](https://musicbrainz.org/doc/Release), [CAA API](https://musicbrainz.org/doc/Cover_Art_Archive/API).

**Engineering inference:** Artist/title lookup is catalog matching, not acoustic fingerprinting. Without usable stream text it cannot identify the audio. Even a correct recording match does not tell us which album edition the broadcaster used. Returned art should be treated as associated cover art, not a verified broadcast album. CAA documents missing-image responses and community-selected representative release-group artwork; availability is best effort. [CAA API](https://musicbrainz.org/doc/Cover_Art_Archive/API)

## MusicBrainz and Cover Art Archive

- The hosted MusicBrainz web service is free for noncommercial use; commercial service use is handled separately. Public metadata lookup needs no API key. [API FAQ](https://musicbrainz.org/doc/MusicBrainz_API/FAQ)
- Keep MusicBrainz requests at **one per second or less** and identify the app with a meaningful User-Agent including contact information, preferably app/version. Rate limiting includes source-IP checks, and overload can return HTTP 503. [API](https://musicbrainz.org/doc/MusicBrainz_API), [rate limits](https://musicbrainz.org/doc/MusicBrainz_API/Rate_Limiting)
- Distinguish **data licensing** from **hosted service access**: core MusicBrainz data is CC0; supplementary data is CC BY-NC-SA 3.0. The MusicBrainz dataset does not include cover art. [Data licenses](https://musicbrainz.org/doc/About/Data_License)
- CAA is a separate publicly accessible artwork repository. Its policy warns that images remain subject to artists' and labels' rights; accessibility does not establish a blanket image-reuse license. This note makes no conclusion about a particular use. [CAA policy](https://musicbrainz.org/doc/Cover_Art_Archive)
- CAA supports front thumbnails at 250, 500, and 1200 pixels, redirects, and 404/503 outcomes. Do not assume the MusicBrainz numerical rate limit also defines CAA's rate limit. [CAA API](https://musicbrainz.org/doc/Cover_Art_Archive/API)

## Native stream metadata

Apple provides [AVPlayerItemMetadataOutput](https://developer.apple.com/documentation/avfoundation/avplayeritemmetadataoutput) for timed metadata and an [ICY stream-title identifier](https://developer.apple.com/documentation/avfoundation/avmetadataidentifier/icymetadatastreamtitle). Start with native callbacks and probe each target station before considering a custom parser; this is an implementation recommendation, not a guarantee that every stream supplies usable fields.

Icecast's [MP3 format implementation](https://raw.githubusercontent.com/xiph/Icecast-Server/master/src/format_mp3.c) checks the client's `icy-metadata` request header, responds with `icy-metaint`, and encodes metadata block lengths as a byte multiplied by 16. `StreamTitle` is raw text, not guaranteed separate artist/title fields. HLS should use native timed metadata handling rather than assuming ICY byte framing applies to every stream. These findings were independently supplied by the parent research task.

## Last.fm

- `track.getInfo` accepts artist/title or MBID, requires a **developer API key**, and does **not** require listener authentication. Its example contains album information and image URLs, but an example is not a completeness guarantee. [Method documentation](https://www.last.fm/api/show/track.getInfo)
- Current API terms permit noncommercial data use subject to restrictions and require a separate commercial agreement for commercial use. They also require attribution/links, prescribe caching according to response headers, and impose a 100 MB reasonable-usage cap. Critically, **§5.1.8 excludes images/artwork from the agreement**, despite image fields in method examples. Therefore, do not treat Last.fm as an automatically cleared artwork provider. These are scoped observations about the published terms, not a legal determination. [API terms](https://www.last.fm/api/tos)

## ACRCloud

ACRCloud recognizes audio using fingerprinting, which is a different capability from artist/title catalog lookup. Its current terms specify a default **14-calendar-day trial**, possibly ending earlier at its quota, unless otherwise stated. Signup/order terms control; ongoing free recognition usage has not been verified. Do not label it a free ongoing fallback. [Service description](https://www.acrcloud.com/pricing/), [terms §17.1](https://www.acrcloud.com/terms/)

## Suggested implementation constraints, pending decision

Keep playback independent of enrichment. Trigger a lookup only when usable track text changes; cache successful and missing results, throttle requests, and ignore late results after station/track changes. Preserve the broadcaster's display text. Prefer a confidently associated artwork candidate; otherwise show station branding. Handle ambiguous names, talk segments, missing metadata, unavailable art, and service errors without interrupting audio. A later public release should revisit provider access and artwork terms; ad-free distribution alone does not settle those questions.

# Radio directory alternatives

Research date: 2026-10-21. Scope: alternatives to Radio Browser for finding ʻOpihi 107.7 / KOPI through a supported API usable by a personal native iOS app.

## Findings

| Service | ʻOpihi listing | Supported developer access verified | Implication |
| --- | --- | --- | --- |
| Online Radio Box | Yes: [ʻOpihi 107.7](https://onlineradiobox.com/us/opihi1077/?lang=uk) includes station information and playlist. | No public directory API documentation or free third-party client access was verified. Its [terms, sections 4 and 4.1](https://onlineradiobox.com/terms?lang=en), restrict content reuse and say audio may be streamed only through the player embedded in or facilitated by its service. | A confirmed consumer listing is not evidence of an integration we can adopt. Do not use its internal endpoints as a supported API. |
| Streema | Yes: [ʻOpihi 107.7 – KOPI](https://streema.com/radios/Opihi_107.7_KOPI). | No supported public API or free third-party client access was verified. Its [current English About page](https://streema.com/about/) describes the website and Simple Radio apps, with no developer program. The [French About page](https://fr.streema.com/about/) contains older wording about considering an API; this is not proof of current availability. | Another confirmed listing, but no verified replacement API. The lack of found documentation does not establish that no partner API exists. |
| radio.net | No ʻOpihi listing was verified in this search. | Its official [broadcaster page](https://corporate.radio.net/Broadcasters/) offers a metadata **push** API with access requested by email. This sends artist/song metadata **to** radio.net; it is not documented as a station discovery API for clients. Its [linking agreement](https://corporate.radio.net/linking-agreement-terms-conditions/) describes partners using its databases with permission. | No verified free self-service directory API suitable for this app. Do not confuse the push API with directory search. |
| SHOUTcast | Not verified. | Its [official API page](https://directory.shoutcast.com/Developer) explicitly supports integrating radio stations into iOS/Android apps and links API documentation. It asks prospective API partners to submit company and application details. | A real integration candidate, but this research has not verified ʻOpihi coverage, current free personal-use terms, or ability to obtain access without a partner application. |

Online Radio Box also has a [KCBX listing](https://onlineradiobox.com/us/ksbx/?lang=en), but the retrieved page describes the Santa Barbara 89.5 MHz relay and reports unavailable playback. This reinforces that catalog presence alone does not verify a working, current stream. KCBX's own [Ways to Listen page](https://www.kcbx.org/streaming-kcbx) confirms current streaming via its app, NPR app, and Apple Music; these consumer options do not by themselves establish a developer API.

## Answer supported by this research

Additional primary-source and live API checks:

- [TuneIn's developer documentation](https://developer.tunein.com/cfp_login) describes assigned partner IDs, certification and a production agreement. This is not verified free self-service access. ʻOpihi coverage was not verified.
- Radio Browser live read-only requests to [opihi](https://de1.api.radio-browser.info/json/stations/byname/opihi) returned an empty array; [kopi](https://de1.api.radio-browser.info/json/stations/byname/kopi) returned unrelated international stations. This is a limited name/call-sign check on one mirror, not proof of absence under every alias.
- [KCBX](https://de1.api.radio-browser.info/json/stations/byname/kcbx) returned `KCBX San Luis Obispo, CA`, station UUID `f5f2e8cf-6f71-4ff3-9054-2b1da6a82e10`, stream `https://kcbx-ice.streamguys1.com/kcbx-hi`, and `lastcheckok=1`. This confirms a directory entry and its reported health; native playback remains untested.
- [Online World Radio's published API documentation](https://github.com/AnowHosting/online-world-radio-api) advertises a free unauthenticated station search. The documented `https://onlineworldradio.com/api/v1/stations?q=opihi` endpoint returned HTTP 404 during this check. No coverage or usable integration was verified.
- Radio Browser documents an [add-station endpoint](https://docs.radio-browser.info/#add-radio-station). A simpler proposed alternative to a private catalog is to validate ʻOpihi's official stream, then submit the missing listing to the community directory. No submission has been made; this is a proposal, not an accepted design change.

Other directories definitely list ʻOpihi. This research did **not** establish another free, documented, supported directory API that returns ʻOpihi and is ready for use in our native client. We should distinguish those two claims when answering the user. No account, contact request, station submission, or other external mutation was performed.

## Limits

This is a targeted documentation and public-listing review, not an exhaustive inventory of all services. A listing was not treated as proof of stream availability or permission for a third-party client. No conclusion is drawn that an undocumented/private partner API does not exist. The English Online Radio Box station page failed to fetch; its localized first-party listing was available through search indexing.

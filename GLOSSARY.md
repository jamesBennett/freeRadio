# Free Radio

A radio listening app for finding stations, keeping a personal selection, and controlling playback.

## Language

**Station**:
A named radio broadcaster or channel that a listener can select and listen to.
_Avoid_: Track, song

**Pinned station**:
A station the listener has explicitly saved to their personal selection; the selection is empty until the listener adds stations.
_Avoid_: Favorite, bookmark

**Player**:
The app's listening screen showing the selected station, available song information and artwork, and playback controls.

**Track**:
An individual song broadcast by a station, distinct from the station itself.

**Artwork**:
The album cover associated with a track, when available.
_Avoid_: Station logo

**Station directory**:
A searchable catalog of stations and their listening information, distinct from the broadcasters that supply the audio.

**Now-playing metadata**:
Information supplied about the content currently being broadcast, which may identify a song, a program, or only the station.
_Avoid_: Guaranteed song identity

**Metadata enrichment**:
Additional information matched to the reported artist and track, such as an album cover, from a music catalog.
_Avoid_: Audio recognition

**Audio recognition**:
Identification of a recording from a sample of its sound rather than from the broadcaster's text.
_Avoid_: Metadata extraction

**Pause**:
A listening state that retains the current playback session while silencing it; resuming returns to the current live broadcast.
_Avoid_: Time shifting, recording

**Stop**:
Ending the playback session while retaining the selected station for future listening.

**Live broadcast**:
The station's current continuous output, subject to normal streaming delay rather than an exact real-time guarantee.

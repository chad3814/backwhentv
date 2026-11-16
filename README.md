# BackWhenTV for tvOS

A native Apple TV front end for [backwhen.stream/tv](https://www.backwhen.stream/tv/):
a 24/7 cable-style guide, archive television from the Internet Archive, a
WeatherStar-style weather channel, and commercial breaks between shows.

The app is a thin client over the same public JSON the website uses. It computes
what should be on right now, tunes into the middle of that programme, and rolls
into the next one on the schedule.

## What it does

- Full-screen **cable guide** with a selected-channel preview showing the
  channel, now playing, elapsed/remaining time, up next, and an optional
  programme overview from OpenMetadata
- Tunes into the live point of each programme (not always from the start)
- **Channel surfing** with the remote, plus a channel banner with clock
- Weather channel: local conditions, forecast, extended forecast, alerts,
  radar still, and the smooth-jazz schedule playing underneath
- Rebuilds the site's **commercial pods** deterministically (stingers, sponsor,
  trivia, donation ask) so a mid-break tune-in lands in the same spot
- Falls back from an Archive storage node to `archive.org/download` when a node
  is down, and skips a broken file instead of getting stuck
- Refreshes the rolling six-hour schedule every 45 minutes and on foreground
- Remembers the last channel and restores it on launch

## Requirements

- Xcode 16 or newer (developed against Xcode 27 / tvOS 27 SDK)
- tvOS 17.0+ deployment target
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) if you want to regenerate
  the project after adding or moving files (`brew install xcodegen`)

## Run it

```sh
# Only needed when project.yml or the file layout changes.
xcodegen generate

open BackWhenTV.xcodeproj
```

Choose the **BackWhenTV** scheme and an Apple TV simulator or a device, then Run.

For a physical Apple TV, select the app target → Signing & Capabilities and pick
your development team. The bundle identifier is `stream.backwhen.tv`; change it
if it collides with anything on your account.

### Command line

```sh
# Build for the simulator
xcodebuild -project BackWhenTV.xcodeproj -scheme BackWhenTV \
  -sdk appletvsimulator -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build

# Unit + UI tests
xcodebuild -project BackWhenTV.xcodeproj -scheme BackWhenTV \
  -sdk appletvsimulator -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO test
```

## Controls

| Remote | Action |
| --- | --- |
| **Menu** | Open the guide (press again to close) |
| **Select** | Open the guide, or tune the focused channel |
| **Up / Down** | Surf channels while watching; browse rows in the guide |
| **Play / Pause** | Pause, and resume at the live point when pressed again |
| **Home** | Leave the app |

## How it works

All data comes from the public endpoints behind `https://www.backwhen.stream`:

| Endpoint | Used for |
| --- | --- |
| `/api/lineup` | Channel numbers, names, and kinds |
| `/api/schedules?pods=1&hours=6` | Rolling six-hour programme grid with an anchor |
| `/clips/manifest.json` | Stinger, sponsor, trivia, and donation clips |
| `/api/weather`, `/api/weather/extra` | WeatherStar pages |

The schedule is a fixed list of items that repeats from a per-channel anchor.
To find what is on at time `t`:

```
total = sum(item.duration)
position = ((t - anchor) mod total + total) mod total
```

Walk the items until `position` falls inside one; the remainder is the seek
offset. The player seeks there, then advances to the next item when the file
ends or when the scheduled end time arrives (whichever comes first), so a file
whose real duration differs from the guide does not drift the channel.

Commercial pods are flagged with `a: 1`. Instead of playing the single stinger
URL in the grid, the app builds the same pod the website does, seeded by
`channelID:podStartTime`, so every viewer sees the same break. The generator is
a straight port of the site's mulberry32 logic and is covered by fixture tests.

The app intentionally filters to `kind == "ia"` and `kind == "weather"`, matching
the browser player. Pluto's live channels are excluded by the website because
their streams are only available to Pluto's own TV clients; the `board` channel
is just an external donation link. Channels with no schedule in the current
window are hidden.

Playback uses `AVPlayer` directly with a custom overlay, so the app can show its
own guide and banner instead of tvOS's standard transport controls. All media
and API traffic is HTTPS.

### Usage reporting

The app submits the same anonymous viewing stats as the web player to
`POST /api/ev`: on launch, every five minutes, and when it leaves the
foreground. The body is:

```json
{"id":"b42c19c4483d004fd947c5bb","p":"appletv","v":"1.0","r":"","w":{"ia-kids-wb":5}}
```

- `id` is 12 random bytes rendered as 24 lowercase hex characters, generated on
  first use and stored in the app's `UserDefaults`.
- `p` is always `appletv`; `v` is `CFBundleShortVersionString`; `r` is empty.
- `w` maps channel ids to minutes watched, using the same rounding as the web
  player (a partial minute rounds to the nearest minute).
- Switching channels flushes the current channel first. Pausing and leaving the
  foreground stop the clock, so idle time is not counted.
- If a report fails, the minutes stay queued and are included in the next
  attempt.

### Programme metadata (optional)

With an OpenMetadata API key, the guide preview also shows a short overview of
the selected programme. The key is never stored in the repository.

1. Put the key in `open-metadata-api-key` at the repository root. That path is
   ignored by git.
2. Generate the ignored local build setting:

   ```sh
   ./Scripts/make_local_config.sh
   ```

   This writes `Config/Local.xcconfig`. `Config/Base.xcconfig` includes it
   optionally and exposes the value as `OPEN_METADATA_API_KEY`, which is
   substituted into the app's `Info.plist` at build time.
3. Rebuild the app.

Without `Config/Local.xcconfig` the app builds normally and simply skips
metadata. The key is embedded in any app you build, so do not distribute an
archive made with it.

When a schedule is loaded or refreshed, the app queues the current and next
non-advert programme for every non-weather channel. Titles matching
`S[0-9]+E[0-9]+` are looked up as `tv`; everything else as `movies`. Requests go
to `POST https://openmetadata.nexus/api/v1/lookup` in batches of at most 100
with a bearer token. Cleanups such as `RETRO SHORT |` and pipe separators are
removed first.

The lookups send only the programme title and category to `openmetadata.nexus`;
no viewing ID or channel minute data is included.

A returned overview is accepted when the lookup is `resolved`, or when it is
`unresolved` with at least `0.4` confidence and a non-empty overview; low
confidence candidates are ignored. Partial (`202`) answers are polled via
`/api/v1/lookup/{id}`. The queue uses one worker, pauses between batches, and
honours `Retry-After` on `429`. Misses are remembered for the session so the
guide does not repeatedly ask for the same title. The overview replaces the
channel blurb in the guide's preview card while it is focused.

## Project layout

```
BackWhenTV/
  BackWhenTVApp.swift        App entry point
  RootView.swift             Screen composition, focus, remote actions
  Models/Models.swift        Lineup, schedule, clips, weather, derived types
  Services/
    APIClient.swift          JSON endpoints
    GuideStore.swift          Loads/refreshes data; answers "what's on now?"
    ScheduleEngine.swift      Anchor/offset maths and next-program lookup
    PodPlanner.swift          Deterministic commercial pod generator
    PlayerController.swift    AVPlayer, seeking, pods, fallbacks, deadlines
    UsageReporter.swift       Anonymous channel-minute reporting to /api/ev
    MetadataStore.swift       Queues OpenMetadata lookups and caches overviews
    OpenMetadataClient.swift  openmetadata.nexus lookup and polling client
  Views/
    GuideView.swift           Guide grid and focus styling
    BannerView.swift          Channel banner, loading card, no-signal card
    WeatherOverlay.swift      WeatherStar pages
    PlayerLayerView.swift     AVPlayerLayer wrapper
    RemoteSurface.swift       Focusable surface that owns remote commands
    SplashView.swift          Tuning/error screen
    Theme.swift               Colors, condensed type, shared bits
  Assets.xcassets/            App icon and top shelf art
Config/Base.xcconfig          Optional include for the ignored local key
BackWhenTVTests/             Schedule, pod, metadata, and decoding tests
BackWhenTVUITests/           Remote-driven guide smoke test
Scripts/make_artwork.py      Regenerates the icon and top shelf PNGs
Scripts/make_local_config.sh Generates Config/Local.xcconfig from the key file
```

## Tests

- `ScheduleEngineTests` covers slot lookup, wrapping, negative anchors, and
  skipping commercial pods in the "up next" column.
- `PodPlannerTests` pins the generator to output calculated from the website's
  own JavaScript, so the two stay in sync.
- `ModelDecodingTests` covers the live JSON shape, including optional fields.
- `UsageReporterTests` covers id generation/persistence, payload shape, minute
  rounding, channel attribution, and retry behaviour when a report fails.
- `MetadataStoreTests` covers title cleanup, episode/movie categorisation,
  request shape, result filtering, batching, deduplication, and misses.
- `GuideNavigationUITests` launches the app in the simulator, waits for the
  weather channel, opens the guide with Menu, tunes a channel, surfs with Up,
  pauses/resumes, and checks Select also opens the guide.

The UI test hits the live service. If it runs at a moment when the lineup has
changed, adjust the expected channel names in
`BackWhenTVUITests/GuideNavigationUITests.swift`.

## Notes and limitations

- This is live TV: there is no DVR, scrubbing, or on-demand catalogue.
- The guide is a rolling six-hour window. If the service is unreachable for more
  than six hours, the last schedule keeps looping until a refresh succeeds.
- Weather is fixed to the location the website serves (Maquoketa, Iowa).
- A broken media URL shows `NO SIGNAL` for two seconds and skips to the next
  scheduled item.
- Unofficial client. Channel names, programme data, and video belong to their
  respective owners; the Internet Archive supplies the media.

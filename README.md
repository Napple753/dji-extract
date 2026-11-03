# DJI Extract

Personal iOS app that cuts photos, Live Photos and short videos out of Osmo Action 6
recordings over USB-C and saves them to Photos with the capture time of the cut frame.

> This repository is public only so it can use GitHub Actions for free. It is built for my own
> use and is not intended for use by anyone else; no support, issues or pull requests are expected.

Spec: [docs/spec.md](docs/spec.md).
Sample footage verification: [docs/findings.md](docs/findings.md).

## Capture time

```
T_capture = creation_time + startLatency + t + Δ
```

- `creation_time` is the UTC start of the file (measured, see findings).
- `startLatency` = 1.7 s for Osmo Action 6 (measured from a clock recording).
- `t` is the position of the frame in the main file, `Δ` the per-video user offset (default 0).
- The time zone only affects EXIF offsets and display; it defaults to the iPhone's current zone
  and can be changed per video.

## Layout

| Path | Contents |
| --- | --- |
| `Sources/DJIExtractCore` | Pure logic (Foundation only): `CaptureTimeCalculator`, timestamps, LRF time mapping, Live Photo range, DCIM file pairing |
| `Sources/DJIExtractKit` | Media: `VideoMetadataReader`, `FrameExporter`, `LivePhotoExporter`, `ClipExporter`, `PhotoLibrarySaver`, `CameraLibrary`, thumbnails, LRF preview |
| `Sources/DJIExtractUI` | SwiftUI screens (connect, list, editor, save, log) |
| `App/` | iOS app entry point |
| `project.yml` | XcodeGen spec for `DJIExtract.xcodeproj` |

## Tests

```sh
swift test    # Core + Kit tests on macOS; Kit tests use the sample footage at the repo root
```

The sample `DJI_20261102220407_0073_D.MP4` / `.LRF` are not committed. Kit tests that need
them are skipped when they are missing. The same tests also pass on the iOS Simulator
(`xcodebuild test -scheme DJIExtract-Package`, run from a copy of the package without
`DJIExtract.xcodeproj`, since xcodebuild prefers the project when both exist).

## Building

The app is built on GitHub Actions ([.github/workflows/build.yml](.github/workflows/build.yml)), since
a local Xcode build needs more memory than the development Mac has. Every push to `main`, pull
request and manual run (Actions > Build > Run workflow) does two jobs:

- `test`: `swift test` (Kit tests needing the sample footage are skipped).
- `ipa`: `xcodegen generate`, then an unsigned Release build for devices, uploaded as the
  `DJIExtract-unsigned-ipa` artifact (kept 14 days).

`DJIExtract.xcodeproj` is generated and not committed. To build locally anyway:

```sh
xcodegen generate
xcodebuild -project DJIExtract.xcodeproj -scheme DJIExtract -destination 'generic/platform=iOS Simulator' build
```

## Installing on the iPhone

A free Personal Team cannot sign in CI, so the IPA is signed on install with your Apple ID.

With the iPhone connected and unlocked, run:

```sh
scripts/install-latest.sh [run-id]
```

It downloads the IPA from the latest successful Build run on main (or the given run),
signs it with the newest unexpired Xcode provisioning profile for `xyz.napple.DJIExtract`
and its certificate from the keychain, and installs it with `devicectl`. The profile comes
from building the app once from Xcode with the Personal Team; when it expires (7 days),
build from Xcode again to renew it.

Manual alternative:

1. Download `DJIExtract-unsigned.ipa` from the latest successful Build run
   (`gh run download -n DJIExtract-unsigned-ipa`).
2. Sign and install it with a sideloading tool such as Sideloadly, using your Apple ID
   (the same one as the Personal Team). Keep the bundle ID `xyz.napple.DJIExtract`.
3. Enable Developer Mode on the iPhone and trust the developer in
   Settings > General > VPN & Device Management.
4. The free-account signature expires after 7 days; sign and install again to renew.
5. Debugger access is not available this way; use the in-app Log screen.

## Status

Implemented: everything in the spec's first version, verified on macOS and the iOS Simulator
against the sample footage (metadata, HEIC/EXIF, lossless and accurate clips, Live Photo files).
The app builds for the simulator and for devices (unsigned, in CI). Not yet verified on device:
USB folder access, playback, Photos saving, Live Photo playback in Photos, cable-pull handling.

Open items:

- Re-measure `startLatency` with more clock recordings (single sample so far).
- Split recordings (no sample yet).
- HDR / 10-bit to SDR conversion for stills (currently AVFoundation's `forceSDR`).
- Live Photo length (fixed at 3 s for now).

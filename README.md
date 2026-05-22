# Mirror

A continuous security-camera recorder for macOS. Mirror captures your built-in
(or external) camera and microphone and writes rolling, time-stamped MP4
segments to a folder you choose, automatically pruning old clips. It ships as a
lightweight menu bar app plus a set of shell scripts you can run headlessly at
login.

> **Note:** the green camera indicator light is a hardware feature on Macs and
> **cannot** be disabled. It will be lit the entire time Mirror is recording.

## Install

```sh
brew install emerytech/mirror/mirror
```

This installs:

- `Mirror.app` — the menu bar app (start/stop, settings, recordings folder).
- `mirror-record`, `mirror-status`, `mirror-prune` — the underlying scripts.
- [`ffmpeg`](https://ffmpeg.org/) as a dependency.

Homebrew prints the path to `Mirror.app` after install; open it with `open`
(see the caveats brew shows, or run `brew info mirror`).

## Usage

### Menu bar app

Launch `Mirror.app`. The menu bar icon lets you start/stop recording, open the
recordings folder, and configure quality, segment length, retention, camera,
microphone, and launch-at-login. macOS will prompt for camera and microphone
permission on first record.

### Headless (record at login, no UI)

To run the recorder as a background service that starts at login:

```sh
brew services start mirror
```

Stop it with `brew services stop mirror`. Check what's happening with:

```sh
mirror-status
```

## Configuration

The scripts read these environment variables (the menu bar app sets them for
you):

| Variable                 | Default                     | Meaning                          |
| ------------------------ | --------------------------- | -------------------------------- |
| `MIRROR_DIR`             | `~/Documents/SecurityCam`   | Where clips are written          |
| `MIRROR_VIDEO`           | `FaceTime HD Camera`        | Capture device name              |
| `MIRROR_AUDIO`           | `MacBook Pro Microphone`    | Mic name (empty = video only)    |
| `MIRROR_SEGMENT`         | `600`                       | Segment length in seconds        |
| `MIRROR_FPS`             | `30`                        | Frame rate                       |
| `MIRROR_BITRATE`         | `4000k`                     | Video bitrate                    |
| `MIRROR_RETENTION_DAYS`  | `3`                         | Days of clips to keep            |

## Build from source

```sh
git clone https://github.com/emerytech/homebrew-mirror.git
cd homebrew-mirror
./menubar/build.sh        # produces menubar/Mirror.app
```

To install the headless LaunchAgents from a source checkout:

```sh
./install.sh              # uninstall with ./uninstall.sh
```

## License

[MIT](LICENSE)

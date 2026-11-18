# Front Tire Guides

Howdy all,

The 2025 Bronco Sport has Trail View, with tire guides on the front camera that show where the front tires will go as
you turn the wheel. Earlier trucks don't have it. This mod adds tire guides to the front camera of 2021 and later
Bronco Sports with SYNC 3. Two tracks of tread blocks follow the steering wheel, and the part hidden under the bumper
is drawn in orange. They work in the normal front view and the 180 degree split view.

## What you need

- A Bronco Sport with the factory front camera and SYNC 3.4, build **22110, 22200, 22251, 23088, 23188 or 26057** (Settings >
  General > About SYNC). The installer refuses any other.
- The F-Mods jailbreak with **FMods Tools 2.8 or newer**.
- A FAT32 USB stick.

## Install

1. Download the zip from the [Releases](https://github.com/Trist0ne/front-tire-guides/releases) page, or build it
   yourself (see Building below). Copy `DONTINDX.MSA` and the `SyncMyMod` folder to the top of an empty FAT32 stick.
   Use one stick per mod, since every F-Mods mod uses a folder called `SyncMyMod`.
2. With the truck PARKED and the engine running, plug the stick into SYNC and wait for the screen to say it's
   installed. Don't switch the truck off or pull the stick before then.
3. Pull the stick out. SYNC restarts.

To remove the mod, do the same with the uninstall zip and SYNC's original files go back in place. If you build it
yourself, `./build.sh --uninstall` makes the uninstall stick.

## Using it

To turn the guides on or off from the camera view, tap the menu button at the top left of the camera picture and use
the Tire Guides button. It's lit when they're on.

The rest of the settings are under Settings > Vehicle > Driver Assistance > Front Camera:

| Setting | What it does |
|---|---|
| Tire Guides | Turns the guides on or off, same as the button in the camera view. |
| Lift Offset | How much taller than stock your truck sits, from Stock to +4 inches in quarter-inch steps (see below). |
| Line Brightness | From light grey (70%) to full white (100%). Starts at 95%. |
| Line Transparency | How much of the ground shows through the lines, from solid (0%) to 50%. Starts at 15%. |

The guides appear a few seconds after SYNC starts. For about the first minute SYNC is busy starting its other programs
and the guides can stutter a little. After that they follow the wheel smoothly.

![The guides' rows on the Front Camera settings page (a render, not a photo)](docs/settings.png)

## Lift Offset

The guides are drawn from measurements of the camera's height, tilt and lens, taken on my First Edition with a 1.75
inch lift and 235/65R17 tires. The mod works out the rest for other heights, so all you need to do is set Lift Offset
to how much your truck is lifted. On a stock truck, leave it on Stock.

## If something goes wrong

Turn Tire Guides off from the camera view or the settings page and nothing is drawn. To take the mod off completely,
use the uninstall stick.

## See also

[Enhanced Camera Control](https://github.com/Trist0ne/enhanced-camera-control) puts the front camera button in charge
and keeps the camera working up to about 19 mph. The two mods work independently and share the Front Camera settings
page.

## How it works

- `program/guidesd.c` runs on SYNC. It reads the steering angle from SYNC's vehicle-data service, which sends about ten
  values a second at uneven intervals, smooths it, and writes what the screen layer needs 30 times a second.
- `screen/GuidesOverlay.qml` draws the guides on SYNC's graphics chip. A vertex shader bends a strip of ground along
  the steering arc and through the camera model, and a fragment shader colours it. Each frame, the script only hands
  over one number.
- SYNC runs every one of Ford's screens on a single Qt 5.6 script engine. Whenever that engine clears away objects that
  scripts have dropped, the whole screen freezes for about a tenth of a second, and reading a file through a request
  creates a lot of them. So the steering angle is passed as the size of tiny empty image files, which a script reads
  as plain numbers. The comments in `guidesd.c` and `GuidesLayer.qml` go into detail.
- `calibration/tirepath.js` and `program/tirepath.c` hold the same camera and tire-path math, in JavaScript for the
  calibration tool and in C for SYNC.

## What it changes on SYNC

The uninstaller removes all of this and puts Ford's files back exactly as they were.

| What | Where |
|---|---|
| The program | `/fs/images/fmods_apps_data/FrontTireGuides` |
| The screen layer | `/fs/mp/fordhmi/qml/hmirvc/frontguides` |
| Calibration, lift, line settings and the on/off switch | `/fs/rwdata/frontguides` |
| One line in SYNC's startup script, after the line that launches SYNC's services | `/fs/mp/scripts/startup_gf.sh` |
| A layer in the camera popup, and a button in the camera view's menu | `RVCPopup.qml`, `CameraViewButtons.qml` |
| Its rows on the camera settings page, and a Front Camera entry in Driver Assistance | `RVCSettings.qml`, `DriverAssistSettingsMenu.qml` |

The installer only changes a Ford file if it's the stock file for this SYNC build. If it isn't, the install stops,
except for the settings page, where it carries on without the settings rows. The Front Camera entry is shared with
Enhanced Camera Control. Either mod can be installed or removed on its own, and the entry is removed with whichever one
goes last.

The mod sends nothing to the truck and reads no module. It only subscribes to SYNC's own copy of the steering angle and
the camera view.

## Building

`./build.sh [out dir]` builds the stick folder. The program is cross-compiled for QNX 6.5 (armle-v7) in a Docker image
with a QNX 6.5 gcc, set by `QNX_IMAGE` and `QNX_CC`. `./package.sh` builds the install and uninstall zips for a
release. No Ford software is included.

## Support

The mod is free. If you'd like to say thanks, you can buy me a coffee at [ko-fi.com/trist0n](https://ko-fi.com/trist0n).

## Disclaimer

This is an independent hobby project. It isn't made, endorsed or supported by Ford Motor Company or F-Mods, and it
contains none of their software. It changes how your truck's infotainment system behaves, so you install and use it at
your own risk, and it may affect your warranty. The camera is an aid; always look outside before you move.

## License

MIT: see [LICENSE](LICENSE).

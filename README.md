# Front Tire Guides

Tire guides on the front camera of a 2021+ Bronco Sport with SYNC 3, in the style of the 2025 model's Trail View: two
tracks of tread blocks showing where the front tires will go as you turn the wheel, including the part hidden under
the bumper (drawn in orange). They work in the normal front view and in the 180-degree split view.

> Status: pre-release. Built for and driven on one truck. Read "Calibration" before trusting where the guides sit.

## What you need

- A Bronco Sport with the factory front camera and SYNC 3 on build **3.4.23188** (the installer refuses any other).
- The F-Mods jailbreak with **FMods Tools 2.8 or newer**.
- A FAT32 USB stick.

## Install

1. Get the stick files: the zip from this repository's [Releases](https://github.com/Trist0ne/front-tire-guides/releases)
   page, or build them yourself (below). Copy `DONTINDX.MSA` and the `SyncMyMod` folder to the top of an empty
   FAT32 stick. (One mod per stick: every F-Mods mod uses the folder name `SyncMyMod`.)
2. With the truck parked and the engine running, plug the stick into SYNC and wait for "installed" on the screen. Do not switch off or
   pull the stick before that.
3. Pull the stick. SYNC restarts.

To remove it, do the same with the uninstall folder (`./build.sh --uninstall`, or set `UNINSTALL=1` in
`SyncMyMod/install.conf`). SYNC's files are put back exactly as they were.

## Using it

- **In the camera view:** the menu button at the top left of the camera picture has a Tire Guides button on front
  views. Lit = on.
- **Settings > Vehicle > Driver Assistance > Front Camera:**
  - *Tire Guides*: the same on / off.
  - *Lift Offset*: how much taller than stock the truck sits, from Stock to +4 inches in quarter-inch steps.
  - *Line Brightness*: from light grey (70%) to full white (100%); 95% by default.
  - *Line Transparency*: how much of the ground shows through the lines, from solid (0%) to 50%; 15% by default.

The guides are available a few seconds after SYNC starts. For the first minute or so after a start SYNC is busy
launching its other programs, and the guides can hitch slightly; after that they follow the wheel smoothly.

![The guides' rows on the Front Camera settings page (a render, not a photo)](docs/settings.png)

## Calibration

Where the guides sit depends on a calibration of the camera (`calibration/frontcam.json`): its height, tilt and lens.
The one shipped was measured on a single First Edition truck with a 1.75 inch lift and 235/65R17 tires, using tape
lines on the ground. For other heights the Lift Offset slider moves the camera's height in the arithmetic; nothing
else changes.

**That makes the stock-height and other-lift positions an extrapolation that has not been checked on another truck.**
Before relying on the guides near an obstacle, check them: put a bottle on the ground just ahead of a front tire,
steer at it, and see that the guide passes over it. If your camera sits differently you can measure your own
calibration: `calibration/calibrate.js` explains how (ground marks at known positions, read off a photo of the screen).

## If something goes wrong

- **Switch it off:** Tire Guides off (camera view or settings page) and nothing is drawn.
- **Remove it:** the uninstall stick puts Ford's files back exactly as they were.

## See also

[Enhanced Camera Control](https://github.com/Trist0ne/enhanced-camera-control): the front camera on and off by its
button only, up to about 19 mph. The two mods are independent and share one "Front Camera" settings page.

## What it changes on SYNC

Everything below is removed by the uninstaller, and Ford's files are restored byte for byte.

| What | Where |
|---|---|
| The program | `/fs/images/fmods_apps_data/FrontTireGuides` |
| The screen layer | `/fs/mp/fordhmi/qml/hmirvc/frontguides` |
| Calibration, lift, the line settings, the switch | `/fs/rwdata/frontguides` |
| One line in SYNC's startup script, after the line that launches SYNC's services | `/fs/mp/scripts/startup_gf.sh` |
| A layer in the camera popup; a button in the camera view row | `RVCPopup.qml`, `CameraViewButtons.qml` |
| Its rows on the camera settings page; a "Front Camera" entry in Driver Assistance | `RVCSettings.qml`, `DriverAssistSettingsMenu.qml` |

A Ford file is only changed if it is Ford's stock file for this build; otherwise the install stops (or, for the
settings page, carries on without it). The "Front Camera" entry is shared with Enhanced Camera Control: either mod can
be installed or removed without the other, and the entry goes with the last of them.

It sends nothing to the truck and reads no module. Its only request is a subscription to SYNC's own copy of the
steering angle and of the camera view.

## How it works

- **`program/guidesd.c`** runs on SYNC. It takes the steering angle from SYNC's vehicle-data service (about ten values
  a second, not evenly spaced), smooths it, and writes what the screen layer needs 30 times a second.
- **`screen/GuidesOverlay.qml`** draws the guides on SYNC's graphics chip: a vertex shader carries a strip of ground
  along the steering arc and through the camera model, and a fragment shader colours it. Per frame the script hands
  over one number.
- **The picture channel.** SYNC's screen software is one Qt 5.6 script engine shared by all of Ford's screens. It
  freezes the whole screen for about a tenth of a second whenever it clears away objects that scripts have dropped,
  and reading a file through a request makes a lot of them. So the steering is passed as the *sizes* of tiny empty
  image files, which reach a script as plain numbers. See the comments in `guidesd.c` and `GuidesLayer.qml`.
- **`calibration/tirepath.js`** and **`program/tirepath.c`** hold the same camera and tire-path arithmetic, in
  JavaScript for the calibration tool and in C for SYNC.

## Building

`./package.sh` packs the install and uninstall sticks as zip files for a release. `./build.sh [out dir]` builds the stick folder. The program is cross-compiled for QNX 6.5 (armle-v7) in a Docker image
holding a QNX 6.5 gcc (`QNX_IMAGE`, `QNX_CC`).

No Ford software is included here.

## Support

This mod is free. If it is useful to you and you would like to say thanks, you can leave a tip at
[ko-fi.com/trist0n](https://ko-fi.com/trist0n). Entirely optional.

## Disclaimer

An independent hobby project. It is not made, endorsed or supported by Ford Motor Company or by F-Mods, and it
contains none of their software. It changes how your truck's infotainment system behaves: you install and use it at
your own risk, and it may affect your warranty. The camera is an aid; look outside before you move.

## License

MIT: see [LICENSE](LICENSE).

# GVU Emu Mode — spruceOS Integration Guide

This document describes how to set up GVU as a video player "emulator" in spruceOS, so video files in the MEDIA ROM folder launch directly into GVU playback.

## Overview

GVU's emu mode accepts a file path as `argv[1]` and goes straight to playback, skipping the browser. When the user presses B or the video ends, GVU saves the resume position and exits back to the game list. The full GVU browser is still accessible via the X menu "Open GVU Browser" option.

## Files to deploy

### 1. GVU binaries → `Emu/MEDIA/`

Copy from the CI build zip into the existing MEDIA emu directory:

```
Emu/MEDIA/
├── bin32/gvu              ← armhf binary
├── bin32/fetch_subs       ← subtitle downloader (armhf)
├── bin64/gvu              ← aarch64 binary
├── bin64/fetch_subs       ← subtitle downloader (aarch64)
├── gvu_lib32/             ← isolated GVU armhf libs (SDL2, zlib)
├── gvu_lib32_a30/         ← VERNEED-patched SDL2 for A30 glibc 2.23
├── gvu_lib64/             ← isolated GVU aarch64 libs
└── resources/             ← fonts, cacert.pem, subtitle scripts
    ├── fonts/DejaVuSans.ttf
    ├── cacert.pem
    ├── scrape_covers.sh
    ├── clear_covers.sh
    ├── fetch_subtitles.py
    └── ...
```

GVU's libs are in separate `gvu_lib*` directories to avoid conflicts with ffplay's libs in `lib32/`/`lib64/`.

### 2. Launcher script → `Emu/MEDIA/open_gvu_browser.sh`

Create this file for the X menu "Open GVU Browser" option:

```sh
#!/bin/sh
export OPEN_GVU_BROWSER=true
exec /mnt/SDCARD/Emu/MEDIA/../../spruce/scripts/emu/standard_launch.sh "$@"
```

### 3. Update `Emu/MEDIA/config.json`

Add `"gvu"` to the emulator options and add the launchlist entry:

```json
{
    "launchlist": [
        {
            "name": "Open GVU Browser",
            "launch": "/mnt/SDCARD/Emu/MEDIA/open_gvu_browser.sh"
        }
    ],
    "menuOptions": {
        "Emulator_32": {
            "options": ["gvu", "ffplay", "gme"],
            "selected": "gvu"
        },
        "Emulator_64": {
            "options": ["gvu", "ffplay", "gme"],
            "selected": "gvu"
        }
    }
}
```

(Only the changed fields shown — merge into the existing config.json.)

## spruceOS script changes

### 4. `spruce/scripts/emu/lib/media_functions.sh` — add `run_gvu()`

Add this function before `run_ffplay()`:

```sh
run_gvu() {
    export HOME="$EMU_DIR"
    cd "$EMU_DIR"

    # GVU uses its own isolated lib dirs to avoid conflicts with ffplay
    if [ "$PLATFORM" = "A30" ]; then
        GVU_BIN="$EMU_DIR/bin32/gvu"
        export LD_LIBRARY_PATH="$EMU_DIR/gvu_lib32_a30:$EMU_DIR/gvu_lib32:$LD_LIBRARY_PATH"
    elif [ "$PLATFORM_ARCHITECTURE" = "aarch64" ]; then
        GVU_BIN="$EMU_DIR/bin64/gvu"
        export LD_LIBRARY_PATH="$EMU_DIR/gvu_lib64:$LD_LIBRARY_PATH"
    else
        GVU_BIN="$EMU_DIR/bin32/gvu"
        export LD_LIBRARY_PATH="$EMU_DIR/gvu_lib32:$LD_LIBRARY_PATH"
    fi

    export SDL_VIDEODRIVER=dummy
    export GVU_PLATFORM="$PLATFORM"
    export GVU_DISPLAY_W="$DISPLAY_WIDTH"
    export GVU_DISPLAY_H="$DISPLAY_HEIGHT"
    export GVU_DISPLAY_ROTATION="$DISPLAY_ROTATION"
    export GVU_INPUT_DEV="$EVENT_PATH_READ_INPUTS_SPRUCE"
    export GVU_PYTHON="$DEVICE_PYTHON3_PATH"
    export GVU_CACERT_PATH="$EMU_DIR/resources/cacert.pem"

    if [ "$OPEN_GVU_BROWSER" = "true" ]; then
        "$GVU_BIN" > ${LOG_DIR}/${CORE}-${PLATFORM}.log 2>&1
    else
        "$GVU_BIN" "$ROM_FILE" > ${LOG_DIR}/${CORE}-${PLATFORM}.log 2>&1
    fi
}
```

### 5. `spruce/scripts/emu/standard_launch.sh` — add gvu case

In the `MEDIA` case block, add gvu as the first check:

```sh
"MEDIA")
    if [ "$CORE" = "gvu" ] || [ "$OPEN_GVU_BROWSER" = "true" ]; then
        . /mnt/SDCARD/spruce/scripts/emu/lib/media_functions.sh
        run_gvu
    elif [ "$CORE" = "ffplay" ]; then
        . /mnt/SDCARD/spruce/scripts/emu/lib/media_functions.sh
        run_ffplay
    elif [ "$CORE" = "mpv" ]; then
        . /mnt/SDCARD/spruce/scripts/emu/lib/media_functions.sh
        run_mpv
    else
        run_retroarch
    fi
    ;;
```

The `OPEN_GVU_BROWSER` check ensures the X menu "Open GVU Browser" always routes to GVU regardless of the selected emulator.

### 6. `spruce/scripts/homebutton_watchdog.sh` — add kill_gvu()

Add the kill function and pgrep check:

```sh
kill_gvu() {
    log_message "homebutton_watchdog.sh: Killing GVU!"
    killall -q -15 gvu
}
```

Add to the `kill_emulator()` chain before the `else` fallback:

```sh
elif pgrep "gvu" >/dev/null; then
    kill_gvu
```

GVU's SIGTERM handler saves the resume position before exiting, so the gameswitcher gets a clean screenshot and the user resumes where they left off on next launch.

## How it works

### Direct playback (selecting a file from the MEDIA game list)
1. User selects a video file (mp4, mkv, etc.) from the MEDIA section
2. spruceOS calls `standard_launch.sh` with the file path
3. `CORE=gvu` routes to `run_gvu()`
4. GVU opens the file directly, skipping the browser
5. B button or end of video → saves resume position → exits to game list
6. Home button hold → watchdog sends SIGTERM → GVU saves and exits → gameswitcher opens

### Browser mode (X menu → "Open GVU Browser")
1. User presses X in the MEDIA game list
2. Selects "Open GVU Browser" from the menu
3. `open_gvu_browser.sh` sets `OPEN_GVU_BROWSER=true` and calls `standard_launch.sh`
4. GVU launches with no file argument → opens the full media browser
5. User can browse shows, seasons, manage cover art, download subtitles, etc.

### Resume behavior
- Direct mode: resume position saved on exit (B, SIGTERM, or end of video)
- Next launch of the same file resumes from the saved position
- Resume data is stored in GVU's standard history file

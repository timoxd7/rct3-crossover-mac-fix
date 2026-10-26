# RollerCoaster Tycoon 3 (Epic Games) on macOS with CrossOver

Fixes for **RollerCoaster Tycoon 3: Complete Edition** from the Epic Games Store, running through the Epic Games Launcher in **CrossOver** on Apple Silicon Macs:

| Symptom | Cause | Fix |
|---|---|---|
| Game crashes on start, or leaves a **black screen you can't exit** (Cmd+Q does nothing, only a hard reboot helps) | Default resolution `0 0` makes the game load a 640px GUI that the Epic version doesn't ship → null-pointer crash | Set a real resolution in `Options.txt` |
| The black-screen lock-up itself | The crash happens in fullscreen; Wine's crash dialog opens *behind* the black fullscreen window, which keeps the keyboard | Run the game windowed (`Fullscreen 0`) |
| Window too small, or partly hidden by the notch | Resolution doesn't match the usable screen area | Pick the largest standard mode that fits below the menu bar |
| Button sounds work, but **no music** | Music is WMA; CrossOver's bundled GStreamer has no WMA decoder | Convert the tracks to PCM WAV, keeping the `.wma` filenames |
| No direct way to start the game | Epic doesn't create a Start Menu entry | Add a `RollerCoaster Tycoon 3` shortcut to the bottle |

Tested with CrossOver 26.3, macOS 26 (Tahoe), M2 Max, RCT3 Complete Edition 3.2.5.13 (Epic).

## Quick fix

> ⚠️ Don't start the game before applying the fix. If you're already stuck on the black screen, see [Emergency exit](#emergency-exit).

```bash
brew install ffmpeg              # needed for the music fix
git clone https://github.com/timoxd7/rct3-crossover-mac-fix.git
cd rct3-crossover-mac-fix
./fix-rct3.sh                    # bottle "Epic Games Store", resolution picked automatically
```

Then start the game by double-clicking **RollerCoaster Tycoon 3** in the bottle in CrossOver, or from the Epic Games Launcher as usual. The game has no Epic DRM, so it starts fine without the launcher.

Options:

```bash
./fix-rct3.sh --bottle "My Bottle"      # different CrossOver bottle name
./fix-rct3.sh --resolution 1680x1050    # choose the window size yourself
./fix-rct3.sh --no-music                # skip the music conversion
./fix-rct3.sh --no-shortcut             # don't add the CrossOver shortcut
```

The script is safe to run again. It backs up `Options.txt` to `Options.txt.bak` and the original music to `Music.orig-wma/`.

## What the script changes (manual steps)

All paths are inside the bottle, e.g. `~/Library/Application Support/CrossOver/Bottles/Epic Games Store/drive_c/`.

### 1. Resolution and windowed mode

Edit `users/crossover/AppData/Roaming/Frontier/RCT3/Options.txt`. Create it if it doesn't exist; the game fills in the other settings itself:

```
Resolution 1920 1200
Fullscreen 0
```

- The width must be **at least 800**. The Epic version only ships GUI layouts for 800, 1024 and 1280 (`gui/800`, `gui/1024`, `gui/1280`), and `Resolution 0 0` (the default) falls back to 640.
- Use a **standard display mode** (e.g. 1920×1200, 1920×1080, 1680×1050, 1440×900, 1280×800). Non-standard sizes such as 1984×1240 are silently replaced with a small default.
- To keep everything clear of the notch, choose a mode that fits the usable screen area (below the menu bar, beside the Dock) minus ~28 pt for the window title bar. On a 16" MacBook Pro at "More Space" (2056×1329 pt), that's 1920×1200. The script works this out for you.
- Leave **Fullscreen off** in the game's own options menu as well.

### 2. Music

The game builds a DirectShow graph (File Reader → Sample Grabber → DirectSound Renderer) for each `.wma` track. CrossOver's GStreamer can read the ASF container but has no WMA audio decoder, so no graph can be rendered. Wine's GStreamer splitter detects the format from the file contents, not the extension, so PCM WAV data in a file still named `*.wma` plays fine:

```bash
cd ".../Program Files/Epic Games/RollerCoasterTycoon3"
cp -Rp Music Music.orig-wma
for f in Music.orig-wma/*.wma; do
  ffmpeg -nostdin -loglevel error -y -i "$f" -c:a pcm_s16le -ar 44100 -ac 2 -f wav "Music/$(basename "$f")"
done
```

The menu music crossfades between random tracks, and a single undecodable track makes it mute itself, so **all** tracks must be converted. The WAV files take about 1 GB instead of 90 MB.

> If you "Verify" the game in the Epic launcher, it may restore the original WMA files. Just run the script again.

### 3. Shortcut

The script writes a Windows shortcut to `users/crossover/AppData/Roaming/Microsoft/Windows/Start Menu/Programs/RollerCoaster Tycoon 3.lnk` (target `C:\Program Files\Epic Games\RollerCoasterTycoon3\RCT3.exe`), using `make_lnk.py` because Wine's script host can't create one in a CrossOver bottle. It then runs `cxmenu --sync`, so the shortcut appears in the bottle in CrossOver with the game's icon. CrossOver may also create a Mac app for it in `~/Applications/CrossOver/`.

`extract_icon.py` is a small extra helper that pulls the game icon out of `RCT3.exe` as an `.ico`, e.g. for making your own Dock launcher.

## Emergency exit

If the game ever hangs or shows a black screen, close it from Terminal (or over SSH from another device):

```bash
pkill -9 -f RCT3.exe; pkill -9 -f -i winedbg
```

In windowed mode, Cmd+Q and Force Quit (Cmd+Option+Esc) work normally.

## How this was diagnosed

- The game's `CrashDump.txt` showed `Access Violation ... at 0107:0048c0ce, Read from location 00000008`, the same crash with every graphics backend (Wine/wined3d, DXVK, D3DMetal).
- Tracing file access (`CX_DEBUGMSG=+file` via CrossOver's `wine` CLI) showed the last thing before the crash was `GUI\640\Resolution.Common.ovl` not being found. The game's `Options.txt` contained `Resolution 0 0`.
- For the music, a `+quartz` trace showed `FilterGraph2_RenderFile ... Returning 0x80040218` (VFW_E_CANNOT_RENDER) for the WMA tracks. CrossOver's `lib64/gstreamer-1.0` has `libgstasf` but no WMA decoder (no gst-libav).
- All tests ran with a watchdog that force-kills `RCT3.exe` and `winedbg` after 60 s, so a hang couldn't lock up the Mac again.

Related Wine bugs: [35017](https://bugs.winehq.org/show_bug.cgi?id=35017) (RCT3 no music), [26396](https://bugs.winehq.org/show_bug.cgi?id=26396) (RCT3 audio needed native quartz).

## License

MIT. Not affiliated with Frontier Developments, Atari, Epic Games or CodeWeavers.

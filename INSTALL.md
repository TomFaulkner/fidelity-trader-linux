# Installing Active Trader Pro (Classic) from scratch

Reproduces the working install. Assumes Omarchy/Arch + Hyprland + Proton already installed.
Everything below is exactly what was done, in order.

Prerequisite: `~/Downloads/setup.exe` — the ATP installer, downloaded from Fidelity while
logged in. It is 564 KB and is only a bootstrapper.

---

## 0. Environment

```bash
export PROTON="$HOME/.local/share/Steam/steamapps/common/Proton - Experimental"
export WINEPREFIX="$HOME/.local/share/wineprefixes/atp"
export WINEDLLPATH="$PROTON/files/lib/vkd3d:$PROTON/files/lib/wine:$PROTON/files/lib/wine/icu"
export LD_LIBRARY_PATH="$PROTON/files/lib/x86_64-linux-gnu:$PROTON/files/lib/i386-linux-gnu"
export GST_PLUGIN_SYSTEM_PATH_1_0="$PROTON/files/lib/x86_64-linux-gnu/gstreamer-1.0"
export PATH="$PROTON/files/bin:$PATH"
```

These came from reading Proton's own `proton` script (`init_wine()`), which builds:

```
LD_LIBRARY_PATH = <lib>/x86_64-linux-gnu : <lib>/aarch64-linux-gnu : <lib>/i386-linux-gnu
WINEDLLPATH     = <lib>/vkd3d : <lib>/wine
```

Get them wrong and you get `libvkd3d-1.dll not found` / `wined3d.dll not found` / ICU
forwarding errors. Getting `WINEDLLPATH` wrong on prefix creation is what leaves the prefix
without vkd3d — rebuild the prefix after fixing it.

There is no system `wine`; Proton's is `wine-11.0` and works fine standalone.

---

## 1. Create the prefix

```bash
mkdir -p "$WINEPREFIX"
wine wineboot --init
```

Must be **64-bit** (`WINEARCH=win64`) — the app is 64-bit and CefSharp's natives are x64.

Do **not** copy Proton's `files/share/default_pfx` as a template: it has no `dosdevices/`
(Proton's script creates those), which leaves the prefix broken with
`could not find DOS drive` / `could not load kernel32.dll`.

Copy the ICU DLLs in if `icu.dll` forwarding fails:

```bash
cp "$PROTON/files/lib/wine/icu/x86_64-windows/"*.dll "$WINEPREFIX/drive_c/windows/system32/"
cp "$PROTON/files/lib/wine/icu/i386-windows/"*.dll    "$WINEPREFIX/drive_c/windows/syswow64/"
```

---

## 2. .NET Framework 4.8

```bash
winetricks -q dotnet48
```

`winetricks` is fine with Proton's wine as long as it is on `PATH`. Takes ~10 minutes.

Verify:

```bash
wine reg query 'HKLM\Software\Microsoft\NET Framework Setup\NDP\v4\Full' | grep -i release
#    Release    REG_DWORD    0x80eb1        (= 528049, i.e. 4.8)
```

If `Release` is missing or `clr.dll` is dated 2010, the install did not complete — re-run
with `--force`.

> **Run this detached.** A foreground command that exceeds a 120 s shell timeout will kill
> it mid-install and leave a half-installed prefix:
> `setsid nohup ./install.sh > log 2>&1 < /dev/null & disown`

---

## 3. Fonts — this one is fatal, do not skip

The prefix ships with **zero fonts**. WPF's font fallback calls `Version.Parse()` on garbage
and calls `Environment.FailFast("Unrecoverable system error")`. The app dies before any
window appears:

```
at MS.Internal.Shaping.TypefaceMap.MapUnresolvedCharacters(...)
Message: Unrecoverable system error.
```

`winetricks corefonts` fails without `cabextract` (which needs root). Instead, use the
IExpress self-extractor — the font installers are IExpress archives and support `/C /T:`:

```bash
mkdir -p cf && cd cf
for f in andale32 arial32 arialb32 comic32 courie32 georgi32 impact32 times32 \
         trebuc32 verdan32 webdin32; do
  curl -sSL -o "$f.exe" "https://github.com/pushcx/corefonts/raw/master/$f.exe"
done
# extract (no cabextract, no root)
for f in *.exe; do wine "$f" /C /T:"C:\\fontext\\${f%.exe}"; done
# install
find "$WINEPREFIX/drive_c/fontext" \( -iname '*.ttf' -o -iname '*.ttc' \) \
  -exec cp {} "$WINEPREFIX/drive_c/windows/Fonts/" \;
```

WPF specifically wants real families (Arial/Tahoma/Segoe UI) — copying Liberation/Noto as a
stopgap is **not** enough on its own.

---

## 4. Get the ClickOnce payload

```bash
./scripts/fetch-atp.sh
```

Chain (all unauthenticated, all reachable):

```
https://www.fidelity.com/webcontent/ATPInstaller/x64/ActiveTraderProInstaller64.application
  → Application Files/ActiveTraderProInstaller64_1_0_0_62/ActiveTraderProInstaller64.exe.manifest
  → ActiveTraderProInstaller64.exe           (contains the real URL as a UTF-16 string)

https://www.fidelity.com/webcontent/ActiveTraderPro-64/atp/ClickOnce/Prod-Deploy.Application
  → 11.1.826.0/application.exe.manifest
  → 332 files
```

Two things to know:

- `mapFileExtensions="true"` → every file is served with a **`.deploy`** suffix appended,
  except `.manifest` files.
- Filenames in the manifests use backslash separators for subdirectories.

Result: 332 files, 319 MB on disk, zero download errors.

---

## 5. Install the app

```bash
mkdir -p "$WINEPREFIX/drive_c/Program Files/Fidelity"
cp -r atp-files "$WINEPREFIX/drive_c/Program Files/Fidelity/ActiveTraderPro"
```

---

## 6. The Windows-version fix (unlocks hardware rendering)

```bash
./scripts/wine-fixes.sh
```

winetricks leaves the prefix reporting **Windows 7** because it sets these DWORDs:

```
HKLM\Software\Microsoft\Windows NT\CurrentVersion
    CurrentMajorVersionNumber = 6   ← Wine actually reads THIS, not CurrentVersion
    CurrentMinorVersionNumber = 1
```

Set them to `10` / `0` (and `CurrentVersion=10.0`, `CurrentBuildNumber=19042` for tidiness).

Before: `Render Mode: SoftwareOnly`
After:

```
Is Windows Microsoft Windows NT 10.0.19042 Service Pack 1 supports hardware rendering.
Hardware Rendering: True
Render Capability: 2
Render Mode: Default
```

> Note: `winecfg -v win10` hangs (it opens a GUI). Edit the registry directly.

---

## 7. Launch

```bash
fidelity-atp
```

**Wait.** The login window takes well over a minute to render its contents on first paint.

---

## Layout afterwards

```
~/.local/share/wineprefixes/atp/          Wine prefix (~1.3 GB)
~/.local/bin/fidelity-atp                 Launcher
~/.local/share/applications/fidelity-atp.desktop
~/.local/share/icons/hicolor/*/apps/fidelity-atp.png
```

Logs (very useful — see TROUBLESHOOTING):

```
~/.local/share/wineprefixes/atp/drive_c/ProgramData/
  Fidelity Investments/Fidelity Active Trader/Logs/Atp.log
```

Verbose logging is currently enabled in `ActiveTraderPro.exe.config` (NLog
`levels="Trace,Debug,Info,Warn,Error,Fatal"`). Revert with
`ActiveTraderPro.exe.config.bak` if you want the original `Info` level back.

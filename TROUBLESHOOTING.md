# Troubleshooting & tooling

How to re-derive any of this, and the tools that worked.

---

## Verify the install is healthy

```bash
source ~/.local/share/wineprefixes/atp-env.sh     # or bin/atp-env.sh
export PATH="$PROTON/files/bin:$PATH"

# .NET version
wine reg query 'HKLM\Software\Microsoft\NET Framework Setup\NDP\v4\Full' | grep -i release
#   expect 0x80eb1 (528049)

# reported Windows version (must be 10.0)
wine reg query 'HKLM\Software\Microsoft\Windows NT\CurrentVersion' | grep -iE 'CurrentVersion|CurrentMajor|CurrentMinor'

# fonts present
ls "$WINEPREFIX/drive_c/windows/Fonts" | wc -l     # was 0 before, ~43 after
```

Then check the app's own log — it is the single most useful signal:

```
~/.local/share/wineprefixes/atp/drive_c/ProgramData/
  Fidelity Investments/Fidelity Active Trader/Logs/Atp.log
```

Expect to see:

```
Is Windows Microsoft Windows NT 10.0.19042 … Hardware Rendering: True
Render Capability: 2
Render Mode: Default
Startup Sequence - DisplayLoginWindow
```

---

## Decompiling .NET assemblies

There is no .NET SDK, so `dotnet tool install -g ilspycmd` won't work. But the **runtime**
(10.0.11) is present, and `ilspycmd` ships as a NuGet package:

```bash
VER=$(curl -s https://api.nuget.org/v3-flatcontainer/ilspycmd/index.json \
      | python3 -c "import sys,json;print(json.load(sys.stdin)['versions'][-1])")
curl -sSL -o ilspycmd.nupkg \
  "https://api.nuget.org/v3-flatcontainer/ilspycmd/$VER/ilspycmd.$VER.nupkg"
mkdir -p ilspycmd && (cd ilspycmd && unzip -q ../ilspycmd.nupkg)

# whole assembly
dotnet ilspycmd/tools/net10.0/any/ilspycmd.dll -o out Shell.dll

# single type (much faster)
dotnet ilspycmd/tools/net10.0/any/ilspycmd.dll -t 'Fmr.ActiveTrader.WPF.ATP.Shell.Views.ShellView' Shell.dll
```

This is what cracked the render-mode question. Prefer it over dnSpy on this system.

---

## Compiling test apps inside the prefix

.NET Framework ships a compiler, and the GAC has the framework assemblies:

```bash
FW='C:\windows\Microsoft.NET\Framework64\v4.0.30319'
wine "$FW\csc.exe" /nologo /target:exe /out:"C:\atptest\Np.exe" "C:\atptest\Np.cs" \
  /r:"$FW\System.dll"
```

WPF assemblies must be referenced by **full GAC path** (there are no reference assemblies):

```
C:\windows\Microsoft.NET\assembly\GAC_MSIL\PresentationFramework\v4.0_4.0.0.0__31bf3856ad364e35\PresentationFramework.dll
C:\windows\Microsoft.NET\assembly\GAC_32\PresentationCore\v4.0_4.0.0.0__31bf3856ad364e35\PresentationCore.dll
C:\windows\Microsoft.NET\assembly\GAC_MSIL\WindowsBase\…\WindowsBase.dll
C:\windows\Microsoft.NET\assembly\GAC_MSIL\System.Xaml\v4.0_4.0.0.0__b77a5c561934e089\System.Xaml.dll
```

Useful probes written this way: `Dns.GetHostEntry` + `HttpWebRequest` (is Wine networking
OK?) and `GetNetworkParams` via P/Invoke (what DNS servers does Windows report?).

---

## Reading PE resources (how the bootstrapper gave up its URL)

`setup.exe`'s `BASEURL` and `SETUPCFG` are PE resources; `SETUPCFG` is **UTF-16**. Minimal
Python: parse the section table, walk the resource directory (`/40/BASEURL`,
`/41/SETUPCFG`), decode UTF-16LE.

Other useful string greps:

```bash
strings -el -n 6 Foo.dll      # .NET string literals live in the #US heap as UTF-16
strings     -n 6 Foo.dll      # metadata / type names (ASCII)
```

The URL to the real ATP manifest was only visible with `-el`.

---

## Pulling one file out of a huge MSIX

No need to download 256 MB. Range-fetch the tail, find the ZIP64 EOCD via the locator
(`PK\x06\x07`), read the central directory, then range-fetch just the one entry:

```python
# tail chunk, then:
li = tail.rfind(b"PK\x06\x07")
z64_off, = struct.unpack("<Q", tail[li+8:li+16])
cd_size, cd_off = struct.unpack("<QQ", tail[z64_off-base+40 : z64_off-base+56])
```

MSIX uses **ZIP64**, so the classic EOCD `cd_off` reads `0xFFFFFFFF`. Also note MSIX
percent-encodes filenames — `unquote()` them on extraction.

This is how the Trader+ app icon (`appiconLogo.targetsize-256.png`) was obtained.

---

## Screenshot / UI verification

```bash
# find the window
hyprctl clients -j | python3 -c "
import sys,json
for c in json.load(sys.stdin):
    if 'Active Trader Pro' in (c.get('title') or ''):
        x,y=c.get('at'); w,h=c.get('size'); print(f'{x},{y} {w}x{h}')"
grim -g "X,Y WxH" shot.png
```

Since images can't be viewed directly here, analyse statistically:

```bash
magick shot.png -crop 16x10@ +repage -format "%[fx:standard_deviation]\n" info:
# tiles with stdev > 0.10 have content; ~0.02 is a flat fill
```

**Caveat:** this produced a false negative during the investigation (see README's timing
gotcha). Use it to compare states, never to declare failure on its own.

---

## Chromium / CEF diagnostics

Command-line switches **do** reach CEF through `ActiveTraderPro.exe` (confirmed —
`--enable-logging` produced real Chromium output):

```bash
wine ActiveTraderPro.exe --log-file=C:\\cef.log --enable-logging=stderr --v=1
wine ActiveTraderPro.exe --log-net-log=C:\\netlog.json --net-log-capture-mode=Default
```

Netlog error codes seen: `-137` = ERR_NAME_NOT_RESOLVED, `os_error 11003` =
WSAHOST_NOT_FOUND. These appear for Chromium's background requests and are **not** fatal.

Also: `winedump` is not installed; use Python `struct` parsing or `strings` instead.

---

## If it breaks after an update

ATP self-updates. If it stops working:

1. `wine reg query …\CurrentVersion | grep -i CurrentMajor` — winetricks may not run again,
   but a rewrite could reset it. Re-apply `scripts/wine-fixes.sh`.
2. Re-check fonts: `ls "$WINEPREFIX/drive_c/windows/Fonts" | wc -l`.
3. Read `Atp.log` first — it names the failing module.
4. If the app redownloads itself via ClickOnce it will fail (no ClickOnce in Wine);
   re-materialize with `scripts/fetch-atp.sh` and copy over.

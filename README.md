# Fidelity Trader+ / Active Trader Pro on Linux

Getting Fidelity's trading platforms running on Linux (Omarchy / Arch, Hyprland) without
RDP into a Windows box.

## Status

| Platform | Status | Notes |
|---|---|---|
| **Fidelity Trader+ Desktop** (new) | **Impossible** | WinUI 3 + WebView2 + MSIX. Hard Wine blockers, not fixable. |
| **Fidelity Trader+ Web** | **Works** | Installed as a desktop app. Streaming data, advanced charting. |
| **Active Trader Pro Classic** | **Works** | Fully functional — login, positions, charts. The main win. |

**Bottom line:** Trader+ Desktop cannot be made to run. ATP Classic *does* run, and it is
the app that was previously only reachable over RDP.

---

## Quick start (if you already have the prefix)

```bash
fidelity-atp                     # or "Fidelity Active Trader Pro" in the app launcher
```

Give the login window **a minute or two** to render on first paint — see
[the timing gotcha](#the-timing-gotcha-read-before-you-debug).

Fresh install → [INSTALL.md](INSTALL.md).

---

## The three platforms

### 1. Fidelity Trader+ Desktop — dead end

`https://digital.fidelity.com/stgw/digital/atp-win/FidelityTraderPlus.msix`

It is not an installer, it is an **MSIX** package (a ZIP64 archive). Internally:

- .NET MAUI + **WinUI 3** (Windows App SDK) + **WebView2** (Edge) + SkiaSharp
- `AppxManifest.xml`: `EntryPoint="Windows.FullTrustApplication"`, `rescap:runFullTrust`

Four independent blockers:

1. **MSIX** — Wine has no MSIX deployment. Worked around by unzipping and URL-decoding
   filenames (`Fidelity%20Trader%2B.exe` → `Fidelity Trader+.exe`), which does get it launching.
2. **`NtCreateWaitCompletionPacket` is not implemented in Wine at all** (grepped every
   Proton Wine library — zero hits). WinUI's `DispatcherQueueController` needs it.
   Crash: exception `0x80000100`.
3. **WinUI 3 / WinRT** — needs XAML, DirectComposition and WinRT activation support Wine lacks.
4. **WebView2** — no Edge WebView2 runtime under Wine, and the UI is largely a WebView2 shell.

Do not spend time here.

### 2. Fidelity Trader+ Web — works today

`https://digital.fidelity.com/ftgw/digital/traderplus`

This is Fidelity's own answer for people who can't install the desktop app. Installed as a
proper app entry using Omarchy's `omarchy-launch-webapp` convention:

- `~/.local/share/applications/fidelity-trader-plus.desktop`
- Icon: `fidelity-traderplus` at 5 sizes in `~/.local/share/icons/hicolor/`

The icon was pulled straight out of the 256 MB MSIX without downloading it, by
range-fetching the ZIP64 central directory and then the single icon entry — see
[TROUBLESHOOTING.md](TROUBLESHOOTING.md#pulling-one-file-out-of-a-huge-msix).

### 3. Active Trader Pro Classic — works

This is the real prize. It is a **WPF + CefSharp (Chromium)** app on .NET Framework 4.x,
which is a far better fit for Wine than WinUI 3.

The catch: it ships via **ClickOnce**, which Wine does not support at all. The entire
install was reverse-engineered and materialized by hand — 332 files, ~254 MB.

Full detail: [INSTALL.md](INSTALL.md) and [FINDINGS.md](FINDINGS.md).

---

## How the pieces fit

```
setup.exe (Visual Studio bootstrapper)
  └─ BASEURL https://www.fidelity.com/webcontent/ATPInstaller/x64/
     └─ ActiveTraderProInstaller64.application        (ClickOnce deployment manifest)
        └─ ActiveTraderProInstaller64.exe             (small WPF installer)
           └─ hardcodes the real target:
              https://www.fidelity.com/webcontent/ActiveTraderPro-64/atp/ClickOnce/Prod-Deploy.Application
                 └─ 11.1.826.0/application.exe.manifest   →  332 files
```

The URL for the real manifest is only visible as a UTF-16 string inside
`ActiveTraderProInstaller64.exe`:

```
https://www.fidelity.com/webcontent/ActiveTraderPro-64/atp/ClickOnce/Prod-Deploy.Application
```

---

## Known issues (ATP Classic)

| Issue | Severity | Notes |
|---|---|---|
| UI is a little slow | Minor | Acceptable in practice. |
| Right-click menu: black box until the mouse moves | Minor | WPF popup repaint / layered-window issue. Possibly *caused* by hardware rendering — untested. |
| Closing the window does not exit the process | Minor | Process lingers, still holding stdio. Kill it manually. |
| `WPFJSBridgeModel` `ArgumentNullException` | Cosmetic | Caught and logged; app continues. |
| `IsMacOsVersionSupportHWRendering` `FormatException` | Cosmetic | The app detects "Crossover_mac" and takes its Mac code path. Harmless — caught. |
| `WSALookupServiceBegin failed` (CEF) | Cosmetic | Chromium network-change notifier. Benign. |

---

## The timing gotcha — read before you debug

**A flat/blank screenshot of the login window is NOT proof that it failed.**

The login page is a CEF (Chromium) control and it takes **well over 50 seconds** to render
under Wine. During the investigation I concluded "CEF has no network access" on the basis of
a flat screenshot at ~50 s plus a minimal test app that never loaded `example.com`. Both were
wrong; the app works fine. Wait, and trust your eyes over automation.

Similarly, `net_error: -137 / os_error 11003` in a Chromium netlog does not mean the app is
broken — those come from Chromium's own background requests.

---

## Repo contents

| Path | What |
|---|---|
| [INSTALL.md](INSTALL.md) | Reproducible install from scratch |
| [FINDINGS.md](FINDINGS.md) | Technical deep dive — ClickOnce chain, rendering, DNS, dead ends |
| [TROUBLESHOOTING.md](TROUBLESHOOTING.md) | Tooling, verification, how to re-derive things |
| `bin/fidelity-atp` | Launcher (on PATH) |
| `bin/atp-env.sh` | Wine/Proton environment |
| `scripts/fetch-atp.sh` | Materializes the ClickOnce payload |
| `scripts/wine-fixes.sh` | Applies the prefix registry fixes |
| `scripts/fonts-iexpress.sh` | Installs corefonts without `cabextract`/root |

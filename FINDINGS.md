# Findings

Technical detail behind the install. Written so this doesn't have to be re-derived.

---

## Platform

- Omarchy (Arch), Hyprland, kernel `7.2.5-3-omarchy`
- Proton `- Experimental`, `experimental-11.0-20260910b-x86_64` → **wine-11.0**
- No system wine. `dotnet` runtime 10.0.11 present but **no SDK**
- AMD Ryzen 7 7840HS / Radeon 780M, 5120x1440 + 3840x2160 displays

---

## Fidelity Trader+ Desktop (the new app) — why it's impossible

Download: `https://digital.fidelity.com/stgw/digital/atp-win/FidelityTraderPlus.msix`
(256,628,837 bytes).

It's an **MSIX** = ZIP64 archive. `AppxManifest.xml`:

```xml
<Application Id="App" Executable="Fidelity Trader+.exe"
             EntryPoint="Windows.FullTrustApplication">
<rescap:Capability Name="runFullTrust" />
```

Contents reveal the stack: `Microsoft.UI.Xaml.dll`,
`Microsoft.WindowsAppRuntime.Bootstrap.dll`, `Microsoft.Web.WebView2.Core.dll`,
`WebView2Loader.dll`, `libSkiaSharp.dll`, `coreclr.dll` (self-contained .NET),
`Microsoft.Maui.*`, `Telerik.Maui.Controls.WinUI`.

Blockers, in the order they bite:

1. **MSIX** — no Wine installer support. Workaround: unzip with URL-decoding of filenames
   (`Fidelity%20Trader%2B.exe` → `Fidelity Trader+.exe`). This does get it launching; the
   `.NET` apphost otherwise looks for `Fidelity Trader+.dll` and fails with
   "The application to execute does not exist".
2. **`NtCreateWaitCompletionPacket` does not exist in Proton's Wine.** Grepped every library
   under `files/lib/wine` and `files/lib/x86_64-linux-gnu` — zero hits. WinUI's
   `Microsoft.UI.Dispatching.DispatcherQueueController` requires it:
   ```
   wine: Call from 00006FFFFFF9C280 to unimplemented function
         ntdll.dll.NtCreateWaitCompletionPacket, aborting
   Unhandled exception code 80131506
   ```
3. **WinUI 3 / WinRT** — `RoGetActivationFactory` is a semi-stub in Wine.
4. **WebView2** — the UI is largely an Edge WebView2 shell (`Fmr.PooledWebViewLibrary.dll`,
   `webview-logging.js`). No runtime under Wine.

Fixing #1 is easy; #2–#4 are not reachable.

---

## ATP Classic — the ClickOnce chain

`setup.exe` (564 KB) is a **Visual Studio bootstrapper** (`vsbootstrapper`, see
`HKLM\Software\Microsoft\VisualStudio\Setup`). Its PE resources hold:

| Resource | Value |
|---|---|
| `40/BASEURL` | `https://www.fidelity.com/webcontent/ATPInstaller/x64/` |
| `41/SETUPCFG` | UTF-16 INI-style config (11,976 bytes) |

`SETUPCFG` says: application `ActiveTraderProInstaller64`, prereq
**.NET Framework 4.6.2**, and the ClickOnce file `ActiveTraderProInstaller64.application`.

That `.application` → `Application Files/ActiveTraderProInstaller64_1_0_0_62/…manifest`
→ `ActiveTraderProInstaller64.exe` (166 KB, WPF, uses `InPlaceHostingManager`).

Inside that exe, as a **UTF-16** string (invisible to plain `strings`):

```
https://www.fidelity.com/webcontent/ActiveTraderPro-64/atp/ClickOnce/Prod-Deploy.Application
```

That's the real target. `Prod-Deploy.Application`:

- Product `Fidelity Active Trader Pro®64`, version `11.1.826.0`
- `install="true"`, `mapFileExtensions="true"`, `createDesktopShortcut="true"`
- Application manifest: `11.1.826.0/application.exe.manifest` (217,991 bytes)

Manifest yields **332 entries**: 282 `dependentAssembly` + 49 `file` (+ the manifest).
254 MB logical, 319 MB on disk.

Two parsing gotchas:
- `mapFileExtensions="true"` → append `.deploy` to every URL, **except** `.manifest`
- manifest names use `\` separators for subdirectories

Wine has **no ClickOnce at all**, so the only path is materializing the files by hand and
running `ActiveTraderPro.exe` directly. This works — there is no install step, no registry,
no shortcut registration needed.

### What the app actually is

- **WPF** on .NET Framework 4.x (reports itself as `10.6.1103.0`)
- **CefSharp** / CEF: `libcef.dll` (201 MB), `CefSharp.BrowserSubprocess.exe`,
  `chrome_elf.dll`, `icudtl.dat`, `libEGL/libGLESv2`, `vk_swiftshader.dll`, paks
- Infragistics (`InfragisticsWPF4.v11.2`), Telerik, PostSharp, NLog, LaunchDarkly
- Prism-ish: MEF catalog loads ~60 modules in two phases (`AppModules.Bootstrap`,
  `AppModules.Phase1`) — visible in `ActiveTraderPro.exe.config`

CEF is initialized in `BrowserHost.dll`:

```csharp
var settings = new CefSettings();
settings.LocalesDirPath = directoryName;
settings.UserAgent = PlatformUtils.UserAgent() + GetCefSharpVersion();
settings.RegisterScheme(new CefCustomScheme { SchemeName = "atp", IsSecure = true, ... });
Cef.Initialize(settings, true, (IBrowserProcessHandler)null);
```

Login window: `LoginBrowserHostView` (XAML `views/loginbrowserhostview.xaml`) hosting
`BrowserHostControl`, which wraps a CefSharp `ChromiumWebBrowser`.

Login URL: `WebLoginEndpoint.url` + `.redirect` from the local config:

```
https://digital.fidelity.com/prgw/digital/signin/atp?exp=new&
AuthRedUrl=https://www.fidelity.com/webcontent/ATPConfig/version_10_6/configuration_2_0.shtml
```

---

## The rendering investigation (the part that actually mattered)

`ShellView` decides WPF's render mode:

```csharp
if (!flag && (IsMacOsVersionSupportHWRendering() || IsWindowsOsVersionSupportHWRendering()))
    RenderOptions.ProcessRenderMode = RenderMode.Default;
```

- `IsMacOsVersionSupportHWRendering()` — always fails here (throws `FormatException`, is
  caught, returns false). It calls `PlatformUtils.GetMACHostVersion()` which ends up in WMI
  (`ManagementObjectSearcher`); Wine has no real WMI, so the version string is unparseable.
- **`IsWindowsOsVersionSupportHWRendering()` does not check for Mac at all.** It only needs
  `PlatformUtils.IsMinWinNTVersion(10, 0)` and the LaunchDarkly flag
  `ATP-ForceHWRendering` → `EnableHwRenderinginPc = true` (already true).

So the whole problem was the **reported Windows version**, nothing to do with Mac detection.

Wine was reporting `6.1.19042` because `winetricks` (for dotnet48) sets these DWORDs:

```
CurrentMajorVersionNumber = 6
CurrentMinorVersionNumber = 1
```

Wine reads **those**, not the `CurrentVersion` string. Setting them to `10` / `0` flipped
`Render Mode: SoftwareOnly` → `Default` and `Hardware Rendering: True`.

Symptom before the fix: `Render Mode: SoftwareOnly`, blank/black CEF content area.

---

## The network false lead — documented so it isn't repeated

I built a minimal CefSharp app (compiled in-prefix with .NET's `csc`) to test CEF in isolation:

| Address | Result |
|---|---|
| `data:text/html,…` + `--disable-gpu` | rendered |
| `http://example.com` | blank |
| `https://example.com` | blank |
| `http://172.66.147.243` (raw IP) | blank |

Chromium netlog showed `net_error: -137` (ERR_NAME_NOT_RESOLVED), `os_error: 11003`.
Wine's `ipconfig /all` shows adapters/gateways but **no DNS servers**; `GetNetworkParams`
returns only `127.0.0.53`.

I concluded "CEF has no network access." **That was wrong.** Meanwhile:

- .NET in the same prefix resolved DNS fine and returned `HTTP 200`
- ATP itself downloaded its 257 KB config from Fidelity successfully
- The user logged in and positions loaded

The truth: the login page is simply **slow** — far more than 50 s to paint. The test app's
failures were never reproduced against the real target.

Supporting detail: `WSALookupServiceBegin failed` (Chromium's network-change notifier) and
the `-137` errors come from Chromium's background traffic and are **not** fatal.

**Lesson:** a flat screenshot at ~50 s is not evidence of failure. Wait minutes, and trust a
human looking at the screen over automated pixel statistics.

---

## Dead ends (do not redo)

| Attempt | Result |
|---|---|
| DXVK (`WINEDLLOVERRIDES=d3d11=n;dxgi=n;…`) | **Worse.** `Render Capability` dropped 2 → 0 and it crashed. Use wined3d. |
| `--disable-gpu` on ATP | No effect (it *does* reach CEF — verified via `--enable-logging` working). |
| `--single-process`, `--enable-features=NetworkServiceInProcess` | No effect. |
| `--disable-features=AsyncDns` | No effect. |
| `--ignore-certificate-errors` | No effect (and undesirable for a brokerage app). |
| `--use-angle=swiftshader` | No effect. |
| `--no-proxy-server` | No effect. No proxy/PAC is configured anyway. |
| Native WPF login (`IsWPFLoginFeatureEnabled.Value=true` + registry `QA-login=true`) | `DisplayLoginWindow` **hardcodes** `LoginBrowserHostView`, so this never switches views. Reverted. |
| `winecfg -v win10` | Hangs — it opens a GUI. Edit the registry. |
| Copying Proton's `default_pfx` as a prefix template | Broken prefix — it has no `dosdevices/`. |
| `dnSpy.Console.exe` under Wine | `IOException: Invalid handle` at `Console.set_OutputEncoding` — needs a real console. Use `ilspycmd` instead. |
| `winetricks corefonts` | Needs `cabextract` (root). Use the IExpress `/C /T:` route. |

---

## Shell gotchas that cost real time

- **`pkill -f 'ActiveTraderPro'` kills your own shell** if that string appears anywhere in
  your command line — including inside a heredoc you just wrote. Put the kill logic in a
  script file and invoke the script.
- A 120 s shell timeout **kills detached background jobs** too (`nohup` protects against
  SIGHUP, not SIGKILL to the process group). Launch with `setsid nohup … & disown` and keep
  the launching command short.
- Reading a PE binary with `head` dumps binary garbage into the transcript. Use `strings`,
  `file`, or a Python parser.

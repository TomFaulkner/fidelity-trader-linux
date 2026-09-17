#!/bin/bash
# Apply the prefix registry fixes. Safe to re-run.
#
# The important one: Wine reports its Windows version from the DWORDs
# CurrentMajorVersionNumber / CurrentMinorVersionNumber — NOT from the
# CurrentVersion string. winetricks sets these to 6/1 (Windows 7) for dotnet48,
# which makes ATP fall back to RenderMode.SoftwareOnly.
#
# Before:  Render Mode: SoftwareOnly
# After:   Is Windows ... 10.0.19042 ... Hardware Rendering: True
#          Render Mode: Default
#
# Do NOT use `winecfg -v win10` — it hangs (opens a GUI).
set -euo pipefail
source "$(dirname "$(readlink -f "$0")")/../bin/atp-env.sh"
export PATH="$PROTON/files/bin:$PATH"

K='HKLM\Software\Microsoft\Windows NT\CurrentVersion'

set_dword() { wine reg add "$K" /v "$1" /t REG_DWORD /d "$2" /f > /dev/null; }
set_sz()    { wine reg add "$K" /v "$1" /t REG_SZ    /d "$2" /f > /dev/null; }

set_dword CurrentMajorVersionNumber 10
set_dword CurrentMinorVersionNumber 0
set_sz    CurrentVersion            10.0
set_sz    CurrentBuild              19042
set_sz    CurrentBuildNumber        19042
set_sz    ProductName               "Windows 10 Pro"

echo "current values:"
wine reg query "$K" | grep -iE 'CurrentVersion|CurrentMajor|CurrentMinor|CurrentBuildNumber|ProductName'

echo
echo "Re-launch ATP and confirm in Atp.log:"
echo "  'Hardware Rendering: True'   and   'Render Mode: Default'"

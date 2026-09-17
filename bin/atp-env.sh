#!/bin/bash
# Proton/Wine environment for the Fidelity Active Trader Pro prefix.
# Source this before running wine/winetricks against the prefix.
#
#   source bin/atp-env.sh
#
# These values come from Proton's own `proton` script (init_wine()):
#   LD_LIBRARY_PATH = <lib>/x86_64-linux-gnu : <lib>/aarch64-linux-gnu : <lib>/i386-linux-gnu
#   WINEDLLPATH     = <lib>/vkd3d : <lib>/wine
# Getting WINEDLLPATH wrong at prefix-creation time is what leaves the prefix
# without vkd3d ("libvkd3d-1.dll not found" -> wined3d/d3d11/d2d1 all fail).

export PROTON="${PROTON:-$HOME/.local/share/Steam/steamapps/common/Proton - Experimental}"
export WINEPREFIX="${WINEPREFIX:-$HOME/.local/share/wineprefixes/atp}"

export WINEDLLPATH="$PROTON/files/lib/vkd3d:$PROTON/files/lib/wine:$PROTON/files/lib/wine/icu"
export LD_LIBRARY_PATH="$PROTON/files/lib/x86_64-linux-gnu:$PROTON/files/lib/i386-linux-gnu"
export GST_PLUGIN_SYSTEM_PATH_1_0="$PROTON/files/lib/x86_64-linux-gnu/gstreamer-1.0"

export PATH="$PROTON/files/bin:$PATH"

# Do NOT force DXVK here. Tried it: WPF's Render Capability drops from 2 to 0
# and the app crashes. wined3d is correct for this app.

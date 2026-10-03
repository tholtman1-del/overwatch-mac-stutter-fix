#!/bin/zsh
# Overwatch shader-stutter fix for macOS (CrossOver) - uninstaller.
# Removes the runtime copy, the launcher and the Desktop shortcut. CrossOver, the bottle, the game
# and its settings were never modified and stay as they are.
HERE=${0:A:h}
if [[ -f $HERE/lib/common.sh ]]; then source "$HERE/lib/common.sh"
else source "$HOME/Library/Application Support/OverwatchMac/lib/common.sh" || exit 1; fi
[[ -d $OWMAC_HOME ]] || die "nothing to uninstall ($OWMAC_HOME missing)"

ask "Uninstall the Overwatch stutter fix?" n || exit 0

DXMT_CACHE="$(getconf DARWIN_USER_CACHE_DIR)dxmt/Overwatch.exe"
if [[ -d $OWMAC_HOME/shader-cache-saved ]]; then
  rm -rf "$DXMT_CACHE"; mkdir -p "${DXMT_CACHE:h}"; mv "$OWMAC_HOME/shader-cache-saved" "$DXMT_CACHE"
  info "restored the shader cache saved by a --cold run"
fi
rm -f "$HOME/Desktop/Overwatch (stutter fix).command"
rm -rf "$OWMAC_HOME"
info "Uninstalled. Start Battle.net from CrossOver as usual to play with the stock setup."

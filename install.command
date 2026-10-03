#!/bin/zsh
# Overwatch shader-stutter fix for macOS (CrossOver) - installer.
#
# Usage: ./install.command [--bottle "Bottle Name"]
#
# Without options it finds the CrossOver bottle where Battle.net and Overwatch are installed.
#
# What it does (nothing inside CrossOver.app, the bottle or the game folder is modified):
#   1. Clones CrossOver's Wine runtime into ~/Library/Application Support/OverwatchMac/runtime
#      (APFS clone: instant and takes no extra space on the same disk).
#   2. Replaces the runtime copy's DXMT with upstream DXMT v0.80 plus the patched 64-bit d3d11.dll
#      (async pipelines, pre-warm, low-priority shader compilers - see README).
#   3. Writes a launcher to the Desktop: "Overwatch (stutter fix).command".
set -e
PKG=${0:A:h}
source "$PKG/lib/common.sh"

BOTTLE_ARG=
while (( $# )); do
  case $1 in
    --bottle) BOTTLE_ARG=$2; shift ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
  shift
done

print -P "%BOverwatch shader-stutter fix for macOS - installer%b\n"

# --- checks -----------------------------------------------------------------------------------------
[[ $(uname -m) == arm64 ]] || warn "Only tested on Apple Silicon Macs."
CX_APP=$(find_crossover) || die "CrossOver.app not found. Install CrossOver, or set CROSSOVER_APP=/path/to/CrossOver.app"
CX_VER=$(crossover_version "$CX_APP")
info "CrossOver $CX_VER at $CX_APP"
if [[ ${CX_VER%%.*} != 26 ]]; then
  warn "This package was built and tested with CrossOver 26.3. Other versions may not work."
  ask "Continue anyway?" n || exit 1
fi

# --- bottle -------------------------------------------------------------------------------------------
if [[ -n $BOTTLE_ARG ]]; then
  BOTTLE=$BOTTLE_ARG
  [[ -f "$(bottles_dir)/$BOTTLE/$BNET_EXE_REL" ]] || die "Battle.net not found in bottle \"$BOTTLE\""
else
  bottles=("${(@f)$(find_bnet_bottles)}")
  bottles=(${bottles:#})
  (( ${#bottles} )) || die "No CrossOver bottle with Battle.net found. Install Battle.net + Overwatch first, or pass --bottle."
  BOTTLE=${bottles[1]}
  if (( ${#bottles} > 1 )); then
    print "Bottles with Battle.net:"; for i in {1..${#bottles}}; print "  $i) ${bottles[$i]}"
    read "n?Which one? [1] "; BOTTLE=${bottles[${n:-1}]}
    [[ -n $BOTTLE ]] || die "invalid choice"
  fi
fi
info "Bottle: $BOTTLE"
[[ -f "$(bottles_dir)/$BOTTLE/$OW_EXE_REL" ]] || warn "Overwatch.exe not found in this bottle yet - install the game from Battle.net first."

# --- runtime clone ------------------------------------------------------------------------------------
mkdir -p "$OWMAC_HOME"
RUNTIME="$OWMAC_HOME/runtime/CrossOver"
[[ -d $OWMAC_HOME/runtime ]] && { info "Removing previous runtime copy"; rm -rf "$OWMAC_HOME/runtime"; }
mkdir -p "$OWMAC_HOME/runtime"
info "Copying CrossOver's Wine runtime (APFS clone if possible)"
cp -cR "$CX_APP/Contents/SharedSupport/CrossOver" "$OWMAC_HOME/runtime/" 2>/dev/null \
  || { warn "APFS clone not possible (different disk), doing a full copy (~1 GB)"; rm -rf "$RUNTIME"; cp -R "$CX_APP/Contents/SharedSupport/CrossOver" "$OWMAC_HOME/runtime/"; }
print -r -- "$CX_VER" > "$OWMAC_HOME/runtime/crossover-version"

# --- DXMT v0.80 + patched d3d11.dll ---------------------------------------------------------------------
(cd "$PKG/payload" && shasum -a 256 -c SHA256SUMS >/dev/null) || die "payload checksum mismatch - download the package again"
DXMT_TGZ="$OWMAC_HOME/dxmt-$DXMT_VERSION-builtin.tar.gz"
if [[ ! -f $DXMT_TGZ ]] || [[ $(shasum -a 256 "$DXMT_TGZ" | cut -d' ' -f1) != $DXMT_SHA256 ]]; then
  info "Downloading DXMT $DXMT_VERSION from GitHub"
  curl -fL --progress-bar -o "$DXMT_TGZ" "$DXMT_URL" || die "download failed: $DXMT_URL"
fi
[[ $(shasum -a 256 "$DXMT_TGZ" | cut -d' ' -f1) == $DXMT_SHA256 ]] || die "DXMT archive checksum mismatch"
[[ -d $RUNTIME/lib/dxmt ]] || die "unexpected CrossOver layout: $RUNTIME/lib/dxmt missing"
mv "$RUNTIME/lib/dxmt" "$RUNTIME/lib/dxmt.crossover"
mkdir -p "$RUNTIME/lib/dxmt"
tar xzf "$DXMT_TGZ" -C "$RUNTIME/lib/dxmt" --strip-components 1
[[ -f $RUNTIME/lib/dxmt/x86_64-windows/d3d11.dll ]] || die "unexpected DXMT archive layout"
cp "$RUNTIME/lib/dxmt/x86_64-windows/d3d11.dll" "$RUNTIME/lib/dxmt/x86_64-windows/d3d11.dll.upstream"
cp "$PKG/payload/d3d11.dll" "$RUNTIME/lib/dxmt/x86_64-windows/d3d11.dll"

xattr -dr com.apple.quarantine "$OWMAC_HOME/runtime" 2>/dev/null || true
codesign -s - -f "$RUNTIME/lib/dxmt/x86_64-unix/winemetal.so" >/dev/null 2>&1 || warn "could not sign winemetal.so"

# --- config + launcher ------------------------------------------------------------------------------------
{
  print -r -- "# Written by install.command - $(date)"
  print -r -- "CX_APP=${(q)CX_APP}"
  print -r -- "CX_VER=${(q)CX_VER}"
  print -r -- "BOTTLE=${(q)BOTTLE}"
} > "$OWMAC_CONFIG"

mkdir -p "$OWMAC_HOME/lib" "$OWMAC_HOME/tools"
cp "$PKG/launch.command" "$PKG/uninstall.command" "$OWMAC_HOME/"
cp "$PKG/lib/common.sh" "$OWMAC_HOME/lib/"
cp "$PKG/tools/ow-bench.py" "$OWMAC_HOME/tools/"
chmod +x "$OWMAC_HOME/launch.command" "$OWMAC_HOME/uninstall.command" "$OWMAC_HOME/tools/ow-bench.py"

SHORTCUT="$HOME/Desktop/Overwatch (stutter fix).command"
print -r -- "#!/bin/zsh" > "$SHORTCUT"
print -r -- "exec ${(q)OWMAC_HOME}/launch.command \"\$@\"" >> "$SHORTCUT"
chmod +x "$SHORTCUT"

print
info "Installed. Start Overwatch with \"Overwatch (stutter fix)\" on your Desktop, then click Play in Battle.net."
info "Set Overwatch to DirectX 11 (Options > Video). DXMT has no DirectX 12."
info "Uninstall: $OWMAC_HOME/uninstall.command"

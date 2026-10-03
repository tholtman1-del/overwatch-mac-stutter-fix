#!/bin/zsh
# Overwatch shader-stutter fix for macOS (CrossOver) - launcher.
#
# Usage: launch.command [--d3dmetal] [--sync] [--fps] [--bench NAME [--cold]]
#        launch.command --restore-cache
#
#   (default)   DirectX 11 on DXMT v0.80 with the patched d3d11.dll: async pipelines, pre-warm and
#               low-priority shader compilers (see README). Overwatch must be set to DirectX 11.
#   --d3dmetal  CrossOver's stock D3DMetal (DX11 or DX12), for comparison.
#   --sync      turn async pipelines off (comparison).
#   --fps       show Apple's Metal performance HUD.
#   --bench NAME  write every frame time to ~/Library/Application Support/OverwatchMac/bench/;
#               summarise with tools/ow-bench.py. A replay (Career Profile > History > Replays) gives
#               a repeatable scene.
#   --cold      start with an empty DXMT shader cache, to measure first-time compile stutter. Your
#               cache is saved once and put back with --restore-cache.
#
# Tuning (environment variables): DXMT_PREWARM=0|1, DXMT_COMPILER_PRIORITY=low|normal|critical,
# DXMT_COMPILER_THREADS=N, DXMT_ASYNC_PSO=0|1.
#
# Overwatch inherits the graphics setup from Battle.net, so Battle.net itself is started through the
# runtime copy. A Battle.net already running in the bottle is closed first (asks).
HERE=${0:A:h}
if [[ -f $HERE/lib/common.sh ]]; then source "$HERE/lib/common.sh"
else source "$HOME/Library/Application Support/OverwatchMac/lib/common.sh" || exit 1; fi
[[ -f $OWMAC_CONFIG ]] || die "not installed ($OWMAC_CONFIG missing) - run install.command first"
source "$OWMAC_CONFIG"

W="$OWMAC_HOME/runtime/CrossOver/bin/wine"
[[ -x $W ]] || die "runtime copy missing - run install.command again"
if [[ $(crossover_version "$CX_APP") != $CX_VER ]]; then
  warn "CrossOver was updated ($CX_VER -> $(crossover_version "$CX_APP")); run install.command again to refresh the runtime copy."
fi
export WINEPREFIX="$(bottles_dir)/$BOTTLE"
[[ -d $WINEPREFIX ]] || die "bottle not found: $BOTTLE"

MODE=dxmt ASYNC=${DXMT_ASYNC_PSO:-1} FPS= BENCH= COLD=
DXMT_CACHE="$(getconf DARWIN_USER_CACHE_DIR)dxmt/Overwatch.exe"
SAVED_CACHE="$OWMAC_HOME/shader-cache-saved"
while (( $# )); do
  arg=$1; shift
  case $arg in
    --d3dmetal) MODE=d3dmetal ;;
    --sync)     ASYNC=0 ;;
    --fps)      FPS=1 ;;
    --bench)    BENCH=$1; shift ;;
    --cold)     COLD=1 ;;
    --restore-cache)
      [[ -d $SAVED_CACHE ]] || die "no saved cache"
      rm -rf "$DXMT_CACHE"; mkdir -p "${DXMT_CACHE:h}"; mv "$SAVED_CACHE" "$DXMT_CACHE"
      info "DXMT shader cache restored"; exit 0 ;;
    -h|--help) sed -n '2,24p' "$0"; exit 0 ;;
    *) die "unknown option: $arg" ;;
  esac
done

if pgrep -f "Battle\.net\.exe|Overwatch\.exe" >/dev/null; then
  ask "Battle.net/Overwatch is running and must be restarted to use the fix. Close it now?" n || exit 1
  "$OWMAC_HOME/runtime/CrossOver/bin/wineserver" -k 2>/dev/null
  sleep 3
fi

if [[ -n $COLD ]]; then
  if [[ ! -d $SAVED_CACHE ]]; then
    [[ -d $DXMT_CACHE ]] && mv "$DXMT_CACHE" "$SAVED_CACHE" || mkdir -p "$SAVED_CACHE"
  fi
  rm -rf "$DXMT_CACHE"
  info "Cold run: empty DXMT shader cache (put your real one back with --restore-cache)"
fi
if [[ -n $BENCH ]]; then
  mkdir -p "$OWMAC_HOME/bench"
  LOG="$OWMAC_HOME/bench/$BENCH-$MODE-$([[ $ASYNC == 1 ]] && echo async || echo sync)-$(date +%Y%m%d-%H%M%S).txt"
  export DXMT_FRAMETIME_LOG="Z:${LOG//\//\\}"
  info "Frame times -> $LOG"
fi

export CX_GRAPHICS_BACKEND=$MODE
export DXMT_ASYNC_PSO=$ASYNC
export DXMT_PREWARM=${DXMT_PREWARM:-1}
export DXMT_COMPILER_PRIORITY=${DXMT_COMPILER_PRIORITY:-low}
export DXMT_COMPILER_THREADS=${DXMT_COMPILER_THREADS:-4}
[[ -n $FPS ]] && export MTL_HUD_ENABLED=1

info "backend=$MODE async=$ASYNC prewarm=$DXMT_PREWARM compilers=$DXMT_COMPILER_PRIORITY/$DXMT_COMPILER_THREADS"
info "Starting Battle.net - click Play on Overwatch."
# Wine logging off (it costs CPU); "launch Pro" opens Battle.net on Overwatch.
CX_DEBUGMSG=${CX_DEBUGMSG:--all} exec "$W" --bottle "$BOTTLE" \
  'C:\Program Files (x86)\Battle.net\Battle.net.exe' --exec="launch Pro"

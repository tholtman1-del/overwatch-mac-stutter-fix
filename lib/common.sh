# Shared helpers for install.command, launch.command and uninstall.command (zsh).
# Only tools that ship with macOS are used (zsh, perl, cp, codesign, curl, shasum).

OWMAC_HOME="$HOME/Library/Application Support/OverwatchMac"
OWMAC_CONFIG="$OWMAC_HOME/config.sh"
DXMT_VERSION="v0.80"
DXMT_URL="https://github.com/3Shain/dxmt/releases/download/v0.80/dxmt-v0.80-builtin.tar.gz"
DXMT_SHA256="8f260e36b5739e68f3bad613381441385c4dc7b85b78ba8de653d5a6a264529d"

info() { print -P "%F{cyan}==>%f $*"; }
warn() { print -P "%F{yellow}warning:%f $*" >&2; }
die()  { print -P "%F{red}error:%f $*" >&2; exit 1; }

# Ask a yes/no question; $2 is the default (y or n).
ask() {
  local answer prompt="[y/N]"
  [[ $2 == y ]] && prompt="[Y/n]"
  read "answer?$1 $prompt "
  [[ -z $answer ]] && answer=$2
  [[ $answer == [yY]* ]]
}

# Locate CrossOver.app: $CROSSOVER_APP, the usual folders, then Spotlight.
find_crossover() {
  local app
  for app in "$CROSSOVER_APP" /Applications/CrossOver.app "$HOME/Applications/CrossOver.app"; do
    [[ -n $app && -x $app/Contents/SharedSupport/CrossOver/bin/wine ]] && { print -r -- "$app"; return 0; }
  done
  app=$(mdfind "kMDItemCFBundleIdentifier == 'com.codeweavers.CrossOver'" 2>/dev/null | head -1)
  [[ -n $app && -x $app/Contents/SharedSupport/CrossOver/bin/wine ]] && { print -r -- "$app"; return 0; }
  return 1
}

crossover_version() {
  /usr/bin/defaults read "$1/Contents/Info" CFBundleShortVersionString 2>/dev/null
}

bottles_dir() {
  print -r -- "$HOME/Library/Application Support/CrossOver/Bottles"
}

BNET_EXE_REL="drive_c/Program Files (x86)/Battle.net/Battle.net.exe"
OW_EXE_REL="drive_c/Program Files (x86)/Overwatch/_retail_/Overwatch.exe"

# Prints the bottles that contain Battle.net, the ones with Overwatch installed first.
find_bnet_bottles() {
  local b
  for b in "$(bottles_dir)"/*(N/); do
    [[ -f $b/$BNET_EXE_REL && -f $b/$OW_EXE_REL ]] && print -r -- "${b:t}"
  done
  for b in "$(bottles_dir)"/*(N/); do
    [[ -f $b/$BNET_EXE_REL && ! -f $b/$OW_EXE_REL ]] && print -r -- "${b:t}"
  done
  return 0
}

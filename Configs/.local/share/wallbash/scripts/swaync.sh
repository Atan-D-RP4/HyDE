#!/usr/bin/env bash

# shellcheck source=$HOME/.local/bin/hyde-shell
# shellcheck disable=SC1091
if ! source "$(which hyde-shell)"; then
  echo "[wallbash] code :: Error: hyde-shell not found."
  echo "[wallbash] code :: Is HyDE installed?"
  exit 1
fi

confDir="${confDir:-$HOME/.config}"
cacheDir="${cacheDir:-$XDG_CACHE_HOME/hyde}"
WALLBASH_SCRIPTS="${WALLBASH_SCRIPTS:-$hydeConfDir/wallbash/scripts}"
swayncDir="${confDir}/swaync"

# Create swaync directory if it doesn't exist
mkdir -p "${swayncDir}"

# Process the template and create the style.css
envsubst <"${cacheDir}/wallbash/swaync-style.css" >"${swayncDir}/style.css"

# Reload swaync configuration
if pgrep -x swaync >/dev/null; then
  swaync-client --reload-css
  swaync-client --reload-config
fi

echo "[wallbash] swaync :: Configuration updated"
#!/bin/sh
# Open the current Flutter app on Linux. Extra arguments go to flutter run.
set -eu
cd -- "$(dirname -- "$0")"

if [ "$(uname -s)" != "Linux" ]; then
  printf '%s\n' 'This launcher runs the Linux desktop app.' >&2
  exit 1
fi

if [ -x "$HOME/flutter/3.44.8/bin/flutter" ]; then
  export PATH="$HOME/flutter/3.44.8/bin:$PATH"
fi
if ! command -v flutter >/dev/null 2>&1; then
  printf '%s\n' 'Flutter was not found. Install it at ~/flutter/3.44.8 or add it to PATH.' >&2
  exit 1
fi

exec flutter run --device-id linux "$@"

#!/bin/sh
# Build per-ABI release APKs and install the matching one on every connected phone.
set -e
cd "$(dirname "$0")"
export PATH="$HOME/flutter/3.44.8/bin:$PATH" ANDROID_HOME="$HOME/Android/sdk"
adb="$ANDROID_HOME/platform-tools/adb"

# arm64 only: every phone in use is arm64, and compiling one ABI instead of three is much faster.
[ "$1" = "--no-build" ] || flutter build apk --release --split-per-abi --target-platform android-arm64

"$adb" devices -l
ready=$("$adb" devices | awk 'NR>1 && $2=="device" {print $1}')
if [ -z "$ready" ]; then
  echo
  echo "No phone ready for install. Check the state shown above:"
  echo "  (nothing listed)  plug in and unlock the phone"
  echo "  unauthorized      tap Allow on the USB debugging prompt"
  echo "  no permissions    replug the phone, or run: $adb kill-server"
  echo "  offline           unmount jmtpfs/mtpfs, then replug"
  echo "Then install without rebuilding: $0 --no-build"
  exit 1
fi

for d in $ready; do
  abi=$("$adb" -s "$d" shell getprop ro.product.cpu.abi | tr -d '\r')
  apk="build/app/outputs/flutter-apk/app-$abi-release.apk"
  [ -f "$apk" ] || apk=build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
  echo "Installing $apk on $d"
  "$adb" -s "$d" install -r "$apk"
  "$adb" -s "$d" shell monkey -p com.gymer.gymer -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || true
done

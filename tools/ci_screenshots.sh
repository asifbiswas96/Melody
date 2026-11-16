#!/usr/bin/env bash
# Melody CI: install the debug APK on the emulator, seed a test track, capture
# Home / Library / mini player / Now Playing screenshots, upload to tmpfiles.
set -x
adb install -r "$(find /home/runner/work -name '*.apk' 2>/dev/null | head -1)"

adb push tools/glass_test.mp3 /sdcard/Music/glass_test.mp3
adb shell am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d file:///sdcard/Music/glass_test.mp3 || true

mkdir -p shots
cat > /tmp/tap.py <<'PYEOF'
import sys, re, xml.etree.ElementTree as ET
want = sys.argv[1].lower()
for node in ET.parse('/tmp/ui.xml').iter('node'):
    txt = (node.get('text') or '').lower()
    desc = (node.get('content-desc') or '').lower()
    if want in txt or want in desc:
        m = re.match(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', node.get('bounds'))
        if m:
            l, t, r, b = map(int, m.groups())
            print((l + r) // 2, (t + b) // 2)
            sys.exit(0)
sys.exit(1)
PYEOF

tap_text() {
  adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1
  adb pull /sdcard/ui.xml /tmp/ui.xml >/dev/null 2>&1 || return 1
  XY=$(python3 /tmp/tap.py "$1") || return 1
  adb shell input tap $XY
}
shot() { adb shell screencap -p "/sdcard/$1.png" && adb pull "/sdcard/$1.png" "shots/$1.png"; }

adb shell monkey -p com.neurobyte.melody.debug -c android.intent.category.LAUNCHER 1
sleep 20
for i in $(seq 1 12); do
  tap_text "For You" && break
  tap_text "Skip" || tap_text "Get started" || tap_text "Next" || tap_text "Allow" || tap_text "Done" || sleep 3
  sleep 2
done
sleep 3
shot 01_home

tap_text "Library" || true
sleep 3
shot 02_library
tap_text "Songs" || true
sleep 2
for i in $(seq 1 10); do tap_text "Melody Glass Test" && break || sleep 3; done
sleep 4
shot 03_miniplayer
tap_text "Melody Glass Test" || true
sleep 3
shot 04_nowplaying

echo "### Screenshots" >> "$GITHUB_STEP_SUMMARY"
for f in shots/*.png; do
  R=$(curl -sS --retry 3 -F "file=@$f" https://tmpfiles.org/api/v1/upload || true)
  L=$(echo "$R" | jq -r '.data.url // "UPLOAD_FAILED"')
  echo "$f -> $L" | tee -a "$GITHUB_STEP_SUMMARY"
done

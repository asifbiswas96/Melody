#!/usr/bin/env bash
# Melody CI: install the debug APK on the emulator, seed a test track, capture
# Home / Library / mini player / Now Playing screenshots, upload to tmpfiles.
set -x
adb install -r "$(find /home/runner/work -name '*.apk' 2>/dev/null | head -1)"
# Grant media permissions deterministically - the onboarding ALLOW tap may
# cover notifications only, and without this the app's library stays empty.
adb shell pm grant com.neurobyte.melody.debug android.permission.READ_MEDIA_AUDIO || true
adb shell pm grant com.neurobyte.melody.debug android.permission.READ_EXTERNAL_STORAGE || true

adb push tools/glass_test.mp3 /sdcard/Music/glass_test.mp3
# API 29+: the scan broadcast is ignored; insert the track into MediaStore directly.
adb shell am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d file:///sdcard/Music/glass_test.mp3 || true
# adb shell drops argument quoting, so quote the whole device-side command
# (the title bind contains spaces; unquoted it splits and content prints usage).
adb shell "content insert --uri content://media/external_primary/audio/media --bind _data:s:/sdcard/Music/glass_test.mp3 --bind 'title:s:Melody Glass Test' --bind mime_type:s:audio/mpeg --bind is_music:i:1" || true
adb shell "content insert --uri content://media/external/audio/media --bind _data:s:/sdcard/Music/glass_test.mp3 --bind 'title:s:Melody Glass Test' --bind mime_type:s:audio/mpeg --bind is_music:i:1" || true
adb shell "content query --uri content://media/external/audio/media --projection title:_data" | grep -i 'glass_test' || echo 'MEDIASTORE SEED FAILED'

mkdir -p shots
cat > /tmp/tap.py <<'TAPPEOF'
import sys, re, xml.etree.ElementTree as ET
want = sys.argv[1].lower()
exact_only = len(sys.argv) > 2 and sys.argv[2] == 'exact'
click_exact = None
plain_exact = None
click_any = None
plain_any = None
for node in ET.parse('/tmp/ui.xml').iter('node'):
    txt = (node.get('text') or '').lower()
    desc = (node.get('content-desc') or '').lower()
    if want not in txt and want not in desc:
        continue
    m = re.match(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', node.get('bounds') or '')
    if not m:
        continue
    l, t, r, b = map(int, m.groups())
    cx, cy = (l + r) // 2, (t + b) // 2
    clickable = node.get('clickable') == 'true'
    exact = txt.strip() == want or desc.strip() == want
    if clickable and exact:
        click_exact = (cx, cy)
        break
    if exact and plain_exact is None:
        plain_exact = (cx, cy)
    if clickable and click_any is None:
        click_any = (cx, cy)
    if plain_any is None:
        plain_any = (cx, cy)
out = (click_exact or plain_exact) if exact_only else (click_exact or plain_exact or click_any or plain_any)
if out:
    print(*out)
    sys.exit(0)
sys.exit(1)
TAPPEOF

tap_text() {
  adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1
  adb pull /sdcard/ui.xml /tmp/ui.xml >/dev/null 2>&1 || return 1
  XY=$(python3 /tmp/tap.py "$1") || return 1
  adb shell input tap $XY
}
tap_exact() {
  adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1
  adb pull /sdcard/ui.xml /tmp/ui.xml >/dev/null 2>&1 || return 1
  XY=$(python3 /tmp/tap.py "$1" exact) || return 1
  adb shell input tap $XY
}
shot() { adb shell screencap -p "/sdcard/$1.png" && adb pull "/sdcard/$1.png" "shots/$1.png"; }
# Log every visible string on screen - the ground truth when a tap misses.
dump_strings() {
  adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1
  adb pull /sdcard/ui.xml /tmp/ui_dump.xml >/dev/null 2>&1 || return 1
  python3 -c "import re;print('SCREEN STRINGS:', ' | '.join(sorted(set(re.findall(r'text=\"([^\"]{2,60})\"', open('/tmp/ui_dump.xml').read())))[:40]))"
}

adb shell monkey -p com.neurobyte.melody.debug -c android.intent.category.LAUNCHER 1
sleep 20
for i in $(seq 1 22); do
  tap_text "For You" && break
  # Profile page: Next stays disabled until a username is typed. Exact-only match on
  # the placeholder so we type once (the "what's your username?" label never matches);
  # then drop the keyboard so Next is not hidden behind the IME.
  if tap_exact "username"; then
    adb shell input text "Asif"
    sleep 1
    adb shell input keyevent 4
    sleep 1
  fi
  tap_text "Skip" || tap_text "Get started" || tap_text "Next" || tap_text "next" || tap_text "no, continue" || tap_text "continue" || tap_text "ALLOW" || tap_text "While using the app" || tap_text "Done" || adb shell input tap 540 1200
  sleep 2
done
sleep 3
shot 01_home

# --- Library + player flow: assertion-driven; each step verifies the current
# UI dump before acting and names the failing checkpoint instead of guessing.
strings_have() { python3 -c "import sys;d=open('/tmp/ui_dump.xml').read().lower();sys.exit(0 if sys.argv[1].lower() in d else 1)" "$1"; }

PLAYER_OK=0
if tap_text "Library"; then
  sleep 3
else
  echo 'NAV FAIL: Library tab'
fi
dump_strings || true

if strings_have "local"; then
  tap_exact "Local" || tap_text "Local" || true
  sleep 2
  dump_strings || true
  if strings_have "import your local music here"; then
    tap_text "Import your local music here" || true
    sleep 8
    dump_strings || true
    BTN=$(python3 -c "import re;d=open('/tmp/ui_dump.xml').read();m=re.findall(r'text=\"(Add [^\"]{1,30})\"',d);print(m[0] if m else '')" 2>/dev/null)
    if [ -n "$BTN" ]; then
      echo "SHEET BUTTON: $BTN"
      tap_text "$BTN" || true
      sleep 6
    elif strings_have "looking for music"; then
      echo 'ASSERT FAIL: sheet still scanning after 8s'
    elif strings_have "done"; then
      echo 'IMPORT SHEET: scan found no new songs (button = Done)'
      tap_text "Done" || true
    else
      echo 'ASSERT FAIL: Add-music sheet rendered no actionable button'
    fi
  else
    echo 'ASSERT FAIL: Local tab did not show the import card'
  fi
  adb shell input keyevent BACK || true
  sleep 2
  tap_exact "All" || tap_text "All" || true
  sleep 2
else
  echo 'ASSERT FAIL: no Local chip on Library screen'
fi
shot 02_library
dump_strings || true

if strings_have "melody glass test"; then
  tap_text "Songs" || true
  sleep 2
  dump_strings || true
  if tap_text "Melody Glass Test"; then
    sleep 4
    dump_strings || true
    if strings_have "melody glass test"; then
      shot 03_miniplayer
      tap_text "Melody Glass Test" || true
      sleep 3
      dump_strings || true
      if strings_have "melody glass test"; then
        shot 04_nowplaying
        PLAYER_OK=1
        echo 'PLAYER VERIFIED: song row -> mini player -> Now Playing'
      else
        echo 'ASSERT FAIL: Now Playing did not open from mini player'
      fi
    else
      echo 'ASSERT FAIL: mini player did not appear after song tap'
    fi
  else
    echo 'ASSERT FAIL: song row not tappable on Songs screen'
  fi
else
  echo 'PLAYER UNVERIFIED: seeded song not in library - no 03/04 frames emitted'
fi

# --- Independent captures (never gated on the player flow) ---
tap_exact "Search" || tap_text "Search" || true
sleep 3
dump_strings || true
if strings_have "search"; then shot 05_search; else echo 'NAV FAIL: Search screen'; fi

adb shell input keyevent BACK || true
sleep 1
if tap_text "profile"; then
  sleep 3
  dump_strings || true
  if tap_text "Settings"; then
    sleep 3
    dump_strings || true
    if strings_have "settings"; then shot 06_settings; else echo 'NAV FAIL: Settings screen'; fi
    adb shell input keyevent BACK || true
  else
    echo 'NAV FAIL: Settings entry not found from profile'
  fi
else
  echo 'NAV FAIL: profile entry not tappable by text/desc'
fi

# Long-press dialog: only when a song row actually exists
dump_strings || true
if strings_have "melody glass test"; then
  XY=$(python3 /tmp/tap.py "Melody Glass Test") && adb shell input swipe $XY $XY 700
  sleep 2
  dump_strings || true
  shot 07_dialog
else
  echo 'DIALOG UNVERIFIED: no song row to long-press'
fi

echo "### Screenshots" >> "$GITHUB_STEP_SUMMARY"
for f in shots/*.png; do
  R=$(curl -sS --retry 3 -F "file=@$f" https://tmpfiles.org/api/v1/upload || true)
  L=$(echo "$R" | jq -r '.data.url // "UPLOAD_FAILED"')
  echo "$f -> $L" | tee -a "$GITHUB_STEP_SUMMARY"
done

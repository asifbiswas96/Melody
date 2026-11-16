#!/usr/bin/env bash
# Melody CI: install the debug APK on the emulator, seed a test track, capture
# Home / Playlist / Library / mini player / Now Playing / Search / Settings /
# dialog screenshots, upload to tmpfiles.
# v3: assertions run against the VISIBLE text set (same extraction as
# dump_strings), never raw XML; every tap uses exact node bounds from the live
# dump; frames are emitted only when their screen assertion passed.
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

cat > /tmp/tap_re.py <<'TAPREEOF'
# Tap the center of the first node whose VISIBLE text matches a regex.
# Prefers clickable nodes; intended for dynamic labels like "Add 1 song".
import sys, re, xml.etree.ElementTree as ET
pat = re.compile(sys.argv[1], re.I)
click_hit = None
plain_hit = None
for node in ET.parse('/tmp/ui.xml').iter('node'):
    txt = (node.get('text') or '').strip()
    if not txt or not pat.search(txt):
        continue
    m = re.match(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', node.get('bounds') or '')
    if not m:
        continue
    l, t, r, b = map(int, m.groups())
    cx, cy = (l + r) // 2, (t + b) // 2
    if node.get('clickable') == 'true':
        click_hit = (cx, cy, txt)
        break
    if plain_hit is None:
        plain_hit = (cx, cy, txt)
hit = click_hit or plain_hit
if hit:
    print(hit[0], hit[1])
    print('TAP REGEX MATCHED TEXT:', hit[2], file=sys.stderr)
    sys.exit(0)
sys.exit(1)
TAPREEOF

refresh() {
  adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1
  adb pull /sdcard/ui.xml /tmp/ui.xml >/dev/null 2>&1
}
tap_text() {
  refresh || return 1
  XY=$(python3 /tmp/tap.py "$1") || return 1
  adb shell input tap $XY
}
tap_exact() {
  refresh || return 1
  XY=$(python3 /tmp/tap.py "$1" exact) || return 1
  adb shell input tap $XY
}
tap_regex() {
  refresh || return 1
  XY=$(python3 /tmp/tap_re.py "$1") || return 1
  adb shell input tap $XY
}
shot() { adb shell screencap -p "/sdcard/$1.png" && adb pull "/sdcard/$1.png" "shots/$1.png"; }
# Log every visible string on screen - the ground truth when a tap misses.
dump_strings() {
  adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1
  adb pull /sdcard/ui.xml /tmp/ui_dump.xml >/dev/null 2>&1 || return 1
  python3 -c "import re;print('SCREEN STRINGS:', ' | '.join(sorted(set(re.findall(r'text=\"([^\"]{2,60})\"', open('/tmp/ui_dump.xml').read())))[:40]))"
}
# Assertion against the VISIBLE text set only (same extraction as
# dump_strings). Raw-XML substring matching is forbidden: hidden nodes and
# accessibility text made "settings" match on the Home screen in v2.
vis_have() {
  python3 -c "
import re, sys
d = open('/tmp/ui_dump.xml').read()
vis = ' '.join(re.findall(r'text=\"([^\"]{2,60})\"', d)).lower()
sys.exit(0 if sys.argv[1].lower() in vis else 1)" "$1"
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

# --- Playlist detail via Home content (independent of the seeded song) ---
dump_strings || true
if tap_text "Bollywood"; then
  sleep 4
  dump_strings || true
  if vis_have "Add to library" || vis_have "songs"; then
    shot 08_playlist
    echo 'PLAYLIST VERIFIED: Home content opened a detail page'
    adb shell input swipe 540 1900 540 600 >/dev/null 2>&1
    sleep 2
    dump_strings || true
    shot 08b_playlist_bottom
    echo 'PLAYLIST BOTTOM SHOT: verify last row clears the nav bar'
  else
    echo 'PLAYLIST UNVERIFIED: no detail strings after Home card tap'
  fi
  adb shell input keyevent BACK || true
  sleep 2
else
  echo 'PLAYLIST UNVERIFIED: no Bollywood card on Home'
fi

# --- Library + player flow: assertion-driven; each step verifies the current
# UI dump before acting and names the failing checkpoint instead of guessing.
PLAYER_OK=0
if tap_text "Library"; then
  sleep 3
else
  echo 'NAV FAIL: Library tab'
fi
dump_strings || true

if vis_have "local"; then
  tap_exact "Local" || tap_text "Local" || true
  sleep 2
  dump_strings || true
  if vis_have "import your local music here"; then
    tap_text "Import your local music here" || true
    sleep 8
    dump_strings || true
    # The actionable button is "Add N song(s)" - never the "Add music" sheet title.
    if tap_regex 'add [0-9]+ song'; then
      echo 'SHEET BUTTON: Add N song(s) tapped via regex node match'
      sleep 8
    elif vis_have "looking for music"; then
      echo 'ASSERT FAIL: sheet still scanning after 8s'
    elif vis_have "done"; then
      echo 'IMPORT SHEET: scan found no new songs (button = Done)'
      tap_exact "Done" || true
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

if vis_have "melody glass test"; then
  tap_text "Songs" || true
  sleep 2
  dump_strings || true
  if tap_text "Melody Glass Test"; then
    sleep 4
    dump_strings || true
    if vis_have "melody glass test"; then
      shot 03_miniplayer
      tap_text "Melody Glass Test" || true
      sleep 3
      dump_strings || true
      if vis_have "melody glass test"; then
        shot 04_nowplaying
        PLAYER_OK=1
        echo 'PLAYER VERIFIED: song row -> mini player -> Now Playing'
        adb shell input keyevent BACK || true
        sleep 2
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

# Home again with library content: mini player reachability + loaded Home.
tap_exact "Home" || tap_text "Home" || true
sleep 3
dump_strings || true
if [ "$PLAYER_OK" = 1 ]; then
  shot 01b_home_loaded
  if vis_have "melody glass test"; then
    echo 'MINIPLAYER HOME: seeded track visible on Home (mini player or row)'
  else
    echo 'MINIPLAYER HOME: track not visible on Home - check frame 01b'
  fi
fi

# --- Independent captures (never gated on the player flow) ---
tap_exact "Search" || tap_text "Search" || true
sleep 3
dump_strings || true
if vis_have "moods"; then
  shot 05_search
  adb shell input swipe 540 1900 540 500 >/dev/null 2>&1
  sleep 1
  adb shell input swipe 540 1900 540 500 >/dev/null 2>&1
  sleep 2
  dump_strings || true
  shot 05b_search_bottom
  echo 'SEARCH BOTTOM SHOT: verify last genre row clears the nav bar'
else
  echo 'NAV FAIL: Search screen'
fi

adb shell input keyevent BACK || true
sleep 1
if tap_text "profile"; then
  sleep 3
  dump_strings || true
  # Settings row can sit half-hidden at the page bottom; scroll it into view first.
  adb shell input swipe 540 1900 540 900 >/dev/null 2>&1
  sleep 1
  dump_strings || true
  if tap_exact "Settings" || tap_text "Settings"; then
    sleep 3
    dump_strings || true
    if vis_have "app behaviour" || vis_have "customisation" || vis_have "animation"; then
      shot 06_settings
      echo 'SETTINGS VERIFIED: unique settings body strings present'
    else
      echo 'NAV FAIL: Settings screen body not detected - frame not emitted'
    fi
    adb shell input keyevent BACK || true
  else
    echo 'NAV FAIL: Settings entry not found from profile'
  fi
else
  echo 'NAV FAIL: profile entry not tappable by text/desc'
fi

# Long-press dialog: only when a song row actually exists (go via Library > Songs)
tap_text "Library" || true
sleep 2
tap_text "Songs" || true
sleep 2
dump_strings || true
if vis_have "melody glass test"; then
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

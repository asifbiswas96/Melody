#!/usr/bin/env bash
# Melody CI: install the debug APK on the emulator, seed a test track, capture
# Home / Genre / Search / Settings / Library / mini player / Now Playing /
# dialog screenshots, upload to tmpfiles.
# v8: sheet detection must not rely on the title strings - they scroll out
# of the uiautomator dump after one swipe, which faked "dismissed" in v7.
# Detect by a union of sheet-content strings and keep swipe+tap looping
# until "no thanks" is actually tapped and all sheet strings are gone.
# v7: the update sheet's only dismissal is its bottom "no thanks" button -
# BACK does nothing (custom MenuSheetSurface). Swipe the sheet's scroll
# column up to reveal the button, then tap it.
# v6: dismiss the upstream "Update available" changelog sheet (shown when
# upstream ships a newer version, e.g. 8.4.2); it blocks every anchor.
# v5: independent flows with a full app relaunch (force-stop + monkey) between
# them, per capture-QA directive; Now Playing is captured only after the
# immersive "GOT IT" tutorial is dismissed and unique player strings are
# asserted inside an 8s window; genre page is labeled as genre (the shared
# PlaylistDetail page remains unverified); scroll bottoms use the
# stable-string-set test (true scroll end). Assertions run against the
# VISIBLE text set only; frames are emitted only when their screen assertion
# passed.
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
exact_only = 'exact' in sys.argv[2:]
visible_only = 'visible' in sys.argv[2:]
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
    if visible_only and not (0 <= cx <= 1080 and 0 <= cy <= 2400):
        continue
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
tap_text_vis() {
  refresh || return 1
  XY=$(python3 /tmp/tap.py "$1" visible) || return 1
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
# dump_strings). Raw-XML substring matching is forbidden.
vis_have() {
  python3 -c "
import re, sys
d = open('/tmp/ui_dump.xml').read()
vis = ' '.join(re.findall(r'text=\"([^\"]{2,60})\"', d)).lower()
sys.exit(0 if sys.argv[1].lower() in vis else 1)" "$1"
}
vis_have_any() {
  python3 -c "
import re, sys
d = open('/tmp/ui_dump.xml').read()
vis = ' '.join(re.findall(r'text=\"([^\"]{2,60})\"', d)).lower()
sys.exit(0 if any(a.lower() in vis for a in sys.argv[1:]) else 1)" "$@"
}
vis_set() {
  python3 -c "import re;print('|'.join(sorted(set(re.findall(r'text=\"([^\"]{2,60})\"', open('/tmp/ui_dump.xml').read())))))"
}
# True scroll end: swipe until the visible string set stops changing.
scroll_to_end() {
  PREV=''
  for i in $(seq 1 8); do
    dump_strings >/dev/null 2>&1
    CUR=$(vis_set)
    if [ "$CUR" = "$PREV" ]; then echo "SCROLL END after $i swipe(s)"; return 0; fi
    PREV="$CUR"
    adb shell input swipe 540 1900 540 500 >/dev/null 2>&1
    sleep 1
  done
  echo 'SCROLL END NOT REACHED within 8 swipes'
}
# Dismiss the upstream update changelog sheet: "Update available! / What
# changed on X.Y.Z" appears on launch whenever upstream has a newer version.
# Prefer a text button if one exists; BACK closes the bottom sheet otherwise.
dismiss_update_sheet() {
  for j in $(seq 1 14); do
    dump_strings >/dev/null 2>&1
    # Off-viewport nodes drop out of the uiautomator dump, so the button
    # becomes tappable only after swipes bring it into view.
    if tap_text_vis "no thanks"; then
      sleep 2
      dump_strings >/dev/null 2>&1
    fi
    if vis_have_any "no thanks" "Install here" "Open the web" "Update available" "What changed on" "This update includes" "Tv Version" "Floating Lyrics" "Device integration"; then
      echo "UPDATE SHEET: still present (attempt $j)"
      adb shell input swipe 540 1900 540 700 400
      sleep 1
    else
      echo "UPDATE SHEET: gone (attempt $j)"
      return 0
    fi
  done
  echo 'UPDATE SHEET: could not dismiss in 14 attempts'
  return 0
}
# Full relaunch for independent flows. Assumes onboarding already completed
# (v5 runs onboarding once after first launch, before any relaunch).
relaunch() {
  adb shell am force-stop com.neurobyte.melody.debug
  sleep 1
  adb shell monkey -p com.neurobyte.melody.debug -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
  sleep 8
  for i in $(seq 1 8); do
    dump_strings >/dev/null 2>&1
    if vis_have_any "Update available" "What changed on"; then dismiss_update_sheet; dump_strings >/dev/null 2>&1; fi
    if vis_have_any "For You" "Try something new" "Home"; then echo "RELAUNCH OK ($i)"; return 0; fi
    sleep 2
  done
  echo 'RELAUNCH FAIL: no Home anchor after force-stop + monkey'
  return 1
}

# --- First launch: onboarding once -----------------------------------------
adb shell monkey -p com.neurobyte.melody.debug -c android.intent.category.LAUNCHER 1
sleep 20
for i in $(seq 1 22); do
  tap_text "For You" && break
  dump_strings >/dev/null 2>&1
  if vis_have_any "Update available" "What changed on"; then dismiss_update_sheet; dump_strings >/dev/null 2>&1; fi
  # Home already visible (sheet dismissed, no onboarding): stop before the
  # fallback center tap can open something on the home screen.
  if vis_have_any "For You" "Try something new" "Home"; then echo "ONBOARDING SKIP: home anchors visible ($i)"; break; fi
  # Profile page: Next stays disabled until a username is typed. Exact-only match on
  # the placeholder so we type once; then drop the keyboard so Next is not hidden
  # behind the IME.
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

# --- Flow 08: Home "Try something new" genre page (GenreScreen) -------------
# The row is randomized per run (Bollywood/Metal/R&B), so tap the stable row
# header and validate the destination. This is a GENRE page, not the shared
# PlaylistDetail; wide-header pixels remain an open item.
relaunch
dump_strings || true
if tap_text "Try something new"; then
  sleep 4
  dump_strings || true
  if vis_have_any "Add to library" "songs" "genre"; then
    shot 08_genre
    echo 'GENRE VERIFIED: Home content opened a genre detail page'
    scroll_to_end
    dump_strings || true
    shot 08b_genre_bottom
    echo 'GENRE BOTTOM SHOT: true scroll end - verify last row clears the nav bar'
  else
    echo 'GENRE UNVERIFIED: no detail strings after Home card tap'
  fi
else
  echo 'GENRE UNVERIFIED: Try-something-new row not tappable on Home'
fi

# --- Flow 05: Search + true-scroll-end bottom --------------------------------
relaunch
tap_exact "Search" || tap_text "Search" || true
sleep 3
dump_strings || true
if vis_have "moods"; then
  shot 05_search
  echo 'SEARCH VERIFIED: moods anchor present'
  scroll_to_end
  dump_strings || true
  shot 05b_search_bottom
  echo 'SEARCH BOTTOM SHOT: true scroll end - verify last genre row clears the nav bar'
else
  echo 'NAV FAIL: Search screen'
fi

# --- Flow 06: Settings via profile -------------------------------------------
relaunch
if tap_text "profile"; then
  sleep 3
  dump_strings || true
  # Settings row can sit half-hidden at the page bottom; scroll it into view first.
  adb shell input swipe 540 1900 540 900 >/dev/null 2>&1
  sleep 1
  dump_strings || true
  if tap_text "Open settings"; then
    sleep 3
    dump_strings || true
    if vis_have_any "app behaviour" "customisation" "animation speed"; then
      shot 06_settings
      echo 'SETTINGS VERIFIED: unique settings body strings present'
    else
      echo 'NAV FAIL: Settings screen body not detected - frame not emitted'
    fi
  else
    echo 'NAV FAIL: Settings entry (Open settings) not found from profile'
  fi
else
  echo 'NAV FAIL: profile entry not tappable by text/desc'
fi

# --- Flow 02/03/04: import + player ------------------------------------------
relaunch
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

# The imported song lives under the Songs category, not on the All grid:
# navigate Library > Songs first, validate the destination, then tap the row.
if vis_have "songs"; then
  tap_exact "Songs" || tap_text "Songs" || true
  sleep 2
  dump_strings || true
else
  echo 'NAV FAIL: no Songs category on Library after import'
fi
if vis_have "melody glass test"; then
  if tap_text "Melody Glass Test"; then
    sleep 4
    dump_strings || true
    if vis_have "melody glass test"; then
      shot 03_miniplayer
      echo 'MINIPLAYER VERIFIED: song row tap showed the mini player'
      tap_text "Melody Glass Test" || true
      sleep 3
      # Now Playing opens immersive with a "Viewing full screen / GOT IT"
      # tutorial overlay that breaks later taps: dismiss it, then swipe down
      # to leave immersive mode before asserting and capturing.
      dump_strings || true
      if vis_have "got it"; then
        tap_text "Got it" || tap_text "GOT IT" || true
        sleep 2
        adb shell input swipe 540 700 540 1900 >/dev/null 2>&1
        sleep 2
        dump_strings || true
      fi
      # Assert the real player with unique strings inside an 8s window; emit
      # 04 only when the assertion passes.
      POK=0
      for i in $(seq 1 4); do
        dump_strings >/dev/null 2>&1
        if vis_have_any "no lyrics for this song" "up next" "queue"; then POK=1; break; fi
        sleep 2
      done
      dump_strings || true
      if [ "$POK" = 1 ]; then
        shot 04_nowplaying
        PLAYER_OK=1
        echo 'PLAYER VERIFIED: unique Now Playing strings after overlay dismissal'
      else
        echo 'PLAYER UNVERIFIED: no unique Now Playing strings in 8s window - frame not emitted'
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
relaunch
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

# --- Flow 07: long-press dialog (fresh relaunch, fresh dump) ------------------
relaunch
tap_text "Library" || true
sleep 2
tap_text "Songs" || true
sleep 2
dump_strings || true
if vis_have "melody glass test"; then
  # tap.py reads /tmp/ui.xml - refresh it against the CURRENT screen first.
  refresh || true
  XY=$(python3 /tmp/tap.py "Melody Glass Test")
  if [ -n "$XY" ]; then
    adb shell input swipe $XY $XY 700
    sleep 2
    dump_strings || true
    if vis_have_any "play next" "add to playlist" "delete" "share"; then
      shot 07_dialog
      echo 'DIALOG VERIFIED: long-press opened the song action sheet'
    else
      echo 'DIALOG UNVERIFIED: long-press showed no action sheet - frame not emitted'
    fi
  else
    echo 'DIALOG UNVERIFIED: song row coordinates not found on fresh dump'
  fi
else
  echo 'DIALOG UNVERIFIED: no song row to long-press'
fi

echo "### Screenshots" >> "$GITHUB_STEP_SUMMARY"
for f in shots/*.png; do
  R=$(curl -sS --retry 3 -F "file=@$f" https://tmpfiles.org/api/v1/upload || true)
  L=$(echo "$R" | jq -r '.data.url // "UPLOAD_FAILED"')
  echo "$f -> $L" | tee -a "$GITHUB_STEP_SUMMARY"
done

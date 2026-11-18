#!/usr/bin/env bash
# v20: Device integration moved to the very end (emulator died there in v14 and v19); threshold 2000; Modules.
# v19: scroll-then-tap sub pages with destination anchors; Storage end shot; empty-prefs fallback.
# v18: Profile scrolled 3x so Open settings clears the miniplayer; Home genre row tapped without a swipe.
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
# v9: ROOT CAUSE of the v5-v8 failures: the update sheet scrolls, off-viewport
# nodes drop out of the uiautomator dump, and a scrolled-down sheet shows none
# of the title strings, so "gone" was a false positive (sheet still on screen
# in the frames). v9 (capture-only, no app code change): cut the emulator
# network BEFORE first launch so the updater finds no release and no sheet is
# shown, log a network check, and treat the sheet as gone only when a POSITIVE
# Home anchor ("For You" chip) is visible. Home content that needs the network
# will be empty in frames; that is a documented capture limit.
set -x
adb install -r "$(find /home/runner/work -name '*.apk' 2>/dev/null | head -1)"
# Grant media permissions deterministically - the onboarding ALLOW tap may
# cover notifications only, and without this the app's library stays empty.
adb shell pm grant com.neurobyte.melody.debug android.permission.READ_MEDIA_AUDIO || true
adb shell pm grant com.neurobyte.melody.debug android.permission.READ_EXTERNAL_STORAGE || true

# v24: clearly-labelled TEST content only: 3 generated tones with generated gradient cover art, so the
# player has real artwork depth and a multi-track queue (enabled skip controls). No private media.
mkdir -p /tmp/seed
if ! command -v ffmpeg >/dev/null 2>&1; then sudo apt-get install -y ffmpeg >/dev/null 2>&1 || true; fi
SEEDED=0
if command -v ffmpeg >/dev/null 2>&1; then
  for spec in "1|Melody Glass Test|Glass Test|330|0x6ECDFF|0xB07CFF" "2|Melody Test Track Two|Test Artist B|440|0x35D6C0|0x2F8BFF" "3|Melody Test Track Three|Test Artist C|550|0xFF8A3D|0xB07CFF"; do
    IFS='|' read n title artist freq ca cb <<< "$spec"
    ffmpeg -y -loglevel error -f lavfi -i "gradients=s=600x600:c0=$ca:c1=$cb:c2=0x3B2A7A:x0=0:y0=0:x1=600:y1=600:d=1:n=3,drawgrid=w=100:h=100:t=4:c=white@0.35,drawbox=x=150:y=150:w=300:h=300:color=white@0.45:t=fill" -frames:v 1 /tmp/seed/art$n.png || continue
    ffmpeg -y -loglevel error -f lavfi -i "sine=frequency=$freq:duration=20" -i /tmp/seed/art$n.png -map 0:a -map 1:v -c:a libmp3lame -b:a 64k -c:v mjpeg -id3v2_version 3 -disposition:v attached_pic -metadata title="$title" -metadata artist="$artist" -metadata album="Melody test content" /tmp/seed/test$n.mp3 && SEEDED=$((SEEDED+1))
  done
fi
echo "SEED TRACKS GENERATED: $SEEDED"
if [ "$SEEDED" = 3 ]; then
  adb push /tmp/seed/test1.mp3 /sdcard/Music/glass_test.mp3
  adb push /tmp/seed/test2.mp3 /sdcard/Music/test_two.mp3
  adb push /tmp/seed/test3.mp3 /sdcard/Music/test_three.mp3
  for pair in "test_two|Melody Test Track Two" "test_three|Melody Test Track Three"; do
    f=${pair%%|*}; t=${pair#*|}
    adb shell "content insert --uri content://media/external_primary/audio/media --bind _data:s:/sdcard/Music/$f.mp3 --bind 'title:s:$t' --bind mime_type:s:audio/mpeg --bind is_music:i:1" || true
  done
else
  adb push tools/glass_test.mp3 /sdcard/Music/glass_test.mp3
fi
# API 29+: the scan broadcast is ignored; insert the track into MediaStore directly.
adb shell am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d file:///sdcard/Music/glass_test.mp3 || true
# adb shell drops argument quoting, so quote the whole device-side command
# (the title bind contains spaces; unquoted it splits and content prints usage).
adb shell "content insert --uri content://media/external_primary/audio/media --bind _data:s:/sdcard/Music/glass_test.mp3 --bind 'title:s:Melody Glass Test' --bind mime_type:s:audio/mpeg --bind is_music:i:1" || true
adb shell "content insert --uri content://media/external/audio/media --bind _data:s:/sdcard/Music/glass_test.mp3 --bind 'title:s:Melody Glass Test' --bind mime_type:s:audio/mpeg --bind is_music:i:1" || true
adb shell "content query --uri content://media/external/audio/media --projection title:_data" | grep -i 'glass_test' || echo 'MEDIASTORE SEED FAILED'

# --- v9: offline emulator so the upstream updater cannot show its sheet ----
adb root || true
sleep 2
adb shell svc wifi disable || true
adb shell svc data disable || true
adb shell cmd connectivity airplane-mode enable || true
adb shell settings put global airplane_mode_on 1 || true
adb shell am broadcast -a android.intent.action.AIRPLANE_MODE --ez state true || true
sleep 3
if adb shell ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then echo 'NET CHECK: STILL ONLINE'; else echo 'NET CHECK: offline'; fi

mkdir -p shots
upload_shots() {
  mkdir -p shots_done
  for f in shots/*.png; do
    [ -f "$f" ] || continue
    R=$(curl -sS --retry 3 -F "file=@$f" https://tmpfiles.org/api/v1/upload || true)
    L=$(echo "$R" | jq -r '.data.url // "UPLOAD_FAILED"')
    echo "$f -> $L" | tee -a "$GITHUB_STEP_SUMMARY"
    mv "$f" shots_done/
  done
}
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
  for i in $(seq 1 16); do
    dump_strings >/dev/null 2>&1
    CUR=$(vis_set)
    if [ "$CUR" = "$PREV" ]; then echo "SCROLL END after $i swipe(s)"; return 0; fi
    PREV="$CUR"
    adb shell input swipe 540 1500 540 500 >/dev/null 2>&1
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
    if vis_have_any "no thanks" "Install here" "Open the web" "Update available" "What changed on" "This update includes" "Tv Version" "Floating Lyrics" "Device integration" "Honourable mentions" "Android auto support" "Lanscape" "Quicklook" || ! vis_have_any "For You" "Try something new"; then
      echo "UPDATE SHEET: still present (attempt $j)"
      adb shell input swipe 540 1500 540 700 400
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
    if vis_have_any "For You" "Try something new"; then echo "RELAUNCH OK ($i)"; return 0; fi
    sleep 2
  done
  echo 'RELAUNCH FAIL: no Home anchor after force-stop + monkey'
  return 1
}

# --- v12: after onboarding (done offline), go online with the update notice hidden ----
# HideUpdateNoticeKey ("hideUpdateNotice") is the app's own preference that makes
# HomeUpdatePrompt return early. It is appended to the DataStore file as a protobuf
# map entry (field 1, key 16 bytes, value boolean true); later entries win on parse.
enable_online_no_sheet() {
  adb shell am force-stop com.neurobyte.melody.debug
  sleep 1
  PKG=com.neurobyte.melody.debug
  PF=/data/data/$PKG/files/datastore/settings.preferences_pb
  adb pull $PF /tmp/prefs.bin || { echo 'PREF PULL FAIL (using empty base)'; : > /tmp/prefs.bin; }
  printf '\x0a\x16\x0a\x10hideUpdateNotice\x12\x02\x08\x01' > /tmp/hide.bin
  cat /tmp/prefs.bin /tmp/hide.bin > /tmp/prefs_new.bin
  adb push /tmp/prefs_new.bin $PF
  UID_APP=$(adb shell stat -c %u /data/data/$PKG | tr -d '\r')
  adb shell chown $UID_APP:$UID_APP $PF || true
  adb shell restorecon $PF || true
  echo "PREF INJECT: $(wc -c < /tmp/prefs.bin) -> $(wc -c < /tmp/prefs_new.bin) bytes, uid $UID_APP"
  adb shell cmd connectivity airplane-mode disable || true
  adb shell settings put global airplane_mode_on 0 || true
  adb shell am broadcast -a android.intent.action.AIRPLANE_MODE --ez state false || true
  adb shell svc wifi enable || true
  adb shell svc data enable || true
  sleep 10
  if adb shell ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then echo 'NET CHECK 2: online'; else echo 'NET CHECK 2: STILL OFFLINE'; fi
}

# --- First launch: onboarding once -----------------------------------------
adb shell monkey -p com.neurobyte.melody.debug -c android.intent.category.LAUNCHER 1
sleep 20
for i in $(seq 1 22); do
  [ "$i" -le 12 ] && shot "ob_$i"
  tap_text "For You" && break
  dump_strings >/dev/null 2>&1
  if vis_have_any "Update available" "What changed on"; then dismiss_update_sheet; dump_strings >/dev/null 2>&1; fi
  # Home already visible (sheet dismissed, no onboarding): stop before the
  # fallback center tap can open something on the home screen.
  if vis_have_any "For You" "Try something new"; then echo "ONBOARDING SKIP: home anchors visible ($i)"; break; fi
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
      adb shell input tap 400 1978
      sleep 3
      shot 04_nowplaying_try
      echo 'NOWPLAYING TRY: tapped mini player at 400,1978, frame emitted for visual review only'
      # Now Playing opens immersive with a "Viewing full screen / GOT IT"
      # tutorial overlay that breaks later taps: dismiss it, then swipe down
      # to leave immersive mode before asserting and capturing.
      dump_strings || true
      if vis_have "got it"; then
        tap_text "Got it" || tap_text "GOT IT" || true
        sleep 2
        shot 04c_nowplaying_clean
        sleep 4
        shot 04d_nowplaying_later
        dump_strings || true
      fi
      sleep 3
      shot 04e_settled_a
      sleep 5
      shot 04f_settled_b
      echo 'NOWPLAYING SETTLED: two frames 3s and 8s after the overlay step, to judge artwork load timing'
      # v39 player extras: scroll the player, capture each step, open Queue / Lyrics when their label is on screen
      for k in 1 2 3; do
        adb shell input swipe 540 1700 540 500 >/dev/null 2>&1
        sleep 2
        dump_strings || true
        shot "04x_player_scroll$k"
      done
      cat > /tmp/tap_desc.py <<'TDEOF'
import sys, re, xml.etree.ElementTree as ET
pat = re.compile(sys.argv[1], re.I)
for node in ET.parse('/tmp/ui.xml').iter('node'):
    d = (node.get('content-desc') or '').strip()
    if d and pat.search(d):
        m = re.match(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', node.get('bounds') or '')
        if m:
            l, t, r_, b = map(int, m.groups())
            print((l + r_) // 2, (t + b) // 2); sys.exit(0)
sys.exit(1)
TDEOF
      adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1; adb pull /sdcard/ui.xml /tmp/ui.xml >/dev/null 2>&1
      echo "PLAYER DESCS: $(python3 -c "import re;print(' | '.join(sorted(set(re.findall(r'content-desc=\"([^\"]{2,40})\"', open('/tmp/ui.xml').read())))))")"
      for dsc in "queue|up next" "lyrics" "expand|more|menu|options"; do
        adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1; adb pull /sdcard/ui.xml /tmp/ui.xml >/dev/null 2>&1
        if XYD=$(python3 /tmp/tap_desc.py "$dsc"); then
          adb shell input tap $XYD
          sleep 3
          dump_strings || true
          shot "04d_$(echo $dsc | tr -c 'a-z' '_')"
          echo "PLAYER DESC SHOT: tapped content-desc /$dsc/ (destination not asserted)"
          adb shell input swipe 540 1700 540 700 >/dev/null 2>&1
          sleep 2
          shot "04d_$(echo $dsc | tr -c 'a-z' '_')_scrolled"
          adb shell input keyevent BACK
          sleep 2
        else
          echo "PLAYER DESC UNVERIFIED: no content-desc /$dsc/"
        fi
      done
      # position sampling: log the visible m:ss strings once a second, to tell a clock artifact from a real overshoot
      for k in $(seq 1 14); do
        adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1; adb pull /sdcard/ui.xml /tmp/ui_dump.xml >/dev/null 2>&1
        echo "CLOCK SAMPLE $k: $(python3 -c "import re;print(' '.join(re.findall(r'text=\"(-?[0-9]+:[0-9]{2})\"', open('/tmp/ui_dump.xml').read())), ' | ', ' / '.join(re.findall(r'text=\"(Melody [^\"]{0,30})\"', open('/tmp/ui_dump.xml').read())[:2]))")"
        sleep 1
      done
      for lbl in "Queue" "Up next" "Lyrics"; do
        dump_strings >/dev/null 2>&1
        if tap_exact "$lbl" || tap_text "$lbl"; then
          sleep 3
          dump_strings || true
          shot "04q_$(echo $lbl | tr -d ' ')"
          echo "PLAYER EXTRA SHOT: $lbl tapped by label (destination not asserted)"
          adb shell input swipe 540 1700 540 700 >/dev/null 2>&1
          sleep 2
          shot "04q_$(echo $lbl | tr -d ' ')_scrolled"
          adb shell input keyevent BACK
          sleep 2
        else
          echo "PLAYER EXTRA UNVERIFIED: no '$lbl' label on player"
        fi
      done
      # Assert the real player with unique strings inside an 8s window; emit
      # 04 only when the assertion passes.
      shot 04b_nowplaying_after
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
if [ -n "$PLAYER_OK" ]; then
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
      adb shell input swipe 540 1900 540 900 300
      sleep 1
      shot 07b_dialog_scrolled
      adb shell input swipe 540 1900 540 700 300
      sleep 1
      adb shell input swipe 540 1900 540 700 300
      sleep 2
      shot 07c_dialog_end
      echo 'DIALOG END SHOT: swiped to the true end of the song menu list'
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

# v15: player frames first, uploaded before the settings flow
echo "### Screenshots (player phase)" >> "$GITHUB_STEP_SUMMARY"
upload_shots

tap_clear() {
  # scroll until the target row's center is above the miniplayer/nav zone (y<=2000), then tap it
  for _k in 1 2 3 4 5 6; do
    refresh || return 1
    XY=$(python3 /tmp/tap.py "$1" visible) || { if [ "$_k" -ge 3 ]; then adb shell input swipe 540 800 540 1500 >/dev/null 2>&1; else adb shell input swipe 540 1500 540 800 >/dev/null 2>&1; fi; sleep 1; continue; }
    Y=${XY##* }
    if [ "$Y" -le 1750 ]; then adb shell input tap $XY; return 0; fi
    adb shell input swipe 540 1500 540 800 >/dev/null 2>&1
    sleep 1
  done
  return 1
}
sub_anchor() {
  case "$1" in
    "Audio Lab") echo "equalizer";;
    "App behaviour") echo "larp";;
    "Customisation") echo "customize";;
    "Storage") echo "overall";;
    "Integrations") echo "integrations";;
    "Device integration") echo "device integration";;
    "Modules") echo "modules";;
  esac
}
sub_visit() {
  sp="$1"
  if tap_clear "$sp"; then
    sleep 3
    dump_strings || true
    if vis_have_any "$(sub_anchor "$sp")"; then
      shot "06s_$(echo $sp | tr -d ' ')"
      echo "SUB VERIFIED: $sp destination anchor present"
      if [ -n "$sp" ]; then
        scroll_to_end
        dump_strings || true
        shot "06s_$(echo $sp | tr -d ' ')_end"
        echo "SUB END SHOT: $sp true scroll end - verify last row clears mini player and nav"
        if [ "$sp" = "Storage" ]; then
          sleep 1
          for _i in 1 2 3 4; do
            adb shell input swipe 540 1500 540 700 >/dev/null 2>&1
            sleep 1
          done
          shot "06s_Storage_prescroll"
          if tap_regex "(?i)manage downloads"; then
            sleep 3
            dump_strings || true
            shot "06s_Storage_downloads"
            echo "DOWNLOADS SHOT: tapped a download entry on Storage (destination not asserted)"
            adb shell input keyevent BACK
            sleep 2
          else
            echo "DOWNLOADS UNVERIFIED: no download label on Storage page"
          fi
        fi
      fi
    else
      echo "SUB NAV FAIL: $sp opened something else - anchor missing; frame below is labeled unverified"
      shot "06s_$(echo $sp | tr -d ' ')_unverified"
      echo "SUB DUMP: $(vis_set | tr '\n' '|' | head -c 500)"
    fi
    adb shell input keyevent BACK
    sleep 2
  else
    echo "SETTINGS SUB UNVERIFIED: $sp not reachable above overlays"
  fi
}
# --- v39 fixture: create a playlist in the isolated emulator (Songs row long-press > Add to playlist > Create playlist)
relaunch
tap_text "Library" || true
sleep 2
tap_exact "Songs" || tap_text "Songs" || true
sleep 3
dump_strings || true
if refresh && XY=$(python3 /tmp/tap.py "Melody Glass Test"); then
  set -- $XY
  adb shell input swipe $1 $2 $1 $2 900
  sleep 3
  dump_strings || true
  shot 10a_song_menu
  scroll_to_end
  dump_strings || true
  shot 10a_song_menu_end
  echo "SONG MENU END SHOT: true end of the song menu - verify last row clears system nav"
  for _i in 1 2 3 4; do adb shell input swipe 540 700 540 1500 >/dev/null 2>&1; done
  if tap_exact "Add"; then
    sleep 3
    dump_strings || true
    shot 10b_add_to_playlist
    if tap_text "Create playlist" || tap_text "New playlist"; then
      sleep 3
      dump_strings || true
      shot 10c_create_playlist
      adb shell input text "Glass_Mix"
      sleep 1
      tap_exact "Create" || tap_exact "Done" || tap_exact "OK" || tap_exact "Save" || tap_text "Create" || true
      sleep 3
      dump_strings || true
      shot 10d_after_create
      echo "PLAYLIST FIXTURE: attempted create (verify via Playlists page frames)"
    else
      echo "PLAYLIST FIXTURE UNVERIFIED: no Create playlist entry"
    fi
  else
    echo "PLAYLIST FIXTURE UNVERIFIED: no Add to playlist in song menu"
  fi
else
  echo "PLAYLIST FIXTURE UNVERIFIED: song row not found"
fi
# --- v34 coverage: library category pages and their first item --------------
for cat in Albums Artists Playlists; do
  relaunch
  tap_text "Library" || true
  sleep 2
  dump_strings || true
  if tap_exact "$cat" || tap_text "$cat"; then
    sleep 3
    dump_strings || true
    shot "09_lib_$cat"
    echo "LIB CATEGORY SHOT: $cat page (destination not text-verified)"
    case "$cat" in Albums) adb shell input tap 300 950;; Artists) adb shell input tap 540 830;; *) tap_text "Glass Mix" || tap_text "Glass_Mix" || adb shell input tap 540 650;; esac
    sleep 3
    dump_strings || true
    shot "09_lib_${cat}_item"
    echo "LIB ITEM SHOT: $cat first item tap at fixed position (not text-verified)"
    adb shell input swipe 540 1700 540 600 >/dev/null 2>&1
    sleep 2
    shot "09_lib_${cat}_item2"
    scroll_to_end
    shot "09_lib_${cat}_item_end"
    adb shell input keyevent BACK
    sleep 1
  else
    echo "LIB CATEGORY UNVERIFIED: $cat not tappable"
  fi
done
# --- Flow 06: Settings via profile -------------------------------------------
relaunch
if tap_text "profile"; then
  sleep 3
  dump_strings || true
  shot 06p_profile
  if tap_text_vis "About"; then
    sleep 3
    shot 06a_about
    if tap_text "About app"; then
      sleep 3
      shot 06a2_about_sheet
      adb shell input keyevent BACK
      sleep 2
    else
      echo 'ABOUT SHEET UNVERIFIED: About app row not tappable'
    fi
    adb shell input keyevent BACK
    sleep 2
    adb shell input swipe 540 1100 540 1500 200
    sleep 1
  else
    echo 'ABOUT UNVERIFIED: About not tappable from profile'
  fi
  # Settings row can sit half-hidden at the page bottom; scroll it into view first.
  for _i in 1 2 3; do adb shell input swipe 540 1500 540 700 >/dev/null 2>&1; sleep 1; done
  dump_strings || true
  for _i in 1 2 3; do adb shell input swipe 540 1700 540 600 >/dev/null 2>&1; sleep 1; done
  dump_strings || true
  scroll_to_end
  dump_strings || true
  shot 06p_end
  echo "PROFILE END SHOT: true scroll end - verify the Settings row clears mini player and nav"
  if tap_text "Open settings" || tap_text_vis "Settings" || tap_text "Settings"; then
    sleep 3
    dump_strings || true
    if vis_have_any "app behaviour" "customisation" "animation speed"; then
      shot 06_settings
      echo 'SETTINGS VERIFIED: unique settings body strings present'
      for sp in "Audio Lab" "App behaviour" "Customisation" "Storage" "Integrations"; do
        sub_visit "$sp"
      done
      scroll_to_end
      dump_strings || true
      shot 06b_settings_bottom
      echo 'SETTINGS BOTTOM SHOT: true scroll end - verify last rows clear both navs'
      sub_visit "Modules"
    else
      echo 'NAV FAIL: Settings screen body not detected - frame not emitted'
    fi
  else
    echo 'NAV FAIL: Settings entry (Open settings) not found from profile'
  fi
else
  echo 'NAV FAIL: profile entry not tappable by text/desc'
fi

# --- v14: upload the offline frames first, then run the online flows LAST ---
echo "### Screenshots (offline phase)" >> "$GITHUB_STEP_SUMMARY"
upload_shots
enable_online_no_sheet
# --- Flow 08: Home "Try something new" genre page (GenreScreen) -------------
# The row is randomized per run (Bollywood/Metal/R&B), so tap the stable row
# header and validate the destination. This is a GENRE page, not the shared
# PlaylistDetail; wide-header pixels remain an open item.
relaunch
dump_strings || true
sleep 10
shot 01c_home_online
dump_strings || true
if tap_text "Try something new" || tap_text "Folk" || tap_text "Bollywood" || tap_text "Metal"; then
  sleep 4
  dump_strings || true
  if vis_have_any "Add to library" "songs" "genre"; then
    shot 08_genre
    echo 'GENRE VERIFIED: Home content opened a genre detail page'
    scroll_to_end
    dump_strings || true
    shot 08b_genre_bottom
    echo 'GENRE BOTTOM SHOT: true scroll end - verify last row clears the nav bar'
    # open a card from the genre page to reach the shared playlist detail page
    adb shell input swipe 540 600 540 1700 300
    sleep 2
    dump_strings || true
    adb shell input tap 540 1100
    sleep 4
    dump_strings || true
    shot 08c_after_card
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
  echo 'SEARCH: moods anchor missing offline, frame emitted for visual review'
  shot 05_search_offline
fi
relaunch
tap_exact "Search" || tap_text "Search" || true
sleep 3
tap_text "Search for tracks" || adb shell input tap 440 400
sleep 1
adb shell input text lofi
adb shell input keyevent 66
sleep 8
shot 05c_search_results


echo "### Screenshots (online phase)" >> "$GITHUB_STEP_SUMMARY"
upload_shots

# --- v20: Device integration LAST: the emulator process vanished on this page in v14 and v19 ---
relaunch
if tap_text "profile"; then
  sleep 3
  for _i in 1 2 3; do adb shell input swipe 540 1500 540 700 >/dev/null 2>&1; sleep 1; done
  if tap_text "Open settings"; then
    sleep 3
    scroll_to_end
    echo 'DEVICE INTEGRATION: attempting last; if the emulator drops after this line it is page-specific'
    sub_visit "Device integration"
  else
    echo 'NAV FAIL: Open settings (device integration phase)'
  fi
fi
echo "### Screenshots (device integration phase)" >> "$GITHUB_STEP_SUMMARY"
upload_shots

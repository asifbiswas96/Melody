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

# v43 diagnostics: host-side logcat so an emulator death leaves evidence (printed on exit)
adb logcat -c >/dev/null 2>&1 || true
( adb logcat -v time > /tmp/lc_all.txt 2>&1 & ) 
diag_tail() {
  echo "### LOGCAT DIAG (crash/ANR/memory lines)"
  grep -aE "FATAL EXCEPTION|ANR in|Fatal signal|OutOfMemory|lowmemorykiller|Process .* has died|am_proc_died|am_crash|Out of memory" /tmp/lc_all.txt 2>/dev/null | tail -25 | cut -c1-220
  echo "### CRASH STACKS (50 lines after each FATAL)"
  grep -a -A50 "FATAL EXCEPTION" /tmp/lc_all.txt 2>/dev/null | cut -c1-240 | head -200
  echo "### CRASH BUFFER"
  adb logcat -b crash -d 2>/dev/null | cut -c1-240 | head -120
  echo "### LOGCAT LAST LINES"
  tail -12 /tmp/lc_all.txt 2>/dev/null | cut -c1-220
}
trap diag_tail EXIT
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

# --- v46 DIRECT PLAYER: state-gated gestures + read-only audio diagnostics, then stop (no tour) ---
on_player() {
  dump_strings >/dev/null 2>&1 || return 1
  python3 - <<'PYEOF'
import re, sys
d = open('/tmp/ui_dump.xml').read()
t = re.findall(r'text="([^"]{1,60})"', d)
times = [x for x in t if re.fullmatch(r'-?\d+:\d\d', x)]
bad = [x for x in t if x in ('Search your library', 'Library', 'Songs', 'For You')]
sys.exit(0 if len(times) >= 2 and not bad else 1)
PYEOF
}
on_page() {
  dump_strings >/dev/null 2>&1 || return 1
  python3 - <<'PYEOF'
import re, sys
d = open('/tmp/ui_dump.xml').read()
t = ' | '.join(re.findall(r'text="([^"]{1,60})"', d)).lower()
sys.exit(0 if ('up next' in t or 'queue' in t or 'lyrics' in t) and 'search your library' not in t else 1)
PYEOF
}
ensure_player() {
  for _a in 1 2 3; do
    if on_player; then return 0; fi
    adb shell input tap 400 1978; sleep 3
    dump_strings >/dev/null 2>&1 || true
    if vis_have "got it"; then tap_text "Got it" || tap_text "GOT IT" || true; sleep 3; fi
  done
  on_player
}
media_state() {
  echo "MEDIA STATE $1: $(adb shell dumpsys media_session 2>/dev/null | grep -aoE 'state=PlaybackState \{state=[A-Z_]+\([0-9]\), position=[0-9]+, buffered position=[0-9]+, speed=[0-9.]+' | head -1)"
}
gesture() {
  # $1 label, rest: adb input args. Gate on the player first; never swipe Library.
  lbl=$1; shift
  if ensure_player; then
    shot "g_${lbl}_before"
    adb shell input "$@"
    sleep 3
    dump_strings || true
    shot "g_${lbl}_after"
    if on_page; then echo "ROUTE RESULT $lbl: queue/lyrics-type page strings present"; else echo "ROUTE RESULT $lbl: no queue/lyrics strings after gesture"; fi
  else
    echo "GATE FAIL $lbl: player not on screen after 3 attempts, gesture skipped (this does NOT show the page is absent)"
    shot "g_${lbl}_gatefail"
  fi
}
close_page() {
  if on_page && ! on_player; then adb shell input swipe 540 600 540 1700 500; sleep 3; fi
}
relaunch
tap_text "Library" || true
sleep 2
tap_exact "Songs" || tap_text "Songs" || true
sleep 3
tap_text "Melody Glass Test" || true
sleep 4
adb shell input tap 400 1978
sleep 3
dump_strings || true
if vis_have "got it"; then tap_text "Got it" || tap_text "GOT IT" || true; sleep 3; fi
media_state start
if ensure_player; then
  echo "DIRECT PLAYER: player gate passed"
  shot d00_player
  gesture card_swipe swipe 540 1480 540 700 500
  close_page
  gesture strip_swipe swipe 540 2300 540 800 500
  close_page
  if ensure_player; then
    adb shell input tap 909 1367; sleep 2
    dump_strings || true
    shot d03_chevron_menu
    if tap_text "Other menu"; then sleep 3; dump_strings || true; shot d04_other_menu; echo "ROUTE: Other menu tapped (strings dumped above)"; else echo "ROUTE: Other menu row not found by text"; fi
  else
    echo "GATE FAIL chevron: player not on screen"
  fi
  # read-only diagnostics once the last item passes its duration
  for k in $(seq 1 16); do
    media_state "wait$k"
    P=$(adb shell dumpsys media_session 2>/dev/null | grep -aoE 'position=[0-9]+' | head -1 | cut -d= -f2)
    if [ -n "$P" ] && [ "$P" -gt 24000 ]; then echo "END DIAG: position $P ms"; break; fi
    sleep 5
  done
  media_state end
  echo "### AUDIO FLINGER (read-only)"
  adb shell dumpsys media.audio_flinger 2>&1 | grep -aE "Output thread|Standby|Tracks of|Active|state|Frames|Underruns|Mixer" | head -50 | cut -c1-200
  echo "### MEDIA SESSION (read-only)"
  adb shell dumpsys media_session 2>&1 | grep -aE "PlaybackState|metadata|active=|Sessions Stack" | head -12 | cut -c1-300
  echo "### MEDIA PLAYER"
  adb shell dumpsys media.player 2>&1 | head -25 | cut -c1-200
  ensure_player || true
  shot d99_player_end
else
  echo "GATE FAIL: player never reached, diagnostics skipped"
  shot d00_gatefail
fi
echo "### Screenshots (direct player)" >> "$GITHUB_STEP_SUMMARY"
upload_shots
exit 0

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
  if tap_exact "Add"; then
    sleep 3
    dump_strings || true
    shot 10b_add_to_playlist
    if tap_text "Create playlist" || tap_text "New playlist"; then
      sleep 3
      dump_strings || true
      shot 10c_create_playlist
      tap_text "Name your playlist" || adb shell input tap 540 900
      sleep 1
      adb shell input text "Glass_Mix"
      sleep 1
      shot 10c2_name_typed
      sleep 1
      tap_exact "Create playlist" || tap_text "Create playlist" || true
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
# --- v45: put a song into Glass_Mix, then open the populated playlist detail ---
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
  if tap_exact "Add"; then
    sleep 3
    dump_strings || true
    if tap_text "Glass_Mix"; then
      sleep 3
      dump_strings || true
      shot 10e_added_to_playlist
      echo "PLAYLIST INSERT: tapped Glass_Mix row in Add-to-playlist list"
    else
      echo "PLAYLIST INSERT UNVERIFIED: no Glass_Mix row"
    fi
  else
    echo "PLAYLIST INSERT UNVERIFIED: no Add in song menu"
  fi
fi
relaunch
tap_text "Library" || true
sleep 2
if tap_exact "Playlists" || tap_text "Playlists"; then
  sleep 3
  if tap_text "Glass_Mix" || tap_text "Glass Mix"; then
    sleep 3
    dump_strings || true
    shot 09_playlist_detail_populated
    echo "PLAYLIST DETAIL SHOT: populated detail (check song count in strings above)"
    adb shell input swipe 540 1700 540 600 >/dev/null 2>&1
    sleep 2
    shot 09_playlist_detail_populated_2
    scroll_to_end
    shot 09_playlist_detail_populated_end
  else
    echo "PLAYLIST DETAIL UNVERIFIED: Glass_Mix row not found"
  fi
fi
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
# v44: focused run, the online phase (genre, search, device integration) is skipped; those screens were captured in earlier runs
# --- v45: bounded player diagnostics (crash stacks so far, media position vs duration, queue/lyrics routes) ---
echo "### CRASH EXCERPT AFTER SETTINGS"
grep -a -A40 "FATAL EXCEPTION" /tmp/lc_all.txt 2>/dev/null | cut -c1-240 | head -120
for n in 1 2 3; do echo "SEED DURATION test$n: $(ffprobe -v error -show_entries format=duration -of csv=p=0 /tmp/seed/test$n.mp3 2>&1)"; done
relaunch
tap_text "Library" || true
sleep 2
tap_exact "Songs" || tap_text "Songs" || true
sleep 3
if tap_text "Melody Glass Test"; then
  sleep 4
  adb shell input tap 400 1978
  sleep 3
  dump_strings || true
  if vis_have "got it"; then tap_text "Got it" || tap_text "GOT IT" || true; sleep 3; fi
  shot 04z_player_open
  media_probe() {
    echo "MEDIA PROBE $1: $(adb shell dumpsys media_session 2>/dev/null | grep -aE 'state=PlaybackState|metadata:' | head -4 | tr '\n' ' ' | cut -c1-420)"
    echo "MEDIA DURATION $1: $(adb shell dumpsys media_session 2>/dev/null | grep -aoE 'android.media.metadata.DURATION[^,]{0,30}' | head -2 | tr '\n' ' ')"
    adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1; adb pull /sdcard/ui.xml /tmp/ui_dump.xml >/dev/null 2>&1
    echo "CLOCK SAMPLE $1: $(python3 -c "import re;d=open('/tmp/ui_dump.xml').read();print(' '.join(re.findall(r'text=\"(-?[0-9]+:[0-9]{2})\"', d)), ' | ', ' / '.join(re.findall(r'text=\"(Melody [^\"]{0,30})\"', d)[:2]))")"
  }
  for k in 1 2 3 4 5 6 7 8; do media_probe $k; sleep 3; done
  # route 1: chevron menu, then its "Other menu" row
  adb shell input tap 909 1367
  sleep 2
  dump_strings || true
  shot 04m_chevron_menu
  if tap_text "Other menu"; then
    sleep 3
    dump_strings || true
    shot 04n_other_menu
    echo "PLAYER ROUTE: tapped Other menu from chevron menu"
    adb shell input keyevent BACK
    sleep 2
  fi
  adb shell input keyevent BACK
  sleep 2
  # route 2: slow swipe up starting on the card below the seek bar (PULL), then on the bottom strip
  adb shell input swipe 540 1480 540 700 500
  sleep 3
  dump_strings || true
  shot 04r_swipe_card
  echo "PLAYER ROUTE: slow swipe up from the card (540,1480)"
  adb shell input swipe 540 2300 540 800 500
  sleep 3
  dump_strings || true
  shot 04s_swipe_strip
  echo "PLAYER ROUTE: slow swipe up from the bottom strip (540,2300)"
  adb shell input swipe 540 2300 540 800 500
  sleep 3
  dump_strings || true
  shot 04t_swipe_strip_again
  media_probe 9
else
  echo 'PLAYER DIAG UNVERIFIED: song row not tappable'
fi
echo "### Screenshots (player extras phase)" >> "$GITHUB_STEP_SUMMARY"
upload_shots

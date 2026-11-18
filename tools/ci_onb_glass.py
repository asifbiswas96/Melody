# CI-only: the Melody patch zips overwrite the onboarding sources after checkout, so the glass
# treatment of onboarding is applied to the zips' versions here (UI only, no logic change).
import re, os, glob
B = 'app/src/main/kotlin/com/mochyy/mochymusic/ui/'

def edit(path, pairs, imports=()):
    s = open(B + path).read()
    for old, new in pairs:
        assert old in s, 'anchor missing in %s: %s' % (path, old[:60])
        s = s.replace(old, new)
    add = [i for i in imports if i not in s]
    if add:
        k = s.index('\nimport ')
        s = s[:k + 1] + '\n'.join(add) + '\n' + s[k + 1:]
    open(B + path, 'w').write(s)
    print('patched', path)

BORDER = 'import androidx.compose.foundation.border'
EDGE = 'import com.mochyy.mochymusic.ui.component.MelodyGlassEdgeBrush'
GLOW = 'import com.mochyy.mochymusic.ui.component.melodyGlowBackground'

p = B + 'screens/setup/onboarding/OnboardingDesign.kt'
s = open(p).read()
a = s.index('internal fun PageBadge')
b = s.index('internal enum class OnbButtonStyle')
s = s[:a] + ('internal fun PageBadge(icon: Painter, size: Dp = 40.dp) {\n'
    '    com.mochyy.mochymusic.ui.component.GlassIconTile(size = size) {\n'
    '        Icon(icon, contentDescription = null, tint = Color(0xFFF4F7FF), modifier = Modifier.size(size * 0.5f))\n'
    '    }\n}\n\n') + s[b:]
open(p, 'w').write(s)

edit('screens/setup/onboarding/OnboardingDesign.kt', [
    ('val Card = Color(0xFF0E1A38)', 'val Card = Color(0x9E101A30)'),
    ('val CardPressed = Color(0xFF1A2A4A)', 'val CardPressed = Color(0xB8203A66)'),
    ('val Field = Color(0xFF0E1A38)', 'val Field = Color(0x9E101A30)'),
    ('val ButtonSecondary = Color(0xFF16224A)', 'val ButtonSecondary = Color(0x9E101A30)'),
    ('.background(if (style == OnbButtonStyle.Primary) Onb.ButtonPrimary else Onb.ButtonSecondary)',
     '.background(if (style == OnbButtonStyle.Primary) Brush.verticalGradient(listOf(Color(0xFF6ECDFF), Color(0xFF4FB4F0))) else Brush.verticalGradient(listOf(Onb.ButtonSecondary, Onb.ButtonSecondary)))\n'
     '            .border(1.dp, MelodyGlassEdgeBrush, CircleShape)'),
    ('color = if (style == OnbButtonStyle.Primary) Color.White else Onb.Muted,',
     'color = if (style == OnbButtonStyle.Primary) Color(0xFF06121F) else Onb.Title,'),
    ('.background(Onb.Field)', '.background(Onb.Field)\n                    .border(1.dp, MelodyGlassEdgeBrush, CircleShape)'),
    ('.background(if (pressed) Onb.CardPressed else Onb.Card)',
     '.background(if (pressed) Onb.CardPressed else Onb.Card)\n            .border(1.dp, MelodyGlassEdgeBrush, shape)'),
], [BORDER, EDGE])

edit('screens/setup/SetupWizardScreen.kt', [
    ('.background(Onb.Page),\n        ) {', '.background(Onb.Page)\n                .melodyGlowBackground(),\n        ) {'),
], [GLOW])

edit('screens/setup/onboarding/CardMoments.kt', [
    ('"welcome to mochy!"', '"welcome to Melody!"'),
    ('silver = true,', 'silver = false,'),
])

edit('screens/setup/WelcomeStep.kt', [
    ('.background(WelcomeColors.Page)\n            .clickable(', '.background(WelcomeColors.Page)\n            .melodyGlowBackground()\n            .clickable('),
    ('.clip(RoundedCornerShape(28.dp))\n                .graphicsLayer {\n                    translationY = leave',
     '.clip(RoundedCornerShape(28.dp))\n                .border(1.dp, MelodyGlassEdgeBrush, RoundedCornerShape(28.dp))\n                .graphicsLayer {\n                    translationY = leave'),
], [GLOW, BORDER, EDGE])

# audit: any Mochy wording still in default-locale strings or UI literals (report only)
for f in glob.glob('app/src/main/res/values/*.xml'):
    for n, l in enumerate(open(f, errors='ignore'), 1):
        if re.search('mochy', l, re.I) and 'name="' in l and not l.strip().startswith('<!--'):
            print('AUDIT-STR', os.path.basename(f), n, l.strip()[:140])
for f in glob.glob(B + '**/*.kt', recursive=True):
    for n, l in enumerate(open(f, errors='ignore'), 1):
        if re.search(r'"[^"]*mochy[^"]*"', l, re.I) and not re.search(r'import|package|R\.|Uri|http|\.mochy|Log|TAG|"mochy[a-z_.]*"\s*[,)]', l, re.I):
            print('AUDIT-KT', f[len(B):], n, l.strip()[:140])

# ---- brand text pass: user-visible "mochy" wording -> Melody (resource names/ids untouched) ----
KEEP = ('mochydh', 'developer_name', 'mochy-preserve', 'mochyymodule')
SUBS = [
    (re.compile(r'mochy[ -]?music', re.I), 'Melody'),
    (re.compile(r'\bmochyEqualizer', re.I), 'Melody Equalizer'),
    (re.compile(r'\bmochy\b', re.I), 'Melody'),
]
tag = re.compile(r'^(\s*<(?:string|item)\b[^>]*>)(.*?)(</(?:string|item)>\s*)$')
n_changed = 0
for f in glob.glob('app/src/main/res/values*/*.xml'):
    if re.search(r'(styles|themes|attrs|colors|dimens)', os.path.basename(f)):
        continue
    lines = open(f, encoding='utf-8', errors='surrogateescape').read().split('\n')
    out = []
    ch = False
    for l in lines:
        m = tag.match(l)
        if m and re.search('mochy', m.group(2), re.I) and not any(k in l for k in KEEP) and not re.match(r'\s*[@?]', m.group(2)):
            t = m.group(2)
            for rx, rep in SUBS:
                t = rx.sub(rep, t)
            l = m.group(1) + t + m.group(3)
            ch = True
            n_changed += 1
        out.append(l)
    if ch:
        open(f, 'w', encoding='utf-8', errors='surrogateescape').write('\n'.join(out))
print('brand text lines changed:', n_changed)

def soft(path, pairs):
    p = B + path
    s = open(p).read()
    for old, new in pairs:
        if old in s:
            s = s.replace(old, new)
        else:
            print('SOFT MISS', path, old[:50])
    open(p, 'w').write(s)

soft('screens/update/UpdateSheet.kt', [('"MOCHY $installed"', '"MELODY $installed"')])
soft('screens/update/AboutSheet.kt', [('"MOCHY $installed"', '"MELODY $installed"')])
soft('screens/update/UpdatePromptSheet.kt', [('for mochy, then', 'for Melody, then')])
soft('screens/settings/CipherSettingsScreen.kt', [('mochy caches that script', 'Melody caches that script')])
print('brand pass done')

# ---- glass surfaces for the screens the zips left on opaque / grey cards ----
GLASS = 'Color(0x9E101A30)'
GLASS_HI = 'Color(0xB8203A66)'
def recolor(path, names, value):
    p = B + path
    t = open(p).read()
    for nm in names:
        rx = re.compile(r'(\b(?:val|const val) +' + nm + r'\b *(?::[^=]+)?= *)Color\(0x[0-9A-Fa-f]{8}\)')
        t, k = rx.subn(lambda m: m.group(1) + value, t)
        if k != 1:
            print('RECOLOR MISS', path, nm, k)
    open(p, 'w').write(t)

recolor('screens/settings/ProfileScreen.kt', ['PageCard'], GLASS)
recolor('screens/recap/StatsScreen.kt', ['StatsCard'], GLASS)
recolor('screens/settings/storage/StorageParts.kt', ['StorageCard'], GLASS)
recolor('screens/settings/integrations/IntegrationRow.kt', ['CardColor'], GLASS)
recolor('screens/settings/integrations/discord/DiscordSettingCards.kt', ['Card'], GLASS)
recolor('screens/settings/integrations/discord/DiscordSettingCards.kt', ['ToggleCard'], GLASS_HI)
recolor('screens/settings/devspace/DevStyle.kt', ['DevCard'], GLASS)
recolor('screens/profile/UserProfilePage.kt', ['ListensCardGrey'], GLASS)
recolor('screens/audiolab/AudioLabKit.kt', ['Card'], GLASS)
recolor('screens/audiolab/LabHeaderCard.kt', ['CardColor', 'PanelColor'], GLASS)
recolor('screens/audiolab/LabHeaderCard.kt', ['CardEdge'], 'Color(0x33FFFFFF)')
recolor('screens/search/SearchDesign.kt', ['Tile'], GLASS)
recolor('screens/search/SearchDesign.kt', ['TileHigh'], GLASS_HI)
recolor('component/HomeCards.kt', ['HopInCardBg'], GLASS)
soft('screens/audiolab/AudioLabScreen.kt', [('.background(HubCard)', '.background(Color(0x9E101A30))')])
edit('screens/setup/onboarding/CardMoments.kt', [
    ('Color(0xFF2A2A2A), Color(0xFF0E0E0E)', 'Color(0xFF16306A), Color(0xFF03050F)'),
    ('Modifier.fillMaxSize().background(Onb.Page))', 'Modifier.fillMaxSize().background(Onb.Page).melodyGlowBackground())'),
], [GLOW])
print('glass surfaces done')

# ---- say plainly that support/donate links go to the upstream Mochy Music developers ----
soft('screens/update/AboutSheet.kt', [('"Support me please :3 \\u2192"', '"Support the upstream Mochy Music developers \\u2192"')])
soft('screens/donate/DonateSheet.kt', [
    ('Here\u2019s a way to support and donate to us!', 'These links support the upstream Mochy Music developers, not Melody.'),
    ('Support us on Ko-fi', 'Support upstream on Ko-fi'),
    ('Support us on SociaBuzz', 'Support upstream on SociaBuzz'),
    ('Support us on Buy Me a Coffee', 'Support upstream on Buy Me a Coffee'),
])
soft('screens/donate/SupportSheet.kt', [('useful for us if you support the developer', 'useful for the upstream Mochy Music developers if you support them')])
soft('screens/update/UpdateSheet.kt', [('"Help us!"', '"Support upstream"')])
print('upstream labels done')
# v19: Audio Lab page: navy glow backdrop (was flat 141416) and glass groups
soft('screens/audiolab/AudioLabPage.kt', [
    ('.background(PageBackdrop)\n            .dotGrid()', '.background(Color(0x4D101A30))\n            .dotGrid()'),
    ('.background(Color(0xFF1A1A1C))\n            .padding(12.dp)', '.background(Color(0x9E101A30))\n            .padding(12.dp)'),
])
print('audiolab glow done')
_p = B + 'screens/audiolab/AudioLabPage.kt'
_s = open(_p).read()
assert 'melodyGlowBackground()' in _s
if 'ui.component.melodyGlowBackground' not in _s:
    _s = _s.replace('\nimport ', '\nimport com.mochyy.mochymusic.ui.component.melodyGlowBackground\nimport ', 1)
open(_p, 'w').write(_s)

# v21: Player transport as three 3D glass gems (skip, big play, skip) instead of bare huge glyphs on a pill
_p = B + 'player/PlayerControls.kt'
_s = open(_p).read()
def _rep(old, new, cnt=1):
    global _s
    assert _s.count(old) == cnt, (old[:60], _s.count(old))
    _s = _s.replace(old, new)
_rep('val buttonSize = (maxWidth * 0.21f).coerceIn(64.dp, 96.dp)', 'val buttonSize = (maxWidth * 0.17f).coerceIn(54.dp, 80.dp)')
_rep('val iconSize = buttonSize * 0.73f', 'val iconSize = buttonSize * 0.46f')
_rep('''                holdLabel = "0.5\\u00D7",
                holdPulseMs = 900L,
                flagshipGlyph = flagshipGlyph,
                modifier = Modifier.size(buttonSize)''', '''                holdLabel = "0.5\\u00D7",
                holdPulseMs = 900L,
                flagshipGlyph = flagshipGlyph,
                modifier = Modifier.size(buttonSize).glassGem(RoundedCornerShape(50), GemBlue, 0.5f)''')
_rep('''                holdLabel = "2\\u00D7",
                holdPulseMs = 420L,
                flagshipGlyph = flagshipGlyph,
                modifier = Modifier.size(buttonSize)''', '''                holdLabel = "2\\u00D7",
                holdPulseMs = 420L,
                flagshipGlyph = flagshipGlyph,
                modifier = Modifier.size(buttonSize).glassGem(RoundedCornerShape(50), GemBlue, 0.5f)''')
_rep('''                tint = Color.White,
                iconSize = iconSize,
                flagshipGlyph = flagshipGlyph,
                modifier = Modifier.size(buttonSize)''', '''                tint = Color.White,
                iconSize = iconSize * 1.2f,
                flagshipGlyph = flagshipGlyph,
                modifier = Modifier.size(buttonSize * 1.3f).glassGem(RoundedCornerShape(50), GemTeal, 0.95f)''')
_rep('''                .background(Color(0xFF0E1A38).copy(alpha = 0.62f))
                .border(1.dp, Color(0xFF6ECDFF).copy(alpha = 0.28f), RoundedCornerShape(50))
                .padding(vertical = 10.dp)''', '''                .background(Color(0x66101A30))
                .border(1.dp, Color(0x40FFFFFF), RoundedCornerShape(50))
                .padding(vertical = 12.dp)''')
_s = _s.replace('\nimport ', '\nimport com.mochyy.mochymusic.ui.component.GemBlue\nimport com.mochyy.mochymusic.ui.component.GemTeal\nimport com.mochyy.mochymusic.ui.component.glassGem\nimport ', 1)
open(_p, 'w').write(_s)
print('player gems done')

# v21: player info card as a rich glass card, round side buttons as glass gems
_p = B + 'player/SongInfoRow.kt'
_s = open(_p).read()
_o = """            .background(com.mochyy.mochymusic.ui.component.MelodyGlassTint)
            .border(
                1.dp,
                com.mochyy.mochymusic.ui.component.MelodyGlassEdgeBrush,
                androidx.compose.foundation.shape.RoundedCornerShape(28.dp),
            )
            .padding(horizontal = 16.dp, vertical = 6.dp)"""
assert _s.count(_o) == 1
_s = _s.replace(_o, """            .padding(horizontal = 16.dp, vertical = 10.dp)""")
_o2 = """                    .clip(CircleShape)
                    .background(containerColor)
            ) {

                if (boldIcon) {"""
assert _s.count(_o2) == 1
_s = _s.replace(_o2, """                    .glassGem(androidx.compose.foundation.shape.RoundedCornerShape(percent = 36), GemBlue, 0.5f)
            ) {

                if (boldIcon) {""")
_s = _s.replace('\nimport ', '\nimport com.mochyy.mochymusic.ui.component.GemBlue\nimport com.mochyy.mochymusic.ui.component.glassCard\nimport com.mochyy.mochymusic.ui.component.glassGem\nimport ', 1)
open(_p, 'w').write(_s)
print('song card done')

# v22: flagship Now Playing transport (the row the player really uses) as 3D glass gems
_p = B + 'player/flagship/FlagshipTransport.kt'
_s = open(_p).read()
_o = """            .size(touch)
            .graphicsLayer {
                val s = press()
                scaleX = s
                scaleY = s
                alpha = if (enabled) 1f else 0.36f
            }
"""
assert _s.count(_o) == 1
_s = _s.replace(_o, _o + "            .padding(5.dp)\n            .glassGem(androidx.compose.foundation.shape.RoundedCornerShape(percent = 36), GemBlue, 0.55f)\n")
_o = """                    } else Modifier
                ),
        ) {
            if (ended) {"""
assert _s.count(_o) == 1
_s = _s.replace(_o, """                    } else Modifier.padding(3.dp).glassGem(androidx.compose.foundation.shape.RoundedCornerShape(percent = 36), GemTeal, 0.75f)
                ),
        ) {
            if (ended) {""")
_s = _s.replace('\nimport ', '\nimport com.mochyy.mochymusic.ui.component.GemBlue\nimport com.mochyy.mochymusic.ui.component.GemTeal\nimport com.mochyy.mochymusic.ui.component.glassGem\nimport ', 1)
open(_p, 'w').write(_s)
print('flagship transport done')

# v23: Audio Lab sheet translucent over the navy glow (was solid black); settings rows get gem tiles
_p = B + 'screens/audiolab/AudioLabPage.kt'
_s = open(_p).read()
assert _s.count('private val SheetColor = Color.Black') == 1
_s = _s.replace('private val SheetColor = Color.Black', 'private val SheetColor = Color(0xB3081326)')
open(_p, 'w').write(_s)
_p = B + 'component/Preference.kt'
_s = open(_p).read()
_o = """            Box(
                modifier = Modifier.padding(horizontal = 4.dp),
            ) {
                icon()
            }

            Spacer(Modifier.width(12.dp))"""
assert _s.count(_o) == 1
_s = _s.replace(_o, """            GlassIconTile(size = 36.dp, glow = 0.4f) {
                icon()
            }

            Spacer(Modifier.width(12.dp))""")
open(_p, 'w').write(_s)
print('v23 audiolab sheet + settings tiles done')

# v24: ONE glass player card behind info + seek bar + transport (was a small info strip over a separate pill);
# skip glyph scaled to sit inside its gem; deck pill no longer drawn separately.
_p = B + 'player/flagship/FlagshipTransport.kt'
_s = open(_p).read()
_o = """        Spacer(
            modifier = Modifier
                .fillMaxSize()
                .drawBehind { drawSkipGlyph(shapes, cycle.phase(), unit.toPx(), Color.White, backwards) },
        )"""
assert _s.count(_o) == 1
_s = _s.replace(_o, """        Spacer(
            modifier = Modifier
                .fillMaxSize()
                .graphicsLayer { scaleX = 0.6f; scaleY = 0.6f }
                .drawBehind { drawSkipGlyph(shapes, cycle.phase(), unit.toPx(), Color.White, backwards) },
        )""")
for a, b in (('Color(0xFF0A1226).copy(alpha = 0.50f)', 'Color(0xFF0A1226).copy(alpha = 0f)'), ('Color(0xFF6ECDFF).copy(alpha = 0.22f),', 'Color(0xFF6ECDFF).copy(alpha = 0f),')):
    assert _s.count(a) == 1, a
    _s = _s.replace(a, b)
open(_p, 'w').write(_s)
_p = B + 'player/BottomSheetPlayer.kt'
_s = open(_p).read()
_o = """                        letTouchesThroughWhenHidden()
                    }

                    .onGloballyPositioned { coords ->
                        if (coords.parentLayoutCoordinates == null) return@onGloballyPositioned
"""
assert _s.count(_o) == 1
_card = """                        letTouchesThroughWhenHidden()
                    }
                    .drawBehind {
                        val l = 10.dp.toPx()
                        val w = size.width - l * 2f
                        val up = controlsDrawShift.toPx() - 6.dp.toPx()
                        val h = size.height + up - 34.dp.toPx()
                        val r = androidx.compose.ui.geometry.CornerRadius(34.dp.toPx(), 34.dp.toPx())
                        val tl = androidx.compose.ui.geometry.Offset(l, -up)
                        val sz = androidx.compose.ui.geometry.Size(w, h)
                        drawRoundRect(
                            brush = androidx.compose.ui.graphics.Brush.linearGradient(
                                listOf(Color(0x40FFFFFF), Color(0x33101A38), Color(0x66050A1C)),
                                start = androidx.compose.ui.geometry.Offset(l, -up),
                                end = androidx.compose.ui.geometry.Offset(l + w, h - up),
                            ),
                            topLeft = tl, size = sz, cornerRadius = r,
                        )
                        // soft top-left sheen
                        drawRoundRect(
                            brush = androidx.compose.ui.graphics.Brush.radialGradient(
                                listOf(Color(0x33FFFFFF), Color.Transparent),
                                center = androidx.compose.ui.geometry.Offset(l + w * 0.18f, -up + h * 0.06f),
                                radius = w * 0.7f,
                            ),
                            topLeft = tl, size = sz, cornerRadius = r,
                        )
                        // lit rim
                        drawRoundRect(
                            brush = androidx.compose.ui.graphics.Brush.linearGradient(
                                listOf(Color(0x80FFFFFF), Color(0x1FFFFFFF), Color(0x666ECDFF)),
                                start = androidx.compose.ui.geometry.Offset(l, -up),
                                end = androidx.compose.ui.geometry.Offset(l + w, h - up),
                            ),
                            topLeft = tl, size = sz, cornerRadius = r,
                            style = androidx.compose.ui.graphics.drawscope.Stroke(width = 1.5.dp.toPx()),
                        )
                    }

                    .onGloballyPositioned { coords ->
                        if (coords.parentLayoutCoordinates == null) return@onGloballyPositioned
"""
_s = _s.replace(_o, _card)
if 'import androidx.compose.ui.draw.drawBehind' not in _s:
    _s = _s.replace('\nimport ', '\nimport androidx.compose.ui.draw.drawBehind\nimport ', 1)
open(_p, 'w').write(_s)
print('v24 unified player card done')

# v25: Settings main list: category rows and recommended card use the 3D gem tile (were dark tile + pale glyph)
_p = B + 'screens/settings/MochySettingsScreen.kt'
_s = open(_p).read()
_o = """            Box(
                modifier = Modifier
                    .size(40.dp)
                    .clip(RoundedCornerShape(14.dp))
                    .background(Color(0xFF6ECDFF).copy(alpha = 0.14f))
                    .border(1.dp, Color(0xFF6ECDFF).copy(alpha = 0.25f), RoundedCornerShape(14.dp)),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    painter = painterResource(iconRes),
                    contentDescription = null,
                    tint = Color(0xFF9FE3FF),
                    modifier = Modifier.size(20.dp)
                )
            }"""
assert _s.count(_o) == 1
_s = _s.replace(_o, """            com.mochyy.mochymusic.ui.component.GlassIconTile(size = 42.dp, glow = 0.5f) {
                Icon(
                    painter = painterResource(iconRes),
                    contentDescription = null,
                    tint = Color.White,
                    modifier = Modifier.size(24.dp)
                )
            }""")
for sz, isz, res in (('38', '18', 'R.drawable.settings'), ('44', '22', 'recommendedItem.iconRes')):
    _o = """                                    Box(
                                        modifier = Modifier
                                            .size(%sdp)
                                            .clip(CircleShape)
                                            .background(IconBgColor),
                                        contentAlignment = Alignment.Center
                                    ) {""" % (sz + '.')
    if _s.count(_o) != 1:
        _o = _o.replace('                                    ', '                                ', 1) if False else _o
    print('recommended block', sz, _s.count(_o))
open(_p, 'w').write(_s)
print('v25 settings category gems done')

# v27: tighten the player card: the transport row moves up into the empty band and the card bottom follows
_p = B + 'player/BottomSheetPlayer.kt'
_s = open(_p).read()
_o = "                val transportModifier = Modifier\n"
assert _s.count(_o) == 1
_s = _s.replace(_o, _o + "                    .offset(y = (-40).dp)\n")
open(_p, 'w').write(_s)
print('v27 tighter player card done')

# v29: song/album/playlist menus: the last row must clear the system navigation buttons
for _f in ['SongMenu','AlbumMenu','PlaylistMenu','SelectionSongsMenu','YouTubeSongMenu','YouTubeAlbumMenu','YouTubePlaylistMenu','YouTubeArtistMenu']:
    _p = B + 'menu/%s.kt' % _f
    _s = open(_p).read()
    _o = 'bottom = 8.dp + WindowInsets.systemBars.asPaddingValues().calculateBottomPadding(),'
    assert _s.count(_o) == 1, (_f, _s.count(_o))
    _s = _s.replace(_o, 'bottom = 8.dp + maxOf(WindowInsets.systemBars.asPaddingValues().calculateBottomPadding(), 88.dp),')
    open(_p, 'w').write(_s)
print('v29 menu bottom clearance done')

# v31: full-app audit fixes. (a) every settings row icon becomes a glass gem tile (was a light circle chip
# with a dark glyph); (b) the sheet primary button ("Done") becomes a glass pill instead of a flat grey one.
_p = B + 'component/SettingsGroup.kt'
_s = open(_p).read()
_o = """            Box(
                modifier = Modifier
                    .size(32.dp)
                    .clip(androidx.compose.foundation.shape.CircleShape)
                    .background(Color(0xFFE5E5EA)),
                contentAlignment = Alignment.Center
            ) {"""
assert _s.count(_o) == 1, 'settings icon box'
_s = _s.replace(_o, """            com.mochyy.mochymusic.ui.component.GlassIconTile(
                size = 36.dp,
                glow = 0.45f,
                tint = listOf(
                    com.mochyy.mochymusic.ui.component.GemBlue,
                    com.mochyy.mochymusic.ui.component.GemViolet,
                    com.mochyy.mochymusic.ui.component.GemTeal,
                    com.mochyy.mochymusic.ui.component.GemSky,
                )[(((item.highlightKey ?: item.descriptionText ?: "").hashCode() % 4) + 4) % 4],
            ) {""")
open(_p, 'w').write(_s)
_p = B + 'screens/update/UpdateSheet.kt'
_s = open(_p).read()
_o = """            .clip(CircleShape)
            .background(Color.White.copy(alpha = 0.26f))
            .clickable(interactionSource = interaction, indication = RemoteFocus, onClick = onClick),"""
assert _s.count(_o) == 1, 'sheet primary button'
_s = _s.replace(_o, """            .com_glassPill()
            .clickable(interactionSource = interaction, indication = RemoteFocus, onClick = onClick),""".replace('.com_glassPill()', '.glassGem(CircleShape, GemBlue, 0.55f)'))
_s = _s.replace('\nimport ', '\nimport com.mochyy.mochymusic.ui.component.GemBlue\nimport com.mochyy.mochymusic.ui.component.glassGem\nimport ', 1)
_s = _s.replace('Text(text = text, fontSize = 17.sp, fontWeight = FontWeight.Bold, letterSpacing = (-0.4).sp)',
                'Text(text = text, fontSize = 17.sp, fontWeight = FontWeight.Bold, letterSpacing = (-0.4).sp, color = Color.White)')
open(_p, 'w').write(_s)
print('v31 settings icon gems + glass sheet button done')

# v32: audit round 2: sheet/row surfaces and icon chips in the Update, Device integration and Modules screens.
def _sub(path, pairs, imports=()):
    _p = B + path
    _s = open(_p).read()
    for _o, _n in pairs:
        assert _s.count(_o) == 1, (path, _o[:70], _s.count(_o))
        _s = _s.replace(_o, _n)
    for _i in imports:
        if _i not in _s:
            _k = _s.index('\nimport ')
            _s = _s[:_k + 1] + _i + '\n' + _s[_k + 1:]
    open(_p, 'w').write(_s)
    print('v32 patched', path)

_PILL = ('.clip(CircleShape)\n            .background(androidx.compose.ui.graphics.Brush.verticalGradient(listOf(Color(0xE66ECDFF), Color(0xE62F8BFF))))\n'
         '            .border(1.dp, Color.White.copy(alpha = 0.35f), CircleShape)')
_BORDER = 'import androidx.compose.foundation.border'
# translucent row surface for every sheet that uses it
_sub('player/menu/MenuSheet.kt', [('val MenuRowSurface = Color(0xFF0E1A38)', 'val MenuRowSurface = Color(0xA60E1A38)')])
# update sheet: glass pill (even gradient, no blob) and gem tile on the action rows
_sub('screens/update/UpdateSheet.kt', [
    ('.glassGem(CircleShape, GemBlue, 0.55f)', _PILL),
    ("""        Box(
            contentAlignment = Alignment.Center,
            modifier = Modifier
                .graphicsLayer { alpha = contentAlpha }
                .size(28.dp)
                .clip(CircleShape)
                .background(Color(0xFFDADADA)),
        ) {""", """        com.mochyy.mochymusic.ui.component.GlassIconTile(
            size = 34.dp,
            glow = 0.45f,
            modifier = Modifier.graphicsLayer { alpha = contentAlpha },
        ) {"""),
], [_BORDER])
# device integration: glass pill Done, gem chips, solid (not dashed) add box
_sub('screens/devices/DevicesKit.kt', [
    ('.background(if (bright) Color.White else Color.White.copy(alpha = 0.26f))',
     '.background(if (bright) androidx.compose.ui.graphics.Brush.verticalGradient(listOf(Color.White, Color.White)) else androidx.compose.ui.graphics.Brush.verticalGradient(listOf(Color(0xE66ECDFF), Color(0xE62F8BFF))))\n            .border(1.dp, Color.White.copy(alpha = 0.35f), CircleShape)'),
    ("""            Box(Modifier.size(30.dp).clip(CircleShape).background(Faint), contentAlignment = Alignment.Center) {
                Icon(icon, contentDescription = null, tint = Color.White.copy(alpha = if (enabled) 1f else 0.4f), modifier = Modifier.size(16.dp))
            }""", """            com.mochyy.mochymusic.ui.component.GlassIconTile(size = 34.dp, glow = 0.45f) {
                Icon(icon, contentDescription = null, tint = Color.White.copy(alpha = if (enabled) 1f else 0.4f), modifier = Modifier.size(16.dp))
            }"""),
], [_BORDER])
_sub('screens/devices/DeviceIntegrationSheet.kt', [
    ('style = Stroke(stroke, pathEffect = PathEffect.dashPathEffect(floatArrayOf(9.dp.toPx(), 7.dp.toPx()))),', 'style = Stroke(stroke),'),
])
_sub('screens/settings/modules/ModuleParts.kt', [
    ('style = Stroke(width = 2.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(14.dp.toPx(), 10.dp.toPx()))),', 'style = Stroke(width = 1.5.dp.toPx()),'),
])
# modules banner: the upstream drawing becomes a glass gem tile with a search glyph
_sub('screens/settings/modules/ModulesScreen.kt', [
    ("""        Image(
            painterResource(R.drawable.modules_bar_mochy), null,
            contentScale = ContentScale.Fit,
            modifier = Modifier.align(Alignment.Bottom).padding(top = 10.dp).fillMaxHeight(),
        )""", """        com.mochyy.mochymusic.ui.component.GlassIconTile(size = 64.dp, glow = 0.6f) {
            androidx.compose.material3.Icon(androidx.compose.material.icons.Icons.Rounded.Search, contentDescription = null, modifier = Modifier.size(32.dp))
        }"""),
], ['import androidx.compose.foundation.layout.size', 'import androidx.compose.material.icons.Icons', 'import androidx.compose.material.icons.rounded.Search'])
print('v32 done')

# v33: translucent glass for the Audio Lab hub cards, lab cards and module rows.
_HE = '.border(1.dp, Color(0xFF6ECDFF).copy(alpha = 0.18f), RoundedCornerShape(%d.dp))'
_sub('screens/audiolab/AudioLabKit.kt', [('val Row = Color(0xFF14213F)', 'val Row = Color(0xA614213F)'), ('val Chip = Color(0xFF13203C)', 'val Chip = Color(0xA613203C)')])
_sub('screens/settings/modules/ModuleParts.kt', [('internal val ModuleRowColor = Color(0xFF131314)', 'internal val ModuleRowColor = Color(0xB30E1A38)')])
print('v33 done')

_E = '.border(1.dp, Color(0xFF6ECDFF).copy(alpha = 0.18f), %s)'
_sub('screens/gesture/CustomisationCards.kt', [
    ('.height(RoundingCardHeight)\n                .clip(CardShape)\n                .background(LabColors.Card),', '.height(RoundingCardHeight)\n                .clip(CardShape)\n                .background(LabColors.Card)\n                ' + _E % 'CardShape' + ',') ,
    ('.clip(SliderCardShape)\n            .background(LabColors.Card)', '.clip(SliderCardShape)\n            .background(LabColors.Card)\n            ' + _E % 'SliderCardShape'),
    ('.height(StyleCardHeight)\n            .clip(CardShape)\n            .background(LabColors.Card)', '.height(StyleCardHeight)\n            .clip(CardShape)\n            .background(LabColors.Card)\n            ' + _E % 'CardShape'),
    ('private val SwatchColor = Color(0xFFD9D9D9)', 'private val SwatchColor = Color(0xCC6ECDFF)'),
])
print('v33b done')

_sub('screens/update/VersionRing.kt', [
    ('ringColor: Color = Color.White.copy(alpha = 0.08f),', 'ringColor: Color = Color(0xFF6ECDFF).copy(alpha = 0.10f),'),
    ('textColor: Color = Color.White.copy(alpha = 0.3f),', 'textColor: Color = Color(0xFF6ECDFF).copy(alpha = 0.38f),'),
])
print('v33c done')

# v34: replace (not recolor) the upstream compositions: version ring art, audio lab sketches, cover-rounding sample, id card layout.
_SR = 'screens/update/VersionRing.kt'
_t = open(B + _SR).read()
assert _t.count('fun VersionRing(') == 1
_t = _t.replace('fun VersionRing(', 'fun VersionRingOld(')
_t += """

/** glass orbs behind the version: two soft glows and a frosted edge, fading as the sheet scrolls; it carries no text */
@Composable
fun VersionRing(
    text: String,
    modifier: Modifier = Modifier,
    scrollProgress: () -> Float = { 0f },
    radius: androidx.compose.ui.unit.Dp = 140.dp,
    band: androidx.compose.ui.unit.Dp = 46.dp,
    ringColor: androidx.compose.ui.graphics.Color = androidx.compose.ui.graphics.Color.White,
    textColor: androidx.compose.ui.graphics.Color = androidx.compose.ui.graphics.Color.White,
    turnMillis: Int = 26_000,
) {
    androidx.compose.foundation.layout.Box(
        modifier
            .size(radius * 2)
            .graphicsLayer { alpha = (1f - scrollProgress()).coerceIn(0f, 1f) }
            .drawBehind {
                val c = androidx.compose.ui.geometry.Offset(size.width / 2f, size.height / 2f)
                val r = size.minDimension / 2f
                drawCircle(
                    androidx.compose.ui.graphics.Brush.radialGradient(
                        listOf(androidx.compose.ui.graphics.Color(0x556ECDFF), androidx.compose.ui.graphics.Color(0x00031020)),
                        center = c, radius = r,
                    ), r, c,
                )
                val c2 = androidx.compose.ui.geometry.Offset(c.x + r * 0.35f, c.y + r * 0.3f)
                drawCircle(
                    androidx.compose.ui.graphics.Brush.radialGradient(
                        listOf(androidx.compose.ui.graphics.Color(0x4435D6C0), androidx.compose.ui.graphics.Color(0x0035D6C0)),
                        center = c2, radius = r * 0.6f,
                    ), r * 0.6f, c2,
                )
                drawCircle(androidx.compose.ui.graphics.Color.White.copy(alpha = 0.10f), r * 0.78f, c, style = androidx.compose.ui.graphics.drawscope.Stroke(1.5.dp.toPx()))
            },
    ) {}
}
"""
for _imp in ('import androidx.compose.foundation.layout.size', 'import androidx.compose.ui.draw.drawBehind', 'import androidx.compose.ui.graphics.graphicsLayer', 'import androidx.compose.ui.unit.dp'):
    if _imp not in _t:
        _k = _t.index('\nimport ')
        _t = _t[:_k + 1] + _imp + '\n' + _t[_k + 1:]
open(B + _SR, 'w').write(_t)
print('v34 ring replaced')

_AL = 'screens/audiolab/AudioLabScreen.kt'
_t = open(B + _AL).read()
_o1 = "        Box(Modifier.matchParentSize()) { sketch() }\n        Column(Modifier.padding(start = 24.dp"
_o2 = "        Box(Modifier.matchParentSize()) { sketch() }\n        Column(Modifier.padding(horizontal = 20.dp"
assert _t.count(_o1) == 1 and _t.count(_o2) == 1
_gem = ("        Box(Modifier.matchParentSize().padding(end = %d.dp), contentAlignment = Alignment.CenterEnd) {\n"
        "            com.mochyy.mochymusic.ui.component.GlassIconTile(size = %d.dp, glow = 0.55f) {\n"
        "                androidx.compose.material3.Icon(%s, contentDescription = null, tint = Color.White, modifier = Modifier.size(%d.dp))\n"
        "            }\n        }\n")
_t = _t.replace(_o1, (_gem % (22, 76, 'if (title == "Equalizer") androidx.compose.material.icons.Icons.Rounded.Tune else androidx.compose.material.icons.Icons.Rounded.AutoAwesome', 38)) + "        Column(Modifier.padding(start = 24.dp")
_t = _t.replace(_o2, (_gem % (16, 44, 'if (title.contains("Quality", true)) androidx.compose.material.icons.Icons.Rounded.GraphicEq else androidx.compose.material.icons.Icons.Rounded.SwapHoriz', 24)) + "        Column(Modifier.padding(horizontal = 20.dp")
for _imp in ('import androidx.compose.material.icons.Icons', 'import androidx.compose.material.icons.rounded.Tune', 'import androidx.compose.material.icons.rounded.AutoAwesome', 'import androidx.compose.material.icons.rounded.GraphicEq', 'import androidx.compose.material.icons.rounded.SwapHoriz'):
    if _imp not in _t:
        _k = _t.index('\nimport ')
        _t = _t[:_k + 1] + _imp + '\n' + _t[_k + 1:]
open(B + _AL, 'w').write(_t)
print('v34 audio lab gems')

_CC = 'screens/gesture/CustomisationCards.kt'
_t = open(B + _CC).read()
_a = _t.index('private fun RoundingSwatch(')
_b = _t.index('// a bare line like the mock')
_new = '''private fun RoundingSwatch(radiusPx: Float, modifier: Modifier) {
    Canvas(modifier = modifier) {
        val r = radiusPx.coerceIn(0f, MaxCoverRadius).dp.toPx()
        val side = 96.dp.toPx()
        val left = size.width - side - 26.dp.toPx()
        val top = (size.height - side) / 2f
        val corner = CornerRadius(r.coerceAtMost(side / 2f), r.coerceAtMost(side / 2f))
        drawRoundRect(
            brush = Brush.linearGradient(listOf(Color(0xCC6ECDFF), Color(0x88A58BFF)), Offset(left, top), Offset(left + side, top + side)),
            topLeft = Offset(left, top), size = Size(side, side), cornerRadius = corner,
        )
        drawRoundRect(
            color = Color.White.copy(alpha = 0.40f),
            topLeft = Offset(left, top), size = Size(side, side), cornerRadius = corner,
            style = Stroke(width = 1.5.dp.toPx()),
        )
        drawRoundRect(
            brush = Brush.verticalGradient(listOf(Color.White.copy(alpha = 0.30f), Color.Transparent), top, top + side * 0.5f),
            topLeft = Offset(left + 6.dp.toPx(), top + 6.dp.toPx()), size = Size(side - 12.dp.toPx(), side * 0.4f),
            cornerRadius = CornerRadius((r * 0.6f).coerceAtMost(side * 0.2f)),
        )
    }
}

'''
_t = _t[:_a] + _new + _t[_b:]
_o = "        drawLine(Color.White, Offset(start, y), Offset(start + (end - start) * shown, y), stroke, StrokeCap.Round)\n"
assert _t.count(_o) == 1
_t = _t.replace(_o, _o.replace('Color.White,', 'Color(0xFF6ECDFF),') + "        drawCircle(Color.White, 8.dp.toPx(), Offset(start + (end - start) * shown, y))\n        drawCircle(Color(0xFF6ECDFF), 8.dp.toPx(), Offset(start + (end - start) * shown, y), style = Stroke(2.dp.toPx()))\n")
for _imp in ('import androidx.compose.ui.graphics.Brush', 'import androidx.compose.ui.geometry.CornerRadius', 'import androidx.compose.ui.geometry.Offset', 'import androidx.compose.ui.geometry.Size', 'import androidx.compose.ui.graphics.drawscope.Stroke'):
    if _imp not in _t:
        _k = _t.index('\nimport ')
        _t = _t[:_k + 1] + _imp + '\n' + _t[_k + 1:]
open(B + _CC, 'w').write(_t)
print('v34 customize sample + slider')

_ID = 'screens/setup/onboarding/ProfileIdCard.kt'
_t = open(B + _ID).read()
_a = _t.index('            MarqueeStrip(\n                text = "${name}')
_e = 'running = marqueeRunning,\n            )\n'
_b = _t.index(_e, _a) + len(_e)
_t = _t[:_a] + _t[_b:]
assert _t.count('if (showIdCardOf) {') == 1
_t = _t.replace('if (showIdCardOf) {', 'if (false) {')
_o = '.padding(start = unit * 22f, top = unit * 20f, end = unit * 12f, bottom = unit * 18f)'
assert _t.count(_o) == 1
_t = _t.replace(_o, '.padding(start = unit * 22f, top = unit * 20f, end = unit * 22f, bottom = unit * 18f)')
_o = '.clip(CircleShape)\n                            .background(if (silver) Color(0xFF5A5A60) else Color(0xFF1F2F55))'
assert _t.count(_o) == 1
_t = _t.replace(_o, '.clip(CircleShape)\n                            .background(if (silver) Color(0xFF5A5A60) else Color(0xFF1F2F55))\n                            .border(2.dp, Color(0xFF6ECDFF).copy(alpha = 0.55f), CircleShape)')
open(B + _ID, 'w').write(_t)
print('v34 id card recomposed')

# v35: profile page: the end clears the mini player and nav (240dp), the Mochy discord promo card is dropped, Open settings gets a gem tile.
_sub('screens/settings/ProfileScreen.kt', [
    ("                        DiscordCard(onClick = { context.openDevUrl(DiscordUrl) })\n                        Spacer(Modifier.height(28.dp))", "                        Spacer(Modifier.height(12.dp))"),
    ("                        OpenSettingsRow(onClick = { navController.navigate(\"mochy_settings\") })\n                        Spacer(Modifier.height(180.dp))", "                        OpenSettingsRow(onClick = { navController.navigate(\"mochy_settings\") })\n                        Spacer(Modifier.height(260.dp))"),
    ("""        Box(
            modifier = Modifier
                .size(36.dp)
                .clip(CircleShape)
                .background(Color(0xFFD9D9D9)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(painterResource(R.drawable.settings), contentDescription = null, tint = Color(0xFF101A30), modifier = Modifier.size(18.dp))
        }""", """        com.mochyy.mochymusic.ui.component.GlassIconTile(size = 38.dp, glow = 0.45f) {
            Icon(painterResource(R.drawable.settings), contentDescription = null, tint = Color.White, modifier = Modifier.size(19.dp))
        }"""),
])
print('v35 done')

# v36: modules info card gem tile instead of the drawn phones; neutral Melody sample lines in the lyrics style previews.
_sub('screens/settings/modules/ModulesScreen.kt', [
    ("        TwoPhones(Modifier.padding(start = 26.dp, top = 12.dp).width(84.dp).fillMaxHeight())\n        Spacer(Modifier.width(18.dp))",
     "        Spacer(Modifier.width(22.dp))\n        com.mochyy.mochymusic.ui.component.GlassIconTile(size = 52.dp, glow = 0.5f) {\n            androidx.compose.material3.Icon(androidx.compose.material.icons.Icons.Rounded.Extension, contentDescription = null, tint = Color.White, modifier = Modifier.size(26.dp))\n        }\n        Spacer(Modifier.width(16.dp))"),
], ['import androidx.compose.material.icons.rounded.Extension'])
_sub('screens/gesture/CustomisationLivePreviews.kt', [
    ('"if i am a stone"', '"soft glass in the light"'),
    ('"would you still love me?"', '"every song feels new"'),
    ('"of course, what do you mean my love"', '"play it all night long"'),
])
print('v36 done')

# v37: detail pages in the glass backdrop (artist page navy + glow instead of cover-colour black; album/playlist cover wash ends in navy), glass skeleton/avatar tint, Integrations rows with glass edges.
_sub('screens/artist/ArtistScreen.kt', [
    ('targetValue = themeColor ?: MaterialTheme.colorScheme.background,', 'targetValue = com.mochyy.mochymusic.ui.theme.MelodyNavyDeep,'),
    ('.drawBehind { drawRect(background.value) }\n    ) {', '.drawBehind { drawRect(background.value) }\n            .melodyGlowBackground(true)\n    ) {'),
], ['import com.mochyy.mochymusic.ui.component.melodyGlowBackground'])
_sub('component/detail/DetailCoverBackground.kt', [
    ('0f to animatedColor,\n', '0f to animatedColor.copy(alpha = 0.6f),\n'),
    ('0.35f to animatedColor.copy(alpha = 0.55f),', '0.35f to animatedColor.copy(alpha = 0.32f),'),
    ('1f to backgroundColor,', '1f to com.mochyy.mochymusic.ui.theme.MelodyNavyDeep.copy(alpha = 0.6f),'),
])
_sub('component/RevealOnAppear.kt', [('val BoneColor = Color(0xFFD9D9D9).copy(alpha = 0.22f)', 'val BoneColor = Color(0xFF6ECDFF).copy(alpha = 0.16f)')])
_sub('screens/settings/integrations/IntegrationRow.kt', [
    ('            .clip(CardShape)\n            .background(CardColor)\n', '            .clip(CardShape)\n            .background(CardColor)\n            .border(1.dp, Color(0xFF6ECDFF).copy(alpha = 0.18f), CardShape)\n'),
    ('                .clip(IconShape)\n                .background(iconBackground),', '                .clip(IconShape)\n                .background(iconBackground)\n                .border(1.dp, Color.White.copy(alpha = 0.35f), IconShape),'),
], ['import androidx.compose.foundation.border'])
print('v37 done')

# v38: album/playlist detail recomposed (cover inset in a glass frame over navy glow, no full-bleed wash), glass empty state.
_PD = 'component/detail/PlaylistDetail.kt'
_t = open(B + _PD).read()
def _rep(t, o, n):
    assert t.count(o) == 1, (o[:60], t.count(o))
    return t.replace(o, n)
_t = _rep(_t, 'targetValue = themeColor ?: MaterialTheme.colorScheme.background,\n        animationSpec = tween(600),\n        label = "playlistTheme",', 'targetValue = com.mochyy.mochymusic.ui.theme.MelodyNavyDeep,\n        animationSpec = tween(600),\n        label = "playlistTheme",')
_t = _rep(_t, 'SideEffect { accent.value = if (effectiveRoundCapsule) Color.Black else themeColor }', 'SideEffect { accent.value = if (effectiveRoundCapsule) Color.Black else com.mochyy.mochymusic.ui.theme.MelodyNavyDeep }')
_t = _rep(_t, 'Modifier.drawBehind { drawRect(background.value) }\n                }\n            )', 'Modifier.drawBehind { drawRect(background.value) }.melodyGlowBackground(true)\n                }\n            )')
_t = _rep(_t, '            .height(coverHeight),\n    ) {\n        if (cover != null) {\n            cover(Modifier.fillMaxSize())\n        } else {\n            if (softRequest != null) {',
 '            .height(coverHeight),\n    ) {\n      Box(\n        Modifier\n            .matchParentSize()\n            .padding(start = 30.dp, end = 30.dp, top = 84.dp, bottom = 170.dp)\n            .clip(RoundedCornerShape(34.dp))\n            .border(1.dp, com.mochyy.mochymusic.ui.component.MelodyGlassEdgeBrush, RoundedCornerShape(34.dp)),\n      ) {\n        if (cover != null) {\n            cover(Modifier.fillMaxSize())\n        } else {\n            if (softRequest != null) {')
_k = '        Box(\n            modifier = Modifier\n                .matchParentSize()\n                .drawWithCache {\n                    val bg = background.value\n                    val top = Brush.verticalGradient(\n                        0f to Color.Black.copy(alpha = 0.34f),'
_t = _rep(_t, _k, '      }\n' + _k)
for _imp in ('import com.mochyy.mochymusic.ui.component.melodyGlowBackground', 'import androidx.compose.foundation.border', 'import androidx.compose.foundation.layout.padding', 'import androidx.compose.foundation.shape.RoundedCornerShape', 'import androidx.compose.ui.draw.clip'):
    if _imp not in _t:
        _k2 = _t.index('import ')
        _t = _t[:_k2] + _imp + '\n' + _t[_k2:]
open(B + _PD, 'w').write(_t)
print('v38 playlist/album detail recomposed')

_LD = 'screens/library/LibraryDesign.kt'
_t = open(B + _LD).read()
_a = _t.index('fun LibraryEmptyState(')
_b = _t.index('/**\n * One of the half-width cards')
_t = _t[:_a] + '''fun LibraryEmptyState(modifier: Modifier = Modifier, text: String = "Nothing to show here") {
    Box(
        modifier = modifier.fillMaxWidth().padding(vertical = 40.dp, horizontal = SearchHorizontalPadding),
        contentAlignment = Alignment.Center,
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(28.dp))
                .background(Color(0x9E101A30))
                .border(1.dp, com.mochyy.mochymusic.ui.component.MelodyGlassEdgeBrush, RoundedCornerShape(28.dp))
                .padding(vertical = 32.dp, horizontal = 20.dp),
        ) {
            com.mochyy.mochymusic.ui.component.GlassIconTile(size = 64.dp, glow = 0.5f) {
                androidx.compose.material3.Icon(Icons.Rounded.LibraryMusic, contentDescription = null, tint = Color.White, modifier = Modifier.size(30.dp))
            }
            Spacer(Modifier.height(14.dp))
            Text(
                text = text,
                color = SearchColors.Secondary,
                fontSize = 14.sp,
                fontWeight = FontWeight.Medium,
            )
        }
    }
}

''' + _t[_b:]
for _imp in ('import androidx.compose.material.icons.Icons', 'import androidx.compose.material.icons.rounded.LibraryMusic'):
    if _imp not in _t:
        _k2 = _t.index('import ')
        _t = _t[:_k2] + _imp + '\n' + _t[_k2:]
open(B + _LD, 'w').write(_t)
print('v38 empty state')

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

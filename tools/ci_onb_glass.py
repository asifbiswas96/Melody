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
                modifier = Modifier.size(buttonSize).glassGem(RoundedCornerShape(50), GemSky, 0.5f)''')
_rep('''                holdLabel = "2\\u00D7",
                holdPulseMs = 420L,
                flagshipGlyph = flagshipGlyph,
                modifier = Modifier.size(buttonSize)''', '''                holdLabel = "2\\u00D7",
                holdPulseMs = 420L,
                flagshipGlyph = flagshipGlyph,
                modifier = Modifier.size(buttonSize).glassGem(RoundedCornerShape(50), GemSky, 0.5f)''')
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
_s = _s.replace('\nimport ', '\nimport com.mochyy.mochymusic.ui.component.GemSky\nimport com.mochyy.mochymusic.ui.component.GemTeal\nimport com.mochyy.mochymusic.ui.component.glassGem\nimport ', 1)
open(_p, 'w').write(_s)
print('player gems done')

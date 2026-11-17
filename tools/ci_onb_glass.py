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
    lines = open(f, encoding='utf-8', errors='surrogateescape').read().split('\n')
    out = []
    ch = False
    for l in lines:
        m = tag.match(l)
        if m and re.search('mochy', m.group(2), re.I) and not any(k in l for k in KEEP):
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

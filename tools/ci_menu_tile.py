# CI-only: the Melody patch zips overwrite Menu.kt after checkout, so the glass icon tile is
# applied to the zip's version of MenuItemRow here (UI only, no logic change).
p = 'app/src/main/kotlin/com/mochyy/mochymusic/ui/component/Menu.kt'
s = open(p).read()
old = "            Box(\n                contentAlignment = Alignment.Center,\n                modifier = Modifier.size(SheetIconSize),\n            ) {"
assert old in s, 'tile anchor missing'
s = s.replace(old, "            GlassIconTile(size = 34.dp) {")
old2 = ".padding(horizontal = 14.dp, vertical = 14.dp),"
assert old2 in s, 'padding anchor missing'
s = s.replace(old2, ".padding(horizontal = 14.dp, vertical = 9.dp),")
open(p, 'w').write(s)
print('Menu.kt glass tile applied')

import json, html, sys, os
import fit, config
S = fit.S
res = json.load(open(S + 'result.json'))
order = [g for g in fit.GUNS]
SET = lambda g: 'RS Modern' if 'RS_Modern' in fit.GUNS[g]['card'] else ('BD22' if 'bd22' in fit.GUNS[g]['card'] else 'Vanilla VR')
NOTE = {
 'WM_Chainsaw': 'Rear handle runs fore and aft (87 degrees). Written as 80, the most the card takes.',
 'WM_LongbarChainsaw': 'Rear handle runs fore and aft (87 degrees). Written as 80, the most the card takes.',
 'BD_Chainsaw': 'Rear handle runs fore and aft (87 degrees). Written as 80, the most the card takes.',
 'BD_FlameCannon': 'The hand goes inside the cannon. Your palm point was already in the middle of the bore. No rake.',
 'WM_PlasmaCarbine': 'Your height was right; your point was 7.7 cm off to the side of the grip. Centred.',
 'WM_BreachMP5': 'Your palm point sat below the grip, and the card\'s trigger point is a copy of it. Placed by the guard rule only.',
 'WM_Bolter': 'Your palm point was on the rear sight. Moved down to the grip.',
 'RS_VRGrenade': 'Your palm point was 4.6 cm outside the grenade. Now the centre of its body.',
 'BD_Grenade': 'Centre of the grenade body.',
 'BD_Hellish': 'The handle is a slanted bar with the trigger on it (rake 70).',
 'WM_Flamer': 'Its trigger guard runs to the bottom of the grip, so placed by the trigger rule only.',
 'WM_Flamethrower': 'Fuel-nozzle handle with no guard step: kept your height, centred on the handle.',
 'BD_Flamethrower': 'Fuel-nozzle handle with no guard step: kept your height, centred on the handle.',
 'WM_DoubleBarrel': 'Straight wrist with no guard step: kept your height, centred on the wrist.',
 'BD_Axe': 'Kept your heights on the handle, centred.',
 'BD_Dragonslayer': 'Kept your heights on the hilt, centred.',
 'WM_ChainsawHeavy': 'Kept your heights on both handles, centred.',
 'WM_Chaingun': 'Your off-hand point was 15 cm below the side handle. Moved onto it.',
 'WM_RPG': 'Your palm point was 3.25 to the wrong side of the grip (same mesh as the Rocket Launcher). Now the grip centre.',
 'WM_SSG': 'Straight wrist; reads 44 degrees from one start and 57 from another. The sheet shows 44.',
 'BD_Railgun': 'Reads 29.5 from a pistol-grip start and 40 from a stock start. The sheet shows 29.5.',
 'WM_Tec9': 'Off hand on the magazine, held like a vertical grip.',
 'BD_MP40': 'Off hand on the magazine, held like a vertical grip.',
}
NEEDS = ['WM_PlasmaCarbine', 'BD_Hellish', 'WM_Chainsaw', 'WM_LongbarChainsaw', 'BD_Chainsaw', 'BD_FlameCannon', 'WM_SSG', 'BD_Railgun', 'WM_BreachMP5', 'WM_Bolter', 'RS_VRGrenade']
SUPWORD = {'same': 'wraps the gun hand', 'wrap': 'round the forend', 'cup': 'cups the forend', 'vgrip': 'vertical grip', 'handle': 'on the handle', 'none': 'same as palm'}
f3 = lambda v: '%.3f, %.3f, %.3f' % tuple(v) if v else '&ndash;'
rows = []; sheets = []
for cls in order:
    r = res[cls]; g = fit.GUNS[cls]
    rk = r.get('rake')
    rake_txt = ('%.1f' % rk if rk is not None and -10 <= rk <= 80 else ('80 (measured %.0f)' % rk if rk is not None else '&ndash;'))
    note = NOTE.get(cls, '')
    if r.get('unified_from'): note = (note + ' ' if note else '') + 'Same mesh as %s, same numbers.' % r['unified_from']
    big = (r.get('palm_move_cm') or 0) > 3.0
    rows.append(dict(cls=cls, set=SET(cls), hand=r['hand'], ok=r.get('ok'), old_p=r['old_palm'], new_p=r.get('palm'), mp=r.get('palm_move_cm'),
                     rake=rake_txt, old_s=r['old_supportat'], new_s=r.get('supportat'), ms=r.get('sup_move_cm'), sm=SUPWORD.get(r.get('sup_mode') or 'none', ''),
                     note=note, big=big, needs=cls in NEEDS))
def tr(x):
    cls = x['cls']
    flag = '<span class="pill warn">look</span>' if x['needs'] else ('<span class="pill">moved %.1f cm</span>' % x['mp'] if x['big'] else '')
    newp = f3(x['new_p']) if x['ok'] else 'not changed'
    return ('<tr data-set="%s"%s><td class="gun"><a href="#%s">%s</a> %s<div class="sub">%s hand</div></td>'
            '<td class="num"><span class="now">%s</span><span class="new">%s</span></td><td class="num">%s</td><td class="num">%s</td>'
            '<td class="num"><span class="now">%s</span><span class="new">%s</span><div class="sub">%s</div></td><td class="num">%s</td><td class="note">%s</td></tr>') % (
        x['set'], ' class="needs"' if x['needs'] else '', cls, cls, flag, x['hand'],
        f3(x['old_p']), newp, '%.1f' % x['mp'] if x['mp'] is not None else '&ndash;', x['rake'],
        f3(x['old_s']), f3(x['new_s']), x['sm'], '%.1f' % x['ms'] if x['ms'] is not None else '&ndash;', html.escape(x['note']))
table = '\n'.join(tr(x) for x in rows)
needs = '\n'.join('<li><a href="#%s">%s</a> %s</li>' % (c, c, html.escape(NOTE[c])) for c in NEEDS)
sheet_html = '\n'.join('<figure id="%s" data-set="%s"><figcaption><b>%s</b><span>%s</span></figcaption><img loading="lazy" src="sheets/%s.jpg" alt="Review sheet for %s: side and top views with the palm and support points"></figure>' % (
    x['cls'], x['set'], x['cls'], html.escape(x['note']) if x['note'] else '', x['cls'], x['cls']) for x in rows)
diff = html.escape(open(S + 'grip_cards.diff').read()) if os.path.exists(S + 'grip_cards.diff') else 'run emit.py first'
n_ok = sum(1 for x in rows if x['ok']); n_rake = sum(1 for x in rows if x['ok'] and x['rake'] != '&ndash;')
page = open(config.HERE / 'page_tpl.html').read()
for k, v in dict(TABLE=table, NEEDS=needs, SHEETS=sheet_html, DIFF=diff, NOK=str(n_ok), NALL=str(len(rows)), NRAKE=str(n_rake)).items():
    page = page.replace('{{%s}}' % k, v)
os.makedirs(S + 'page/sheets', exist_ok=True)
from PIL import Image
for x in rows:                                   # the sheets, as JPEGs beside the page
    src = S + 'sheets/%s.png' % x['cls']
    if os.path.exists(src):
        im = Image.open(src).convert('RGB')
        if im.width > 1000: im = im.resize((1000, int(im.height * 1000 / im.width)), Image.LANCZOS)
        im.save(S + 'page/sheets/%s.jpg' % x['cls'], quality=74, optimize=True)
open(S + 'page/index.html', 'w', encoding='utf-8').write(page)
print(len(page) // 1024, 'KB')

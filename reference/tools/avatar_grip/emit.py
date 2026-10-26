"""Write the fitted grip numbers into COPIES of the cards (av/cards_out/...) and a diff.
Never touches the originals. Run against the owner's tree only after the review is OK'd."""
import sys, json, os, re, difflib, shutil
import fit
SRC = fit.W
OUT = fit.S + 'cards_out/'
res = json.load(open(fit.S + 'result.json'))
STAMP = '  # palm, rake, supportat: fitted 2026-10-10 to c_doom_marine\'s hand (avatar grip review)'
f3 = lambda v: ', '.join('%.3f' % x for x in v)

def plan(only=()):
    """per card file: [(cls, gripstart, gripend, {key: value})]; only: limit to these guns"""
    per = {}
    for cls, g in fit.GUNS.items():
        if only and cls not in only: continue
        r = res.get(cls, {})
        if not r.get('ok'): continue
        vals = {'palm': f3(r['palm'])}
        if r['rake'] is not None:
            vals['rake'] = '%.1f' % min(80.0, max(-10.0, r['rake']))   # the card takes -10..80; chainsaw rear handles (87) get 80
        if r.get('sup_ok') and r.get('supportat'): vals['supportat'] = f3(r['supportat'])
        per.setdefault(g['card'], []).append((cls, g['gripstart'], g['gripend'], vals))
    return per

def patch(text, items):
    L = text.split('\n')
    for cls, gs, ge, vals in sorted(items, key=lambda t: -t[1]):     # bottom up, line numbers stay valid
        i0 = gs - 1                                                  # 'grip' line
        i1 = next(j for j in range(i0 + 1, len(L)) if L[j].rstrip() == 'end')   # its column-0 'end'
        assert L[i0].strip() == 'grip' and L[i1].strip() == 'end', (cls, L[i0], L[i1])
        block = L[i0 + 1:i1]
        done = set()
        for j, line in enumerate(block):
            m = re.match(r'^(\s*)(palm|rake|supportat)(\s*=\s*)([^#]*?)(\s*(#.*)?)$', line)
            if m and m.group(2) in vals:
                block[j] = m.group(1) + m.group(2) + m.group(3) + vals[m.group(2)] + (m.group(5) or '')
                done.add(m.group(2))
        if 'rake' in vals and 'rake' not in done:
            k = next((j for j, l in enumerate(block) if re.match(r'^\s*palm\s*=', l)), len(block) - 1)
            ind = re.match(r'^(\s*)', block[k]).group(1) if block else '  '
            pad = ' ' * max(0, len('supportat') - len('rake')) if re.match(r'^\s*palm\s{2,}', block[k]) else ''
            block.insert(k + 1, ind + 'rake' + pad + ' = ' + vals['rake'])
        for key in ('palm', 'supportat'):
            if key in vals and key not in done:
                block.insert(0, '  %s = %s' % (key, vals[key]))
        if STAMP not in block: block.insert(0, STAMP)
        L[i0 + 1:i1] = block
    return '\n'.join(L)

if __name__ == '__main__':
    if os.path.isdir(OUT): shutil.rmtree(OUT)
    diffs = []
    for card, items in sorted(plan(sys.argv[1:]).items()):
        raw = open(SRC + card, encoding='latin1', newline='').read()
        eol = '\r\n' if '\r\n' in raw else '\n'          # keep the file's own line endings
        src = raw.replace('\r\n', '\n')
        new = patch(src, items).replace('\n', eol)
        os.makedirs(os.path.dirname(OUT + card), exist_ok=True)
        open(OUT + card, 'w', encoding='latin1', newline='').write(new)
        diffs += list(difflib.unified_diff(src.split('\n'), new.replace('\r\n', '\n').split('\n'), 'RS_VR_Weapons/' + card, 'RS_VR_Weapons/' + card, n=1, lineterm=''))
    open(fit.S + 'grip_cards.diff', 'w').write('\n'.join(diffs) + '\n')
    print(len(diffs), 'diff lines;', sum(1 for d in diffs if d.startswith('+') and not d.startswith('+++')), 'added/changed')

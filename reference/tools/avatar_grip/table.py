"""The gun table from the LIVE cards and MODELDEFs (not the 2026-10-02 CSV): per weapon its
card file and grip-block lines, hand, type, prop, mesh file, drawn frame, Scale, and the grip
values the card states today. Hidden surfaces come from the CSV (MODELDEF SurfaceSkin)."""
import re, json, csv, glob, os
import config
W = str(config.WEAPONS) + '/'
CARDS = sorted(glob.glob(W + 'WMCARD.[0-9]*')) + [W + 'WMCARD.grenade', W + 'bd22/WMCARD.bd22',
         W + 'RS_Modern/WMCARD.breach', W + 'RS_Modern/WMCARD.breach_set']
MDEFS = [W + 'MODELDEF.txt', W + 'plus/MODELDEF.txt', W + 'bd22/MODELDEF.txt', W + 'RS_Modern/MODELDEF.txt']
trip = lambda s: [float(x) for x in s.replace(',', ' ').split()]

def cards():
    """top-level blocks start at column 0 and close with `end` at column 0"""
    out = {}; order = []
    for f in CARDS:
        L = open(f, encoding='latin1').read().split('\n')
        cur = None; blk = None
        for i, raw in enumerate(L):
            s = raw.split('#')[0].split('//')[0].rstrip()
            if not s.strip(): continue
            top = not raw[:1].isspace()
            if top:
                if s.strip() == 'end': blk = None; continue
                m = re.match(r'weapon\s+"([^"]+)"', s)
                if m:
                    cur = dict(cls=m.group(1), card=os.path.relpath(f, W), line=i + 1, grip={}, griplines={}, kv={})
                    out[cur['cls']] = cur; order.append(cur['cls']); blk = 'weapon'; continue
                if s.strip() == 'grip' and cur: blk = 'grip'; cur['gripstart'] = i + 1; continue
                blk = 'other'; continue
            ind = len(raw) - len(raw.lstrip())
            if '=' in s and ind <= 2 and blk in ('weapon', 'grip'):
                k, v = [x.strip() for x in s.split('=', 1)]
                if blk == 'weapon': cur['kv'].setdefault(k, v)
                else: cur['grip'][k] = v; cur['griplines'][k] = i + 1
    for c in order:   # base inheritance for the weapon keys
        x = out[c]; kv = x['kv']
        b = kv.get('base')
        while b and b in out:
            for k, v in out[b]['kv'].items():
                if k not in kv and k != 'base': kv[k] = v
            b = out[b]['kv'].get('base')
    return out, order

def modeldefs():
    out = {}
    for f in MDEFS:
        t = open(f, encoding='latin1').read()
        t = re.sub(r'//[^\n]*', '', t)
        for m in re.finditer(r'Model\s+(\w+)\s*\{(.*?)\}', t, re.S):
            name, body = m.group(1), m.group(2)
            d = dict(file=os.path.relpath(f, W))
            p = re.search(r'Path\s+"([^"]+)"', body); d['path'] = p.group(1) if p else ''
            d['models'] = dict((int(a), b) for a, b in re.findall(r'Model\s+(\d+)\s+"([^"]+)"', body))
            s = re.search(r'Scale\s+([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)', body); d['scale'] = [float(x) for x in s.groups()] if s else [1, 1, 1]
            fr = re.findall(r'FrameIndex\s+\w+\s+\w+\s+0\s+(\d+)', body); d['frame'] = int(fr[0]) if fr else 0
            d['surfskin'] = re.findall(r'SurfaceSkin\s+(\d+)\s+(\d+)\s+"([^"]*)"', body)
            out[name] = d
    return out

if __name__ == '__main__':
    C, order = cards(); M = modeldefs()
    csvr = {r['weapon_class']: r for r in csv.DictReader(open(config.CSV))}
    rows = []
    for c in order:
        x = C[c]; kv = x['kv']
        prop = kv.get('prop', '').strip('"'); md = M.get(prop, {})
        mm = re.findall(r'"([^"]+)"', kv.get('model', ''))
        base = W + ('bd22/' if 'bd22' in x['card'] else 'RS_Modern/' if 'RS_Modern' in x['card'] else '')
        mesh = base + mm[0] + '/' + mm[1] if len(mm) == 2 else ''
        if not os.path.exists(mesh): mesh = base + md.get('path', '') + '/' + md.get('models', {}).get(0, '')
        cr = csvr.get(c, {})
        r = dict(cls=c, card=x['card'], line=x['line'], gripstart=x.get('gripstart'), gripend=x.get('gripend'),
                 hand=kv.get('hand', 'main'), type=kv.get('type', ''), prop=prop, mesh=os.path.relpath(mesh, W),
                 mesh_ok=os.path.exists(mesh), frame=md.get('frame', 0), scale=md.get('scale'), mdef=md.get('file'),
                 hidden=[h for h in cr.get('hidden', '').split(';') if h], csv_frame=cr.get('draw_frame'), csv_scale=cr.get('scale'),
                 cm_per_unit=round(abs(md.get('scale', [1])[0]) * 2.941, 4) if md else None,
                 grip=x['grip'], griplines=x['griplines'])
        rows.append(r)
        print('%-20s %-5s %-12s %-50s fr=%-3s sc=%-8s ok=%s csvfr=%s csvsc=%s palm=%s sup=%s cls=%s' % (
            c, r['hand'], r['type'], r['mesh'][-50:], r['frame'], r['scale'][0] if r['scale'] else None, r['mesh_ok'], r['csv_frame'],
            (r['csv_scale'] or '').split(' ')[0], x['grip'].get('palm'), x['grip'].get('supportat'), x['grip'].get('class')))
    json.dump(rows, open(config.OUT / 'guns.json', 'w'), indent=1)
    print(len(rows))

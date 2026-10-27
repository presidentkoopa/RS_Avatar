"""Where the avatar's grip socket goes on each working part (slide, charging handle, bolt,
pump, break-open barrels): the middle of the part's own cross-section at its grab point."""
import sys, os, json, struct
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import config
import parts as CP
import hudrender, gunview, mesh as GM

ROOT = str(config.WEAPONS)
G = {g['cls']: g for g in json.load(open(str(config.OUT / 'guns.json')))}   # table.py
CM_PER_MAP = 100.0 / 34.0

def mesh_entry(gun):
    while gun not in G and gun in CP.BASE: gun = CP.BASE[gun]
    return G.get(gun)

def md3_parts(path, frame):
    names = GM.md3_surfaces(path)
    out = {}
    for nm, (tris, xyz) in zip(names, hudrender.load(path)):
        out[nm.lower()] = np.asarray(xyz[min(frame, len(xyz) - 1)], float)
    return out

def iqm_info(path, frame):
    d = open(path, 'rb').read()
    h = struct.unpack_from('<27I', d, 16)
    (ver, fsize, flags, ntext, otext, nmesh, omesh, nva, nvert, ova, ntri, otri, oadj, njoint, ojoint,
     npose, opose, nanim, oanim, nframe, nchan, oframe, obounds, ncom, ocom, next_, oext) = h
    txt = d[otext:otext + ntext]
    s = lambda o: txt[o:txt.index(b'\0', o)].decode('latin1')
    arrays = {}
    for i in range(nva):
        typ, fl, fmt, size, off = struct.unpack_from('<5I', d, ova + i * 20)
        dt = {0: 'i1', 1: 'u1', 2: '<i2', 3: '<u2', 4: '<i4', 5: '<u4', 7: '<f4', 8: '<f8'}[fmt]
        arrays[typ] = np.frombuffer(d, dtype=dt, count=nvert * size, offset=off).reshape(nvert, size)
    joints = []
    for i in range(njoint):
        name, parent = struct.unpack_from('<Ii', d, ojoint + i * 48)
        joints.append((s(name), parent))
    meshes = []
    for i in range(nmesh):
        name, mat, fv, nv, ft, nt = struct.unpack_from('<6I', d, omesh + i * 24)
        meshes.append((s(name), s(mat), fv, nv))
    pos = gunview.load_iqm(path, frame)[0][1]   # skinned positions, all vertices
    return joints, meshes, arrays[4].astype(int), arrays[5].astype(float), pos

def part_verts(p, ent):
    path = os.path.join(ROOT, ent['mesh'])
    fr = int(ent.get('frame') or 0)
    if path.lower().endswith('.md3'):
        S = md3_parts(path, fr)
        vs = [S[n.lower()] for n in p['surfaces'] if n.lower() in S]
        return np.concatenate(vs) if vs else None
    joints, meshes, bi, bw, pos = iqm_info(path, fr)
    sel = np.zeros(len(pos), bool)
    for n in p['surfaces']:
        for (mn, mat, fv, nv) in meshes:
            if n.lower() in (mn.lower(), mat.lower()): sel[fv:fv + nv] = True
    if p.get('joint'):
        names = [j[0].lower() for j in joints]
        if p['joint'].lower() in names:
            root = names.index(p['joint'].lower())
            sub = {root}
            changed = True
            while changed:
                changed = False
                for i, (nm, par) in enumerate(joints):
                    if par in sub and i not in sub: sub.add(i); changed = True
            dom = bi[np.arange(len(bi)), np.argmax(bw, 1)]
            sel |= np.isin(dom, list(sub))
    return pos[sel] if sel.any() else None

def frame_axes(bore):
    b = np.array(bore, float); b /= np.linalg.norm(b)
    up = np.array([0, 0, 1.0]) - b * b[2]; up /= np.linalg.norm(up)
    ac = np.cross(up, b)          # +Y-ish (left in MD3 axes)
    return b, ac, up

def fit(p):
    gun = p['gun']
    ent = mesh_entry(gun)
    if ent is None: return dict(err='no mesh entry')
    V = part_verts(p, ent)
    if V is None or len(V) < 4: return dict(err='no part vertices (surfaces %s joint %s)' % (p['surfaces'], p.get('joint')))
    cmu = abs(ent['scale'][0]) * CM_PER_MAP            # cm per mesh unit
    g = np.array(p['grab'], float)
    b, ac, up = frame_axes(CP.BAR.get(gun, [1, 0, 0]))
    d = V - g
    along = d @ b; aa = d @ ac; uu = d @ up
    for wcm in (1.0, 1.5, 2.25, 3.4, 5.0, 7.5):
        w = wcm / cmu
        m = (np.abs(along) <= w) & (np.hypot(aa, uu) <= 9.0 / cmu)
        if m.sum() >= 12: break
    how = 'slab'
    if m.sum() < 12:
        # A low-poly part (a pump drawn as a tube with vertices only at its ends) has nothing
        # near the grab along the bore: its whole cross-section is the same all the way along.
        m = np.hypot(aa, uu) <= 9.0 / cmu
        how = 'whole part'
    if m.sum() < 4: return dict(err='nothing of the part near its grab point')
    ca = (aa[m].min() + aa[m].max()) / 2; cu = (uu[m].min() + uu[m].max()) / 2
    seat = g + ac * ca + up * cu
    subj = p.get('subject') or ('slide' if p.get('role') == 'action' else '')
    if subj == 'slide':
        # A CLAW STAYS AT THE GRAB. The owner put the slide's oval where the fingers take it --
        # the rear serrations, a charging handle's T, a bolt's knob -- and the part's middle can be
        # a bolt body hidden in the receiver. The socket goes toward the middle by at most the
        # hand's own hole radius (c_doom_marine 0.77 map units, 2.3 cm), no further.
        lim = 2.3 / cmu
        dv = seat - g
        if np.linalg.norm(dv) > lim: seat = g + dv * (lim / np.linalg.norm(dv)); how += ', held to 2.3 cm from the grab'
    wid = (aa[m].max() - aa[m].min()) * cmu; hgt = (uu[m].max() - uu[m].min()) * cmu
    # [HANDAXIS] THE LINE A WRAPPING HAND CLOSES ROUND. Unstated, the script takes the bore -- a
    # pump, a barrel, a launcher tube. A part that is locally taller than it is long (a bullpup's
    # pump grip) or that runs across the gun (a minigun's side bar) says so: measured in a 4 cm
    # box round the seat, whichever of bore, across and up the part is longest along.
    axis = None
    if subj in ('forend', 'foregrip'):
        dd = V - seat
        al, ac2, up2 = dd @ b, dd @ ac, dd @ up
        box = 4.0 / cmu
        ext = []
        for k, (x, o1, o2) in enumerate(((al, ac2, up2), (ac2, al, up2), (up2, al, ac2))):
            mm = (np.abs(o1) <= box) & (np.abs(o2) <= box) & (np.abs(x) <= 25.0 / cmu)
            ext.append((x[mm].max() - x[mm].min()) * cmu if mm.sum() > 3 else 0.0)
        k = int(np.argmax(ext))
        if k == 2 and ext[2] > 1.3 * ext[0]:
            axis = [0.0, 0.0, -1.0]                        # down the grip, as a pistol grip
        elif k == 1 and ext[1] > 1.3 * ext[0]:
            cen = V.mean(0)
            sgn = 1.0 if ((seat - cen) @ ac) >= 0 else -1.0  # toward the bar's free end
            axis = [round(float(x), 3) for x in (ac * sgn)]
        local_ext = [round(e, 1) for e in ext]
    else:
        local_ext = None
    return dict(seat=[round(float(x), 3) for x in seat], axis=axis, local_ext_cm=local_ext, how=how, slab_cm=wcm, n=int(m.sum()),
                width_cm=round(float(wid), 2), height_cm=round(float(hgt), 2),
                moved_cm=round(float(np.linalg.norm(seat - g) * cmu), 2), cm_per_unit=cmu)

if __name__ == '__main__':
    P = CP.parse()
    sel = [p for p in P if p.get('role') == 'action' or p.get('subject') in ('slide', 'forend', 'foregrip')]
    res = []
    for p in sel:
        r = fit(p); r.update(gun=p['gun'], part=p['id'], subject=p.get('subject') or ('slide' if p.get('role') == 'action' else ''),
                             grab=p['grab'], handseat=p.get('handseat'), file=p['file'], line=p['line'],
                             grab_line=p.get('grab_line'), handseat_line=p.get('handseat_line'), handaxis_line=p.get('handaxis_line'), type=p.get('type'))
        res.append(r)
        print('%-20s %-15s %-8s %s' % (p['gun'], p['id'], r['subject'],
              r.get('err') or 'seat %s  part %.1fx%.1f cm  %.1f cm from grab  (%s, %d v)%s' % (r['seat'], r['width_cm'], r['height_cm'], r['moved_cm'], r['how'], r['n'], ('  AXIS %s ext %s' % (r['axis'], r['local_ext_cm'])) if r['axis'] else (' ext %s' % r['local_ext_cm'] if r['local_ext_cm'] else ''))))
    json.dump(res, open(str(config.OUT / 'seats.json'), 'w'), indent=1)

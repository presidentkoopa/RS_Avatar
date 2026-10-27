"""Fit Ermac's posed hands on a REMA gun mesh and read off the grip frame the cards want:
palm (centre of the handle where the closed fingers' hole is), rake (handle tilt back from
+Z), supportat (centre of the part the off hand closes on). Work frame: cm, F = mesh +X,
L = mesh +Y, U = mesh +Z, cm = mesh units x |Scale| x 2.941 (34 map units per metre).
Ermac's hand is resized to the reference body's hand (c_doom_marine) about the top of
its fist, because the avatar's hand, not Ermac's, is what closes on the gun in game."""
import sys, os, json, math, numpy as np
from scipy import ndimage
from scipy.spatial import cKDTree
import config
S = str(config.OUT) + '/'
import mesh, hole, ermac
ermac.SETS['chainsaw'] = ('chainsaw/chainsaw.md3', 0, 29, 14, 29)
W = str(config.WEAPONS) + '/'
GUNS = {r['cls']: r for r in json.load(open(S + 'guns.json'))} if os.path.exists(S + 'guns.json') else {}
EREF = json.load(open(str(config.DATA / 'eref.json')))
CM_PER_MAP = 100.0 / 34.0
# c_doom_marine palm width 2.03 map units (RS_AVATAR.md section 3) = 5.97 cm here;
# Ermac's hand measures about 8.7 cm across (wrist-end span in his pistol pose).
HAND_SCALE = (2.03 * CM_PER_MAP) / 8.7

def trip(s): return np.array([float(x) for x in s.replace(',', ' ').split()])

def target(cls):
    r = GUNS[cls]
    T, V = mesh.load(W + r['mesh'], r['frame'], r['hidden'])
    c = abs(r['scale'][0]) * CM_PER_MAP
    return V * c, T, c

def surf_pts(V, T):
    a, b, cc = V[T[:, 0]], V[T[:, 1]], V[T[:, 2]]
    out = [V[np.unique(T)], (a + b + cc) / 3]
    for w in (0.25, 0.5, 0.75):
        out += [a * w + b * (1 - w), b * w + cc * (1 - w), cc * w + a * (1 - w)]
    return np.concatenate(out)

def basis(a):
    a = a / np.linalg.norm(a)
    seed = np.array([0, 1.0, 0]) if abs(a[1]) < 0.9 else np.array([0, 0, 1.0])
    e2 = seed - a * (seed @ a); e2 /= np.linalg.norm(e2)
    e1 = np.cross(e2, a)
    return e1, e2

def section(V, T, p, a, half=12.0, res=0.05, pick='contain', dil=0.3):
    """the solid cross-section of the mesh in the plane through p normal to a, around p:
    returns (centre 3D, (size e1, size e2), area cm2) of the region holding p or nearest it"""
    a = a / np.linalg.norm(a); e1, e2 = basis(a)
    d = (V - p) @ a
    A, B, C = T[:, 0], T[:, 1], T[:, 2]
    segs = []
    for (i, j) in ((A, B), (B, C), (C, A)):
        di, dj = d[i], d[j]
        m = di * dj < 0
        w = di[m] / (di[m] - dj[m])
        segs.append((np.nonzero(m)[0], V[i[m]] + (V[j[m]] - V[i[m]]) * w[:, None]))
    # pair the two crossing points of each triangle
    pts = {}
    for idx, q in segs:
        for k, x in zip(idx, q): pts.setdefault(k, []).append(x)
    n = int(2 * half / res) + 1
    img = np.zeros((n, n), bool)
    for k, ps in pts.items():
        if len(ps) < 2: continue
        P0, P1 = ps[0] - p, ps[1] - p
        u0, v0, u1, v1 = P0 @ e1, P0 @ e2, P1 @ e1, P1 @ e2
        if max(abs(u0), abs(v0), abs(u1), abs(v1)) > half * 1.5: continue
        L = max(abs(u1 - u0), abs(v1 - v0)) / res
        for t in np.linspace(0, 1, int(L) + 2):
            iu = int((u0 + (u1 - u0) * t + half) / res); iv = int((v0 + (v1 - v0) * t + half) / res)
            if 0 <= iu < n and 0 <= iv < n: img[iu, iv] = True
    if not img.any(): return None
    dimg = ndimage.binary_dilation(img, iterations=max(1, int(dil / res)))
    lab, nl = ndimage.label(dimg)
    c0 = n // 2
    objs = ndimage.find_objects(lab)
    best = None
    for k, sl in enumerate(objs, 1):
        if sl is None or pick != 'contain': continue
        if sl[0].start <= c0 < sl[0].stop and sl[1].start <= c0 < sl[1].stop:
            sub = ndimage.binary_fill_holes(lab[sl] == k)
            if sub[c0 - sl[0].start, c0 - sl[1].start]:
                ar = int(sub.sum())
                if best is None or ar < best[1]: best = (k, ar)
    if best is None:
        dist, (iu, iv) = ndimage.distance_transform_edt(lab == 0, return_indices=True)
        if dist[c0, c0] * res > 2.5: return None
        k = lab[iu[c0, c0], iv[c0, c0]]
    else:
        k = best[0]
    reg = np.argwhere((lab == k) & img)
    lo, hi = reg.min(0), reg.max(0)
    mid = (lo + hi) / 2 * res - half
    centre = p + e1 * mid[0] + e2 * mid[1]
    size = ((hi[0] - lo[0]) * res, (hi[1] - lo[1]) * res)
    area = best[1] * res * res if best is not None else size[0] * size[1]
    return centre, size, best is not None, area

def handle_axis(V, T, p0, a0, span=(-2.0, 2.0), step=0.5, iters=3, fix_axis=False):
    """the handle's centre line near p0: slice normal to the axis guess, centre each
    section, fit a line, repeat. Returns (point on axis nearest p0's level, axis, sections)"""
    p, a = np.array(p0, float), np.array(a0, float) / np.linalg.norm(a0)
    secs = []
    for it in range(iters):
        secs = []
        for s in np.arange(span[0], span[1] + 1e-6, step):
            r = section(V, T, p + a * s, a, half=6.0)
            if r is not None: secs.append((s, r))
        if len(secs) < 3: return None
        C = np.array([r[0] for s, r in secs])
        c = C.mean(0)
        if not fix_axis:
            ev, evec = np.linalg.eigh(np.cov((C - c).T))
            an = evec[:, -1]; an *= np.sign(an @ a)
            if np.degrees(np.arccos(min(1, abs(an @ a)))) < 35: a = an
        p = c + a * ((p0 - c) @ a)    # same level as p0
    return p, a, secs

def rake_of(a):
    a = a * np.sign(a[2]) if abs(a[2]) > 1e-6 else a
    return math.degrees(math.atan2(a[0], a[2]))

def rot_about_L(deg):
    t = math.radians(deg); c, s = math.cos(t), math.sin(t)
    # positive turns +U toward +F (raises the rake)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])

# ---- Ermac --------------------------------------------------------------------
_E = {}
def ermac_ref(eset, which):
    key = (eset, which)
    if key in _E: return _E[key]
    gV, gT = hole.ermac_gun(eset)
    hV, hT = hole.ermac_hand(eset, which)
    ref = EREF['%s_%d' % (eset, which)]
    H = np.array(ref['centre'])
    gpts = surf_pts(gV, gT)
    d, _ = cKDTree(hV).query(gpts); patch = gpts[d < 3.0]
    _E[key] = dict(gV=gV, gT=gT, hV=hV, hT=hT, H=H, hax=np.array(ref['axis']), patch=patch, gpts=gpts)
    return _E[key]

def ermac_handle(eset):
    """Ermac's own handle axis at his gun hand's hole"""
    e = ermac_ref(eset, 1)
    a0 = e['hax'] if abs(e['hax'][2]) > 0.7 else np.array([0.26, 0, 0.97])
    r = handle_axis(e['gV'], e['gT'], e['H'], a0)
    return r

def icp(src, dst, t0, iters=60, keep=0.8):
    tree = cKDTree(dst); t = np.array(t0, float)
    for _ in range(iters):
        d, idx = tree.query(src + t)
        k = np.argsort(d)[:max(10, int(len(d) * keep))]
        step = (dst[idx[k]] - (src[k] + t)).mean(0); t += step
        if np.linalg.norm(step) < 1e-4: break
    d, _ = tree.query(src + t)
    return t, float(np.median(d))

# ---- the grip rule -----------------------------------------------------------
# c_doom_marine's grip socket sits 0.69 palm widths from the index knuckle toward the
# pinky along the grip axis (RS_AVATAR.md 2.5: knuckle centroid + pw x (.., .., 0.19)),
# and the middle finger rides hard up under the trigger guard, whose underside is
# about pw/6 below the index knuckle. So the socket -- the palm point -- is 0.52 pw
# below the guard junction: 0.52 x 2.03 map units = 1.06 map units.
PW_MAP = 2.03
SOCKET_BELOW_JUNCTION = 0.52 * PW_MAP * CM_PER_MAP          # cm

def sect_pts(V, T, q, a):
    a = a / np.linalg.norm(a); e1, e2 = basis(a)
    d = (V - q) @ a
    A, B, C = T[:, 0], T[:, 1], T[:, 2]
    pts = []
    for (i, j) in ((A, B), (B, C), (C, A)):
        di, dj = d[i], d[j]; m = di * dj < 0
        w = di[m] / (di[m] - dj[m]); pts.append(V[i[m]] + (V[j[m]] - V[i[m]]) * w[:, None])
    P = np.concatenate(pts) - q
    return P @ e1, P @ e2

def reach(V, T, q, a, fwd=7.0, back=7.0, side=3.0):
    """how far the mesh reaches forward and back of the axis point, in this section"""
    u, v = sect_pts(V, T, q, a)
    k = (np.abs(v) < side) & (u > -back) & (u < fwd)
    if k.sum() < 2: return None
    return float(u[k].max()), float(-u[k].min())

def junction(V, T, p, a, smax=14.0, step=0.25, grow=1.5):
    """walk up the handle from p until the section reaches further forward (the trigger
    guard) or further back (the tang / receiver) than the handle did. Returns the distance
    up the axis, or None."""
    base = [reach(V, T, p + a * s, a) for s in np.arange(-1.0, 0.01, step)]
    base = [b for b in base if b]
    if not base: return None, []
    f0 = np.median([b[0] for b in base]); b0 = np.median([b[1] for b in base])
    prof = []
    for s in np.arange(step, smax + 1e-6, step):
        r = reach(V, T, p + a * s, a)
        if r is None: continue
        prof.append((round(float(s), 2), round(r[0], 1), round(r[1], 1)))
        if r[0] > f0 + grow or r[1] > b0 + grow:
            return float(s), prof
    return None, prof

def solve_palm(V, T, p0, rake0=15.0, D=None):
    D = SOCKET_BELOW_JUNCTION if D is None else D
    a0 = np.array([math.sin(math.radians(rake0)), 0, math.cos(math.radians(rake0))])
    r = handle_axis(V, T, p0, a0)
    if r is None: return dict(ok=False, why='no handle section at the clicked point')
    p, a, secs = r
    sj, prof = junction(V, T, p, a)
    if sj is None: return dict(ok=False, why='no guard/receiver found above the handle', p=p, a=a, prof=prof)
    jpt = p + a * sj
    q = p + a * (sj - D)
    r2 = handle_axis(V, T, q, a, span=(-2.0, 1.0), step=0.5)
    if r2 is None: return dict(ok=False, why='no handle section at the palm level', p=p, a=a, jpt=jpt)
    q2, a2, secs2 = r2
    # keep the palm the same distance below the junction along the refined axis
    sj2 = (jpt - q2) @ a2
    palm = q2 + a2 * (sj2 - D)
    sec = section(V, T, palm, a2, half=6.0)
    if sec is not None: palm = sec[0]
    return dict(ok=True, palm=palm, axis=a2, rake=rake_of(a2), junction=jpt, sec=sec[1] if sec else None,
                start=p, secs=[(s, r[0], r[1]) for s, r in secs2], prof=prof)

def local_mid_y(V, T, p, r=3.0):
    """the depth of an orthographic click is unreliable: take L from the middle of the mesh
    found around the clicked F,U"""
    P = surf_pts(V, T)
    k = (np.abs(P[:, 0] - p[0]) < r) & (np.abs(P[:, 2] - p[2]) < r)
    if k.sum() < 5: return p
    q = np.array(p, float); q[1] = (P[k, 1].min() + P[k, 1].max()) / 2
    return q

def rake_scan(V, T, p, lo=-10, hi=88, step=2.0):
    """the handle's tilt as the one whose square cut through p is smallest: a prism cut
    at a slant always shows more area than cut square"""
    out = []
    for th in np.arange(lo, hi + 1e-6, step):
        a = np.array([math.sin(math.radians(th)), 0, math.cos(math.radians(th))])
        r = section(V, T, p, a, half=6.0)
        if r is not None and r[2]: out.append((r[3], th, r))
    if not out: return None, []
    out.sort(key=lambda t: t[0])
    return out[0][1], [(round(th, 1), round(ar, 1)) for ar, th, _ in sorted(out, key=lambda t: t[1])]

def rake_fine(V, T, p):
    th, prof = rake_scan(V, T, p)
    if th is None: return None
    th2, _ = rake_scan(V, T, p, lo=max(-10, th - 2.5), hi=min(88, th + 2.5), step=0.5)
    return th2 if th2 is not None else th

def solve_palm2(V, T, p0, rake0=15.0, D=None):
    """solve_palm, then take the handle's tilt from the square cut (the centre line of a
    handle with a trigger guard, finger grooves or a flared heel above or below the hand
    wanders; the smallest cross-section does not) and redo the level along that tilt"""
    D = SOCKET_BELOW_JUNCTION if D is None else D
    r = solve_palm(V, T, p0, rake0=rake0, D=D)
    if not r.get('ok'): return r
    th = rake_fine(V, T, r['palm'])
    if th is None: return r
    a = np.array([math.sin(math.radians(th)), 0, math.cos(math.radians(th))])
    sec = section(V, T, r['palm'], a, half=6.0)
    p = sec[0] if sec else r['palm']
    sj, prof = junction(V, T, p, a)
    if sj is None:
        r['rake_centreline'] = r['rake']; r['rake'] = th; r['axis'] = a; r['note'] = 'level kept from the centre-line solve'
        return r
    jpt = p + a * sj
    palm = p + a * (sj - D)
    sec2 = section(V, T, palm, a, half=6.0)
    if sec2 is not None: palm = sec2[0]
    out = dict(r)
    out.update(palm=palm, axis=a, rake=th, rake_centreline=r['rake'], junction=jpt, sec=sec2[1] if sec2 else r.get('sec'), prof=prof)
    return out

def finger_line(V, T, J, a, lo=-6.5, hi=-1.0, step=0.5):
    """the handle's centre line over the stretch the fingers close on, below the junction J:
    sections cut square to a, each centred; outliers (a magazine or a heel caught in a cut)
    dropped by size; returns (point at J's level, axis, n sections used)"""
    pts = []; sizes = []
    for s in np.arange(lo, hi + 1e-6, step):
        q = J + a * s
        r = section(V, T, q, a, half=6.0)
        if r is None: continue
        if np.linalg.norm((r[0] - q) - a * ((r[0] - q) @ a)) > 2.0: continue
        pts.append(r[0]); sizes.append(r[1][0])
    if len(pts) < 4: return None
    P = np.array(pts); sz = np.array(sizes); med = np.median(sz)
    k = np.abs(sz - med) <= 0.35 * med + 0.3
    if k.sum() < 4: k = np.ones(len(P), bool)
    P = P[k]; c = P.mean(0)
    ev, evec = np.linalg.eigh(np.cov((P - c).T)); an = evec[:, -1]; an *= np.sign(an @ a)
    an[1] = 0.0; an /= np.linalg.norm(an)     # handles lie in the gun's mid-plane
    return c + an * ((J - c) @ an), an, int(k.sum())

def solve_palm3(V, T, p0, rake0=15.0, D=None, iters=4):
    """the palm D below the guard junction, on the handle's centre line, the line taken over
    the finger stretch only and re-cut square to itself until it stops turning"""
    D = SOCKET_BELOW_JUNCTION if D is None else D
    a0 = np.array([math.sin(math.radians(rake0)), 0, math.cos(math.radians(rake0))])
    r = handle_axis(V, T, p0, a0)
    if r is None: return dict(ok=False, why='no handle section at the start point')
    p, a, _ = r
    a = a.copy(); a[1] = 0; a /= np.linalg.norm(a)
    sj, prof = junction(V, T, p, a)
    if sj is None: return dict(ok=False, why='no guard/receiver found above the handle', p=p, a=a, prof=prof)
    J = p + a * sj; hist = []
    for it in range(iters):
        fl = finger_line(V, T, J, a)
        if fl is None: break
        Jc, an, n = fl
        turn = math.degrees(math.acos(min(1.0, abs(an @ a))))
        a = an
        q = Jc - a * 3.0
        sj2, prof = junction(V, T, q, a)
        if sj2 is None: break
        J = q + a * sj2
        hist.append((round(rake_of(a), 1), n, round(turn, 2)))
        if turn < 0.3: break
    palm = J - a * D
    sec = section(V, T, palm, a, half=6.0)
    if sec is not None: palm = sec[0]
    return dict(ok=True, palm=palm, axis=a, rake=rake_of(a), junction=J, sec=sec[1] if sec else None, hist=hist, prof=prof,
                converged=bool(hist))

# c_doom_marine's index fingertip with the shared gun_grip curl sits 1.78 map units up the
# grip axis from its socket and 0.83 out in front (RS_AVATAR.md 2.5 table: index tip from
# socket (0.93, -0.73, -1.57) against grip axis (-0.54, -0.06, 0.84)). The pad that presses
# the trigger is a little short of the tip: 1.70 map units = 5.0 cm.
TRIGGER_ABOVE_SOCKET = 1.70 * CM_PER_MAP

def solve_palm4(V, T, p0, trig, rake0=15.0, iters=6, up=None):
    """the palm where c_doom_marine's socket sits when its index pad is on the trigger: on the
    handle's centre line (fitted over the stretch the other three fingers close on, below
    the trigger), TRIGGER_ABOVE_SOCKET below the trigger's level along that line"""
    up = TRIGGER_ABOVE_SOCKET if up is None else up
    a0 = np.array([math.sin(math.radians(rake0)), 0, math.cos(math.radians(rake0))])
    r = handle_axis(V, T, p0, a0)
    if r is None: return dict(ok=False, why='no handle section at the start point')
    p, a, _ = r
    a = a.copy(); a[1] = 0; a /= np.linalg.norm(a)
    hist = []
    for it in range(iters):
        Lt = (trig - p) @ a
        pts = []; sizes = []
        for s_ in np.arange(Lt - 9.0, Lt - 2.5 + 1e-6, 0.5):
            q = p + a * s_
            sec = section(V, T, q, a, half=6.0)
            if sec is None: continue
            if np.linalg.norm((sec[0] - q) - a * ((sec[0] - q) @ a)) > 2.5: continue
            pts.append(sec[0]); sizes.append(sec[1][0])
        if len(pts) < 4:
            if it == 0: return dict(ok=False, why='too little handle below the trigger', p=p, a=a)
            break
        P = np.array(pts); sz = np.array(sizes); med = np.median(sz)
        k = np.abs(sz - med) <= 0.35 * med + 0.3
        if k.sum() < 4: k = np.ones(len(P), bool)
        P = P[k]; c = P.mean(0)
        ev, evec = np.linalg.eigh(np.cov((P - c).T)); an = evec[:, -1]; an *= np.sign(an @ a)
        an[1] = 0.0; an /= np.linalg.norm(an)
        turn = math.degrees(math.acos(min(1.0, abs(an @ a))))
        a, p = an, c
        hist.append((round(rake_of(a), 1), int(k.sum()), round(turn, 2)))
        if turn < 0.2: break
    Lt = (trig - p) @ a
    palm = p + a * (Lt - up)
    sec = section(V, T, palm, a, half=6.0)
    if sec is not None: palm = sec[0]
    sj, prof = junction(V, T, palm, a)
    jlevel = None if sj is None else sj - SOCKET_BELOW_JUNCTION      # where the junction rule would put it, relative
    return dict(ok=True, palm=palm, axis=a, rake=rake_of(a), junction=(palm + a * sj) if sj is not None else None,
                sec=sec[1] if sec else None, hist=hist, junction_rule_cm=None if jlevel is None else round(float(jlevel), 2),
                trigger_out_cm=round(float(np.linalg.norm((trig - palm) - a * ((trig - palm) @ a))), 2))

def solve_final(V, T, p0, trig, rake0=15.0, level='auto'):
    """axis from the finger stretch below the trigger (solve_palm4), or below the guard
    junction when the trigger is not this handle's (solve_palm3); level from both rules:
      J rule  c_doom_marine's middle finger hard up under the guard: socket 0.52 pw below
      T rule  its index pad on the trigger: socket TRIGGER_ABOVE_SOCKET below the trigger
    averaged when they roughly agree, the J rule when the trigger is far out in front of
    the grip (the finger reaches; the hand does not climb)"""
    r = solve_palm4(V, T, p0, trig, rake0=rake0) if trig is not None else dict(ok=False, why='no trigger point')
    via = 'trigger'
    if not r.get('ok') or r['trigger_out_cm'] > 8.0:
        r = solve_palm3(V, T, p0, rake0=rake0); via = 'junction'
        if not r.get('ok'): return r
        if not r.get('converged'): return dict(ok=False, why='the handle line never settled')
    a = r['axis']; palm = r['palm']
    sec = section(V, T, palm, a, half=6.0)
    base = sec[0] if sec else palm
    sj, prof = junction(V, T, base, a)
    Jlev = None if sj is None else sj - SOCKET_BELOW_JUNCTION                  # relative to base
    Tlev = None; out = None
    if trig is not None:
        Tlev = (trig - base) @ a - TRIGGER_ABOVE_SOCKET
        out = float(np.linalg.norm((trig - base) - a * ((trig - base) @ a)))
    if level == 'trigger' and Tlev is not None:
        lev = Tlev; how = 'trigger rule (the guard on this gun runs to the bottom of the grip)'
    elif Jlev is not None and Tlev is not None and out <= 6.0 and abs(Tlev - Jlev) <= 2.0:
        lev = (Jlev + Tlev) / 2; how = 'mean of guard and trigger rules'
    elif Tlev is not None and out <= 6.0:
        lev = Tlev; how = 'trigger rule (the guard step found is %.1f cm off it)' % (Jlev - Tlev) if Jlev is not None else 'trigger rule'
    elif Jlev is not None:
        lev = Jlev; how = 'guard rule (trigger %.1f cm out in front)' % out if out is not None else 'guard rule'
    elif Tlev is not None:
        lev = Tlev; how = 'trigger rule (no guard step found)'
    else:
        lev = 0.0; how = 'kept the start level'
    palm = base + a * lev
    sec2 = section(V, T, palm, a, half=6.0)
    if sec2 is not None: palm = sec2[0]
    return dict(ok=True, palm=palm, axis=a, rake=rake_of(a), junction=(base + a * sj) if sj is not None else None,
                sec=sec2[1] if sec2 else None, via=via, how=how,
                rule_gap_cm=None if (Jlev is None or Tlev is None) else round(float(Tlev - Jlev), 2),
                trigger_out_cm=None if out is None else round(out, 2),
                j_palm=None if Jlev is None else base + a * Jlev, t_palm=None if Tlev is None else base + a * Tlev)

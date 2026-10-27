"""Solve palm, rake and supportat for every gun on the live cards. Writes av/result.json.
Nothing here touches a card."""
import sys, json, math, numpy as np
import fit
OUT = fit.S + 'result.json'

# per-gun choices: gun hand mode ('grip' pistol grip, 'stock' straight wrist, 'handle' a bar
# with no guard above it, 'ball' a grenade body, 'skip'), optional start point (mesh units,
# replaces the card's palm as the place to start looking), support mode ('same', 'wrap',
# 'handle', 'none', 'vgrip') and optional support start point (mesh units).
TYPE_SUPPORT = {'pistol': 'same', 'revolver': 'same', 'grenade': 'none', 'melee': 'handle'}
CFG = {
    # PINS, set after review. These guns have two readings close in quality and a re-run from
    # different start points can land on either; the reviewed one is held here so that
    # re-running on cards that already hold fitted values reproduces what was written.
    'WM_PumpM37': dict(hand='stock'),       # 35.5: the stock start finds the grip's own line
    'WM_SSG': dict(rake=43.6),              # not 57: checked on the sheet
    'WM_BFG': dict(rake=27.7),
    'WM_RotaryGun': dict(sup='handle', sup_start=(-13.949, 11.047, 10.355)),
    # straight-stock wrist with no guard step: keep the owner's level, centre it on the wrist
    'WM_DoubleBarrel': dict(hand='handle', axis=(0.86, 0, 0.51)),
    # vertical foregrips
    'WM_BullpupPump': dict(sup='vgrip'),
    'WM_Tec9': dict(sup='vgrip'),          # the off hand holds the magazine
    'WM_BreachMK18': dict(sup='vgrip'),
    'WM_BreachMK18S': dict(sup='vgrip'),
    'WM_BreachHK416S': dict(sup='vgrip'),
    'WM_BreachMCX': dict(sup='vgrip'),
    'BD_MP40': dict(sup='vgrip'),          # the off hand holds the magazine
    # the owner's palm is on the rear sight; the grip is the raked handle below it
    'WM_Bolter': dict(start=(-11.5, 0, -5.0)),
    # curved hook grip with a long guard: the owner's height is right, only its depth was off
    'WM_PlasmaCarbine': dict(hand='handle', axis=(0, 0, 1), rake=11.5),
    # its trigger guard is a frame down to the butt of the grip, so the guard step is not a guard
    'WM_Flamer': dict(level='trigger'),
    # the owner's palm is below the MP5's grip, off the mesh
    # ...and its card's trigger point is a copy of that palm, so only the guard rule applies
    'WM_BreachMP5': dict(start=(8.0, 3.4, -6.8), no_trigger=True),
    # the hand goes inside the cannon; there is no handle to fit, so its point is left alone
    'BD_FlameCannon': dict(hand='tube'),
    'WM_BreachG36C': dict(sup='vgrip'),
    # side and loop handles for the off hand
    'WM_Chaingun': dict(sup='handle', sup_start=(-7.3, 22.6, 5.6), sup_axis=(0, 1, 0)),
    'BD_Minigun': dict(sup='handle', sup_axis=(0, 1, 0)),
    'WM_RotaryLauncher': dict(sup='handle'),
    # chainsaws: rear handle and front bar are bars, not pistol grips
    'WM_Chainsaw': dict(hand='handle', axis=(1, 0, 0.05), sup='handle'),
    'WM_ChainsawHeavy': dict(hand='handle', axis=(1, 0, 0.3), sup='handle'),
    'WM_LongbarChainsaw': dict(hand='handle', axis=(1, 0, 0.05), sup='handle'),
    'BD_Chainsaw': dict(hand='handle', axis=(1, 0, 0.05), sup='handle'),
    # fuel-nozzle handles: no guard above them, keep the owner's level
    'WM_Flamethrower': dict(hand='handle', axis=(0.85, 0, 0.5)),
    'BD_Flamethrower': dict(hand='handle', axis=(0.85, 0, 0.5)),
    # melee: the handle, at the owner's level
    'BD_Axe': dict(hand='handle', axis=(0.6, 0, 0.8), sup='handle', sup_axis=(0.6, 0, 0.8)),
    'BD_Dragonslayer': dict(hand='handle', axis=(0.33, 0, 0.94), sup='handle', sup_axis=(0.33, 0, 0.94)),
    # grenades: the hole closes round the body
    'RS_VRGrenade': dict(hand='ball', start=(0, 0, 0), r=9.0, sup='none'),
    'BD_Grenade': dict(hand='ball', start=(0, 0, -3.0), r=6.0, sup='none'),
}
def cfg(cls):
    g = fit.GUNS[cls]
    c = dict(hand='auto', start=None, sup=TYPE_SUPPORT.get(g['type'], 'wrap'), sup_start=None)
    c.update(CFG.get(cls, {}))
    return c

def solve_gun_hand(cls, V, T, cmu, c):
    r = _solve_gun_hand(cls, V, T, cmu, c)
    if r.get('ok') and c.get('rake') is not None:           # a reviewed pin: that tilt, re-centred
        th = math.radians(c['rake']); a = np.array([math.sin(th), 0, math.cos(th)])
        sec = fit.section(V, T, r['palm'], a, half=6.0)
        r = dict(r, axis=a, rake=float(c['rake']), palm=sec[0] if sec else r['palm'], pinned=True)
    return r

def _solve_gun_hand(cls, V, T, cmu, c):
    g = fit.GUNS[cls]
    p0 = (np.array(c['start'], float) if c['start'] is not None else fit.trip(g['grip']['palm'])) * cmu
    if c['hand'] == 'tube':
        # the hand goes inside the cannon: centre the owner's point in the bore, no rake
        sec = fit.section(V, T, p0, np.array([1.0, 0, 0]), half=12.0, pick='contain')
        return dict(ok=True, palm=sec[0] if sec else p0, axis=np.array([0, 0, 1.0]), rake=None, mode='tube', junction=None, sec=None)
    if c['hand'] == 'ball':
        P = fit.surf_pts(V, T)
        k = np.linalg.norm(P - p0, axis=1) < c.get('r', 4.0)
        q = P[k]; ctr = (q.min(0) + q.max(0)) / 2
        return dict(ok=True, palm=ctr, axis=np.array([0, 0, 1.0]), rake=0.0, mode='ball', junction=None, sec=tuple(np.ptp(q, 0)[[0, 1]]))
    p1 = fit.local_mid_y(V, T, p0)
    if c['hand'] == 'handle':
        a0 = np.array(c.get('axis', (0.26, 0, 0.97)), float)
        r = fit.handle_axis(V, T, p1, a0, span=(-2, 2), step=0.5)
        if r is None: return dict(ok=False, why='no handle section at the start point')
        p, a, secs = r
        if a[2] < 0: a = -a
        sec = fit.section(V, T, p, a)
        return dict(ok=True, palm=sec[0] if sec else p, axis=a, rake=fit.rake_of(a), mode='handle', junction=None, sec=sec[1] if sec else None)
    tries = [15, 55] if c['hand'] == 'auto' else ([15] if c['hand'] == 'grip' else [55])
    trig = fit.trip(g['grip']['triggerat']) * cmu if 'triggerat' in g['grip'] and not c.get('no_trigger') else None
    res = []
    for rk in tries:
        r = fit.solve_final(V, T, p1, trig, rake0=rk, level=c.get('level', 'auto'))
        if r.get('ok'): r['rake0'] = rk; res.append(r)
    if not res: return dict(ok=False, why='no handle with a guard or receiver above it near the start point')
    # a pistol grip unless the handle itself says it is a straight stock
    r = res[0]
    if len(res) == 2 and res[0]['rake0'] == 15 and res[0]['rake'] > 45 and res[1]['rake'] > 40:
        r = res[1]
    if len(res) == 2 and abs(res[0]['rake'] - res[1]['rake']) > 8:
        r['ambiguous'] = 'pistol-grip start %.1f, straight-stock start %.1f' % (res[0]['rake'], res[1]['rake'])
    r['mode'] = 'grip' if r['rake'] <= 45 else 'stock'
    return r

def principal(P):
    c = P.mean(0); ev, evec = np.linalg.eigh(np.cov((P - c).T)); return c, evec[:, -1]

def solve_support(cls, V, T, cmu, c, gh):
    g = fit.GUNS[cls]
    mode = c['sup']
    if mode == 'none' or not gh.get('ok'):
        return dict(ok=gh.get('ok', False), supportat=gh.get('palm'), mode='none')
    if mode == 'same':
        return dict(ok=True, supportat=None, mode='same')     # filled in from the placed Ermac hand
    s0 = (np.array(c['sup_start'], float) if c['sup_start'] is not None else fit.trip(g['grip']['supportat'])) * cmu
    if mode == 'wrap':
        s1 = fit.local_mid_y(V, T, s0)
        sec = fit.section(V, T, s1, np.array([1.0, 0, 0]), pick=c.get('sup_pick', 'nearest'), dil=c.get('sup_dil', 0.15))
        if sec is None: return dict(ok=False, why='no forend section at the clicked support point', mode=mode)
        h = sec[1][0]
        if h <= CUP_ABOVE and not c.get('cup'):
            return dict(ok=True, supportat=sec[0], mode=mode, sec=sec[1], axis=np.array([1.0, 0, 0]))
        # too big to close a hand round: the hand cups it from below, its hole one hole
        # radius above the underside, centred across what it cups
        u, v = fit.sect_pts(V, T, s1, np.array([1.0, 0, 0]))     # e1 = down, e2 = L
        P = np.c_[np.full(len(u), s1[0]), s1[1] + v, s1[2] - u]
        k = (np.abs(P[:, 1] - sec[0][1]) < 3.0) & (np.abs(P[:, 2] - s1[2]) < 6.0)
        if k.sum() < 2: return dict(ok=True, supportat=sec[0], mode=mode, sec=sec[1], axis=np.array([1.0, 0, 0]))
        zb = P[k, 2].min()
        kk = (P[:, 2] >= zb) & (P[:, 2] <= zb + 2 * HOLE_R) & (np.abs(P[:, 1] - sec[0][1]) < 6.0)
        yc = (P[kk, 1].min() + P[kk, 1].max()) / 2 if kk.sum() >= 2 else sec[0][1]
        return dict(ok=True, supportat=np.array([s1[0], yc, zb + HOLE_R]), mode='cup', sec=sec[1], axis=np.array([1.0, 0, 0]))
    if mode == 'vgrip':
        r = fit.solve_palm(V, T, fit.local_mid_y(V, T, s0), rake0=c.get('sup_rake0', 0))
        if not r.get('ok'): return dict(ok=False, why='vertical grip: ' + r['why'], mode=mode)
        return dict(ok=True, supportat=r['palm'], mode=mode, sec=r['sec'], axis=r['axis'], rake=r['rake'])
    if mode == 'handle':
        P = fit.surf_pts(V, T)
        k = np.linalg.norm(P - s0, axis=1) < c.get('sup_r', 3.0)
        if k.sum() < 10: return dict(ok=False, why='nothing of the mesh near the clicked support point', mode=mode)
        ctr, ax = principal(P[k]) if c.get('sup_axis') is None else (P[k].mean(0), np.array(c['sup_axis'], float))
        sec = fit.section(V, T, s0, ax)
        if sec is None: return dict(ok=False, why='no section of the support handle', mode=mode)
        return dict(ok=True, supportat=sec[0], mode=mode, sec=sec[1], axis=ax)
    return dict(ok=False, why='unknown support mode ' + mode, mode=mode)

# Ermac's support hole relative to his gun hand's hole on his pistol: where his off hand
# wraps the gun hand's fingers. Scaled to the reference body and turned with the rake.
def same_offset(rake):
    e1 = fit.ermac_ref('pistol', 1); e2 = fit.ermac_ref('pistol', 2)
    d = (e2['H'] - e1['H']) * HS
    d[1] = 0.0
    return fit.rot_about_L(rake - ERMAC_RAKE['pistol']) @ d

HOLE_R = 0.77 * fit.CM_PER_MAP     # c_doom_marine's grip hole radius (RS_AVATAR.md 2.5), cm
CUP_ABOVE = 5.5                    # a part deeper than this is cupped, not wrapped
HS = 5.97 / 6.4          # c_doom_marine palm width / Ermac's (knuckle centres), both cm
ERMAC_RAKE = {'pistol': 15.1, 'rocket': 16.6, 'flamer': 11.1, 'shotgun': 53.9, 'ssg': 63.5}

def run(only=()):
    try: res = json.load(open(OUT))
    except Exception: res = {}
    for cls, g in fit.GUNS.items():
        if only and cls not in only: continue
        V, T, cmu = fit.target(cls)
        c = cfg(cls)
        gh = solve_gun_hand(cls, V, T, cmu, c) if c['hand'] != 'skip' else dict(ok=False, why='skipped')
        sp = solve_support(cls, V, T, cmu, c, gh)
        if sp.get('mode') == 'same' and gh.get('ok'):
            sp['supportat'] = gh['palm'] + same_offset(gh['rake'])
        old_p = fit.trip(g['grip']['palm']); old_s = fit.trip(g['grip']['supportat'])
        out = dict(cls=cls, cmu=cmu, hand=g['hand'], type=g['type'], cfg={k: v for k, v in c.items()},
                   old_palm=old_p.tolist(), old_supportat=old_s.tolist(), ok=bool(gh.get('ok')), why=gh.get('why'))
        if gh.get('ok'):
            out.update(palm=(gh['palm'] / cmu).round(3).tolist(), rake=None if gh['rake'] is None else round(float(gh['rake']), 1), mode=gh['mode'],
                       axis=np.round(gh['axis'], 4).tolist(), sec_cm=np.round(gh['sec'], 2).tolist() if gh.get('sec') is not None else None,
                       junction=(gh['junction'] / cmu).round(3).tolist() if gh.get('junction') is not None else None,
                       ambiguous=gh.get('ambiguous'), how=gh.get('how'), via=gh.get('via'), rule_gap_cm=gh.get('rule_gap_cm'),
                       trigger_out_cm=gh.get('trigger_out_cm'),
                       j_palm=(gh['j_palm'] / cmu).round(3).tolist() if gh.get('j_palm') is not None else None,
                       t_palm=(gh['t_palm'] / cmu).round(3).tolist() if gh.get('t_palm') is not None else None,
                       palm_move_cm=round(float(np.linalg.norm(gh['palm'] - old_p * cmu)), 2))
        out['sup_ok'] = bool(sp.get('ok')); out['sup_why'] = sp.get('why'); out['sup_mode'] = sp.get('mode')
        if sp.get('ok') and sp.get('supportat') is not None:
            out['supportat'] = (np.asarray(sp['supportat']) / cmu).round(3).tolist()
            out['sup_move_cm'] = round(float(np.linalg.norm(np.asarray(sp['supportat']) - old_s * cmu)), 2)
            out['sup_sec_cm'] = np.round(sp['sec'], 2).tolist() if sp.get('sec') is not None else None
            if sp.get('rake') is not None: out['sup_rake'] = round(float(sp['rake']), 1)
        res[cls] = out
        print('%-20s %-6s %-5s rake %-5s palm %-26s (%s cm) sup %-6s %-26s (%s cm) %s %s' % (
            cls, out.get('mode', '-'), g['hand'], out.get('rake', '-'), out.get('palm', out.get('why')), out.get('palm_move_cm', '-'),
            out['sup_mode'], out.get('supportat', out.get('sup_why')), out.get('sup_move_cm', '-'), out.get('ambiguous') or '', ''), flush=True)
    unify(res)
    json.dump(res, open(OUT, 'w'), indent=1)
    return res

def geom_key(cls):
    import hashlib
    V, T, cmu = fit.target(cls)
    P = np.round(V[np.unique(T)] / cmu, 2)
    P = P[np.lexsort(P.T)]
    return hashlib.md5(P.tobytes()).hexdigest()

def unify(res):
    """guns drawn from the same geometry get the same grip numbers: these are points on the
    mesh, and the mesh's handle does not move because a different card holds it. The main-hand
    card's solve wins (it is the one the owner tuned first), else the first card."""
    groups = {}
    for cls in res:
        if not res[cls].get('ok'): continue
        groups.setdefault(geom_key(cls), []).append(cls)
    for k, members in groups.items():
        if len(members) < 2: continue
        lead = sorted(members, key=lambda c: (res[c]['hand'] != 'main', not c.startswith('WM_'), c))[0]
        for c in members:
            res[c]['same_mesh_as'] = [m for m in members if m != c]
            if c == lead: continue
            L = res[lead]
            for key in ('palm', 'rake', 'axis', 'mode', 'junction', 'j_palm', 't_palm', 'how', 'via'):
                if key in L: res[c][key] = L[key]
            if res[c].get('sup_mode') == 'same' and L.get('sup_mode') == 'same':
                res[c]['supportat'] = L['supportat']        # the pistol off hand rides the palm
            cmu = res[c]['cmu']
            res[c]['palm_move_cm'] = round(float(np.linalg.norm((np.array(res[c]['palm']) - np.array(res[c]['old_palm'])) * cmu)), 2)
            if res[c].get('supportat'):
                res[c]['sup_move_cm'] = round(float(np.linalg.norm((np.array(res[c]['supportat']) - np.array(res[c]['old_supportat'])) * cmu)), 2)
            res[c]['unified_from'] = lead
        print('same geometry:', lead, '->', [m for m in members if m != lead])

if __name__ == '__main__':
    run(sys.argv[1:])

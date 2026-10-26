import sys, os, json
import numpy as np
from PIL import Image, ImageDraw
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import config
import parts as CP, seat as FS
import mesh as GM
from avhand import Hand, read_poses, FING, COL

TABLE = str(config.CURL_TABLE)
POSES = read_poses(TABLE)
BS = config.BODY_SCALE
HANDS = {s: Hand(TABLE, s) for s in ('L', 'R')}
CLASS = {'pistol': 'pistol', 'revolver': 'pistol', 'pump': 'shotgun', 'shotgun': 'shotgun', 'breakaction': 'ssg',
         'rifle': 'rifle', 'smg': 'rifle', 'chaingun': 'rifle', 'launcher': 'rocket', 'plasma': 'plasma',
         'railgun': 'plasma', 'flamethrower': 'plasma', 'bfg': 'bfg', 'chainsaw': 'saw'}

def socket(side):
    a = HANDS[side].ax
    return a['gripsocket']

def pose_for(subject, gtype):
    base = {'slide': 'hold_slide', 'forend': 'hold_forend', 'foregrip': 'hold_foregrip'}[subject]
    cls = CLASS.get(gtype or '', '')
    for n in (base + '_' + cls, base):
        if n in POSES: return n
    return None

def place_hand(seat_m, scale, bore_m, subject, side='L', toward=None, pose=None, axis=None):
    s = np.array(scale, float)
    P = s * np.array(seat_m)
    bw = s * np.array(bore_m, float); bw /= np.linalg.norm(bw)
    up = np.array([0, 0, 1.0]) - bw * bw[2]; up /= np.linalg.norm(up)
    left = np.cross(up, bw)
    handside = left if side == 'L' else -left
    across = -handside
    if axis is not None:
        H = s * np.array(axis, float); H /= np.linalg.norm(H)
        k = across if abs(H @ bw) > 0.7 else bw
        B = k - H * (k @ H); B /= np.linalg.norm(B)
    elif subject == 'slide': B, H = across, bw
    else: B, H = across, -bw
    N = np.cross(H, B)
    if side == 'L': N = -N
    N /= np.linalg.norm(N)
    Z = np.cross(B, N)
    RA = np.stack([B, N, Z], 1)
    hand = HANDS[side]
    X, Nn, K = None, None, None
    ax = hand.ax
    Xc = ax['fingeraxis'] / np.linalg.norm(ax['fingeraxis'])
    Yc = -ax['palmnormal']; Yc -= Xc * (Yc @ Xc); Yc /= np.linalg.norm(Yc)
    Zc = np.cross(Xc, Yc)
    RC = np.stack([Xc, Yc, Zc], 1)
    T = P - RA @ (ax['gripsocket'] * BS)
    pts = hand.pose(POSES.get(pose) if pose else None)
    wrist = pts['hand']
    def tw(p): return (T + RA @ (RC.T @ (np.asarray(p) - wrist)) * BS) / s
    out = {'hand': tw(wrist)}
    for f in FING: out[f] = [tw(p) for p in pts[f]]
    return out

VIEWS = {'side': (0, 2, 1, -1), 'top': (0, 1, 2, 1), 'front': (1, 2, 0, 1)}

def draw_view(T, V, partV, hand, marks, name, size, center, span, flipx=False):
    im = Image.new('RGB', (size, size), 'white'); dr = ImageDraw.Draw(im)
    a, b, c, cs = VIEWS[name]
    sx = -1 if flipx else 1
    def pr(p): return (size / 2 + sx * (p[a] - center[a]) / span * size, size / 2 - (p[b] - center[b]) / span * size)
    dep = V[:, c] * cs
    order = np.argsort(dep[T].mean(1))
    A = V[T[:, 0]]; Bv = V[T[:, 1]]; C = V[T[:, 2]]
    n = np.cross(Bv - A, C - A); n /= (np.linalg.norm(n, axis=1, keepdims=True) + 1e-12)
    vd = np.zeros(3); vd[c] = 1
    sh = np.abs(n @ vd)
    for t in order:
        g = int(150 + 90 * sh[t])
        q = [pr(V[k]) for k in T[t]]
        dr.polygon(q, fill=(g, g, g))
    if partV is not None:
        for p in partV:
            x, y = pr(p); dr.point((x, y), fill=(230, 140, 0))
    for f in FING:
        ch = ([pr(hand['hand'])] if f == 'thumb' else []) + [pr(p) for p in hand[f]]
        dr.line(ch, fill=COL[f], width=3)
    for f in FING[1:]:
        dr.line([pr(hand['hand']), pr(hand[f][0])], fill=(90, 90, 90), width=2)
    for p, col in marks:
        x, y = pr(p); dr.ellipse([x - 4, y - 4, x + 4, y + 4], outline=col, width=2)
    dr.text((3, 3), name, fill=(120, 120, 120))
    return im

def sheet(rows, out, size=230):
    W = size * 3; H = size + 16
    img = Image.new('RGB', (W * 2, H * ((len(rows) + 1) // 2)), 'white')
    for i, (title, T, V, partV, hand, marks, center, span, flip) in enumerate(rows):
        x0 = (i % 2) * W; y0 = (i // 2) * H
        d = ImageDraw.Draw(img); d.text((x0 + 4, y0 + 2), title, fill='black')
        for k, nm in enumerate(('side', 'top', 'front')):
            img.paste(draw_view(T, V, partV, hand, marks, nm, size, center, span, flip), (x0 + k * size, y0 + 16))
    img.save(out)

if __name__ == '__main__':
    P = CP.parse()
    seats = {(r['gun'], r['part']): r for r in json.load(open(str(config.OUT / 'seats.json')))}
    want = sys.argv[2].split(',') if len(sys.argv) > 2 else None
    rows = []
    for p in P:
        key = (p['gun'], p['id'])
        if key not in seats or (want and p['gun'] not in want): continue
        r = seats[key]
        if 'seat' not in r: continue
        ent = FS.mesh_entry(p['gun'])
        path = os.path.join(FS.ROOT, ent['mesh'])
        T, V = GM.load(path, int(ent.get('frame') or 0), ent.get('hidden') or [])
        partV = FS.part_verts(p, ent)
        bore = CP.BAR.get(p['gun'], [1, 0, 0])
        pose = pose_for(r['subject'], p.get('type'))
        hand = place_hand(r['seat'], ent['scale'], bore, r['subject'], 'L', pose=pose, axis=r.get('axis'))
        cmu = abs(ent['scale'][0]) * FS.CM_PER_MAP
        span = float(os.environ.get("SPANCM", "22")) / cmu
        center = np.array(r['seat'])
        rows.append(('%s %s (%s, %s) %s' % (p['gun'], p['id'], r['subject'], p.get('type'), pose), T, V, partV, hand,
                     [(np.array(r['grab']), (220, 0, 0)), (np.array(r['seat']), (0, 170, 0))], center, span, ent['scale'][0] < 0))
    sheet(rows, str(config.OUT / sys.argv[1]))

"""Review sheet per gun: where the new palm and support points are against the card's
points today, with Ermac's posed hands (sized to c_doom_marine's hand) drawn on at them."""
import sys, json, math, numpy as np
from PIL import Image, ImageDraw, ImageFont
import fit, render, solve
OUTD = fit.S + 'sheets/'
import os; os.makedirs(OUTD, exist_ok=True)
def _font(names, size):
    for n in names:
        try:
            return ImageFont.truetype(n, size)
        except OSError:
            pass
    return ImageFont.load_default()
FONT = _font(['arial.ttf', 'DejaVuSans.ttf', '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'], 15)
FONTB = _font(['arialbd.ttf', 'DejaVuSans-Bold.ttf', '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'], 17)
_EA = {}
def ermac_anchor(eset):
    """Ermac's gun-hand hole projected on his own handle axis, and that axis's rake"""
    if eset in _EA: return _EA[eset]
    e = fit.ermac_ref(eset, 1)
    a0 = np.array([0.26, 0, 0.97]) if eset not in ('shotgun', 'ssg') else np.array([0.82, 0, 0.57])
    p, a, _ = fit.handle_axis(e['gV'], e['gT'], e['H'], a0)
    anc = p + a * ((e['H'] - p) @ a)
    _EA[eset] = (anc, fit.rake_of(a)); return _EA[eset]

def ermac_support_anchor(eset):
    e = fit.ermac_ref(eset, 2)
    sec = fit.section(e['gV'], e['gT'], e['H'], np.array([1.0, 0, 0]))
    return sec[0] if sec else e['H']

def vgrip_hand(hV, hT, anc, erk, sp, rake):
    R = fit.rot_about_L(rake - erk) * solve.HS
    V = (hV - anc) @ R.T + sp
    V[:, 1] = 2 * sp[1] - V[:, 1]
    return V, hT[:, ::-1]

def placed_hands(r, cmu):
    out = []
    if not r.get('ok'): return out
    palm = np.array(r['palm']) * cmu; rake = r['rake'] if r['rake'] is not None else 15.0
    eset = 'shotgun' if rake > 42 else 'pistol'
    anc, erk = ermac_anchor(eset)
    R = fit.rot_about_L(rake - erk) * solve.HS
    hV, hT = fit.ermac_ref(eset, 1)['hV'], fit.ermac_ref(eset, 1)['hT']
    gunhand = ((hV - anc) @ R.T + palm, hT)
    out.append(('gun', gunhand))
    if r.get('sup_ok') and r.get('supportat') is not None:
        sp = np.array(r['supportat']) * cmu
        if r['sup_mode'] == 'same':
            e2 = fit.ermac_ref('pistol', 2); a1, rk1 = ermac_anchor('pistol')
            R1 = fit.rot_about_L(rake - rk1) * solve.HS
            out.append(('sup', ((e2['hV'] - a1) @ R1.T + palm, e2['hT'])))
        elif r['sup_mode'] == 'vgrip':
            # a vertical grip is held like a pistol grip: Ermac's gun hand, mirrored to the other side
            anc2, erk2 = ermac_anchor('pistol')
            e1 = fit.ermac_ref('pistol', 1)
            V2, T2 = vgrip_hand(e1['hV'], e1['hT'], anc2, erk2, sp, r.get('sup_rake', 0.0))
            out.append(('sup', (V2, T2)))
        elif r['sup_mode'] in ('wrap', 'handle', 'cup'):
            sset = 'shotgun'
            e2 = fit.ermac_ref(sset, 2); sa = ermac_support_anchor(sset)
            out.append(('sup', ((e2['hV'] - sa) * solve.HS + sp, e2['hT'])))
    if r['hand'] == 'off':   # held in the left hand: mirror across the gun's mid-plane
        y0 = palm[1]
        out = [(k, (np.c_[V[:, 0], 2 * y0 - V[:, 1], V[:, 2]], T[:, ::-1])) for k, (V, T) in out]
    return out

def marks(img, kind, rng, px, pts):
    dr = ImageDraw.Draw(img); H = img.size[1]
    for p, shape, col, lab in pts:
        if p is None: continue
        x, y = render.to_px(p, kind, rng, px, H)
        if shape == 'x':
            dr.line([(x - 7, y - 7), (x + 7, y + 7)], fill=col, width=3); dr.line([(x - 7, y + 7), (x + 7, y - 7)], fill=col, width=3)
        elif shape == '+':
            dr.line([(x - 9, y), (x + 9, y)], fill=col, width=3); dr.line([(x, y - 9), (x, y + 9)], fill=col, width=3)
        elif shape == 'o':
            dr.ellipse((x - 8, y - 8, x + 8, y + 8), outline=col, width=3)
        elif shape == 'O':
            dr.ellipse((x - 6, y - 6, x + 6, y + 6), outline=col, width=3)
        elif shape == '^':
            dr.polygon([(x, y - 7), (x - 6, y + 5), (x + 6, y + 5)], outline=col)
        if lab: dr.text((x + 10, y - 8), lab, fill=col, font=FONT)

def line(img, kind, rng, px, a, b, col):
    dr = ImageDraw.Draw(img); H = img.size[1]
    dr.line([render.to_px(a, kind, rng, px, H), render.to_px(b, kind, rng, px, H)], fill=col, width=2)

def view(V, T, hands, kind, rng, px, pts, axis_line):
    gun = render.draw([(V, T, (170, 172, 182))], kind, rng, px)
    both = render.draw([(V, T, (170, 172, 182))] + [(hv, ht, (232, 175, 140) if k == 'gun' else (130, 205, 150)) for k, (hv, ht) in hands], kind, rng, px)
    img = Image.blend(gun, both, 0.6)
    render.grid(img, kind, rng, px)
    if axis_line is not None: line(img, kind, rng, px, axis_line[0], axis_line[1], (90, 200, 255))
    marks(img, kind, rng, px, pts)
    return img

def sheet(cls, r):
    V, T, cmu = fit.target(cls)
    hands = placed_hands(r, cmu)
    op = np.array(r['old_palm']) * cmu; os_ = np.array(r['old_supportat']) * cmu
    np_ = np.array(r['palm']) * cmu if r.get('ok') else None
    ns = np.array(r['supportat']) * cmu if r.get('supportat') else None
    pts = [(op, 'x', (255, 80, 80), 'palm now'), (os_, 'o', (255, 80, 80), 'support now'),
           (np_, '+', (60, 255, 90), 'palm new'), (ns, 'O', (60, 255, 90), 'support new')]
    if r.get('junction'): pts.append((np.array(r['junction']) * cmu, '^', (255, 90, 255), ''))
    ax = None
    if r.get('ok'):
        a = np.array(r['axis']); ax = (np_ - a * 7, np_ + a * 9)
    # frame: the gun hand and the support, padded
    P = fit.surf_pts(V, T)
    focus = [p for p in (op, os_, np_, ns) if p is not None]
    lo = np.min(focus, 0) - 14; hi = np.max(focus, 0) + 14
    glo, ghi = P.min(0), P.max(0)
    lo = np.maximum(lo, glo - 3); hi = np.minimum(hi, ghi + 3)
    span = hi[0] - lo[0]
    if span < 46:
        mid = (lo[0] + hi[0]) / 2; lo[0], hi[0] = mid - 23, mid + 23; span = 46
    px = 1150.0 / span
    side = view(V, T, hands, 'side', (lo[0], hi[0], lo[2], hi[2]), px, pts, ax)
    top = view(V, T, hands, 'top', (lo[0], hi[0], lo[1], hi[1]), px, pts, ax)
    W = max(side.width, top.width)
    head = 84
    img = Image.new('RGB', (W, head + side.height + top.height + 8), (30, 31, 40))
    img.paste(side, (0, head)); img.paste(top, (0, head + side.height + 8))
    d = ImageDraw.Draw(img)
    fmt = lambda v: '(%s)' % ', '.join('%.3f' % x for x in v) if v is not None else '-'
    t1 = '%s   %s hand, %s   1 mesh unit = %.3f cm   grid 5 cm   side view from the gun\'s right; below, top view' % (cls, r['hand'], r['type'], cmu)
    if r.get('ok'):
        t2 = 'palm     now %s  ->  new %s   moves %.1f cm   rake %s (%s)%s' % (fmt(r['old_palm']), fmt(r['palm']), r['palm_move_cm'], '-' if r['rake'] is None else '%.1f deg' % r['rake'], r['mode'],
                                                                                  '   ! ' + r['ambiguous'] if r.get('ambiguous') else '')
    else:
        t2 = 'palm     NOT SOLVED: %s' % r.get('why')
    if r.get('supportat'):
        t3 = 'support  now %s  ->  new %s   moves %.1f cm   (%s)' % (fmt(r['old_supportat']), fmt(r['supportat']), r.get('sup_move_cm', 0), r['sup_mode'])
    else:
        t3 = 'support  NOT SOLVED: %s' % r.get('sup_why')
    for i, t in enumerate((t1, t2, t3)):
        d.text((8, 6 + i * 25), t, fill=(255, 255, 255) if i == 0 else (200, 255, 200), font=FONTB if i == 0 else FONT)
    img.save(OUTD + cls + '.png')
    return OUTD + cls + '.png'

if __name__ == '__main__':
    res = json.load(open(solve.OUT))
    for cls in (sys.argv[1:] or list(res)):
        print(sheet(cls, res[cls]))

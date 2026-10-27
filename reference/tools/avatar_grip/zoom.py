import sys, json, math, numpy as np
import fit, render
from PIL import Image, ImageDraw
res = json.load(open(fit.S + 'result.json'))
ims = []
for cls in sys.argv[1:]:
    g = fit.GUNS[cls]; r = res[cls]
    V, T, c = fit.target(cls)
    P = lambda k: np.array(r[k]) * c if r.get(k) else None
    ctr = P('palm') if r.get('palm') else fit.trip(g['grip']['palm']) * c
    half = 13; px = 24
    rng = (ctr[0] - half, ctr[0] + half, ctr[2] - half, ctr[2] + half)
    img = render.draw([(V, T, (175, 178, 188))], 'side', rng, px); render.grid(img, 'side', rng, px, step=1)
    d = ImageDraw.Draw(img); H = img.size[1]
    def mk(q, col, lab, shape='o'):
        if q is None: return
        x, y = render.to_px(q, 'side', rng, px, H)
        if shape == 'o': d.ellipse((x - 7, y - 7, x + 7, y + 7), outline=col, width=3)
        else: d.rectangle((x - 6, y - 6, x + 6, y + 6), outline=col, width=3)
        d.text((x + 9, y - 8), lab, fill=col)
    if r.get('palm'):
        a = np.array(r['axis']); pm = P('palm')
        d.line([render.to_px(pm - a * 9, 'side', rng, px, H), render.to_px(pm + a * 9, 'side', rng, px, H)], fill=(90, 200, 255), width=2)
    mk(P('palm'), (60, 255, 90), 'new %s' % r.get('rake'))
    mk(P('j_palm'), (255, 90, 255), 'guard rule', 's'); mk(P('t_palm'), (255, 160, 60), 'trigger rule', 's')
    mk(fit.trip(g['grip']['palm']) * c, (255, 255, 255), 'card')
    if 'triggerat' in g['grip']: mk(fit.trip(g['grip']['triggerat']) * c, (255, 60, 60), 'trigger', 's')
    d.text((5, 5), '%s  %s  %s' % (cls, r.get('how') or r.get('why'), r.get('ambiguous') or ''), fill=(255, 255, 255))
    ims.append(img)
W = sum(i.width for i in ims); o_ = Image.new('RGB', (W, ims[0].height)); x = 0
for i in ims: o_.paste(i, (x, 0)); x += i.width
o_ = o_.resize((int(o_.width * 0.6), int(o_.height * 0.6))); o_.save(fit.S + 'zoom.png')

"""Draw the reference body's hand (bones) posed by a curl pose, the way the engine folds it."""
import sys, os, math
import numpy as np
from PIL import Image, ImageDraw
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import config
sys.path.insert(0, str(config.AVATAR_TOOLS))
import measure_avatar as MA
import test_curl as TC
from studio import Studio
FING = ["thumb", "index", "middle", "ring", "pinky"]
COL = {"thumb": (200, 40, 40), "index": (40, 120, 220), "middle": (40, 160, 60), "ring": (180, 120, 20), "pinky": (140, 60, 180)}
ROOT = str(config.BODY_DIR)

def read_poses(path):
    P = {}
    for line in open(path, encoding='utf-8'):
        p = line.split()
        if len(p) == 6 and p[0] == 'pose':
            P.setdefault(p[1], {})[p[2]] = [float(x) for x in p[3:6]]
    return P

class Hand:
    def __init__(self, table, side='R'):
        self.curl = TC.read_curl(table)
        self.model = Studio(os.path.join(ROOT, 'c_doom_marine.mdl'))
        self.palm, self.bones = TC.read_avatar(os.path.join(ROOT, 'c_doom_marine.avatar'))
        self.side = side
        bm = MA.BoneMap(str(config.BODY_MAP))
        self.hand = self.model.by_name[bm.roles['hand_%s' % side]].index
        # canonical frame from the .avatar
        av = open(os.path.join(ROOT, 'c_doom_marine.avatar')).read().split('side ')
        blk = [b for b in av if b.startswith(side)][0]
        g = {}
        for l in blk.split('\n'):
            q = l.split()
            if q and q[0] in ('fingeraxis', 'knuckleaxis', 'palmnormal', 'gripsocket'):
                g[q[0]] = np.array([float(x) for x in q[1:4]])
        self.ax = g

    def pose(self, pc):
        curls = {}
        for f in FING:
            for jn in (1, 2, 3):
                idx, F = self.bones[self.side][f][jn]
                deg, ax = self.curl[f][jn]
                a = MA.unit(tuple(ax[0]*F[0][k] + ax[1]*F[1][k] + ax[2]*F[2][k] for k in range(3)))
                c = pc.get(f, [0, 0, 0])[jn-1] if pc else 0
                curls[idx] = (a, deg * c)
        G = TC.fk(self.model, curls)
        pts = {'hand': np.array(G[self.hand][1])}
        for f in FING:
            ch = []
            for jn in (1, 2, 3):
                idx, F = self.bones[self.side][f][jn]
                ch.append(np.array(G[idx][1]))
            idx3, F3 = self.bones[self.side][f][3]
            M3 = np.array(G[idx3][0])
            d = M3 @ np.array(F3[0])
            L = np.linalg.norm(ch[2] - ch[1]) * 0.85
            ch.append(ch[2] + d / np.linalg.norm(d) * L)
            pts[f] = ch
        return pts

    def basis(self):
        X = self.ax['fingeraxis']; N = self.ax['palmnormal']
        K = np.cross(X, N); K /= np.linalg.norm(K)
        N = np.cross(K, X)
        return X, N, K

def draw(hand, pc, title, S=200):
    pts = hand.pose(pc)
    X, N, K = hand.basis()
    h0 = pts['hand']
    views = [('side (along knuckles)', X, N), ('palm view', X, K), ('fingertip view', K, N)]
    im = Image.new('RGB', (S*3, S+16), 'white'); dr = ImageDraw.Draw(im)
    dr.text((3, 2), title, fill='black')
    span = 7.5
    for vi, (nm, U, V) in enumerate(views):
        ox = vi*S
        dr.text((ox+3, 14), nm, fill=(120, 120, 120))
        def pr(p):
            q = p - h0
            return (ox + S/2 + q @ U / span * S, 16 + S/2 - q @ V / span * S)
        # palm outline
        for f in FING[1:]:
            dr.line([pr(h0), pr(pts[f][0])], fill=(170, 170, 170), width=2)
        for f in FING:
            ch = [pr(pts['hand'])] if f == 'thumb' else []
            ch += [pr(p) for p in pts[f]]
            dr.line(ch, fill=COL[f], width=4)
            x, y = ch[-1]; dr.ellipse([x-3, y-3, x+3, y+3], fill=COL[f])
        # grip socket marker
        gs = h0 + 0  # socket is in hand frame; skip precise
    return im

if __name__ == '__main__':
    table = sys.argv[1]; out = sys.argv[2]; names = sys.argv[3].split(',')
    side = sys.argv[4] if len(sys.argv) > 4 else 'R'
    P = read_poses(table)
    h = Hand(table, side)
    ims = [draw(h, None if n == 'open' else P[n], n) for n in names]
    W, H = ims[0].size
    cols = 2
    sheet = Image.new('RGB', (W*cols, H*((len(ims)+cols-1)//cols)), 'white')
    for i, im in enumerate(ims): sheet.paste(im, ((i % cols)*W, (i//cols)*H))
    sheet.save(out)

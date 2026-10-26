"""Ermac's reference grips: for each of his sets, the hole of the gun hand and of the
support hand, in his controller frame (cm, F L U)."""
import sys, json, numpy as np
import hole, ermac, config
ermac.SETS['chainsaw'] = ('chainsaw/chainsaw.md3', 0, 29, 14, 29)
OUT = str(config.DATA / 'eref.json')
if __name__ == '__main__':
    res = {}
    for n in ermac.SETS:
        for w in (1, 2):
            V, T = hole.ermac_hand(n, w)
            h = hole.hole(V, T)
            ax = h['axis'] * np.sign(h['axis'][2] if abs(h['axis'][2]) > 0.3 else h['axis'][0])
            res['%s_%d' % (n, w)] = dict(centre=h['centre'].round(3).tolist(), axis=ax.round(4).tolist(), n=len(h['pts']),
                                         evals=h['evals'].round(2).tolist(), thr=h['thr'])
            print(n, w, res['%s_%d' % (n, w)])
    json.dump(res, open(OUT, 'w'), indent=1)

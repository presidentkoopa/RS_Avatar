"""Gun meshes in their own FILE space (mesh units, MD3 axes: +X muzzle, +Y left, +Z up),
at the frame the prop is drawn with. IQMs are skinned at that frame; hand meshes inside
the Breach viewmodels (material v_hands*) and parts parked far off the gun are dropped."""
import struct, sys, numpy as np
import gunview, hudrender

def iqm_meshes(path):
    d = open(path, 'rb').read()
    h = struct.unpack_from('<27I', d, 16)
    ntext, otext, nmesh, omesh = h[3], h[4], h[5], h[6]
    txt = d[otext:otext + ntext]
    s = lambda o: txt[o:txt.index(b'\0', o)].decode('latin1')
    out = []
    for i in range(nmesh):
        name, mat, fv, nv, ft, nt = struct.unpack_from('<6I', d, omesh + i * 24)
        out.append((i, s(name), s(mat), nv, nt))
    return out

def md3_surfaces(path):
    d = open(path, 'rb').read()
    nfr, ntag, nsurf, nskin, ofr, otag, osurf, oeof = struct.unpack_from('<8i', d, 76)
    off = osurf; names = []
    for s in range(nsurf):
        names.append(d[off + 4:off + 68].split(b'\0')[0].decode('latin1'))
        off += struct.unpack_from('<10i', d, off + 68)[9]
    return names

def load(path, frame=0, hide=()):
    """-> (tris (n,3) int, verts (m,3) float) mesh units, hidden surfaces removed"""
    hide = [h.lower() for h in hide if h]
    parts = []
    if path.lower().endswith('.iqm'):
        ms = iqm_meshes(path)
        skip = tuple(i for i, n, m, nv, nt in ms if any(h in m.lower() or h in n.lower() for h in hide) or m.lower().startswith('v_hands') or m.lower().startswith('v_arms'))
        for tris, pos in gunview.load_iqm(path, frame, skip):
            parts.append((tris, pos))
    else:
        names = md3_surfaces(path)
        for nm, (tris, xyz) in zip(names, hudrender.load(path)):
            if any(nm.lower() == h or nm.lower().startswith(h) for h in hide):
                continue
            parts.append((tris, xyz[min(frame, len(xyz) - 1)]))
    T = []; V = []; base = 0
    for tris, v in parts:
        T.append(tris + base); V.append(np.asarray(v, float)); base += len(v)
    T = np.concatenate(T); V = np.concatenate(V)
    # drop parts parked far from the gun (the Breach rigs park a spare magazine 140 units
    # below the gun): connected pieces that never come near the rest
    from scipy.sparse import coo_matrix
    from scipy.sparse.csgraph import connected_components
    nv = len(V)
    # weld coincident vertices so a piece split at UV seams is one piece
    key = np.round(V / 1e-3).astype(np.int64)
    _, inv = np.unique(key, axis=0, return_inverse=True)
    inv = inv.ravel()
    TT = inv[T]
    rows = np.r_[TT[:, 0], TT[:, 1]]; cols = np.r_[TT[:, 1], TT[:, 2]]
    m = inv.max() + 1
    ncomp, lab = connected_components(coo_matrix((np.ones(len(rows)), (rows, cols)), shape=(m, m)), directed=False)
    tlab = lab[TT[:, 0]]
    sizes = np.bincount(tlab, minlength=ncomp)
    # grow the gun outward from its biggest piece, taking every piece that comes within
    # GAP of what is already taken; whatever is left is parked away from the gun
    from scipy.spatial import cKDTree
    pieces = [k for k in np.argsort(sizes)[::-1] if sizes[k] > 0]
    pts = {k: np.unique(T[tlab == k]) for k in pieces}
    ext = np.ptp(V[np.unique(T)], 0).max()
    GAP = max(4.0, 0.08 * ext)
    taken = [pieces[0]]; rest = pieces[1:]
    tree = cKDTree(V[pts[pieces[0]]])
    changed = True
    while changed and rest:
        changed = False
        for k in list(rest):
            d, _ = tree.query(V[pts[k]], k=1, distance_upper_bound=GAP)
            if np.isfinite(d).any():
                taken.append(k); rest.remove(k); changed = True
                tree = cKDTree(V[np.unique(np.concatenate([pts[j] for j in taken]))])
    keep = np.isin(tlab, taken)
    return T[keep], V

if __name__ == '__main__':
    for p in sys.argv[1:]:
        if p.endswith('.iqm'):
            for m in iqm_meshes(p): print(p.split('/')[-1], m)
        else:
            print(p.split('/')[-1], md3_surfaces(p))

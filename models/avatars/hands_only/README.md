# hands_only — the original FBX hands and their IQM descendants

Copied out of the archived `presidentkoopa/DXR` repo on 2026-10-20, with the
owner's permission, as the source material for a Hands Only body option.

## What each file is, measured not assumed

| file | format | joints | meshes | animation |
|---|---|---|---|---|
| `hand_final.fbx` | FBX, 24 MB | rigged: skin deformers + BindPose nodes | both hands | one take, `Take 001` |
| `vhand_bothhands_noanim.iqm` | IQM v2, 378 KB | 22 | **2** — `Hand_Low` 1937v, `Hand_Low1` 1937v | **none: 0 poses, 0 anims, 0 frames** |
| `vhand_onehand_4poses.iqm` | IQM v2, 193 KB | 22 | **1** — `Hand_Low` 1937v | 1 anim `VRHandPoses`, **4 frames**, 60 fps |

Was `wadsrc/static/models/vhand.iqm.orig.bak` and `vhand.iqm` respectively.
`wadsrc/static/models/hand.iqm` in that repo is **0 bytes** and was not copied.

**The FBX is the source of record.** Each IQM lost something different: the
`.orig.bak` kept both hands and lost every pose; the live one kept the poses
and lost a hand. Nothing should be rebuilt from either IQM while the FBX
exists.

## The skeleton, from the IQM header

22 joints, one hierarchy, four segments per digit:

```
Root_joint
└─ HANDPALM_joint
   ├─ INDEX_BASE    → INDEX_MID    → INDEX_TOP    → INDEX_UP_TOP
   ├─ MIDDLE_F_BASE → MIDDLE_F_MID → MIDDLE_F_TOP → MIDDLE_F_UP_TOP
   ├─ RING_BASE     → RING_MID     → RING_TOP     → RING_UP_TOP
   ├─ PINK_BASE     → PINK_MID     → PINK_TOP     → PINK_UP_TOP
   └─ THUMB_BASE    → THUMB_MID    → THUMB_TOP    → THUMB_UP_TOP
```

This is a real skeleton, unlike the Force Unleashed hands, which are MD3 and
therefore cannot carry one — those are 1021 baked vertices across 211 and 196
frames, with the finger rig added later in Python and baked back out.

## Textures

`vhand.png` and `textures/lambert1_Base_Color.png` are **byte-identical**
(md5 `26d442eb…`). `lambert1_Base_Color_4.png` is a second, smaller map.
Maya materials on the two FBX meshes were `aiStandardSurface1` and `blinn1`.

## What a Hands Only option will need

The existing avatars in `models/avatars/` are Source-engine
`.mdl` + `.vvd` + `.dx90.vtx` sets with a `.avatar` descriptor beside them.
These hands are IQM, so a Hands Only entry is not another avatar of that kind
and will need its own path through the body selection rather than a new
folder alongside the others.

Bodies currently in use: `c_doom_marine`, `dark_ages_praetor`,
`doomslayer_default`, `pechenko_doomslayer`, `marine_guy_classic`.
**No longer used:** `doomslayer_lowpoly`, `lillwasa_doomguy`.

## Open question

The FBX's take is the only surviving copy of the full pose set. Recovering it
means a fresh FBX → IQM conversion that keeps both meshes and every keyframe,
rather than copying either IQM here. Not attempted yet.

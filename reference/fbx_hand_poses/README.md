# FBX hand poses — reference renders

Renders of the pose frames in `models/avatars/hands_only/hand_final.fbx`, the source of record
for every hand pose the engine uses. Both hands are drawn, each from its **own** skeleton and its
own skin weights — neither is a copy of the other. Rendered headless in Blender 5.1 straight
from the FBX; nothing here passed through an IQM.

`FBX_hand_poses.png` is the contact sheet. `frames/fNNNN_side.png` and `fNNNN_top.png` are each
frame from the side and from above.

## Which frame is which pose

The names are the ones written into `wadsrc/static/vrhandpose.txt` (UZDXREMA) by
`tools/avatar/mkfbxposes.py`. "Hand" says which FBX hand authored it: **A** is the right hand,
**B** the left (detected from the fist, not assumed). A one-hand pose is written for the other
side mirrored, and the generated file says so on that pose.

| frame | pose | hand |
|---|---|---|
| 1   | `fbx_open` (also `open`) — the reference every pose is measured against | both |
| 154 | `fbx_relaxed` | both |
| 193 | `fbx_halfcurl` | both |
| 206 | `fbx_curl` | both |
| 304 | `fbx_crossed` | both |
| 319 | `fbx_fist` (also `fist`) | both |
| 762 | `fbx_twofinger_point` | A |
| 803 | `fbx_fingergun` | A |
| 820 | `fbx_wrap_half` | B |
| 837 | `fbx_wrap_tight` (also `hold_foregrip`, `hold_forend`) | B |
| 944 | `fbx_thumb_out` | B |
| 985 | `fbx_twohand_gun` (A) and `fbx_twohand_support` (B); `fbx_cup` is B | both |

Frames 183, 792, 807, 824, 828, 865, 873, 913, 927, 957 and 993 are rendered too: they are the
in-between and transition frames of the same take, kept so the motion can be read.

## What the FBX does not have

No rifle, pump, magazine or pistol-specific grips. Those come from per-gun fitting (step 3 of the
plan in UZDXREMA `GUNS_IN_AVATAR_HANDS.md`). Until then the engine's `grip_*` poses are the old
curl values, not FBX data.

This folder is left out of `RS_Avatar.pk3` by `pack.py`; it is reference, not game data.

## Added later the same day

| file | what |
|---|---|
| `poses_on_c_doom_marine.png`, `poses_on_slayer_praetor.png` | every FBX pose on two bodies, each hand with its own bones, beside the FBX frame |
| `grips_on_*.png` | the gun and reload poses the engine now uses, composed from the FBX a whole finger at a time |
| `support_poses.png` | the support hand on the other hand's gun: the FBX two-hand hold, a forend wrap, the handlebar fist |
| `data/fbx_pose_mats.json` | the FBX's pose matrices at the frames above, both hands: what `mkfbxposes.py` reads |
| `iqm/hand_fbx_A.iqm`, `iqm/hand_fbx_B.iqm` | both FBX hands exported whole: 1,279 frames, 22 joints, each from its own skeleton and weights, checked against Blender's deformed mesh. B is written unmirrored: draw it with a negative X scale |

The praetor's first sheets left out its palm (skinned to metacarpal and wrist bones the preview
skipped); the ones here are redrawn whole.

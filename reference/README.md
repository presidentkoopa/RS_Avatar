# reference/ — the avatar hands and guns work, in one place

Everything here is for people, not the game: `pack.py` leaves this folder out of `RS_Avatar.pk3`.
Gathered 2026-10-26. The engine side is UZDXREMA branch `avatar-ik-work`.

## The rules this work keeps

- **The FBX is the only source for hand poses**: `models/avatars/hands_only/hand_final.fbx`, the
  owner's two hands, 22 joints each, 1,279 baked frames. Both hands come from their own skeletons;
  neither is ever a copy of the other.
- **Never used**: the DXR `hand.iqm` / `vhand.iqm` / `hand_left_poses.iqm` exports (bad: one lost a hand,
  the other every pose), and Ermac's hands and poses. `tools/avatar_grip` still draws Ermac's hands
  on its review pictures, read-only, as its own README says; nothing from them reaches a pose.
- **No mesh surgery on the avatars.** Each body keeps its own hands; the FBX poses bend each body's
  own finger bones.

## What is where

| folder | what |
|---|---|
| `fbx_hand_poses/` | the FBX poses: contact sheet, every pose frame rendered (`frames/`), the poses on two bodies (`poses_on_*`), the gun and reload poses (`grips_on_*`), the support hand (`support_poses.png`), the pose data the generator reads (`data/`), and both FBX hands exported whole to IQM (`iqm/`) |
| `gun_fit/` | c_doom_marine's hand on every Vanilla VR gun, and the roll experiment |
| `GUN_POSE_STANDARD.md` | what a gun mesh and its card need for an avatar hand to hold it -- the standard for bringing new meshes off the psprite layer |
| `tools/blender/` | the headless Blender scripts that read the FBX |
| `tools/avatar/` | copies of the engine-side generators and preview tools (the working copies are in UZDXREMA `tools/avatar/`) |
| `tools/avatar_grip/` | the 2026-10-10 card-fitting kit (`palm`, `rake`, `supportat`, `handseat`): the rules the Vanilla cards were made with. Copied from `E:\DOOMWork\tools\avatar_grip`, which is in no repository |

## Loading it in game

RS_Ballistics, RS_Avatar, RS_VR_Weapons and RS_VR_Reload, on the UZDXREMA build. The poses are in the
engine (`wadsrc/static/vrhandpose.txt`); the guns and their cards come from RS_VR_Weapons, and the hand
placement on guns and parts from RS_VR_Reload.

## Doing it again

Blender is `C:\Program Files\Blender Foundation\Blender 5.1\blender.exe`, run headless:
`blender --background --factory-startup --python <script> -- <args>`.

1. **The FBX's pose matrices** -- `tools/blender/hands_dump_pose_mats.py <hand_final.fbx> <fbx_pose_mats.json> <frame,frame,...>`.
   The frames used: 1,154,183,193,206,304,319,762,792,803,807,820,824,828,837,865,873,913,927,944,957,985,993.
2. **The engine's pose file** -- UZDXREMA `tools/avatar/mkfbxposes.py <fbx_pose_mats.json> tools/avatar/fbx_poses.json wadsrc/static/vrhandpose.txt`.
   `fbx_poses.json` names each pose: an FBX frame and which hand, or a composed pose (each finger whole
   from an earlier pose). It detects each hand's side from the fist; never assumes it.
3. **Look before it goes in game** -- `tools/avatar/pose_preview.py <vrhandpose.txt> <out.png> <pose,...> <body.mdl> [<body.mdl> ...]`
   (each body's `.vvd`, `.dx90.vtx` and `.avatar` beside it). `REFDIR=fbx_hand_poses/frames POSEJSON=<fbx_poses.json>`
   adds the FBX frame as a first column.
4. **The hand on the guns** -- `tools/avatar_grip/table.py` writes `out/guns.json` from the live cards
   and MODELDEFs; then `tools/avatar/gun_fit_preview.py <guns.json> <mesh root> <vrhandpose.txt> <body.mdl> <out.png> <Gun,...> [bodyscale]`.
   `ROLL=<deg>` turns the hand about the handle.
5. **Fitting a card** -- `tools/avatar_grip` README, "The process" (solve, sheet, review, emit). It
   writes card copies and a diff; installing them is a separate step.
6. **The FBX hands as IQMs** -- `tools/blender/hands_export_both.py <hand_final.fbx> <out.iqm> <A|B>`, through
   `iqm_export_rs.py` (lsalzman's exporter, patched: the per-frame root matrix, the last frame, and a
   mirror for hand B). B is written unmirrored; draw it with a negative X scale.
7. **Renders of FBX frames** -- `tools/blender/hands_contact2.py <hand_final.fbx> <out_dir> <frame,...>`.

## Open, as of 2026-10-26

- The one headset reading: `vr_gun_anchor_diag 1` with a gun held naturally writes `gunanchor.txt`
  to Documents. It is the rotation from the gun's grip frame to the hand; until it is set, the anchored
  hand assumes identity. The left and right hands may need different values.
- Straight-stock shotguns (PumpDoom, AssaultShotgun, SSG, DoubleBarrel): how a stock wrist is held
  decides whether the standard gains a roll or the rakes come down (`GUN_POSE_STANDARD.md` section 7).
- RocketLauncher and RPG: `palm` off the rear grip; refit.
- The support hand's orientation in RS_VR_Reload `AnchorBrace` (uses the main grip's frame).
- No pinch and no one-finger point in the FBX: rounds and shells use the cup, pointing borrows the
  finger gun's index.
- `iqm/` is not wired into ModelSwapper_Hands or the Hands Only body yet.

# VR Body, IK and Gun Grips: Coder Handoff

Sep 27, 2026

The body, arm IK, pose library and gun-grip frames all exist; four bugs and one missing link stop them working together. Fix them in the order below, one step at a time, and test each step before starting the next.

## What is actually broken

Four bugs cause the huge body and the crossed hands, and one missing link means guns are never posed. Everything else needed already exists.

| # | Bug | Where | Symptom |
| --- | --- | --- | --- |
| 1 | The grip matrix carries a x34 scale (`vr_vunits_per_meter`) and a -Z mirror. The rig used it raw. The on-disk patch `VRRig_CleanFrame` removes the scale but rebuilds `z = x ^ y`, which also throws away the handedness. | `vk_openxrdevice.cpp:7306` (grip), `vr_rig.cpp:231`, `:484-509` | Hands and gun 34x too big; the patch alone gives inside-out hands |
| 2 | The Source body is drawn mirrored. The IQM loader swaps y/z on load (`models_iqm.cpp:359-361`); the Source loader does not (`models_studio.cpp:960`). The body root then stands it up with a plain `rotate(-90, X)`, so it lands left-right mirrored. | `vr_rig.cpp:865-880` | Hands cross the body. The log shows the right hand's target on the left of the model. The +90 yaw "fix" turned the body round instead of fixing the mirror. |
| 3 | The hand-bone target still carries `1/worldScale` from `worldToObject`. | `vr_avatar_pose.cpp:575-585`, `:599`, `:679` | Hands about 1.6x the body's size (worldScale 0.616 in the last run) |
| 4 | The arm IK's "right" vector is `up x forward`, which is the body's left. The self-test uses `forward x up`. | `vr_avatar_pose.cpp:688-691` vs `vr_rig_selftest.cpp:328-329` | Elbows bend the wrong way; pole on the wrong side |
| 5 | Nothing tells the hand which gun it holds. The gun-grip frames exist in `hand_left_poses.iqm` (frames 1494+), but no code selects them. The engine's only link (`gun_grip` curl) needs `vr_rig_hold_weapons 1`, which defaults to 0. | `vr_avatar_pose.cpp:225-236`, `vr_rig.cpp:466`, `:767` | Hands never grip guns |

The source on disk is newer than the build that was last run (source staged 11:32; last logged run 10:07). Rebuild from this source before testing anything.

## Step 1: clean the hand frame

A hand frame must be rotation plus position, in map units, with the grip's own handedness kept. Remove the x34 scale and nothing else.

**1a. `vr_rig.cpp` `VRRig_CleanFrame` (\~line 497): keep the grip's handedness.**

```cpp
// before
const FVector3 z = x ^ y;

// after: normalise z but keep the grip's own sign (det -1: right-handed OpenXR -> left-handed render)
FVector3 z = x ^ y;
if ((z | FVector3(v[8], v[9], v[10])) < 0.f) z = -z;
```

A cleaner alternative also removes the pixel-stretch skew. In `GetGripTransform` (`vk_openxrdevice.cpp:7290-7318`), keep the translation and rebuild the 3x3 without `vunits`:

```cpp
VSMatrix r; r.loadIdentity();
r.scale(1, 1, -1);
r.rotate(-90 + doomYaw - hmdorientation[1], 0, 1, 0);
r.multQuaternion(q);
// copy r's 3x3 into the output; leave the translation column as it is
```

If you take the alternative, `VRRig_CleanFrame` becomes a normalise-only safety step.

**1b. `vr_avatar_pose.cpp`, right after `target.multMatrix(rig.Hand(h).handTarget);` (\~line 585): strip `worldToObject`'s scale from the hand target.**

```cpp
{
    float t[16]; memcpy(t, target.get(), sizeof t);
    const float s = sqrtf(t[0]*t[0] + t[1]*t[1] + t[2]*t[2]);
    if (s > 1e-6f)
        for (int c = 0; c < 3; ++c) for (int r = 0; r < 3; ++r) t[c*4 + r] /= s;
    target.loadMatrix(t);
}
```

Do the same for the IK target at `:599` and `:679`. Do not use the existing `StripScale` here: it rebuilds an axis with a cross product and would flip the IQM case.

**Change at the same time:**

- `vr_rig_selftest.cpp:90-94` (T2): expect det -1 on the cleaned grip, not +1. As written it always fails in VR.
- `vr_rig.cpp:411` debug axes: draw the cleaned grip. The raw one draws 204-unit lines.
- `VirtualGrip` (`vr_rig.cpp:303-310`, desktop fake hands): add `out.scale(1, 1, -1)` so desktop testing matches VR.
- Clear every saved `vr_fit_hand_*` and `vr_fit_wpn_*` value in `doomxr.ini`. They were tuned against the x34 and mirrored frames and will now be wrong.

## Step 2: un-mirror the body and fix the arm IK

The body must get the same y/z swap every other model gets, and the IK's sideways vector must point right. Land 2a with Step 1: either one alone leaves the hands inside out or crossed.

**2a. `vr_rig.cpp:865-880` (body root, role 1): swap y/z for Source bodies instead of the plain quarter turn.**

```cpp
// before
out.rotate(-90.f + (float)r_viewpoint.Angles.Yaw.Degrees(), 0, 1, 0);
out.rotate(fwdYaw, 0, 1, 0);
out.rotate(-90.f, 1, 0, 0);
out.scale(scale, scale, scale);

// after
const float fwdDeg = (float)(atan2(a->Forward.Y, a->Forward.X) * 180.0 / M_PI);
out.rotate(fwdDeg - (float)r_viewpoint.Angles.Yaw.Degrees(), 0, 1, 0); // forward -Y => -90 - yaw
if (modelIsSource) out.multMatrix(kSwapYZ);  // file (x,y,z) -> render (x,z,y), the swap IQM/MD3 get at load
out.scale(scale, scale, scale);
```

- Skip the swap for an IQM body; its loader already swapped.
- The result is det -1 in render space. Opaque models do not cull (`hw_models.cpp:55-58`), so this is fine. If `MDL_FORCECULLBACKFACES` is ever set on a body, pass `mirrored = true`.
- MODELDEF `Scale -1` cannot fix this: the rig path returns before any MODELDEF transform (`models.cpp:1223-1226`).
- Delete the `+90` note at `vr_rig.cpp:861-864`. The -Z mirror never touches the grip translation, so it cannot cross the hands.

**2b. `vr_avatar_pose.cpp:688-691`: sideways must be forward x up (body right).**

```cpp
// before: up x forward (points left)
ai.SidewaysRDir = FVector3(up.Y*F.Z - up.Z*F.Y, up.Z*F.X - up.X*F.Z, up.X*F.Y - up.Y*F.X);
// after (up = +Z)
ai.SidewaysRDir = FVector3(a->Forward.Y, -a->Forward.X, 0.f);
```

The head code reuses this vector and its pitch comes out right only by coincidence. Check the head after this change; do not flip both blindly.

**2c. `vr_armik.cpp:259`: measure the clavicle axis from the rig** (`j.ClavRot.Unapply(j.UpperPos - j.ClavPos)`) instead of assuming +X, like the upper arm and forearm already do.

**2d. Carry the twist bones.** After IK moves the upper arm and forearm, their child twist bones stay in the rest pose and tear the skin (`vr_avatar_pose.cpp:703-708`, `:284-322`). Carry every child of a moved joint by `new * old^-1`, as `:635-648` already does for the hand.

**2e. Height from one source.** The body scales from `r_viewpoint` eye height, which is a constant 44.00 in VR (`log-debug.txt:361837-901`). The hands use the real HMD height (`vk_openxrdevice.cpp:7307`). Scale the body from the same HMD height the grips use, or from the saved `vr_fit_height` (written by fit mode, read by nothing today).

## Step 3: the body contract, and the 7 bodies

All 7 bodies in RS\_Avatar pass the engine's minimum, none has left and right swapped, and six have full finger maps. One needs a fix (lowpoly), and the contract needs a few more checks so a bad body is refused at load instead of drawing wrong.

**What the engine enforces today** (`vr_avatar.cpp:474-506`, `.avatar` parsed at `:349-509`):

- `tier` (Full or NoFingers), `height > 0`, `shoulderwidth > 0`, `eyeheight > 0` (checked at draw, `vr_rig.cpp:803`).
- Both `side` blocks, each with `upperarmlen` and `forearmlen > 0`.
- Roles `hand_R`, `hand_L`, `forearm_R`, `forearm_L`, `pelvis`, `head`.
- Full tier: all 30 finger joints (3 per finger, 5 fingers, 2 sides).

**Silently optional today (make these required):** `clavicle_*` and `upperarm_*` (without them there is no arm IK, only a rigid forearm), `chest` (arm-lift limit), `handrest` (without it the hand takes the raw target rotation).

**Add at load:** check each role's bone index against the model and its name (the name is parsed then thrown away at `:414`); check the right side sits at file -X (a handedness check); reject unknown `forward` values. Only the right side's arm lengths are used (`vr_avatar_pose.cpp:435`); use each side's own.

| Body | Tier | Eye / height | Shoulder | R arm upper / fore / hand | Status |
| --- | --- | --- | --- | --- | --- |
| c\_doom\_marine | Full | 71.39 / 78.49 | 16.74 | 12.00 / 12.17 / 4.86 | OK. Checked against the .mdl |
| dark\_ages\_praetor | Full | 69.72 / 77.32 | 17.63 | 10.41 / 10.23 / 5.01 | OK. Knuckle and twist bones present (twist bones need 2d) |
| doomslayer\_default | Full | 82.16 / 91.40 | 20.32 | 13.53 / 11.56 / 7.33 | OK |
| doomslayer\_lowpoly | NoFingers | 77.37 / 81.49 | 28.34 | 14.71 / 16.23 / 0.00 | **Fix: no `handrest` (hands will face wrong), hand length 0, clavicle separation 21.16.** Re-measure or drop |
| lillwasa\_doomguy | Full | 63.77 / 73.56 | 15.61 | 11.78 / 9.05 / 4.74 | OK. Checked against the .mdl. No spine or neck bones |
| marine\_guy\_classic | Full | 66.55 / 74.20 | 16.53 | 11.00 / 9.40 / 5.76 | OK |
| pechenko\_doomslayer | Full | 65.02 / 72.26 | 13.03 | 11.78 / 11.46 / 3.42 | OK but narrow shoulders and short hand; check in the mirror |

All seven use `forward -y`. Start testing with **c\_doom\_marine** only; it is the one checked bone by bone against its model file.

**To make bodies drop-in** (a `.avatar` + model, no code):

1. One avatar actor class, model picked at runtime from the `VRAVATAR` entry (add a `model` key, or `A_ChangeModel` from a native lookup). Today every body needs its own class, MODELDEF block and cvars, which `genbodies.py` writes.
2. Create the hand-fit storage on demand in the engine, as `vr_fit_wpn_*` already is, instead of per-body CVARINFO lines.
3. Build the body menu from the `VRAVATAR` table.
4. Ship the measuring tool that writes `.avatar` files (`measure_avatar.py` plus its `.bonemap`) with the mod. It is not on disk anywhere.
5. Look each avatar's data up from the actor, not the local `vr_avatar` cvar. Today every avatar in multiplayer is posed with the local player's body data and controllers (`vr_rig.cpp:799-865`).

## Step 4: posed hands on guns

Each gun declares a grip class; the weapon system publishes it for the hand holding the gun; the engine curls the body's fingers to that class's pose, with the index finger moving from ready to fire on the trigger. The poses already exist. Nothing connects them yet.

**What exists**

- `hand_left_poses.iqm` (RS\_WorldHands) has 1705 frames: 0-1297 are the RS hand library, 1298+ are Ermac's off-hand poses, and **1494+ are his gun-hand grips**. Nothing in the game references 1494+.
- The engine curls the body's own fingers from `vrhandcurl.txt` (`vr_avatar.cpp:94`; `vr_avatar_pose.cpp:174-247`, `:482-530`). Trigger curls the index, grip curls the other three, thumb-touch curls the thumb. The only gun link is one fixed pose, `gun_grip`, on middle/ring/pinky (`:225-236`). It only runs when `VRRig_HandHoldsWeapon`, which only role 2 sets.
- WMCARD has no grip or pose field. `handprofile.zs` seats the *working* hand on a part (slide, mag, forend) but carries no pose and nothing for the firing hand.

**4a. Data: a `grip` block in each WMCARD weapon block** (it describes that mesh), with defaults per weapon `type` in RS\_VR\_Reload:

```
grip
{
    class   pistol          // picks the finger pose
    seat    x y z           // where the palm sits, in the gun's md3 space
    seatrot yaw pitch roll  // palm orientation on the grip
    support forend          // off-hand pose name when two-handed (optional)
}
```

Get `seat` offline with the old tool `_old/RS_VRBody/tools/ermac/ingame_chain.py` + `seat_solve.py`. `seats.json` already solves 26 Vanilla and Vanilla+ guns by moving each gun's trigger onto a reference trigger. BD22 guns are not solved yet.

**4b. Poses: bake one curl pose per grip class into `vrhandcurl.txt`.** Take Ermac's ready frame for the class (table below), measure each finger joint's curl against the open hand, and write `pose grip_<class> <finger> j1 j2 j3` lines for all five fingers, thumb included. Also write `grip_<class>_fire` from the fire frame. `_old/RS_VRBody/tools/marine/pose_bake.py` already does the direction-based transfer from the RS hand to a body's finger bones; point it at the 1494+ frames.

**4c. Engine: read the pose from the held gun.** In `UpdateCurls`, replace the fixed `"gun_grip"` lookup with the pose name the held prop publishes (a new actor field, for example `VRGripPose`, set by script). Blend the index finger from `grip_<class>` to `grip_<class>_fire` by the trigger value. Fall back to `gun_grip` when a gun publishes nothing.

**4d. Script: publish it.** `WM_System`, next to `PinHand` / `PoseHand` (`system.zs:967`, `:2717-2751`), sets the prop's `VRGripPose` from the card's grip class when the gun is equipped, and clears it when dropped or holstered. One writer only.

| Grip class | Ermac ready / fire frame | Off-hand support | Vanilla / Vanilla+ guns | BD22 guns |
| --- | --- | --- | --- | --- |
| pistol | 1500 / 1501 | 1297 | M4A3, Pistolet, Moonlight, Sunset, Cola revolver, Tec9 | BD\_Pistol, BD\_Revolver |
| shotgun | 1524 / 1525 | 1295 (forend) | Pump M37, Pump Doom, Bullpup pump, Assault shotgun | BD\_Shotgun, BD\_AssaultShotgun, BD\_M79 (check) |
| ssg | 1541 / 1542 | 1295 | SSG, Double barrel | BD\_SSG |
| rifle (chaingun frame) | 1578 / 1579 | 1295 (SMG 1294) | SMG, Rifle, M16, Chaingun, Machine gun, Rotary gun, BFG rifle, Unmaker | BD\_MP40, BD\_SMG, BD\_Rifle, BD\_Machinegun, BD\_Minigun, BD\_Unmaker, BD\_Buzzsaw (check) |
| rocket | 1589 / 1590 | 1295 | Rocket launcher, RPG, Rotary launcher | BD\_RPG, BD\_Hellish |
| plasma | 1600 / 1601 | 1295 | Plasma rifle, Plasma carbine, Railgun, Bolter, Flamer, Flamethrower | BD\_Plasma, BD\_Railgun, BD\_FlameCannon, BD\_Flamethrower |
| bfg | 1607 / 1608 | 1295 | BFG, BFG heavy (old tool used rifle) | BD\_BFG, BD\_BFG10k (check) |
| saw | 1523 / none found | 1294 | Chainsaw, Heavy chainsaw, Longbar chainsaw | BD\_Chainsaw |
| melee | RS fist, frame 3 | none | none | BD\_Axe, BD\_Dragonslayer; BD\_Grenade uses 1293 |

The chaingun and plasma frames are byte-identical, so rifle and plasma can share one pose to start. Rows marked "check" need a render or a look in the headset before trusting them.

## Step 5: hold the gun in the body's hand

When a body is worn, place the gun from the same hand frame the body's hand uses, offset by the gun's grip seat. With no body worn, leave the stock path alone.

- Today the body's hand follows the controller's **grip** pose, while the stock gun path follows the **aim** pose (`models.cpp:1534-1637`). With role 2 off, the two drift apart.
- Role 2 already places the prop from `handTarget` (`vr_rig.cpp:765-791`) but is gated off by `vr_rig_hold_weapons` (default 0, not in any menu).

**Change:**

1. When an avatar is worn, role 2 is on by default. Keep the cvar only as an off switch for comparison.
2. Role 2 builds `out = handTarget * inverse(GripSeat)`. `GripSeat` is the card's `seat` + `seatrot`, taken from md3 space through the prop's MODELDEF Scale and axis swap, so the palm lands on the grip.
3. Keep `vr_fit_wpn_<class>_R/L` as a small trim on top, not the whole placement.
4. Keep `NoteWeaponInHand` (`vr_rig.cpp:789`), so the finger pose from Step 4 engages.
5. Order: role 2 marks the hand as holding before `UpdateCurls` runs. Today `UpdateCurls` runs once per frame at the first body pose, so a prop drawn after the body misses that frame. Run the weapon-in-hand pass before posing bodies.

This replaces the per-gun `wm_*` / `bd_*` seat tuning for players wearing a body. Those seats stay for players without one.

## Conflicts to remove

The old body failed because several systems each thought they owned the hand. Keep one writer per thing.

| Thing | Writers today | Keep |
| --- | --- | --- |
| Hand model | RS\_WorldHands hand actors still spawn (invisible, `+INVISIBLE`, MODELDEF blocks commented out), and the body's own hand | The body's hand. While a body is worn, don't spawn the RS hand actors, or keep them for grab logic only with no pose writes |
| Finger pose | Engine curls, RS hand `ModelFrame` (`handworld.zs:206-208`), `poseHold` written directly by `RS_Held` (`rs_held.zs:1388`) and `RS_Stabilize` (`rs_stabilize.zs:574`) | Engine curls on the body. Script sets only the grip pose name (Step 4d) |
| Grip ownership | Engine `GripClaim*` fields and the `RS_GripArbiterService` lease. WM `PoseHand` writes `GripClaim*` directly (`system.zs:2747-2750`); `WM_CatchToEquip` leases but never writes the engine field (`weaponset.zs:807`) | One arbiter. The old body's holsters broke on exactly this ("game goes nuts" when catching near a holster) |
| Held gun placement | Stock follow-hand path and role 2 | Role 2 when a body is worn (Step 5), stock otherwise |
| Pose vocabularies | RS hand `POSE_*` (frame numbers), the old body's `RPOSE_*` (differs from index 7), FRIK curl names | Curl pose names only. Map everything else to them |

**Dead code to delete** so nobody wires it back in: `model_reach`, `model_fit`, `model_jointfollow` (the old reach-chain body path, already excised from `models.cpp`), the unused `StripScale`, and the three copies of `kSwapYZ` (keep one).

## Test order and pass checks

One body (c\_doom\_marine), one gun (the pistol), no BD22, no holsters, until step 4 passes. Don't start a step until the one before it passes.

| Step | Test | Pass when |
| --- | --- | --- |
| 0 | Rebuild doomxr.exe from the current source; clear `vr_fit_hand_*` / `vr_fit_wpn_*` from the ini | The build's timestamp is after the last source change |
| 1+2 | Desktop: `vr_rig_fake 1`, `vr_avatar_fullbody 1`, move only the right fake hand | The body's right arm follows it; the hand is body-sized; the body faces where you look and turns the same way you turn |
| 1+2 | Headset: stand still, arms at your sides, then straight forward | `HAND R` model x is negative and `HAND L` positive in the log (rest pose is R -23.1, L +23.1); the self-test T2 passes |
| 2 | Raise each hand overhead, cross it over the chest, reach behind | Elbows bend down and out, never through the chest; the forearm skin does not tear at the twist bones |
| 2e | Crouch and stand | The body height tracks your head; it doesn't shrink or float |
| 3 | Switch through all 7 bodies from the menu | Each draws at your height, right hand on right; lowpoly is either fixed or removed from the list |
| 4 | Hold the pistol; pull the trigger slowly | Fingers wrap the grip; the index moves from ready to fire with the trigger |
| 5 | Hold the pistol; look at your hand from the side | The palm sits on the grip, not beside it; the gun doesn't drift from the hand as you rotate your wrist |
| 4+5 | Swap to each grip class (shotgun, rifle, rocket, plasma, saw) | Each shows its own grip; off-hand support pose engages on two-handed guns |
| last | BD22 set, then holsters | BD22 guns take their class from their card; holsters attach to a body bone, not the headset |

## Open questions and unverified items

These were read from code and logs but not confirmed in a running build. Check each one before relying on it.

- [ ] **2a yaw sign.** Once the swap is in, the body's yaw becomes `fwdDeg - yaw` (was `-90 + yaw`). The swap is a reflection, so the sign should flip, but confirm with the Step 1+2 desktop test before building on it.
- [ ] **`vrhandcurl.txt`.** The engine needs it (`vr_avatar.cpp:94`). It is not in RS\_Avatar, and the last log shows no "missing" error, so it is probably inside `doomxr.pk3`. Find it; Step 4b adds the grip poses to it.
- [ ] **Script natives.** RS\_Avatar calls `VRAvatarTable.ActorName`, `GetWeaponFit`, `SetWeaponFit`, `RigHandValid`, `RigHandPos`, `level.SuppressVRInput` and `GetRawStick*`. These were not in the files reviewed. Confirm they exist in the engine build.
- [ ] **Which files the engine build compiles.** The staged `src/CMakeLists.txt` is dated 09-25 and lists none of the `vr_*.cpp` files. Confirm the real build includes them.
- [ ] **Grip picks marked "check"** in the Step 4 table (M79, Minigun, Buzzsaw, BFG, melee, grenade), the saw's fire frame, and per-gun off-hand support frames. Only 1297 (support), 1293-1295 and the Ermac fist/open frames are identified.
- [ ] **Trigger value.** ZScript appears to see only a binary trigger. The engine curl reads the analog value directly, so the ready-to-fire blend belongs in the engine (4c), not script.
- [ ] **BD22 seats.** BD22 guns use `bd_<gun>_*` seats, most still at the placeholder `ofs_y 28.5`. They need grip seats solved like the Vanilla set before Step 5 applies to them.
- [ ] **Fit mode.** It always starts on the left hand (`mRightHand` never initialised). Fire both swaps hands and fires the gun. The on-screen text says `vr_fitmode off`, but only `vr_fitmode_off` or the menu exits. Small fixes, but they will confuse testing.
- [ ] **Mirror panel.** `RSA_MirrorPanel` has no MODELDEF block or quad model, so the mirror shows nothing. The old body folder has a working `mirror_quad.obj` block to copy.

Sources reviewed: engine `UZDXREMA` (rig, avatar, arm IK, model loaders, OpenXR device, `actor.zs`, specs, logs), `RS_Avatar`, `RS_WorldHands`, `RS_VR_Reload`, `RS_VR_Weapons`, `RS_VR_BD22`, and the old `_old/RS_VRBody`.

# VR Body Fix 03: the FRIK port assumes Fallout's bone axes

Answers open problems 1 and 2 in `VR_BODY_STATE_2026-09-28.md`, and very likely 3. The cause was measured, not guessed: every number below was computed from `c_doom_marine.mdl`'s own bind pose, with the same formulas the solver uses.

**Cause:** FRIK was written for Fallout 4's skeleton. There, every arm bone runs along its own local **+X**, and the hand bone is in a fixed "FRIK hand" frame (+X wrist to fingers, -Y the palm normal). `c_doom_marine` is a ValveBiped rig:

- its arm bones run along local **-Y (right)** and **+Y (left)**;
- its left arm bones are its right arm bones **turned 180 degrees** (not mirrored), so every local axis means something different on each side.

The port feeds the raw ValveBiped frames straight in, and three places read them as if they were Fallout's.

This is also why `vr_rig_selftest` passes 12/12: its test rig is built in FRIK's own convention, so it never exercises a ValveBiped frame.

## The evidence (bind pose, c_doom_marine.mdl)

| Bone | Right: bone axis in local | Left: bone axis in local | FRIK assumes |
| --- | --- | --- | --- |
| Clavicle -> UpperArm | (0.26, -0.97, 0) | (-0.26, 0.97, 0) | +X |
| UpperArm -> Forearm | (0, -1, 0) | (0, 1, 0) | +X |
| Forearm -> Hand | (0, -1, 0) | (0, 1, 0) | +X |
| Ulna (forearm twist leaf) | same frame as Forearm: (0, -1, 0) | (0, 1, 0) | +X |

| Hand bone, bind pose | Right | Left | Should be |
| --- | --- | --- | --- |
| `handBack.Z` (`vr_armik.cpp:335`) | **+0.489** | **-0.489** | equal |
| `handSide.Z` (`:338`) | **-0.656** | **+0.656** | equal |
| same, after the fix below | +0.518 / -0.561 | +0.518 / -0.562 | equal |

With mirror-image hands, the two wrist-twist angles come out with **opposite signs**. `twistLimitAngle` then tilts `bendDownDir` up on one arm and down on the other. That is the chicken-winged right elbow at shoulder height and the left elbow hanging low (open problem 1).

## The three wrong places

1. **Hand frame, `vr_armik.cpp:335-339`.** It reads the raw ValveBiped hand rotation as a FRIK hand frame. Result: the elbow height is mirrored between the sides (open problem 1).
2. **Upper-arm roll, `:455-474`.** It flattens against local X and rolls about `(1, 0, 0)`. On this rig X is **perpendicular** to the bone, so the "roll" swings the upper arm sideways off its aim, differently per side. Same for `uloc.X = 0` on the clavicle frame.
3. **Wrist roll and twist leaves, `:486-513`, and `RollLeaf` in `vr_avatar_pose.cpp:389-402`.** The roll angle is measured in the plane perpendicular to local X, and `RollLeaf` rotates the Ulna about its local X. On this rig that axis is across the forearm, so the twist leaf **swings sideways instead of rolling**. That is the gnarled forearm (open problem 2). A leaf swinging with an angle that can wrap is also the best candidate for the snapping (open problem 3); `BONE ... JUMP` doesn't watch the leaves.

## The fix: canonical frames in, real frames out

Don't touch FRIK's maths. Give it the frames it expects, and turn the answer back into the rig's own frames. Compute one constant 3x3 `C` per bone, per side, once from the bind pose, and cache it on the avatar.

**Arm bones (clavicle, upper arm, forearm, and the twist leaves):**

```cpp
// C maps FRIK-canonical -> the bone's own local frame.
// X = along the bone (toward its child), Y = the body's forward made perpendicular to X, Z = X x Y.
// The same formula on both sides, so both arms mean the same thing by X, Y and Z.
static FVRMat3 CanonArm(const FVRMat3& restRot, const FVector3& toChildWorld, const FVector3& bodyForward)
{
    const FVector3 x = Norm(restRot.Unapply(toChildWorld));
    FVector3 f = restRot.Unapply(bodyForward);
    const FVector3 y = Norm(f - x * (x | f));
    FVRMat3 c; c.Col[0] = x; c.Col[1] = y; c.Col[2] = x ^ y;
    return c;
}
```

**Hand (FRIK hand convention: +X wrist to fingers, -Y the palm normal):**

```cpp
// fingeraxis and palmnormal are already in the .avatar, per side, in file space.
static FVRMat3 CanonHand(const FVRMat3& restRot, const FVector3& fingerAxis, const FVector3& palmNormal)
{
    const FVector3 x = Norm(restRot.Unapply(fingerAxis));
    FVector3 p = restRot.Unapply(palmNormal);
    const FVector3 y = Norm((p - x * (x | p)) * -1.f);
    FVRMat3 c; c.Col[0] = x; c.Col[1] = y; c.Col[2] = x ^ y;
    return c;
}
```

For the arm bones, `toChildWorld` is the rest position of the next joint minus this one: clavicle to upperarm, upperarm to forearm, forearm to hand. For a twist leaf, use the forearm's value. `bodyForward` is the avatar's `forward`, `(0, -1, 0)` for all seven bodies.

**Into the solver** (`vr_avatar_pose.cpp` ~line 995, where `aj` / `ai` are filled):

```cpp
aj.ClavRot  = VRMat3_Mul(Mat3Of(restGlobals[clav]),  Cclav);
aj.UpperRot = VRMat3_Mul(Mat3Of(restGlobals[upper]), Cupper);
aj.ForeRot  = VRMat3_Mul(Mat3Of(restGlobals[fore]),  Cfore);
aj.HandRot  = VRMat3_Mul(Mat3Of(restGlobals[hand]),  Chand);
ai.TargetRot = VRMat3_Mul(Mat3Of(placed), Chand);
```

**Out of the solver** (~line 1040): multiply by the transpose (C is orthonormal):

```cpp
gGlobals[upper] = FromMat3Pos(VRMat3_Mul(ao.UpperRot, Transpose(Cupper)), ao.UpperPos);
gGlobals[fore]  = FromMat3Pos(VRMat3_Mul(ao.ForeRot,  Transpose(Cfore)),  ao.ElbowPos);
gGlobals[clav]  = FromMat3Pos(VRMat3_Mul(ao.ClavRot,  Transpose(Cclav)),  aj.ClavPos);
// the hand keeps `placed` exactly, as now
```

**Twist leaves (`RollLeaf`):** roll about the bone's own axis, not local X:

```cpp
// before
roll.rotate(deg, 1.f, 0.f, 0.f);
// after: the leaf's canonical X, in its own local frame
const FVector3 ax = CleafX;          // = Col[0] of the leaf's C (for Ulna: (0,-1,0) right, (0,1,0) left)
roll.rotate(deg, ax.X, ax.Y, ax.Z);
```

With `C` applied, the existing `(1, 0, 0)` rolls, the `X = 0` flattening and the `(0, 0, -1)` wrist reference in `vr_armik.cpp` all mean what FRIK meant, on both sides. Nothing inside the solver needs editing.

The 2c clavicle change (`j.ClavRot.Unapply(upperPos - clavPos)`) becomes redundant once the clavicle is canonical, but it stays correct, so it can stay.

## Add a self-test for it

Add a T13 to `vr_rig_selftest.cpp` that builds a ValveBiped-style arm: bones along local -Y on the right and +Y on the left, left = right turned 180 degrees about X. Solve mirror-image targets and assert the elbows come out mirror images, within 0.5 units. Today it would fail; after the fix it must pass. That closes the gap that let 12/12 pass while the headset showed a chicken wing.

## Check in the headset

1. Hold both hands in mirror-image positions in front of your chest. The two elbows should be at the same height (log: the elbow z values within about 1 unit).
2. Turn one wrist palm-up, then palm-down. The forearm should rotate along its length, with no sideways kink at the wrist.
3. `vr_avatar_bone_diag 1`: add the Ulna / forearm_twist leaves to the JUMP report. They should be as smooth as the elbow (0.3/frame or less).

## Other bodies

Every body goes through this, so the fix is generic. Praetor, doomslayer_default and marine_guy_classic may use different bone conventions again. `C` is measured per body from its own bind pose, so none of them need special code. Log `C` for each body once at load (the three columns per bone) so a strange rig can be spotted from the log.

# VR Body Fix 02: the body turns with the head

Test result (2026-09-28, c_doom_marine): left arm bent into an S, right arm pulled flat across the chest, shoulder looks like it sits in the chest.

**Cause:** the body faces wherever the HEAD looks, but the hands are placed in the player's turn frame. Turn your head to look at an arm and the whole body swings under you, so the hand targets land on the wrong side of the body and the IK drags the arms across the chest.

Steps 1 and 2 from the handoff are in and working: the hands are body-sized, the right-hand target sits on the right at rest, and no scale or mirror problem shows in the log. This is a new, separate bug.

## Evidence

- Body yaw: `vr_rig.cpp:946`: `out.rotate(fwdDeg - r_viewpoint.Angles.Yaw, ...)`. `r_viewpoint.Angles.Yaw` is the view yaw, meaning the turn yaw PLUS the headset's own yaw.
- Hand yaw: `GetGripTransform` (`vk_openxrdevice.cpp:7290-7318`) rotates by `doomYaw - hmdorientation[1]`, and the grip offsets are rotated by `GetViewpointYaw() - hmdorientation[1]` (`:4027`). That is the turn yaw only; the headset's yaw is taken out.
- So when you look right, the body turns right and your real hands end up on its left.
- Log (`log-debug.txt`, last session): with both hands held in front, `HAND R` model x swings between -33 and +27 and `HAND L` between -13 and +37 from one second to the next, while the world positions barely change. Rest is R -23.1 / L +23.1. The hands are steady; the body is turning under them.

## Fix: give the body its own heading

The body faces the way the player's body faces, not the head. It follows the head only past a neck deadzone, and it follows snap and smooth turn 1:1. This is the rule the old RS_VRBody used (`updateBodyYaw`), moved into the engine.

In `VRRig_ObjectToWorld`, role 1 (`vr_rig.cpp` ~line 946), replace the view-yaw line with a body yaw kept across frames:

```cpp
// [BODYYAW] The body faces where the BODY faces, not where the head looks.
CVAR(Float, vr_body_yaw_deadzone, 45.f, CVAR_ARCHIVE)   // free head turn before the hips follow
CVAR(Float, vr_body_yaw_follow,   6.f,  CVAR_ARCHIVE)   // catch-up speed past the deadzone, per second
CVAR(Float, vr_body_yaw_maxneck,  100.f, CVAR_ARCHIVE)  // never let the head get further than this from the body

static double NormDeg(double a) { while (a > 180) a -= 360; while (a < -180) a += 360; return a; }

static double BodyYaw(AActor* pawn)
{
    static bool   init = false;
    static double body = 0, lastTurn = 0;
    static uint64_t lastMs = 0;

    const double head = r_viewpoint.Angles.Yaw.Degrees();           // where the head looks, world
    const double turn = pawn ? pawn->VRTurnYaw.Degrees() : 0.0;     // snap + stick turn, accumulated
    const uint64_t now = I_msTime();

    if (!init) { init = true; body = head; lastTurn = turn; lastMs = now; return body; }

    const double dt = clamp((now - lastMs) / 1000.0, 0.0, 0.1);
    lastMs = now;

    // Controller turn moves the body 1:1 (a snap is a snap).
    body = NormDeg(body + NormDeg(turn - lastTurn));
    lastTurn = turn;

    // Inside the neck deadzone the body does not move; past it, ease toward the head.
    const double d = NormDeg(head - body);
    const double dead = vr_body_yaw_deadzone;
    if (fabs(d) > dead)
    {
        const double excess = d - copysign(dead, d);
        body = NormDeg(body + excess * clamp(vr_body_yaw_follow * dt, 0.0, 1.0));
    }
    // Hard limit: the head never ends up behind the shoulders.
    const double d2 = NormDeg(head - body);
    if (fabs(d2) > vr_body_yaw_maxneck) body = NormDeg(head - copysign((double)vr_body_yaw_maxneck, d2));
    return body;
}

// before
out.rotate(fwdDeg - (float)r_viewpoint.Angles.Yaw.Degrees(), 0, 1, 0);
// after
AActor* pawn = players[consoleplayer].mo;   // the body follows the local player (see note 4)
out.rotate(fwdDeg - (float)BodyYaw(pawn), 0, 1, 0);
```

Check the type of `VRTurnYaw` in `actor.h` (it is `double VRTurnYaw` in ZScript, `actor.zs:793`). If it's a plain double, drop the `.Degrees()`.

## Do these at the same time

1. **Keep the body under the neck, not the eyes.** The root is placed at the eye (`r_viewpoint.Pos`), so the model's feet sit directly under your eyes and its shoulders end up forward of your real shoulders. Move the root back by the model's eye-to-origin offset, rotated by the body yaw. Read the head joint's rest XY from the model, or add an `eyeforward` value to the `.avatar`. Roughly 3 to 4 map units at the marine's scale.
2. **One height everywhere.** `vr_avatar_pose.cpp` ~line 604 still computes `worldScale` from `r_viewpoint.Pos.Z`, the constant 44. The body now scales from the headset height (`vr_rig.cpp`, STEP2E). The arm solver's unit conversion (`armK`) is therefore about 25% off at a real eye height of 35. Use the same `eyeZ` there. Put it in one shared function so the two can't drift again.
3. **Also use the new yaw wherever the IK or the head reads the body's facing.** Anything that uses `r_viewpoint.Angles.Yaw` for the body must use `BodyYaw` instead, or the arms and head will disagree with the torso.
4. **Multiplayer** (later, not now): `BodyYaw` keeps one static state for the local player. Move it onto the avatar actor when you do per-player bodies.

## Test

1. Stand still, look straight ahead, and hold both hands forward. Both arms should reach forward cleanly, with no S and no arm across the chest.
2. Keep your hands still and turn only your head about 30 degrees each way. The body must not move.
3. Turn your head past about 45 degrees and hold it. The body eases round to follow.
4. Snap turn. The body snaps with you.
5. Log check: with hands held still in front, `HAND R` model x stays negative and `HAND L` positive while you look around.

If step 1 still shows a bent or flat arm with the head straight, the next suspect is the arm solver's scale (item 2 above). Send the log from that run.

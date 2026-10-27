# Holsters

![Holsters in action](media/holster_demo.gif)

Reach down. Grab your hip. There's a gun there.

Body-anchored storage for VR weapons: put a weapon somewhere on yourself,
reach back and get it later, with either hand. No weapon-specific setup, no
authoring — it works with whatever `Weapon` classes are actually loaded.

## How it works

- **Store**: grip inside an anchor with a weapon in hand. An empty holster
  takes the weapon and leaves you a fist. An occupied holster **swaps** — the
  weapon that was there comes to that hand instead.
- **Draw**: grip an occupied anchor with an empty (fist) hand to take what's
  stored there.
- **Either hand, any holster.** There's no hand-specific holster and no
  weapon-specific holster — whatever you put somewhere is what's there when
  you reach back, until you touch that slot again yourself.
- Instant by default (`rs_holster_instant_switch`) — store and draw resolve
  in the same tic instead of playing out the weapon's normal raise/lower
  animation, so two-handed near-simultaneous swaps don't fight each other
  over the shared pending-switch state. Turning it off restores normal
  switch speed for holster actions only; ordinary weapon switching (number
  keys, the wheel) is untouched either way.

## On your body (REMA)

With the UZDXREMA engine and a REMA body worn, the hip pairs, the pectorals and
the ammo pouch ride the **body itself** — its pelvis and chest — instead of
hanging off the headset. Crouch, lean, sit or turn your hips under a still head
and they go with you, sitting where you can see them on the model.

- The first time you stand up straight with a body on, each holster is moved
  onto the body from exactly where your headset table had it, so nothing jumps.
- Offsets are kept as fractions of your eye height along the body's own
  pelvis/chest frame, so they carry between bodies of different sizes.
- Edit mode moves both at once; saved profiles keep both.
- The head pair stays on the headset — beside your ears *is* head-relative.
- `rs_holster_body` (menu: Placement → "Holsters ride the worn body") turns it
  off and gives you the headset-only table, exactly as before. With no body
  drawn it falls back to that table on its own.
- `netevent rs-holster-debug` prints whether the body is driving them.

## Positioning

Every anchor is adjustable in-headset — no config file editing, no
proportion-table guessing:

1. **Edit mode** (`rs_holster_edit`) — grab an anchor, move your hand to
   where you actually want it, grip again to drop it there.
2. **Save a profile** for your current posture — standing or seated,
   separately (`rs_holster_save_standing` / `rs_holster_save_seated`).
3. **Switch profiles** mid-session (`rs_holster_switch_profile`) the moment
   you sit down or stand up, without re-editing anything.

`rs_holster_active_count` (menu: 2 / 4 / 6 / 8) chooses how many of the
eight declared torso anchors are live — hips only, up through hips +
shoulders + pectorals + a second hip pair.

## Stored weapon appearance

A holstered weapon shows as a real 3D model at its anchor, not a flat icon:

- Automatically scaled to fit the holster (`rs_holster_prop_fill`, against a
  tunable target size, `rs_holster_prop_visual_radius`) — a BFG and a pistol
  read as comparably sized instead of both taking one flat multiplier.
  `rs_holster_prop_scale`/`_arm` are the exact fallback for the rare model
  the engine can't measure.
- Orientation and centering are corrected automatically per-weapon (reading
  the model's own baked offset/rotation), with pitch/roll/yaw/position trim
  sliders on top for whatever the automatic pass doesn't fully resolve.
- **ModelSwapper-compatible** — a weapon whose displayed model has been
  swapped by ModelSwapper still renders correctly when holstered, not just
  when held.
- The wireframe/bracket marker at each anchor (`rs_holster_markers`) is
  independent of the weapon-model display (`rs_holster_props`) and can be
  shape/color-customized (cold vs. hand-in-range colors, marker scale).

## Requires

- Any weapon-content pack providing standard `Weapon` classes — borrows
  whatever is loaded, never references RS_Main or any other specific pack
  by name.
- The UZDXREMA engine build (for the native holster fields this mod is
  built on).

## Binds

**No default binds — set these yourself under Customize Controls.**

| Action | Alias |
|---|---|
| Store/draw, main hand | `rs_holster_main` (engine sends **F13** for a holster-context grip) |
| Store/draw, off hand | `rs_holster_off` (**F14**) |
| Recalibrate height | `rs_holster_recal` |
| Switch seated/standing profile | `rs_holster_switch_profile` |
| Edit mode toggle | `rs_holster_edit` |
| Save profile — standing / seated | `rs_holster_save_standing` / `rs_holster_save_seated` |
| Load profile — standing / seated | `rs_holster_load_standing` / `rs_holster_load_seated` |
| Reset offsets to defaults | `rs_holster_reset` |
| Debug dump | `rs_holster_debug` |

Grip inside a holster's radius routes to these instead of grip's normal
meaning; outside a holster, or mid-combo, grip behaves exactly as it always
does.

## Tested with

- **VanillaVRPlus** — the primary test arsenal this mod is developed
  against. Full store/draw/swap round-trips, both hands, every torso
  holster, validated clean, plus an extended `idkfa` stress test (full
  arsenal, holsters rearranged live, rapid two-handed swapping) with no
  stuck hands or lost weapons.
- **Blood/Ermac, BrutalDoom, BrutalWolfenstein3D** weapon sets — scanned for
  a known compatibility risk (see below), not yet played/tested in headset.

## Known limitations

- A third-party weapon's own animation code can occasionally trip a
  (harmless) engine safety net if its raise/lower state chain is
  unusually long or malformed — the engine aborts that one animation and
  this mod's own recovery silently re-settles the switch, so it hasn't
  produced a visible stuck hand in testing, but it's a real, logged event on
  some weapon packs (confirmed on three VanillaVRPlus weapons; BrutalDoom's
  pack shares the same pattern pack-wide). Not something to fix here — it's
  third-party content, and the recovery is generic rather than pack-specific.
- Twin (`_2`-suffixed) weapon variants in some unreleased sets still have
  rough edges — actively being worked on.

## Related mods

- **RS_HardPoints** — forearm/wrist mounts (grenades, flashlight, utility
  gear) moved out to their own mod. Loads alongside this one; they share no
  runtime state and each ignores a grip landing in the other's anchors.
- **RS_Reload** — owns the chest ammo pouch anchor and its own documentation.

Still actively getting tuned — but the core is solid: reach, grip, it's
there.

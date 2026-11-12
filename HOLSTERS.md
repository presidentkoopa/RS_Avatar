# Body holsters

First build, 2026-11-12. Six gun holsters, an ammo pouch, a grenade spot.

**Status: written, not compiled, not run.** Nothing can be built or started where this was written.
The engine half (UZDXREMA `p_vrtorso`, `p_vrgear`) was written at the same time by another builder
and is also not compiled. Nobody has seen any of this in a headset.

This is not RSQ TacticalRig loaded as a pk3. It is new code inside RS_Avatar and the engine.
TacticalRig is the floor: the places, the numbers and the rules are its own, read from its source.
The list of what TacticalRig does is UZDXREMA `docs/plans/holsters/TACTICALRIG_FLOOR.md`; the item
numbers below (A1, J2 ...) are that file's. "rig.zs" is `rsq_ubqseries/TacticalRig/zscript/rsqtr/rig.zs`.

Do not load `RSQ_TacticalRig` beside this. Two holster systems would both answer the grip.

## Where the spots are

Metres from your eyes, standing, for a 1.62 m player. Scaled to your height.

| Spot | Forward | Left | Down | Size (radius) | Holds |
|---|---|---|---|---|---|
| Left hip, right hip | 0.00 | 0.18 either side | 0.70 | 0.14 | one gun each |
| Left chest, right chest | 0.10 | 0.12 either side | 0.46 | 0.11 | one gun each |
| Left shoulder, right shoulder | 0.08 behind | 0.18 either side | 0.10 | 0.14 | one gun each, on the back |
| Grenades | 0.12 | centre (belt buckle) | 0.62 | 0.08 | the hand grenade |
| Ammo pouch | 0.22 | 0.18 toward your off hand | 0.64 | 0.11 | ammo for hand reloads |

Seated, the hips, the grenade spot and the pouch move up and forward onto your lap (hips 0.27
forward, 0.12 out, 0.67 down). The engine decides when you are seated.

## What you do

One press does it: **grip, or Use**, with your hand inside the spot. No pull, no push.

- **Store.** Gun in hand, press at a holster: the gun goes in. The first time, that holster becomes
  that gun's own.
- **Draw.** Empty hand, press at a full holster: the gun comes to the hand that pressed.
- **Swap.** Gun in hand, press at its own holster with another gun sitting in it: yours goes in, that
  one comes out.
- **Go home.** A gun that has a holster, pressed at a different holster: it goes to its own. If the
  holster you pressed had a gun, that gun comes to your hand. If another gun was sitting in the
  first gun's home, it moves to the holster you pressed. No gun is lost.
- **Refused.** A press that cannot do anything: a gun at another gun's holster; a gun with no
  holster at a full one; an empty hand at an empty holster; a grenade at a gun holster. You get the
  double pulse, the "can't" sound and a red ring.
- **Free a holster.** Empty hand, press inside an empty holster that belongs to a gun, hold one
  second: the holster belongs to no gun again. White flash.
- **Each hand its own gun.** The off hand stores and draws for itself.
- **Two of the same gun (Brutal Doom 22 VR).** Off hand holding the second copy while the main hand
  holds the gun: put the off-hand one away and both go. At the gun's own holster or a free one,
  both hands go to fists. At another gun's full holster, the off hand goes to its fist and the main
  hand takes that other gun.
- **Grenades.** Press the buckle spot with either hand: the grenade comes to your main hand. Press
  again with the grenade in hand: the gun you had comes back. No grenades left: refused.
- **Ammo pouch.** Pressing there does nothing by itself. The BD22 VR pack's hand reloads ask "is the
  off hand in the pouch?" and take ammo only there. See "The pouch and reloads" below.
- A holster shows a gun only while you still own it. After a death or a pistol start it is empty
  until you have that gun again; then it is back where you kept it.

## What you see

Your own only. Other players' rings and stored guns are not drawn in this build.

- **Rings: faintly always, bright near a hand** (your call, 2026-11-12).
  A gun holster is a wire ball. An item spot (grenades, pouch) is a wire diamond.
  Blue for a gun holster, magenta for an item spot, green with a hand inside, and a size larger
  (x1.15) with a hand inside.
  Faint means 0.25. A hand makes a ring brighter only if a press by that hand would do something
  there: up to 0.35 as it comes near (from 2.5 radii in), 0.70 inside. Of the rings a hand could
  use, only the nearest gets the full brightness.
  A ring round a stored gun or the grenade is drawn fainter (x0.4) so it does not wash the model out.
- **Flashes**, about a second: red = refused, white = freed, green = this holster is now that gun's.
- **Stored guns.** Exactly what you put there, as the model you hold. 0.25 m long on the hips and
  chest, 0.70 m on the back. Hips: muzzle down. Chest: cross-draw. Shoulders: on the back, butt up
  over the shoulder, drawn a little behind and below the spot. Hidden while that gun is in a hand.
  Only guns with a row in `RAGFIT.txt` are drawn.
- **Ammo light.** A small ball in a full holster: green = half a magazine or more, yellow = low,
  red (smaller, pulsing) = nothing. At the grenade spot: green 2 or more, yellow 1, red none.
- **The pouch** on the belt, with a light on its flap for the main-hand gun's reserve ammo.
- **The grenade** hangs at the buckle while you have one and none is in a hand.

## What you feel and hear

Only on your own machine.

| When | Pulse | Sound |
|---|---|---|
| a hand enters a ring | one light pulse (0.18, 3 tics) | none |
| store | one pulse (0.55, 5 tics) | the holster clunk |
| draw | one pulse (0.65, 6 tics) | the draw sound |
| swap | the store pulse | both |
| refused | the only double pulse (0.30, 3 tics, twice) | Doom's "can't use" |
| freed | the store pulse | none |

## The pouch and reloads

The BD22 VR pack (2.0.4e) asks a service named `...RSQTR_RigService` for `pouch.at`
(`src/zscript/rsr/vreload.zs:98-108`). TacticalRig used to answer. RS_Avatar now answers it
(`zscript/gear/gear.zs:851`), from the engine's own record, for every player. With the pack's
"Ammo From the Rig's Pouch Only" on (its default), **a reload takes ammo only with the off hand in
the pouch**, as with TacticalRig. If the pouch turns out to be in the wrong place, turn that pack
option off, or delete that one class, and reloads go back to the pack's own rule.

## Files

| File | What |
|---|---|
| `VRGEAR.txt` | The table the engine reads: the eight spots, empty hands, off-hand copies, pulses, sounds |
| `zscript/gear/gear.zs` | `RAG_Rules`: what a press does. Every player, every machine. `RAG_RSQTR_RigService`: the pouch answer |
| `zscript/gear/look.zs` | `RAG_Look`: rings, guns, lights, pulses, sounds. `RAG_Fit`, `RAG_Shell`, `RAG_Diamond`, `RAG_Light`, `RAG_Pouch`, `RAG_Nade`, `RAG_Gun` |
| `MODELDEF.gear`, `TEXTURES.txt` | The markers, the light, the pouch, the grenade carrier |
| `RAGFIT.txt` | TacticalRig's size-and-facing table for stored guns (62 Brutal Doom rows) |
| `MAPINFO.txt` | Registers `RAG_Rules`, then `RAG_Look` |
| `SNDINFO.txt`, `sounds/RSHODRAW.ogg` | The draw sound (TacticalRig's `rtdraw.ogg`). The store sound was already here |
| `models/rag_wirediamond.obj`, `rag_wire_util.png`, `rag_pouch.md3`, `rag_pouch.png` | Copied from TacticalRig: the diamond, magenta, the pouch |

The engine half: UZDXREMA `src/playsim/p_vrtorso.cpp`, `p_vrgear.cpp`. The contract between the two:
UZDXREMA `docs/plans/holsters/GEAR_CONTRACT.md`.

## TacticalRig floor item -> where it is in this code

`G` = `zscript/gear/gear.zs`, `L` = `zscript/gear/look.zs`, `V` = `VRGEAR.txt`. Items the engine does
(hover, dwell, press, seated, torso) are in UZDXREMA `docs/plans/holsters/BUILD_SIM.md`, not here.

| Floor item | Where |
|---|---|
| A1, A2 hips; A7, A8 chest; A5, A6 shoulders (data) | V:25-30 |
| A4 grenade spot, A14 pouch, A16 seated places, A22 pouch reach (data) | V:31-33 |
| B1 Brutal Doom "Dual..." filed as the single gun | G:61 `HeldAs`, G:90 `SingleOf`, G:225 `FiledGun` |
| B4 the empty hand | G:138 `EmptyMain`; list V:39 |
| B5 things with their own home never enter a gun holster | G:260 `MayEnter`, G:200 `MainKind`, G:772-777 (refusal); list V:61 |
| B6 `MayEnter` | G:260 |
| B7 assignment: one holster per gun | G:250 `LockedTo`, G:279 `Assign` |
| B11 pouch live with the reload pack; `pouch.at` | G:450 `PouchLive`, G:464 `SpotLiveNow`, G:851 `RAG_RSQTR_RigService` |
| C3 actions applied on every machine; dead players ignored | G:810 `WorldTick`, G:825 |
| C4 last draw per hand, for Quick Draw | `VRGear.SetDraw` at G:572, 590, 612, 653, 705, 741 |
| C5 "busy" = inside a spot (the answer for other mods) | G:851 (`rig.busy`) |
| D1 pulses | L:117 `Feel`, L:134 `PlayPulses`, L:192-228; numbers V:64-67 |
| D2 sounds, local | L:151 `Play`; V:74-76; `SNDINFO.txt:40` |
| D3 a press that would be refused is tested first | G:270 `WouldRefuse`; G:564 and G:629 refuse before anything is stored |
| D4 refused: red ring | G:510 `PostRefuse`, L:224-228, L:361-369 |
| D5 assign / free flashes (flash only, no picture) | L:217-223, L:97 `RuleFade`, L:106 `ShowRule` |
| E4 a gun with a home goes home; the gun in its home moves over | G:300 `LockedHome`, G:565-577, G:662-672 |
| F1 grenade to the main hand; press again, the gun comes back | G:716 `NadePress` |
| F2 which grenade (first class that exists) | G:381 `NadeRow`; rows V:32 |
| F3 none with zero grenades; counts as a draw | G:731-742 |
| H1 a holster holds what was put there, while owned | G:50 `Held` |
| H3 a real gun in the main hand | G:200 `MainKind` |
| H4 a gun in the off hand (BD22 copies count) | G:187 `IsMovedGun`, G:208 `OffKind`; copies V:45-56 |
| H5 the off hand goes empty | G:339 `EmptyOff`, G:170 `OffEmptyName` |
| H6 the off hand's gun onto a holster; BD22 dual-wield pair A / B / unassigned | G:621 `HolsterOff`; pair G:630-661 |
| H7 a holster's gun into the off hand | G:696 `DrawOff` |
| J1 holster, main hand (a Dual as one, c refuse, d go home, f store / swap) | G:536 `HolsterMain`: a G:542-560, c G:562-564, d G:565-577, f G:578-598 |
| J2 draw, main hand; one gun, in the hand that drew it | G:603 `DrawMain` |
| J3 the off-hand raise waits for the main hand, and for the two-hand hold | G:331 `QueueOff`, G:352 `TickPairs` |
| K10 free a holster by hand (the rule; the 1 s timing is the engine's) | G:792 `DoFree`; L:220-223 |
| L2 grenade spot press | G:755-756, G:716 |
| L5 pouch press does nothing | G:757-758 |
| L9 refuse before any store | G:562-564, G:629; the refusal events G:510-529 |
| L10 off hand at a gun holster | G:752 `DoPress`, G:761-786 |
| L11 main hand at a gun holster | G:752 `DoPress`, G:761-786 |
| M1 sphere for guns, diamond for items | L:351-356; `MODELDEF.gear:15,39` |
| M2 colours (blue, magenta, green; red and white flashes) | L:359-368; `MODELDEF.gear:15-37` |
| M3 size: x1.15 with a hand inside, x1.25 fading in a flash | L:359-365 |
| M4-M6 when a ring shows: **your rule**, with M5's and M6's numbers for brightness | L:337-341, L:89 `HandAlpha`, L:252 `ClutterHand`, L:271 `RingPart`; G:482 `HandActs` |
| M7 dim ring round a stored item | L:342-346 |
| M9 ammo light, and the grenade count light | L:398-417; G:424 `AmmoState` |
| M12 stored gun: only measured guns, 0.25 m / 0.70 m, hidden while in a hand | L:431-457; lengths V:29-30 |
| M13 how a stored gun hangs | L:445-448; angles V:25-30 |
| M14 where a shoulder gun is shown | L:449-452; V:29-30 |
| M15 placed by its measured middle, length, yaw, pitch; squat things stay small | L:794 `RAG_Gun.Show`, L:466 `RAG_Fit` |
| M18 pouch model and reserve light | L:373-396; G:438 `ReserveState`; `MODELDEF.gear:82` |
| M19 grenade at the buckle | L:419-429, L:664 `RAG_Nade`; `MODELDEF.gear:98` |
| N2 back where you kept it once you own the gun again | G:50 `Held` |
| K1, O17 nothing shown when dead or with no headset | L:306-307 |
| The live / holds bits for the engine, every tic | G:833-839, G:464, G:472 |

## Not in this build

From the contract's own list. Each needs data and rules, not an engine change.

- Other spots: keyring (A9), sabers (A10, A11), whip (A12), flare (A13), flashlight clip (A15),
  cigarette pocket (P7), ShieldSaw's shoulder (P1, E3). Their press rules: B2, B3, B8-B10, L1,
  L3, L4, L6-L8, L12.
- F4 the grenade spot's colour by RSQ Grenade's kind. F2's switch to RSQ Grenade by its two cvars.
- Move holsters by hand, profiles (A21, A23, K13), the mirror (Q26).
- The Wheel's assign / clear events (E1, E2).
- Throwing guns (G, K12, C6). Moving a gun at the watch (I). The Dual key helper (P8).
- The gun's picture above the ring (D5, D6), the streak of light home (D7).
- Tips, the struggle hint, the ghost hand (K16-K18, P3, M8).
- Ammo arc (M10), ammo count digits (M11), saber / whip / flare models (M16, M17), FnF markers (M20).
- Other players' stored guns on their bodies.
- Stored plain-Doom guns (TacticalRig carries 8 meshes for them; RS_Avatar does not).
- Every menu row and slider. There are none.

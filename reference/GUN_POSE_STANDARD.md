# What a gun mesh needs so an avatar hand can hold it

The standard a new mesh must meet before it comes off the psprite layer into the world. Written
2026-10-26 from the Vanilla VR set (36 guns and the grenade), which covers every grip type we have,
and checked on RS Modern, the IQM set.
Most of it is the rules the 2026-10-10 card pass already used (`E:\DOOMWork\tools\avatar_grip\README.md`),
written down as a contract; what this pass added is marked **new**.

## 1. The mesh

- **Axes:** +X to the muzzle, +Y left, +Z up, in the file. Every Vanilla mesh is built this way.
  Everything below is stated in these axes, in mesh units, and **both hands use the same numbers**.
- **Scale:** whatever MODELDEF says, mirror included. A negative scale is undone on the way to the
  screen; it never enters the grip maths (the review tool works in the file's own space for this reason).
- **Hidden surfaces** (a viewmodel's hands, a parked spare magazine) are listed so the fit ignores them.

## 2. The card's grip block: the main hand

| field | what it is | how it is found (avatar_grip rules) |
|---|---|---|
| `palm` | the point on the handle's centre line where the body's grip socket goes | centre line fitted to the cross-sections the three lower fingers close on (2.5–9 cm below the trigger). Height: the **guard rule** (middle finger hard under the guard: socket 0.52 palm widths below the step) and the **trigger rule** (index pad on `triggerat`: socket 5.0 cm below the trigger along the line); within 2 cm take the mean, else the trigger rule; trigger more than 6 cm in front of the grip, the guard rule alone. Depth is always re-centred from the mesh. |
| `rake` | the handle's lean back from +Z, degrees (parser range -10..80) | the fitted centre line |
| `triggerat` | the trigger face | from the mesh |
| `barrel` | the bore direction, when not +X | from the mesh |
| `class` | the grip class (else from the type, card.zs `DefaultGripClass`) | by type |

**The hand's frame on the handle** (vr_rig.cpp `VRRig_GripFrame`, rake squared): knuckle line (index→little
finger) down the handle, palm against the gun's side, fingers along the bore. The engine reads exactly
this; nothing per body is stored on the card.

## 3. The pose the hand takes, by grip class (FBX only)

| class | types | pose (vrhandpose.txt) | from the FBX |
|---|---|---|---|
| pistol | pistol, revolver | `grip_pistol` / `_fire` | three fingers and thumb `fbx_wrap_tight`, index on the trigger `fbx_wrap_half`; fire closes the index to `wrap_tight` |
| shotgun | pump, shotgun | `grip_shotgun` / `_fire` | as pistol |
| ssg | breakaction | `grip_ssg` / `_fire` | as pistol |
| rifle | rifle, smg, chaingun | `grip_rifle` / `_fire` | as pistol |
| rocket, plasma, bfg | launcher; plasma, railgun, flamethrower; bfg | `grip_<class>` / `_fire` | `fbx_wrap_half` (a thick handle) |
| saw | chainsaw | `grip_saw` | the fist round a bar |
| melee | melee, grenade | `gun_grip` (no class pose yet) | |

**new — the handle's thickness decides the class.** `wrap_tight` closes on a pistol-sized handle and
`wrap_half` on a thick one; a gun whose handle is thicker or thinner than its type's usual belongs in the
other class (`class = ...` on the card). The review tool shows it: fingers sunk into the grip or standing off it.

## 4. The off hand

| field | rule |
|---|---|
| `supportat` | the click's position along the gun is kept; the point moves to the middle of the part the off hand closes on. A part deeper than 5.5 cm cannot be wrapped and is cupped (one hole radius, 0.77 mu, above the underside). Pistols: the two-hand hold. Vertical foregrips and held magazines: the palm rule. |
| `supportpart` | the moving part it rides (a pump), if any |
| **new** `supportaxis` | the line the support hand closes round (index→little finger). Today the brace (RS_VR_Reload `AnchorBrace`) places the support hand with the MAIN grip's frame -- bore and straight down -- so a hand on a forend is oriented like a hand on a pistol grip. The part code (`AnchorHeldParts`) already has the right shape for a forend: knuckles across the part, the line along the bore. |
| pose | the engine picks `hold_support_<class>` / `hold_support` (FBX: two-hand hold for pistols, `wrap_half` round a forend or under a tube, the fist on a handlebar) |

## 5. Moving parts (reload hands)

Each part a hand works states `subject` (slide, forend, foregrip, magazine, shell, round), `grab`,
`handseat` (the middle of the part's own cross-section at its grab) and, when the part is not held the
usual way for its subject, `handaxis`. The engine takes `hold_<subject>[_<class>]` from the FBX table.

## 6. Checking a mesh

    python tools/avatar/gun_fit_preview.py <guns.json> <mesh root> wadsrc/static/vrhandpose.txt \
        <body .mdl> <out.png> <Gun,Gun,...> [bodyscale]

`guns.json` is avatar_grip's `table.py` output (the live cards and MODELDEFs). The picture is the body's
own hand mesh, in the class's FBX pose, placed by the engine's rule on the card's `palm` and `rake`, from
the side, from above and along the bore. `ROLL=<deg>` (or `ROLL_<Gun>=`) turns the hand about the handle,
for trying a roll before proposing one.

**A mesh passes when**: the fist closes round the handle with the index at the trigger, nothing sinks
through the grip, the hand is not on top of the gun, and the left hand mirrors the right.

## 7. Vanilla VR, 2026-10-26, c_doom_marine

| | guns |
|---|---|
| sits right | M4A3, Pistolet (+Blue), Moonlight, Sunset, ColaRevolver, Tec9, SMG, PumpM37, BullpupPump, Rifle, M16, PlasmaRifle (+Blue), PlasmaCarbine, Railgun, Bolter, MachineGun, BFG, BFGHeavy, BFGRifle, Unmaker, Flamer, grenade |
| hand off the grip | RocketLauncher, RPG: the hand is in front of the rear grip -- `palm` wrong |
| straight stocks, hand on top of the wrist | PumpDoom (rake 62), AssaultShotgun (73), SSG (44), DoubleBarrel (59): a stock grip rolls the hand under the wrist and probably closes on a shallower line than the card's rake. A ±60° roll alone does not fix it. **Open: the owner's call on how a stock wrist is held** -- that decides whether the standard gains a `roll` field or the rakes change |
| to look at | RotaryGun, RotaryLauncher, Chaingun (handle on the body), Flamethrower2 (rake 75, nozzle grip), the three chainsaws (rear handle runs fore and aft; rake capped at 80) |

## 8. RS Modern (IQM), 2026-10-26, c_doom_marine

The only IQM set, real-world guns. The gun is skinned at the card's drawn frame and the viewmodel's own
hands (material `v_hands*`) are dropped.

| | guns |
|---|---|
| sits right | Glock, Kimber (left hand), MP5, Benelli, MK18, HK416, MCX, G36C |
| not checked | GlockS: its mesh (`glocksil.iqm`) is in RS_VR_Weapons only |

**Real-world check.** The 1911's grip angle is 18 degrees and the Glock's 22 (American Rifleman,
"All In The Grip"; KSG Armory): the cards say Kimber 17.6 and Glock 23.7. The AR family's cards run
26.8 (MCX) to 35.4 (HK416); the HK416 is the one to look at.

## 9. The reload hand on its part, 2026-10-26

`tools/avatar/part_fit_preview.py`: the working hand placed on every slide, charging handle, bolt,
pump, foregrip and break-open barrel by RS_VR_Reload's own rule (AnchorHeldParts), in the FBX
`hold_<subject>` pose. All 21 parts with a card in the two sets have a `handseat` except the
G36C's charging handle, which falls back to its grab.

| | parts |
|---|---|
| right | pistol slides (M4A3, Pistolet, Glock, Kimber: over the top, fingers down the far side); pumps (M37, Doom shotgun: under, palm up); the bullpup's upright pump (held like a pistol grip, its `handaxis`); revolver barrel and crane, SSG and DoubleBarrel barrels, the machine gun's launcher tube (under and round) |
| **a real gun is worked differently** | the AR-family charging handles (MK18, HK416, MCX, the Rifle, the SMG): pulled straight back by the rear T with two fingers, not grabbed over the top. The MP5's cocking handle is on the left of the front tube and the Benelli's bolt handle on the right of the receiver: both pinched from the side. Tec9's bolt the same. All are `subject = slide` today, so they get the slide's overhand grab |

**The standard gains:** a part's subject says how a hand works it, not only what it is called:
`slide` (overhand), and **new** `charginghandle` (rear-T pull) and `bolthandle` (side pinch), each with
its `handaxis` and its pose. The FBX has no pinch, so those two poses are the gap (worklist F12).

Sheets: RS_Avatar `reference/gun_fit/` (`parts_vanilla_1/2.png`, `parts_modern.png`).

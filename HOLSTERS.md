# Body holsters

Reach down. Grip your hip. There's a gun there.

Guns are stored on the body you see: a holster on each hip and one under each collarbone. The
holsters hang on your torso, so they come with you when you crouch, lean or turn.

This is the body-holster system of 2026-11-09 (Phase 1). It replaced RS_Holsters, whose files are
kept in `reference/retired_holsters/` and are neither packed nor loaded. The old demo gif is
`reference/holsters/holster_demo.gif`.

**Status:** Phase 1 boots clean at the desk (builds 1109k and 1109l). The owner's headset results
are still owed. Shoulders, the ammo pouch and the grenade loop are later phases.

## Who does what

The engine decides, the mod reacts. It needs the UZDXREMA engine.

| Part | Where | What it does |
|---|---|---|
| Engine core | UZDXREMA `src/playsim/p_vrgear.cpp` | Every tic, for every player, the same on every machine: where each mount is, which mount a hand is at or heading for, what a grip press means, when a draw clears. |
| The rig | `VRGEAR.txt` | The mounts, the kinds of item, the guns, and the haptic patterns. |
| Rules | `zscript/gear/gear.zs`, `RAG_Rules` | What an action does to the inventory. Runs on every machine, in order. |
| Feel | `gear.zs`, `RAG_Feel` | Haptic signatures and the hum, for this machine's own player only. |
| Look | `gear.zs`, `RAG_Look`, `RAG_Shell`, `RAG_Gun`; `MODELDEF.gear` | The holster shells on the body and the guns in them. Client-side actors only. |

The mounts sit on the sim's torso frame (UZDXREMA `p_vrtorso.h`), which is built from the tic
command alone. Nothing is read back from the drawn body, so netplay stays in step.

## What you do

- **Seat:** grip with a gun in a mount, and it goes in. Pushed into a hip or chest mount with your
  finger off the trigger, a gun seats itself with no button.
- **Draw:** grip a full mount with an empty hand and pull. The gun clears once your hand has
  travelled its clear distance out of the mouth. A fast clear is a quick-draw.
- **Swap:** seat a gun in a full mount and the gun that was there comes to your hand.
- A grip that no mount claims does nothing.
- The torso holds still while a hand is heading for gear, so the holster is where your hand
  expects it.

## What you feel

- A hum in the controller from the one mount your hand is heading for, stronger as you close in.
- Each mount has its own rhythm on arrival, and each gun its own print, so you can tell them apart
  without looking.
- A thunk on seating, a drag while the gun slides out, a snap when it clears, a doubled crack for
  a quick-draw, a double buzz when a press is refused.

## The rig file (`VRGEAR.txt`)

Any loaded mod may add its own `VRGEAR` lump. A later definition of the same name replaces an
earlier one, and `remove <mount>` takes one away.

- `mount <name> { pelvis|chest at <side> <fwd> <up> radius <r> mouth <x> <y> <z> pushin on signature <pattern> }`
  Positions and reaches are fractions of your standing eye height, so they carry between bodies
  and players of different sizes. The mouth is the way a draw leaves.
- `kind <name> { clear <distance> }`: how far an item travels before it is clear.
- `item <WeaponClass> { kind <kind> print <pattern> }`: one line per gun.
- `haptic <name> { pulse <intensity 0-1> <ms> <hz> [gap <ms>] ... }`
- `emptyhand <WeaponClass>`: what a hand holds when it holds nothing.

The default rig has `HipR`, `HipL`, `ChestR` and `ChestL`, and lists Doom's eight weapons.

## Design

UZDXREMA `docs/plans/BODY_HOLSTERS_DESIGN.md` is the design and the phase plan. This file
describes only what Phase 1 ships.

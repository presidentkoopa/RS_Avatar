# Distance grab

Point a palm at something across the room, flick your wrist, and it flies to your hand.

These are RSQ DistanceGrab's gestures. No button is needed for any of them. The hand must be
empty. Every player can do it, and it plays the same on every machine.

**Status (2026-11-12):** first slice. Written to the contract in UZDXREMA
`docs/plans/VRGRAB_API.md`. Not compiled and not played yet. It needs the UZDXREMA engine with
the `VRGrab` core.

## How to play

1. **Aim.** Raise a hand and turn the palm out, a quarter turn of the wrist. The thing that hand
   points at gets an amber ring, and a thin amber beam shows where the hand points. Reach is about
   15 metres.
2. **Lock.** Keep the palm on it for a moment. The ring turns green and you feel a tick. The lock
   stays if you look away.
3. **Pull.** Tip the wrist up sharply as you turn the palm back. It flies to that hand in an arc.
   Turn the palm back without the flick and the lock is let go.
4. **Catch.** Have the palm out when it arrives. A pickup is used at once, as if you had walked
   over it. Anything else, or a pickup you have no room for, stays in your hand. If your hand is
   turned away when it arrives, it drops at your feet.
5. **Carry.** A held thing follows your palm and stops at walls. Leave it behind a wall for half a
   second and the hand lets go.
6. **Throw.** Swing, and turn the palm back in mid-swing. Heavy things leave the hand slower.
7. **Set down.** Turn the palm back with the hand still.
8. **Hold on.** Squeeze the grip while carrying and the grip holds it, whatever the palm does.
   Open the grip to throw or set down.

A thrown thing hurts what it hits, more with weight and speed. An explosive barrel thrown hard
goes off where it lands, and what it kills counts as yours.

A hand that is at a holster, or reaching for one, does not grab.

## Who does what

| Part | Where | What it does |
|---|---|---|
| Engine core | UZDXREMA `src/playsim/p_vrgrab.cpp` | Every tic, for every player, the same on every machine: what each hand points at, the lock, the flick, the catch, the release and its speed. It never moves anything. |
| Numbers | `VRGRAB.txt`, `MASSDEF.txt` | Reach, cone, timings, flight speed, what may be taken, and what things weigh. |
| Rules | `zscript/grab/rules.zs`, `RAB_Rules` | Moves the world: the flight, the catch, the carry, the throw, the damage. Runs on every machine, players in order. |
| Feel | `zscript/grab/feel.zs`, `RAB_Feel` | A pulse and a sound for lock, pull, catch and throw. Your own hands only. |
| Look | `zscript/grab/look.zs`, `RAB_Look`, `RAB_Mark`; `MODELDEF.grab` | The amber and green rings and the beam. Your own hands only. |

## Not in this slice

Fingers closing on the held thing, passing hand to hand, two hands on a heavy thing, grabbing up
close with the grip, weapons caught straight into the hand, hitting with a held thing, doors and
switches, and markers for other players' grabs.

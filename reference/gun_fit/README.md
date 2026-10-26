# gun_fit — the avatar's hand on every Vanilla VR gun

c_doom_marine's own hand mesh, in its grip class's FBX pose, placed on each gun by the engine's rule
(VRRig_GripFrame with the rake squared, the body's `gripsocket` on the card's `palm`), in the gun's own
file space. Three views each: side, top, along the bore. Made by `tools/avatar/gun_fit_preview.py`
from the cards as `tools/avatar_grip/out/guns.json` read them on 2026-10-10.

| sheet | guns |
|---|---|
| `vanilla_fit_1.png` | M4A3, Pistolet, PistoletBlue, Moonlight, Sunset, ColaRevolver, Tec9, SMG, RocketLauncher, RPG |
| `vanilla_fit_2.png` | PumpM37, PumpDoom, BullpupPump, AssaultShotgun, SSG, DoubleBarrel, Rifle, M16 |
| `vanilla_fit_3.png` | PlasmaRifle, PlasmaRifleBlue, PlasmaCarbine, Railgun, Bolter, Chaingun, MachineGun, RotaryGun, RotaryLauncher |
| `vanilla_fit_4.png` | BFG, BFGHeavy, BFGRifle, Unmaker, Chainsaw, ChainsawHeavy, LongbarChainsaw, Flamer, Flamethrower, grenade |
| `roll_p60.png`, `roll_m60.png` | SSG and PumpDoom with the hand turned 60 degrees either way about the handle: neither fixes a straight stock |

What each shows, and what is still open: `../GUN_POSE_STANDARD.md`, section 7.

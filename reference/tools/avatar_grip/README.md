# avatar_grip: putting the REMA avatar's hands on the guns

These tools find, for each gun, the card values that put the worn body's hand on the grip:

- `palm` is where the body's grip socket goes on the handle.
- `rake` is the handle's tilt, in degrees.
- `supportat` is where the off hand closes on the gun.

All three are in mesh units with card axes, and both hands use the same numbers. The tools read the cards and meshes, write pictures for review, and write corrected **copies** of the cards plus a diff. They never touch the real cards. Installing the copies is a separate, deliberate step (see 6).

First run: 2026-10-10, 72 guns: Vanilla VR 37, BD22 25, RS Modern 10.
- Record of that run: `E:\DOOMWork\_backups\avatar_grip_2026-10-10\` (the cards before, and the diff).
- Build and test steps: `E:\DOOMWork\_reports\avatar_grip_2026-10-10\HANDOFF_build_and_test.md`.

## Needs

- Python 3 with `numpy`, `scipy` and `Pillow`.
- `E:\DOOMWork` laid out as it is now. If it lives elsewhere, set `DOOMWORK`.
  - `RS_VR_Weapons` holds the cards, MODELDEFs and meshes.
  - `_reports\gun_seating_2026-10-02\WEAPON_SETS.csv` lists the hidden surfaces.
  - `_old\doom-force-unleashed_devbuild\models` holds Ermac's posed hands. They are only drawn on the review pictures and used for the pistol two-hand offset. They never ship.
- Outputs go to `out\` next to the scripts. Set `AVGRIP_OUT` to send them elsewhere.

## The process

1. `python table.py` reads every live card (grip block, hand, type, prop, mesh) and its MODELDEF (drawn frame, Scale) into `out\guns.json`. Run it whenever a card or MODELDEF changes.
2. `python eref.py` measures Ermac's reference grips into `data\eref.json`. That file is already there; rerun only if his models change.
3. `python solve.py [Gun ...]` fits every gun, or just the ones named, into `out\result.json`. Start from the card's own points and check `solve.py`'s CFG table for that gun.
4. `python sheet.py [Gun ...]` draws a review sheet per gun into `out\sheets\`:
   - views: side and top
   - red: the card today; green: the new value
   - blue line: the handle axis
   - Ermac's hands drawn at the new points, sized to the body
5. Review.
   - `python page.py` builds `out\page\index.html`: the whole set with a table, notes and every sheet.
   - `python zoom.py Gun ...` writes `out\zoom.png`, close-ups of the grip with the guard rule, the trigger rule and the card's trigger point marked.
   - Fix a wrong gun by adding a line for it to CFG in `solve.py`, then rerun 3 and 4 for that gun.
6. `python emit.py [Gun ...]` writes the corrected copies to `out\cards_out\` and the diff to `out\grip_cards.diff`, for every gun in `result.json` or just the ones named.
   - It changes only `palm`, `rake` and `supportat` in each grip block, plus one comment line.
   - It keeps each file's own line endings and never writes a `rake` outside the parser's -10..80.
   - To install: back up the real cards, copy the files from `cards_out\` over them, then rebuild the packs as the handoff says.

**Re-running on cards that already hold fitted values** starts from those values. The median palm moves 0.07 mm and the worst 1.1 cm (WM_SSG), so name only the guns you meant to refit when you run `emit.py`.

## The rules

The reference body is c_doom_marine, the one that works. Its numbers are in `RS_AVATAR.md` (`_reports\gun_seating_2026-10-02`). Sizes are 34 map units to the metre, and pw is the palm width, 2.03 map units.

- **Palm.** It sits on the handle's centre line. The centre line is fitted to square cross-sections of the stretch the three lower fingers close on, 2.5 to 9 cm below the trigger, and re-cut until it stops turning. Two rules set the height along it:
  - **Guard rule.** The middle finger sits hard up under the guard, so the socket is 0.52 pw (1.06 mu, 3.1 cm) below the step where the guard or receiver widens the section.
  - **Trigger rule.** The index pad is on the card's `triggerat`, so the socket is 1.70 mu (5.0 cm) below the trigger's height along the line. This comes from the body's measured index tip, 1.78 mu up the grip axis.
  - How they combine:
    - Within 2 cm of each other: take the mean.
    - Further apart: take the trigger rule.
    - Trigger more than 6 cm in front of the grip (the finger reaches but the hand doesn't climb): take the guard rule alone.
  - Ermac's hands, scaled, give the same depth to within a millimetre or two.
- **Depth.** The owner's clicks came from flat side pictures, so their depth (L) is not trusted. L is always re-centred from the mesh around the clicked F and U.
- **Supportat.** The click's position along the gun is kept, and the point moves to the middle of the part the off hand closes on.
  - A part deeper than 5.5 cm can't be wrapped, so it is cupped: the point goes one hole radius (0.77 mu) above the underside.
  - Pistols use Ermac's two-hand hold, sized to the body.
  - Vertical foregrips and held magazines are fitted with the palm rule.
- **Shared meshes.** Guns drawn from the same geometry get the same palm and rake. The first main-hand card wins.

## Per-gun choices (CFG in solve.py)

| key | meaning |
|---|---|
| `hand='grip'` / `'stock'` | Start from a pistol-grip (15°) or straight-stock (55°) guess. The default `'auto'` tries both. |
| `hand='handle'`, `axis=` | A bar with no guard step (melee, chainsaw handles, fuel-nozzle grips): keep the clicked height and centre it on the bar. |
| `hand='ball'` | A grenade: the middle of the body. |
| `hand='tube'` | The hand goes inside the gun (BD_FlameCannon): centre it in the bore and write no rake. |
| `start=(x,y,z)` | Where to start looking, in mesh units, when the card's point is off the gun. |
| `level='trigger'` | Use the trigger rule only, for when the "guard" is really a frame down to the butt (WM_Flamer). |
| `no_trigger=True` | The card's `triggerat` is a placeholder (WM_BreachMP5). |
| `rake=` | A reviewed pin, for a gun with two readings close in quality. |
| `sup='wrap'` / `'cup'` / `'vgrip'` / `'handle'` / `'same'` / `'none'` | How the off hand holds it. |
| `sup_start`, `sup_axis` | Where to start looking for the off hand's part, and which way it runs. |

## Known limits

- **Chainsaw rear handles** run fore and aft (87°). The card takes at most 80, so 80 is written.
- **Saved values override the cards.** `wm_fit_palm` and `wm_fit_brace` save `vr_gundata_palm_<Prop>` and `vr_gundata_sup_<Prop>` to the ini, and those beat the card.
- **Saved tilts** from `wm_fit` turn the gun about the palm, so moving the palm swings an old tilt.
- **Pixel stretch.** The heights assume the hand is not stretched vertically. RS_AVATAR.md 3 notes the engine may draw the hand 1.2× taller than the gun along world up. If hands look high on every gun, that is the first place to look.

## Files

- **Process:** `config.py` (paths), `table.py`, `eref.py`, `solve.py`, `sheet.py`, `page.py` + `page_tpl.html`, `zoom.py`, `emit.py`.
- **Library:**
  - `mesh.py`: md3 and iqm at the drawn frame. It drops viewmodel hands and parts parked away from the gun (the Breach spare magazine).
  - `fit.py`: sections, handle line, junction and both rules.
  - `hole.py`: the hole a posed hand mesh makes.
  - `render.py`: the pictures.
  - `gunview.py`, `hudrender.py`, `ermac.py`: md3/iqm readers and Ermac's sets, shared with the Quest tools in `RS_QuestHands\tools\posefix`.

## Reload hands: the hand on the slide, the charging handle, the pump

Added 2026-10-11. While a hand works a part of a gun, the avatar's hand is placed ON that part
and rides it. The part is a slide, a charging handle, a bolt, a pump, break-open barrels or a
launcher tube. Its fingers take that thing's shape for the gun's type. Three pieces do it:

1. **Finger shapes.** The engine reads `hold_<subject>` and `hold_<subject>_<class>` from its
   finger table. `UZDXREMA/tools/avatar/mkgrippose.py --holds` bakes them out of Ermac's own
   reload frames in `hand_left_poses.iqm`; its HOLDS table says which frame for which gun type.
   The output is appended to `UZDXREMA/tools/avatar/handcurl.txt`, and that file is copied to
   `wadsrc/static/vrhandcurl.txt`.
2. **Where the palm goes on the part.** Each working part's `handseat` comes from these tools.
   It is the middle of the part's own cross-section at its `grab` point. For a slide-type part
   it stays within 2.3 cm of the grab, because a bolt body hidden in the receiver is not where
   the fingers go. A part held upright or across the gun also gets a `handaxis`.
3. **The hand placed there.** RS_VR_Reload's `WM_System.AnchorHeldParts` does it, through the
   engine's hand anchor. `vr_part_anchor_hand` gates it and is on by default.

Steps, after `python table.py`:

1. `python seat.py` fits every action, pump and foregrip part into `out\seats.json` and prints
   one line each.
2. `python seatsheet.py <name>.png Gun ...` draws c_doom_marine's left hand on those parts into
   `out\<name>.png`: side, top and front views.
   - grey: the gun
   - orange: the part
   - red circle: the grab
   - green circle: the seat
   - fingers: thumb red, index blue, middle green, ring orange, pinky purple
   - It uses the engine's own placement maths (`VRRig_GripFrame` plus the body's `gripsocket`)
     and the hold pose for that gun's type, so a hand drawn wrong here is drawn wrong in the
     game.
3. `python seatemit.py [Gun ...]` writes copies of the cards to `out\seat_cards_out\`. It sets
   `handseat` and, where fitted, `handaxis` on those parts, and keeps line endings. Install the
   copies the same way as the grip cards.

Rerunning on cards that already have the seats changes nothing: the 2026-10-11 cards come back
byte for byte. A gun whose part has no vertices of its own gets no seat; its hand uses the
grab. That is WM_BreachG36C, whose rig moves no mesh with `j_charginghandle`.

Files: `parts.py` (card parts), `seat.py`, `seatsheet.py`, `seatemit.py`, `avhand.py` (the
body's hand posed by a curl pose, the way the engine folds it).

# Holsters and Hardpoints

![Holsters in action](media/holster_demo.gif)

Reach down. Grab your hip. There's a gun there.



toggle 2, 4, 6, 8 holsters arranged in world arround your playerspace.


placement mode - arrange holsters to your liking


save standing and seated profiles


toggle between saved profiles


needs UZDXREMA engine


grip to holster, removing weapon from RS WeaponWheel (if used together)


think of holster like visible 'favorites'


holster with offhand, grab with mainhand, "it just works"


still working bugs out with my weaponsets with _2 twins of guns (not released)



### The arm rig moved out

The forearm and wrist hardpoints that used to ship here (disabled by default)
are now their own mod, **RS_HardPoints** — six mount points on your own off
arm, for grenades, a flashlight, utility gear. Load both at once; they share
nothing at runtime and each ignores a grip that lands in the other's anchors.

That's also where the planned gesture work lives now: palm rolled up
"dr strange" style to arm the wrist mounts, then three controls firing three
different attacks in place, plus a scrollable rolodex of quickslots.



### Requires

- Any weapon-content pack providing standard `Weapon` classes -- borrows whatever is loaded, never references RS_Main or any other specific pack by name
- The UZDXREMA engine build (for the native holster fields this mod is built on)

**No default binds.** Bind the store/draw keys yourself under Customize
Controls — F13 and F14 are what the engine sends for grip.

Still actively getting tuned — but the core is solid: reach, grip, it's there.

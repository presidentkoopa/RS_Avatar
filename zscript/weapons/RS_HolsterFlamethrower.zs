// A holster-testable flamethrower -- an ordinary Weapon, so it drops
// straight into RS_Holsters' existing store/draw pipeline with ZERO changes
// to that system, same reasoning as RS_HolsterFlashlight in this same
// folder. Second proof point that any plain Weapon fits: this one is a
// full-auto spray weapon rather than a utility item, and needs nothing
// beyond the normal Weapon shape either.
//
// ALL THREE asset kinds asked for are here now, not just the gun model:
// - Model + skin + the 4 HBFT weapon-in-hand frames, from RS_Main's
//   RS_GH_Flamethrower (zscript/weapons/rs_gh_weapon/RS_GH_Flamethrower.zs,
//   MODELDEF ~line 6545).
// - The 19-frame RSI0 flame-plume sprite sequence (sprites/combatfx/fire/),
//   which is what the source weapon's ACTUAL projectile
//   (RS_GH_FlameJet, zscript/weapons/rs_gh_weapon/RS_GH_HeavyProjectiles.zs)
//   renders as -- missed on the first pass of this file, which only looked
//   at the weapon class's own States and treated "HBFT" as the whole sprite
//   set. It wasn't: the gun-in-hand frames are a small part of a
//   flamethrower's sprite footprint next to the flame itself.
// - Both sounds (below).
//
// This class does not reference RS_Main or RS_Weapon, so it works with or
// without RS_Main loaded, same "any weapon pack" independence as the rest
// of this mod.
//
// NOT taken, deliberately: RS_Main's own firing MACHINERY, as opposed to
// its assets. The source class extends RS_Weapon and fires through
// RS_AttackProfile/RS_Catalog/RS_BallisticFired (RS_GH_FlameJet's actual
// base class), plus RS_Weapon's whole tier/rolled-stat/GunBonsai system --
// none of that is asset, and porting it would mean either depending on
// RS_Main after all or reimplementing a system this mod has no use for.
// RS_HolsterFlameJet below (a plain Actor, not RS_BallisticFired) is a
// short-range stand-in fired via stock A_CustomMissile, carrying the real
// RSI0 animation but none of the source's damage-profile/pellet-count
// machinery.
//
// SOUNDS: fire and release, both copied from RS_Main's actual source
// folder (sounds/rs_gh_weapon/gh_flamethrower/) -- FLAMER (the fire loop,
// exactly what RS_Main's own RS_GH_Flamethrower plays via
// RS_Catalog.SND_GH_Flamethrower()) and FLAMSTOP (present in that same
// folder, but never actually mapped to a logical sound name or referenced
// anywhere in RS_Main -- wired up here as the release-tail sound, which
// this class does and the source does not). Both files are stored as
// extensionless lumps on disk (real Ogg content, confirmed by file
// signature) -- an easy thing to miss with a plain *.ogg file search,
// which is exactly what happened the first time this file was written:
// it shipped claiming no fire sound existed in the source at all. See
// SNDINFO.txt for the lump mapping.
class RS_HolsterFlamethrower : Weapon
{
	Default
	{
		Weapon.SlotNumber 8;
		Weapon.SelectionOrder 4100;
		Weapon.AmmoType "Cell";
		Weapon.AmmoUse 1;
		Weapon.AmmoGive 40;
		+WEAPON.NOALERT
		+WEAPON.AMMO_OPTIONAL
		+WEAPON.NOAUTOSWITCHTO
		Tag "Holster Flamethrower";
		Inventory.PickupMessage "You found a holster flamethrower.";
	}

	States
	{
	Spawn:
		HBFT A -1;
		Stop;
	Ready:
		HBFT A 1 A_WeaponReady;
		Loop;
	Select:
		HBFT A 1 A_Raise;
		Loop;
	Deselect:
		HBFT A 1 A_Lower;
		Loop;
	Fire:
		HBFT B 1 Bright A_StartSound("rs_holster_flamethrower_fire", CHAN_WEAPON);
		// Single jet, small random angle each cycle -- matches the source's
		// own shape (RollStats: PelletCount = 1, "7.0 degree cone"), not a
		// multi-pellet spray.
		TNT1 A 0 A_CustomMissile("RS_HolsterFlameJet", 0, 0, frandom(-3.5, 3.5));
		HBFT C 1 Bright A_CustomMissile("RS_HolsterFlameJet", 0, 0, frandom(-3.5, 3.5));
		HBFT D 1 A_ReFire();
		// Reached only once the trigger is released -- A_ReFire jumps back
		// to Fire on its own while it is still held, so falling through to
		// here IS the "stopped firing" signal, not something to test for.
		TNT1 A 0 A_StartSound("rs_holster_flamethrower_stop", CHAN_AUTO);
		Goto Ready;
	}
}

// The flame visual itself -- the 19-frame RSI0 sequence RS_GH_FlameJet
// (RS_Main, RS_GH_HeavyProjectiles.zs) renders, on a plain Actor rather
// than RS_Main's RS_BallisticFired base, which this mod does not have.
// Short Speed/lifetime by design, same reasoning the source comment gives
// for its own version: "short range/lifespan matches a flame cone rather
// than a travelling round." The animation itself is the timer -- 19
// frames at 2 tics each (Doom runs 35 tics/sec) is a little over a
// second, then Stop leaves it on the last frame for one more tic before
// the projectile flag machinery removes it same as any other Projectile.
class RS_HolsterFlameJet : Actor
{
	Default
	{
		Speed 14;
		Radius 4;
		Height 4;
		Damage 4;
		DamageType "Fire";
		Scale 0.5;
		Alpha 0.9;
		RenderStyle "Add";
		Projectile;
		+BRIGHT
	}

	States
	{
	Spawn:
		RSI0 "abcdefghijklmnopqrs" 2 Bright;
		Stop;
	Death:
		Stop;
	}
}

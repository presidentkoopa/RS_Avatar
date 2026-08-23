// A holster-testable flamethrower -- an ordinary Weapon, so it drops
// straight into RS_Holsters' existing store/draw pipeline with ZERO changes
// to that system, same reasoning as RS_HolsterFlashlight in this same
// folder. Second proof point that any plain Weapon fits: this one is a
// full-auto spray weapon rather than a utility item, and needs nothing
// beyond the normal Weapon shape either.
//
// Model, skin and all four sprite frames are COPIED (not referenced) from
// RS_Main's RS_GH_Flamethrower (zscript/weapons/rs_gh_weapon/
// RS_GH_Flamethrower.zs, MODELDEF ~line 6545) -- this class does not
// reference RS_Main or RS_Weapon, so it works with or without RS_Main
// loaded, same "any weapon pack" independence as the rest of this mod.
//
// NOT taken, deliberately: RS_Main's own firing machinery. The source
// class extends RS_Weapon and fires through RS_AttackProfile/RS_Catalog/a
// custom RS_GH_FlameJet projectile, plus RS_Weapon's whole tier/rolled-
// stat/GunBonsai system -- none of that is asset, and porting it would
// mean either depending on RS_Main after all or reimplementing a system
// this mod has no use for. Firing here is a plain stock A_FireBullets
// spray instead: full-auto, wide spread, short range, reads as a jet of
// pellets rather than RS_Main's actual flame-particle visual, which this
// mod does not have the projectile assets for.
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
		HBFT B 1 Bright A_FireBullets(14.0, 7.0, 3, 4, "BulletPuff", FBF_NORANDOM);
		TNT1 A 0 A_StartSound("rs_holster_flamethrower_fire", CHAN_WEAPON);
		HBFT C 1 Bright A_FireBullets(14.0, 7.0, 3, 4, "BulletPuff", FBF_NORANDOM);
		HBFT D 1 A_ReFire();
		// Reached only once the trigger is released -- A_ReFire jumps back
		// to Fire on its own while it is still held, so falling through to
		// here IS the "stopped firing" signal, not something to test for.
		TNT1 A 0 A_StartSound("rs_holster_flamethrower_stop", CHAN_AUTO);
		Goto Ready;
	}
}

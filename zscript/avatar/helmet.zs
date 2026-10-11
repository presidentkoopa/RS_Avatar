// RS_Avatar -- the helmet worn on the body's head.
//
// Brought over from RS_VRBody at the owner's instruction (2026-09-30). The model is his:
// the Doom Eternal Classic Slayer helmet, three OBJs -- shell, visor glass and the dark
// interior -- with the ORIGIN AT THE EYE, so the part sits where the head is and turns
// about the eyes. See models/helmet/PROVENANCE.md; the rip is never pushed.
//
// HIDDEN FROM YOU, SEEN BY EVERYTHING ELSE, which is the whole point of it. Two engine
// pieces do that between them and neither is a special case for helmets:
//
//   WornOnBody / WornOnBone   the model is drawn at the body's posed "head" bone and turns
//                             with it. The same attachment the holsters, the pouch and the
//                             sheathed saw will use -- the owner's own note says they all
//                             need one system, so this is not allowed to be a second one.
//
//   <prefix>_eyefade_near/far the shader fades a model out by distance from the EYE, per
//                             pixel and per view. The shell is a few units from your own
//                             eyes so it is gone from your view, while a mirror looking
//                             from across the room sees it whole.
//
// The fade is the honest mechanism for this and a per-view hide would not be better: a
// visor you are looking THROUGH should thin out as it reaches your eye, not vanish at a
// threshold, and the interior shell behind your head stays solid because it is further away.

class RSA_Helmet : Actor
{
	Default
	{
		+NOINTERACTION
		+NOBLOCKMAP
		+NOGRAVITY
		+NOTELEPORT
		+DONTSPLASH
		+SYNCHRONIZED
		+NODAMAGE
		+NOBLOOD

		// Same reason as the body: the rig draws it away from the actor's own position, and
		// culling is done against the actor, so a tight radius culls a helmet plainly on
		// screen -- and only at certain angles, which reads as flickering.
		Radius 32;
		Height 8;

		RenderStyle "Normal";
		Alpha 1.0;
	}

	States
	{
	Spawn:
		// A REAL SPRITE. TNT1 is the engine's "no sprite" name and an actor on it is
		// discarded before the renderer looks for a model -- the fault that kept the body
		// itself invisible for days. PIST is an IWAD sprite, never seen, replaced by the
		// model MODELDEF binds to this frame.
		PIST A -1;
		Stop;
	}
}

//============================================================================
//
// THE BODY'S OWN HELMET COMES OFF WHEN THE UNIVERSAL ONE GOES ON.
//
// Otherwise you wear two, intersecting -- which is what the owner caught: "why is there a
// visor at all, we are using this universal helmet and hiding the helmets of the models".
//
// WHICH SURFACES, MEASURED PER BODY, never guessed. The engine numbers a Source model's
// surfaces by walking bodyparts and taking model 0 of each, then each mesh in turn
// (models_studio.cpp:167-190), and each is named by its material. Run
// tools/avatar/list_surfaces.py over a .mdl to get the list for a new body; for
// c_doom_marine it is:
//
//     0 head      1 eyeball_l   2 eyeball_r
//     3 helmet_c  4 visor_c     5 helmet_ggx   6 visor_ggx      <- these four
//     7 torso     8 cowl        9 legs   10 torso   11-12 legs   13 arms
//
// A table rather than a constant buried in the code, because the next body will number them
// differently and the answer has to be visible beside the model it belongs to.
//
//============================================================================

class RSA_HelmetHide play
{
	// Bodies whose own helmet has to come off, and which surfaces that is.
	// Anything not listed keeps every surface -- a body with no helmet of its own needs
	// nothing hidden, which is the common case and the safe default.
	// HOW RS_VRBODY DID IT, AND WHY THAT IS THE RIGHT WAY.
	//
	// Not SetModelSurfaceHidden -- that writes to modelData, which MODELDEF never creates,
	// so it returns false and hides nothing. RS_VRBody swapped the surface's SKIN for a
	// fully transparent one instead (body_rig.zs:2588, headSkinAt with "invisible.png"),
	// and its own comment records that the invisible half is the half that always worked.
	//
	// A_ChangeModel with CMDL_USESURFACESKIN both creates the model data AND sets the skin,
	// in one call, which is exactly why it does not hit the wall the hide does: the data is
	// not empty afterwards, so ChangeModel does not destroy it again.
	//
	// Callable on another actor -- RS_VRBody calls it as a.A_ChangeModel(...) throughout.
	static void Apply(Actor body, String worn, bool helmetOn)
	{
		if (body == null) return;

		// EVERY BODY WITH A HELMET OF ITS OWN, NOT ONLY THE MARINE (2026-10-11).
		//
		// This handled c_doom_marine and returned for everything else, so praetor,
		// doomslayer_default and marine_guy_classic each wore RS_Avatar's helmet prop ON TOP
		// OF their own sculpted one -- two helmets. In the MIRROR and in any third-person
		// view only: your own view never showed it, because the head is not in the engine's
		// keep list and everything weighted to it collapses there already.
		//
		// FLAT int/String TABLES ON PURPOSE. The obvious shape is one struct per body in a
		// dynamic array, and in this dialect that compiles clean and dies AT LOAD -- an
		// `out` array parameter is the other way to kill a whole class the same way. So the
		// data sits in parallel const arrays of int and String, and a body is a first/count
		// window into them.
		//
		// EVERY SURFACE NUMBER AND SKIN NAME IS READ OUT OF THE .mdl, not typed off a
		// render. The skin to restore to a surface is its OWN material name from the model's
		// texture table, and the directory is "materials/" plus that model's own material
		// dir -- which is precisely what the marine's hand-written pair used to spell out,
		// and is how this was checked: the four marine names below reproduce the old `kOwn`
		// list exactly. Praetor's three cross-check a second, independent way, against the
		// skins RS_VRBody restored to the same meshes: 1001, 1011, 1001_visor_solid.
		//
		// RESTORING THE WRONG NAME IS THE FAILURE TO FEAR and it has already happened here:
		// RS_VRBody asked models/marine for praetor's skin names, so HIDING worked and
		// SHOWING quietly did not -- half a bug, which is the worst kind, and its own
		// comment says nobody suspected the mechanism. Hence names from the file.
		//
		// PRAETOR'S NUMBERS NEED THE LOADER FIX of the same day (models_studio.cpp: the
		// per-model vertex base, and taking the first NON-EMPTY model). Assembled wrongly
		// that body builds 16 surfaces; assembled correctly it builds 24, and these are the
		// 24-surface indices. On an engine without that fix they name the wrong meshes.
		//
		// THE OTHER TWO ARE HANDLED, BUT NOT HERE -- see handler.zs, where the universal
		// helmet is spawned. pechenko_doomslayer and lillwasa_doomguy have a head that IS a
		// helmet, with no face modelled under it, so there is nothing to reveal by hiding:
		// pechenko is one merged surface for the whole body (and plain ValveBiped bones,
		// with nothing matching helm or visor, so by-bone is not available either), and
		// lillwasa's surfaces 1 and 2 ARE its shell and visor. Hiding on either would leave
		// the universal helmet on an empty neck, so they are given no universal helmet
		// instead. Do not "finish the job" by adding them to the table below.
		//
		// doomslayer_lowpoly is absent because it is refused at load and is not registered
		// in VRAVATAR.txt at all.
		static const String kDir[] = {
			"materials/models/auditor/doom/praetor_suit",
			"materials/models/DOOM_The_Dark_Ages/Slayer/praetor",
			"materials/models/doom_eternal/humans/doomslayer/default",
			"materials/models/arachnit/doom_eternal/characters/doom_slayer_marine_guy/classic"
		};
		static const int kFirst[] = { 0, 4,  7, 12 };
		static const int kCount[] = { 4, 3,  5,  5 };
		static const int kSurf[] = {
			3, 4, 5, 6,                  // c_doom_marine:      helmet, visor, + gloss pair
			0, 7, 8,                     // dark_ages_praetor:  visor, helmet, helmet trim
			15, 16, 21, 22, 25,          // doomslayer_default: helmet, visors, gloss
			6, 7, 14, 15, 16             // marine_guy_classic: visors, helmet, interior
		};
		static const String kSkin[] = {
			"models_characters_doommarine_doommarine_helmet_c",
			"models_characters_doommarine_doommarine_visor_c",
			"models_characters_doommarine_doommarine_helmet_ggx",
			"models_characters_doommarine_doommarine_visor_ggx",
			"doomslayer_praetor_1001_visor_solid",
			"doomslayer_praetor_1001",
			"doomslayer_praetor_1011",
			"doomslayer_helmet",
			"doomslayer_helmet_visor_r",
			"doomslayer_helmet_visor",
			"doomslayer_helmet_s",
			"doomslayer_helmet_visor_s",
			"doomslayer_helmet_visor_set3_hq",
			"doomslayer_helmet_visor_set3_hq_1",
			"doomslayer_helmet_set3_1",
			"doomslayer_helmet_interior_set3",
			"doomslayer_helmet_set3"
		};

		int which = -1;
		if      (worn ~== "c_doom_marine")      which = 0;
		else if (worn ~== "dark_ages_praetor")  which = 1;
		else if (worn ~== "doomslayer_default") which = 2;
		else if (worn ~== "marine_guy_classic") which = 3;
		if (which < 0) return;      // a body with no helmet of its own needs nothing

		int first = kFirst[which];
		int count = kCount[which];
		for (int i = 0; i < count; ++i)
		{
			int s = kSurf[first + i];
			if (helmetOn)
				body.A_ChangeModel("", 0, "", "", s, "models/shared", "invisible.png",
					CMDL_USESURFACESKIN, 0, 0, "", "");
			else
				body.A_ChangeModel("", 0, "", "", s, kDir[which], kSkin[first + i],
					CMDL_USESURFACESKIN, 0, 0, "", "");
		}
	}
}

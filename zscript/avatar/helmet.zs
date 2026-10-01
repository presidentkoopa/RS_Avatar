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

		int first = -1, last = -1;
		String path = "", pre = "";
		if (worn ~== "c_doom_marine")
		{
			first = 3; last = 6;
			path = "materials/models/auditor/doom/praetor_suit";
			pre  = "models_characters_doommarine_doommarine_";
		}
		if (first < 0) return;      // a body with no helmet of its own needs nothing

		// Named per surface so turning the helmet back off restores the right skin to the
		// right mesh. The order is the engine's own: 3 helmet, 4 visor, 5 helmet gloss,
		// 6 visor gloss -- see the table above.
		static const String kOwn[] = { "helmet_c", "visor_c", "helmet_ggx", "visor_ggx" };

		for (int s = first; s <= last; ++s)
		{
			if (helmetOn)
				body.A_ChangeModel("", 0, "", "", s, "models/shared", "invisible.png",
					CMDL_USESURFACESKIN, 0, 0, "", "");
			else
				body.A_ChangeModel("", 0, "", "", s, path, pre .. kOwn[s - first],
					CMDL_USESURFACESKIN, 0, 0, "", "");
		}
	}
}

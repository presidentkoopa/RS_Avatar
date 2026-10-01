// RS_Avatar -- the body shows how you are doing.
//
// TAKEN FROM RS_VRBody at the owner's instruction (2026-09-29: "find the code that changes
// body color based on armor or health level and get that for us"). The DESIGN below is his,
// and the rules are quoted from his own CVARINFO there:
//
//   armor_color  "the torso's colour follows how much armour you HAVE: 0-99 your base
//                colour, 100-149 green, 150+ blue."
//   breathe      "below breathe_below health a red copy of the torso fades in and out over
//                it, slowly, faster the closer you are to dying. A sine, never a flash --
//                photosensitivity."
//
// and one more, which is why nothing here ever blends two colours together:
//
//   "nothing ever mixes -- one colour can honestly show one thing."
//
// WHAT IS DIFFERENT HERE, AND WHY IT HAD TO BE.
//
// RS_VRBody swapped pre-authored red, green and blue copies of each surface (its
// blendSurface). Its models ship those skin sets; ours do not, and painting new ones is not
// mine to do. So the same look is reached by tinting the skins he already has -- see
// TRNSLATE.txt for the ladder and for why it is steps rather than a fade.
//
// It also had a separate torso PART to recolour. Our body is one whole model, which the
// owner's own note in RS_VRBody says is the case that broke there: "this used to look only
// at the torso SLOT, which a whole body leaves empty -- so the breath was silently dead the
// moment the whole body went in, and near-death read exactly like full health." There are no
// slots here at all, so that trap cannot be repeated, but it is worth knowing it is what
// this replaces.
//
// RENDER ONLY. A translation is a drawing choice. Nothing here touches the playsim, decides
// anything, or is read by another machine -- see the owner-keyed check in Apply.

class RSA_BodyColour play
{
	// PLAY SCOPE. Assigning an actor's translation is a play-side write, so a data-scoped
	// class cannot do it -- the compiler says "can't call play function from data context".
	// 0 under 100, 1 for 100-149, 2 for 150 and up. How much, not what kind: the colour is
	// the number. Thresholds are the owner's.
	private static int ArmourBand(PlayerPawn pawn)
	{
		let arm = BasicArmor(pawn.FindInventory("BasicArmor"));
		int amount = arm ? arm.Amount : 0;
		if (amount >= 150) return 2;
		if (amount >= 100) return 1;
		return 0;
	}

	//==========================================================================
	//
	// Pick the one colour this body should be wearing, and put it on.
	//
	// `phase` walks 0..1 and is the caller's, so it survives this being a static and so the
	// breath keeps its place across a tic where the body is not drawn.
	//
	//==========================================================================
	static void Apply(Actor body, PlayerPawn pawn, in out double phase)
	{
		if (body == null || pawn == null) return;

		// THE VEHICLE, SECOND TIME. A translation was the wrong one and cost the owner his
		// whole body: a palette remap gives a truecolour Source skin no material, so the
		// model drew nothing at all. The engine now carries ModelTint / ModelTintAmount,
		// which the shader multiplies straight into the skin -- no second set of skins, no
		// palette, and it fades rather than switching.
		let on = CVar.GetCVar("vr_avatar_colour", pawn.player);
		if (on != null && !on.GetBool()) { body.ModelTintAmount = 0.0; return; }

		// KEYED TO THE BODY'S OWNER, NEVER consoleplayer. In co-op every machine ticks every
		// body, and reading the local view here would paint one player's health onto another
		// player's marine. The pawn is passed in for exactly that reason.
		int hp = pawn.Health;
		int below = 33;
		let cb = CVar.GetCVar("vr_avatar_breathe_below", pawn.player);
		if (cb) below = max(1, cb.GetInt());

		bool wantBreathe = true;
		let cw = CVar.GetCVar("vr_avatar_breathe", pawn.player);
		if (cw) wantBreathe = cw.GetBool();

		bool wantArmour = true;
		let ca = CVar.GetCVar("vr_avatar_armour_colour", pawn.player);
		if (ca) wantArmour = ca.GetBool();

		// HURT WINS. Being about to die is the more urgent thing the body can say, and
		// mixing it with the armour colour would make both unreadable -- the owner's rule.
		if (wantBreathe && hp > 0 && hp < below)
		{
			double t = 1.0 - double(hp) / double(below);   // 0 at the threshold, ~1 at death
			double secs = 2.6 - 1.4 * t;                   // one breath per 2.6s down to 1.2s
			phase += 1.0 / (secs * 35.0);
			while (phase >= 1.0) phase -= 1.0;

			// A sine, never a flash. Deeper the worse it is, and it never reaches full,
			// so the armour is always still readable underneath -- photosensitivity, and
			// the owner's own rule from RS_VRBody.
			double amt = (0.5 - 0.5 * cos(phase * 360.0)) * (0.55 + 0.45 * t);
			body.ModelTint = Color(255, 255, 40, 40);
			body.ModelTintAmount = clamp(amt, 0.0, 0.85);
			return;
		}

		phase = 0.0;

		if (wantArmour)
		{
			int band = ArmourBand(pawn);
			if (band == 2) { body.ModelTint = Color(255, 90, 140, 255); body.ModelTintAmount = 0.40; return; }
			if (band == 1) { body.ModelTint = Color(255, 90, 255, 110); body.ModelTintAmount = 0.40; return; }
		}

		// Its own skins, untouched. Zero is the inert value the engine ships, so this
		// costs the renderer nothing.
		body.ModelTintAmount = 0.0;
	}
}

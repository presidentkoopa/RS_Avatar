// RS_Avatar -- spawning and placing the avatar.
//
// VR_BODY_HANDS_SPEC.md M1 task 1.
//
// WHAT THIS DOES AND DELIBERATELY DOES NOT DO. It keeps an avatar actor alive next to each
// player and nothing else. It does not pose it, does not place the drawn model, and does not
// touch a single bone: the rig does all of that per displayed FRAME, in the engine, because
// script runs at 35Hz and a hand does not. Anything here that tried to position the body
// would be a second, slower copy of where the body is -- which is the exact fault that made
// the previous rig untunable, and is written up at the top of src/r_data/vr_rig.h.
//
// So: this is a caretaker. It spawns, it follows, it removes.

class RSA_Handler : EventHandler
{
	// One per player, indexed by player number. Not serialized: an avatar is render-only
	// state, and a loaded save spawns its own on the next tic.
	private Actor mAvatar[MAXPLAYERS];
	private string mWornName[MAXPLAYERS];
	// Where each player's breath is in its cycle. Per player on purpose: two men near death
	// should not breathe in step, and one shared value would put them there.
	private double mBreathPhase[MAXPLAYERS];
	// The helmet worn on each body's head. Its own actor because it is its own model with
	// its own skins, and because the same attachment will carry holsters and a pouch.
	private Actor mHelmet[MAXPLAYERS];
	// Which body last had its own helmet skinned away, and to what. A_ChangeModel
	// allocates, so this is only redone when the answer actually changes.
	private Actor mHidOn[MAXPLAYERS];
	private bool  mHidWas[MAXPLAYERS];
	private string mComplainedAbout[MAXPLAYERS];

	override void WorldTick()
	{
		// ONE AVATAR PER PLAYER, FOR EVERY PLAYER, ON EVERY CLIENT.
		//
		// NOT "the console player only". An EventHandler runs on every client, so keying a
		// spawn on consoleplayer spawns a different set of actors on each machine and
		// desynchronises the game. One per player is identical everywhere.
		//
		// Each player's choice is read from THAT PLAYER'S copy of the cvar, which the
		// engine replicates, so every client agrees about what everyone is wearing.
		// Reading it without naming a player would read the local machine's, and the
		// answer would differ per client -- the same desync wearing a hat.
		//
		// Only the local player's avatar is ever POSED, and posing is render-only, so the
		// others simply stand in their rest pose. That is also how other players' bodies
		// arrive later (spec M8) with nothing restructured.
		for (int i = 0; i < MAXPLAYERS; i++)
		{
			if (!playeringame[i] || players[i].mo == null)
			{
				Retire(i);
				continue;
			}

			// players[i] IS the PlayerInfo; GetCVar takes one to read THAT player's copy.
			CVar c = CVar.GetCVar("vr_avatar", players[i]);
			string want = c ? c.GetString() : "";

			// A changed name is a different body: drop this one and let the next tic
			// spawn the new one, rather than swapping a model under a live actor.
			if (mAvatar[i] != null && mWornName[i] != want)
				Retire(i);

			// "none" is what the menu writes for Off. It cannot be the empty string: the
			// option menu reads a list whose first value is empty as a list of NUMBERS, and
			// then the control shows its first entry forever whatever you pick.
			if (want == "" || want == "none")
			{
				// AN EMPTY NAME IS NOT THE SAME AS "OFF", AND IT USED TO LOOK THE SAME.
				// "none" is the player choosing no body and is silent, correctly. But an
				// EMPTY string means this player's copy of the cvar never got a value --
				// and that retired the body with no message at all, which is
				// indistinguishable from working properly while wearing nothing. The owner
				// spent an evening on that. It says so now, once.
				if (want == "" && mComplainedAbout[i] != "<empty>")
				{
					mComplainedAbout[i] = "<empty>";
					Console.Printf("\cgRS_Avatar: player %d's vr_avatar is EMPTY, so no body "
						"is worn. The cvar exists but this player's copy has no value -- "
						"pick a body in Options > VR Body and Hands, or set vr_avatar.", i);
				}
				Retire(i);
				continue;
			}

			if (mAvatar[i] == null)
			{
				string cn = VRAvatarTable.ActorName(want);
				class<Actor> cls = cn != "" ? (class<Actor>)(cn) : null;
				if (cls == null)
				{
					// ONCE PER NAME, not once per tic. A line every tic is a line nobody
					// can read, and in a headset it is a line nobody can even scroll to.
					if (mComplainedAbout[i] != want)
					{
						mComplainedAbout[i] = want;
						if (cn == "")
							Console.Printf("\cgRS_Avatar: no avatar called '%s'. A VRAVATAR "
								"lump has to name it.", want);
						else
							Console.Printf("\cgRS_Avatar: avatar '%s' wants actor class "
								"'%s', which does not exist.", want, cn);
					}
					continue;
				}
				mAvatar[i] = Actor.Spawn(cls, players[i].mo.pos);
				mWornName[i] = want;
				mComplainedAbout[i] = "";
				if (mAvatar[i] == null)
				{
					Console.Printf("\cgRS_Avatar: could not spawn '%s'.", cn);
					continue;
				}
			}

			// FOLLOW, DO NOT POSE. The actor sits at the player's feet so the renderer
			// culls and lights it correctly. Where the BODY is drawn is the rig's answer
			// and it is a different place -- under the headset, which the playsim cannot
			// see at this rate.
			let av = mAvatar[i];
			let pmo = players[i].mo;
			av.SetOrigin(pmo.pos, true);   // true: interpolated, so it does not judder
			av.angle = pmo.angle;
			av.VRRigRole = 1;
			av.VRRigHand = 0;

			// YOUR OWN HEAD IS NOT IN YOUR EYES (owner, 2026-10-04: bodies "displaying their
			// heads and helmets ... these need to be collapsed or hidden from my eyes").
			//
			// The engine fades a model out by distance from the EYE when its placement prefix
			// carries <prefix>_eyefade_far (models.cpp ModelEyeFadeRange). The helmet has had
			// one since it was written; THE BODIES NEVER HAD A PREFIX AT ALL, so that test
			// returns false on its first line and no body has ever faded. The note below about
			// the head being "hidden in the first case" described an intent, not a path.
			//
			// WHY NOT RS_VRBODY'S WAY, which is where this behaviour came from. It skinned the
			// head surface invisible and drew a SECOND head actor with MASTERNOSEE. That needs
			// the head's surface INDEX per body, and two of these -- doomslayer_lowpoly and
			// doomslayer -- are a single merged surface (tools/avatar/dump_surfaces.py), so
			// there is no head to skin: hiding it hides the whole man. The fade is per DRAW,
			// which buys the same thing for free -- a mirror renders from the mirror's
			// viewpoint, far from this body, so it does not fade there.
			//
			// ONE PREFIX FOR EVERY BODY, deliberately: how far your eye is from your own head
			// does not depend on which model you wear, and one pair of sliders beats seven.
			// These models declare no placement cvars of their own, so naming one displaces
			// nothing. Per-body tuning, if it is ever wanted, is a different name here and
			// needs no other change.
			av.PlacementPrefix = 'rsa_body';

			// WHOSE BODY THIS IS.
			//
			// The engine needs it to answer one question every frame: am I drawing this for
			// the eyes of the person wearing it, or for someone or something else looking at
			// him -- a mirror, a spectator, another player? The head is hidden in the first
			// case and drawn in every other, and without an owner there is no way to tell
			// them apart.
			//
			// `target` is the stock "who does this belong to" pointer and is already
			// serialized and cleaned up when the pawn dies, so it needs nothing new.
			av.target = pmo;

			// WHAT THE BODY SAYS ABOUT HOW YOU ARE DOING. See colour.zs -- the design is
			// the owner's, out of RS_VRBody.
			//
			// Driven from here, per player, because this is the one loop that already has
			// both the body and the pawn it belongs to. The breath's phase is kept per
			// player rather than inside the helper: two players near death should not
			// breathe in lockstep, and a static would make them.
			RSA_BodyColour.Apply(av, pmo, mBreathPhase[i]);

			// THE HELMET RIDES THE HEAD BONE. Nothing here positions it: WornOnBody and
			// WornOnBone tell the renderer to draw it at the body's posed head and turn it
			// with the bone, and the eye fade in MODELDEF takes it out of the wearer's own
			// view while leaving it whole in a mirror.
			//
			// Kept near the body because an actor's own position still decides whether it
			// is drawn at all -- see the note on Actor.FollowActor, which has the same trap.
			bool wantHelmet = true;
			let ch = CVar.GetCVar("vr_avatar_helmet", players[i]);
			if (ch) wantHelmet = ch.GetBool();

			if (wantHelmet)
			{
				if (mHelmet[i] == null)
					mHelmet[i] = Actor.Spawn("RSA_Helmet", pmo.pos);
				if (mHelmet[i] != null)
				{
					mHelmet[i].SetOrigin(pmo.pos, true);
					mHelmet[i].WornOnBody = av;
					mHelmet[i].WornOnBone = 'head';
					// The body's own owner, so a helmet is hidden and drawn by the same
					// rule the head is.
					mHelmet[i].target = pmo;
				}
			}
			else if (mHelmet[i] != null)
			{
				mHelmet[i].Destroy();
				mHelmet[i] = null;
			}

			// The body's own helmet comes off while the universal one is worn, or he wears
			// two, intersecting.
			//
			// ONLY WHEN IT CHANGES. A_ChangeModel allocates, so doing this every tic would
			// be 35 skin swaps a second for a thing that changes when he toggles a menu
			// option. Keyed on the body actor as well as the state, because a new body is a
			// new actor with its own unswapped skins.
			if (mHidOn[i] != av || mHidWas[i] != wantHelmet)
			{
				mHidOn[i] = av;
				mHidWas[i] = wantHelmet;
				RSA_HelmetHide.Apply(av, mWornName[i], wantHelmet);
			}
		}
	}

	override void WorldUnloaded(WorldEvent e)
	{
		for (int i = 0; i < MAXPLAYERS; i++) Retire(i);
	}

	private void Retire(int i)
	{
		if (mHelmet[i] != null)
		{
			mHelmet[i].Destroy();
			mHelmet[i] = null;
		}
		if (mAvatar[i] != null)
		{
			mAvatar[i].Destroy();
			mAvatar[i] = null;
		}
		mWornName[i] = "";
	}
}

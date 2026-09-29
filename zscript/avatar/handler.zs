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
		}
	}

	override void WorldUnloaded(WorldEvent e)
	{
		for (int i = 0; i < MAXPLAYERS; i++) Retire(i);
	}

	private void Retire(int i)
	{
		if (mAvatar[i] != null)
		{
			mAvatar[i].Destroy();
			mAvatar[i] = null;
		}
		mWornName[i] = "";
	}
}

// RS_Avatar -- FIT MODE. VR_BODY_HANDS_SPEC.md M1 task 5.
//
// WHAT IT IS FOR. The derived hand fit (spec B.5) puts the model's hand where the MODEL
// wants it. It cannot know where your hand sits inside the controller, how you hold it, or
// how big your hands are -- so the last part is yours, set once per body, and saved.
//
// THE CONTROLS, after JKXR's weapon alignment mode:
//     turn stick left/right     pick a field   (x, y, z, pitch, yaw, roll)
//     move stick forward/back   change it
//     crouch                    zero that field
//     fire                      swap to the other hand
//
// TWO STICKS, NOT TWO HANDS. The engine exposes the locomotion stick and the turn stick,
// which is what a headset actually has; which physical hand each sits under is the player's
// own control scheme and not something this should assume.
//
// Movement is suppressed while it is on, because those same sticks are doing the adjusting.
//
// AND YOU CANNOT BE HURT WHILE IT IS ON. Owner, 2026-09-26: "i can't be dying while we do
// this." Nothing targets you and nothing damages you, and both are restored to exactly what
// they were on the way out -- not to "off", because he may have had god on already. A
// calibration you have to fight through is one that gets abandoned half done, and a
// half-done fit is worse than none, because it looks deliberate.
//
// LOCAL INPUT, REPLICATED DECISIONS. The sticks are this machine's own and must never decide
// anything the playsim cares about, so they only ever move numbers that end up in an
// archived cvar the renderer reads. Turning the mode on and off arrives as a net event and
// names the player who asked, because `consoleplayer` is a different person on every machine
// and using it here would invulnerate someone else's pawn on their client.

class RSA_FitMode : EventHandler
{
	//==========================================================================
	//
	// SAYING SOMETHING WHERE THE PLAYER CAN ACTUALLY SEE IT.
	//
	// Every message in this file went to Console.Printf, and the player is in a headset. He
	// cannot look at a console, so fit mode refused, explained exactly why, and from where he
	// was sitting did nothing at all -- which is precisely how it came back: "fit gun to hand
	// doesn't do anything". Fifteen messages, none of them readable by the only person they
	// were written for.
	//
	// So they go on the screen as well. Still to the console, because that is what ends up in
	// the log and the log is how any of this gets diagnosed afterwards.
	//
	// MidPrint takes a leading '$' as a language lookup, so a message that ever starts with
	// one would silently become a missing string. Ours start with a colour escape; the guard
	// is here because that is a trap someone will otherwise walk into later.
	//
	//==========================================================================
	private static void Say(String s)
	{
		Console.Printf("%s", s);
		if (s.Left(1) != "$")
			Console.MidPrint(smallfont, s);
	}

	// SEVEN FOR A WEAPON, SIX FOR A HAND. A weapon carries a scale as well, because the
	// models come from a dozen sets at a dozen different scales and none of them is the
	// player's to measure. A hand does not: the body is already sized to the player.
	const FIELDS = 7;
	const FIELD_SCALE = 6;

	private int mPlayer;         // who is fitting; -1 when nobody is
	// 0 the hand, 1 the weapon in that hand, 2 the body (a measured pose, not sliders).
	private int mMode;
	private bool mWeaponMode;    // mMode == 1, kept for readability at the use sites
	private int mBodyHeld;       // tics the trigger has been held in body mode
	private string mWpnClass;    // the class being fitted, while in weapon mode
	private int mField;          // 0 x, 1 y, 2 z, 3 pitch, 4 yaw, 5 roll
	private bool mRightHand;
	private double mVal[FIELDS];
	private string mAvatar;

	// What we changed about the player, so it can be put back rather than guessed at.
	private bool mSavedInvuln;
	private bool mSavedNotarget;

	// Edge detection: a stick held over is one step, not sixty.
	private bool mPrevLeft, mPrevRight, mPrevClick, mPrevSwap;

	override void OnRegister()
	{
		mPlayer = -1;
	}

	private bool Active() const
	{
		return mPlayer >= 0 && playeringame[mPlayer] && players[mPlayer].mo != null;
	}

	//==========================================================================
	//
	// on and off
	//
	//==========================================================================

	private void Begin(int pnum, int mode)
	{
		if (pnum < 0 || !playeringame[pnum] || players[pnum].mo == null) return;
		if (mPlayer >= 0) return;          // already fitting; ignore a second request

		CVar c = CVar.GetCVar("vr_avatar", players[pnum]);
		mAvatar = c ? c.GetString() : "";
		if (mAvatar == "")
		{
			if (pnum == consoleplayer)
				Say(String.Format("\cgFit mode: you are not wearing a body (vr_avatar is empty)."));
			return;
		}

		mPlayer = pnum;
		mMode = mode;
		mWeaponMode = (mode == 1);
		mBodyHeld = 0;
		// The reference line the barrel is aligned against. Engine-side, because it is
		// drawn in the world with the same line buffer the rig's own axes use.
		if (pnum == consoleplayer)
		{
			CVar ray = CVar.FindCVar("vr_fit_aimray");
			if (ray) ray.SetBool(mWeaponMode);
		}
		mField = 0;
		if (mWeaponMode && !FindHeldWeapon())
		{
			mPlayer = -1;
			if (pnum == consoleplayer)
				Say(String.Format("\cgFit mode: no weapon prop is being drawn in that hand. "
					"Take a gun out first."));
			return;
		}
		if (mMode != 2) Load();

		let pmo = players[pnum].mo;
		mSavedInvuln = pmo.bINVULNERABLE;
		mSavedNotarget = (players[pnum].cheats & CF_NOTARGET) != 0;
		pmo.bINVULNERABLE = true;
		players[pnum].cheats |= CF_NOTARGET;

		if (pnum == consoleplayer)
		{
			if (mMode == 2)
				Say(String.Format("\ccBody fit: stand up straight, hold both arms straight out "
					"to the sides, and hold the trigger for a second."));
			else
				Say(String.Format("\ccFit mode on: %s, %s hand. Turn stick picks a field, move "
					"stick changes it, crouch zeroes it, fire swaps hands. `vr_fitmode off` "
					"when it feels right.",
					mWeaponMode ? mWpnClass : mAvatar, mRightHand ? "right" : "left"));
		}
	}

	private void Finish()
	{
		if (mPlayer < 0) return;
		Save();

		if (playeringame[mPlayer] && players[mPlayer].mo != null)
		{
			let pmo = players[mPlayer].mo;
			pmo.bINVULNERABLE = mSavedInvuln;
			if (!mSavedNotarget) players[mPlayer].cheats &= ~CF_NOTARGET;
			// A stuck suppression flag is a player who cannot turn, and nothing else will
			// clear it, so it is cleared here, on level end and on death alike.
			level.SuppressVRInput(false);
		}

		if (mPlayer == consoleplayer)
		{
			CVar ray = CVar.FindCVar("vr_fit_aimray");
			if (ray) ray.SetBool(false);
			Say(String.Format("\ccFit mode off. Saved."));
		}
		mPlayer = -1;
	}

	override void WorldUnloaded(WorldEvent e)
	{
		Finish();
	}

	override void PlayerDied(PlayerEvent e)
	{
		if (e.PlayerNumber == mPlayer) Finish();
	}

	//==========================================================================
	//
	// WHICH WEAPON AM I FITTING?
	//
	// The one whose PROP is being drawn in that hand -- VRRigRole 2 -- not the one the
	// playsim says is selected. During a swap those are different, and fitting the wrong
	// class writes seven numbers onto a gun the player was not even looking at.
	//
	//==========================================================================

	private bool FindHeldWeapon()
	{
		let pmo = players[mPlayer].mo;
		if (pmo == null) return false;

		int wantHand = mRightHand ? 0 : 1;      // as VRRigHand numbers them
		CVar sch = CVar.FindCVar("vr_control_scheme");
		bool rightHanded = (sch == null) || (sch.GetInt() < 10);
		// VRRigHand is main/off; which physical hand that is depends on the control scheme.
		wantHand = (mRightHand == rightHanded) ? 0 : 1;

		ThinkerIterator it = ThinkerIterator.Create("Actor");
		Actor a;
		while (a = Actor(it.Next()))
		{
			if (a.VRRigRole != 2 || a.VRRigHand != wantHand) continue;
			mWpnClass = a.GetClassName();
			return true;
		}
		return false;
	}

	//==========================================================================
	//
	// the numbers: six per hand per body, seven per weapon class per hand (spec C.5)
	//
	//==========================================================================

	private string KeyName() const
	{
		return String.Format("vr_fit_hand_%s_%s", mAvatar, mRightHand ? "R" : "L");
	}

	private void Load()
	{
		for (int i = 0; i < FIELDS; i++) mVal[i] = 0.0;
		if (mWeaponMode) mVal[FIELD_SCALE] = 1.0;   // an unfitted weapon is not scaled away

		string s;
		if (mWeaponMode)
		{
			s = VRAvatarTable.GetWeaponFit(mWpnClass, mRightHand);
		}
		else
		{
			CVar c = CVar.FindCVar(KeyName());
			if (c == null) return;
			s = c.GetString();
		}
		if (s == "") return;

		// A malformed string reads as zeros, which IS the derived fit -- the same fallback
		// the engine uses, so the two can never disagree about an unfitted body.
		// The stored order is the engine's: a hand is "x y z pitch yaw roll" and a weapon is
		// "scale x y z pitch yaw roll". Scale is read into its own slot at the end so the
		// six shared fields keep the same indices in both modes and the controls do not
		// have to know which mode they are in.
		int count = mWeaponMode ? 7 : 6;
		double raw[7];
		for (int i = 0; i < 7; i++) raw[i] = 0.0;

		int at = 0, field = 0;
		while (field < count && at <= s.Length())
		{
			int sp = s.IndexOf(" ", at);
			string piece = (sp < 0) ? s.Mid(at) : s.Mid(at, sp - at);
			if (piece != "")
			{
				raw[field] = piece.ToDouble();
				field++;
			}
			if (sp < 0) break;
			at = sp + 1;
		}

		if (mWeaponMode)
		{
			mVal[FIELD_SCALE] = (raw[0] > 0.0001) ? raw[0] : 1.0;
			for (int i = 0; i < 6; i++) mVal[i] = raw[i + 1];
		}
		else
		{
			for (int i = 0; i < 6; i++) mVal[i] = raw[i];
		}
	}

	private void Save()
	{
		if (mMode == 2) return;      // the body fit writes its own two cvars
		if (mWeaponMode)
		{
			// Scale first, as the engine reads it. The engine creates this cvar on demand:
			// there are far too many weapon classes for CVARINFO to declare.
			string packed = String.Format("%.4f", mVal[FIELD_SCALE]);
			for (int i = 0; i < 6; i++)
				packed = packed .. " " .. String.Format("%.4f", mVal[i]);
			VRAvatarTable.SetWeaponFit(mWpnClass, mRightHand, packed);
			return;
		}

		CVar c = CVar.FindCVar(KeyName());
		if (c == null)
		{
			if (mPlayer == consoleplayer)
				Say(String.Format("\cgFit mode: the cvar %s does not exist, so nothing was "
					"saved. Re-run genbodies.py -- it declares one pair per body.", KeyName()));
			return;
		}

		// `out` is a reserved word in ZScript (out parameters), so this is not called that.
		string packed = "";
		for (int i = 0; i < 6; i++)
		{
			if (i > 0) packed = packed .. " ";
			packed = packed .. String.Format("%.4f", mVal[i]);
		}
		c.SetString(packed);
	}


	//==========================================================================
	//
	// THE BODY FIT: two numbers, measured off the player rather than asked for.
	//
	// vr_fit_height    how high his eyes are, standing straight, in metres
	// vr_fit_armspan   wrist to wrist with both arms out, in metres
	//
	// Everything downstream is scaled from these: the avatar's world scale, and the arm
	// length the solver reaches with. Nobody knows their own armspan, and anyone in a headset
	// can stand in a T for a second -- so it is measured, and it measures the thing that
	// actually matters, which is where the controllers end up when his arms are straight.
	//
	// HELD, NOT TAPPED. A second of holding is a second of standing still, and the sample is
	// taken at the end of it. A tap would catch the instant he reached for the trigger, which
	// is the one moment his arms are not where he thinks they are.
	//
	//==========================================================================

	private void TickBodyFit()
	{
		let pmo = players[mPlayer].mo;
		if (pmo == null) return;

		bool held = (players[mPlayer].cmd.buttons & BT_ATTACK) != 0;
		if (!held)
		{
			mBodyHeld = 0;
			return;
		}
		mBodyHeld++;
		if (mBodyHeld < 35) return;        // a second at 35 tics

		// Both hands have to be tracked, or the span is a guess wearing a number's clothes.
		if (!VRAvatarTable.RigHandValid(0) || !VRAvatarTable.RigHandValid(1))
		{
			Say(String.Format("\cgBody fit: both controllers have to be tracked. Nothing saved."));
			mBodyHeld = 0;
			return;
		}

		Vector3 hR = VRAvatarTable.RigHandPos(0);
		Vector3 hL = VRAvatarTable.RigHandPos(1);
		double spanUnits = (hR - hL).Length();

		// Eye height above his own feet, in map units.
		//
		// NOT `viewz - pos.z`. That is the playsim's view height, and in VR it is a constant 44
		// map units whatever the player is doing -- so this measured every person who ever stood
		// in the T as the same man, and the body was built for him rather than for whoever was
		// wearing it. EyeAboveFloor is where the headset actually is, and is the exact number the
		// rig sizes the body from, so measuring with anything else guarantees the two disagree.
		double eyeUnits = VRAvatarTable.EyeAboveFloor(pmo.pos.z);

		CVar vpm = CVar.FindCVar("vr_vunits_per_meter");
		double unitsPerMetre = vpm ? vpm.GetFloat() : 0.0;
		if (unitsPerMetre < 1.0)
		{
			Say(String.Format("\cgBody fit: vr_vunits_per_meter is not set, so there is no way "
				"to turn units into metres. Nothing saved."));
			mBodyHeld = 0;
			return;
		}

		// MAP UNITS ARE NOT ISOTROPIC. Doom's vertical axis is stretched by pixelstretch (1.2
		// unless a map says otherwise), so a height in map units is metres only after it has been
		// multiplied by it. Leaving it out shortened every saved height by that factor, and the
		// engine then undoes the same stretch when it turns vr_fit_height back into units.
		//
		// The armspan below does NOT want it: with both arms straight out the hands are side by
		// side, so that length lies along the horizontal axes, and those are the unstretched ones.
		double stretch = level.pixelstretch > 0.0 ? level.pixelstretch : 1.2;
		double heightM = eyeUnits * stretch / unitsPerMetre;
		double spanM = spanUnits / unitsPerMetre;

		// REFUSED RATHER THAN SAVED WRONG. A crouch, a dropout or a controller on the desk
		// all produce a plausible number, and a plausible wrong armspan scales every arm in
		// the game by it forever.
		if (heightM < 0.8 || heightM > 2.4)
		{
			Say(String.Format("\cgBody fit: your eyes came out %.2f m from the floor, which is "
				"not a standing person. Stand up and try again.", heightM));
			mBodyHeld = 0;
			return;
		}
		if (spanM < 0.8 || spanM > 2.6)
		{
			Say(String.Format("\cgBody fit: your arms measured %.2f m across, which is not an "
				"armspan. Hold them straight out to the sides.", spanM));
			mBodyHeld = 0;
			return;
		}
		// A person's armspan is close to their height. Far off means one arm was down.
		if (spanM < heightM * 0.7 || spanM > heightM * 1.35)
		{
			Say(String.Format("\cgBody fit: %.2f m tall but %.2f m across -- one arm is probably "
				"not out. Try again.", heightM, spanM));
			mBodyHeld = 0;
			return;
		}

		CVar ch = CVar.FindCVar("vr_fit_height");
		CVar ca = CVar.FindCVar("vr_fit_armspan");
		if (ch == null || ca == null)
		{
			Say(String.Format("\cgBody fit: vr_fit_height / vr_fit_armspan do not exist. "
				"Re-run genbodies.py."));
			mBodyHeld = 0;
			return;
		}
		ch.SetFloat(heightM);
		ca.SetFloat(spanM);

		Say(String.Format("\ccBody fit saved: %.2f m tall at the eyes, %.2f m across the arms.",
			heightM, spanM));
		Finish();
	}

	//==========================================================================
	//
	// per tic
	//
	//==========================================================================

	override void WorldTick()
	{
		if (!Active())
		{
			if (mPlayer >= 0) Finish();
			return;
		}

		// Only the machine holding the controllers can read them, and only that machine
		// should be writing its own cvars. Every other client leaves this alone.
		if (mPlayer != consoleplayer) return;

		let pmo = players[mPlayer].mo;

		if (mMode == 2)
		{
			// The body fit needs him standing and moving his own arms, so the sticks are
			// suppressed for the same reason but nothing else is read.
			level.SuppressVRInput(true);
			TickBodyFit();
			return;
		}

		// The sticks are ours while this is on, or the player walks off while adjusting.
		// This is the call that does it: AxisMask and friends do nothing at all in VR.
		// It lives on LevelLocals, not on the pawn -- VR input is decided per machine,
		// before anything knows which actor it will end up moving.
		level.SuppressVRInput(true);

		// RAW, not the movement the game derived -- that has had deadzones, smoothing and
		// the turn curve applied, and what is wanted here is the stick itself.
		Vector2 mv = level.GetRawStickMove();     // (forward, side)
		Vector2 tn = level.GetRawStickTurn();     // (x, y), x turns you

		// --- pick a field, one step per push -----------------------------
		int nfields = mWeaponMode ? FIELDS : 6;
		bool left = tn.x < -0.6, right = tn.x > 0.6;
		if (left && !mPrevLeft) mField = (mField + nfields - 1) % nfields;
		if (right && !mPrevRight) mField = (mField + 1) % nfields;
		mPrevLeft = left;
		mPrevRight = right;

		// --- change it ---------------------------------------------------
		//
		// Different rates for position and angle, because a couple of millimetres of wrist
		// offset is plainly visible and a couple of degrees of wrist yaw is not.
		if (abs(mv.x) > 0.15)
		{
			// Three rates, because the three kinds of number are nothing like each other:
			// a couple of millimetres of offset is plainly visible, a couple of degrees of
			// wrist angle is not, and scale is a multiplier where 0.01 is a real change.
			double rate = 1.2;
			if (mField < 3) rate = 0.35;
			else if (mField == FIELD_SCALE) rate = 0.01;
			mVal[mField] += mv.x * rate;
			if (mField == FIELD_SCALE && mVal[mField] < 0.05) mVal[mField] = 0.05;
		}

		// --- zero, or swap hands -----------------------------------------
		bool click = (players[mPlayer].cmd.buttons & BT_CROUCH) != 0;
		if (click && !mPrevClick) mVal[mField] = 0.0;
		mPrevClick = click;

		bool swap = (players[mPlayer].cmd.buttons & BT_ATTACK) != 0;
		if (swap && !mPrevSwap)
		{
			Save();
			mRightHand = !mRightHand;
			if (mWeaponMode && !FindHeldWeapon())
			{
				mRightHand = !mRightHand;      // nothing in that hand; stay where we were
				Say(String.Format("\cgFit mode: nothing is drawn in the other hand."));
			}
			else
			{
				Load();
				Say(String.Format("\ccFit mode: %s hand%s.", mRightHand ? "right" : "left",
					mWeaponMode ? (", " .. mWpnClass) : ""));
			}
		}
		mPrevSwap = swap;

		// Written every tic, so the hand moves while the stick is being pushed. The engine
		// reads this cvar where it forms the hand target, so there is no second copy of
		// these numbers anywhere.
		Save();
	}

	//==========================================================================
	//
	// the readout
	//
	// ON THE SCREEN, because the person doing this is in a headset and cannot see a console,
	// scroll back, or read anything he did not cause to appear in front of him.
	//
	//==========================================================================

	override void RenderOverlay(RenderEvent e)
	{
		if (!Active() || mPlayer != consoleplayer) return;

		if (mMode == 2)
		{
			Screen.DrawText(smallfont, Font.CR_GOLD, 8, 8, "BODY FIT",
				DTA_VirtualWidth, 640, DTA_VirtualHeight, 400);
			Screen.DrawText(smallfont, Font.CR_WHITE, 8, 22,
				"stand straight, both arms straight out to the sides",
				DTA_VirtualWidth, 640, DTA_VirtualHeight, 400);
			Screen.DrawText(smallfont, mBodyHeld > 0 ? Font.CR_GREEN : Font.CR_GREY, 8, 34,
				mBodyHeld > 0
					? String.Format("hold the trigger... %d", 35 - mBodyHeld)
					: "then hold the trigger for a second",
				DTA_VirtualWidth, 640, DTA_VirtualHeight, 400);
			return;
		}

		Screen.DrawText(smallfont, Font.CR_GOLD, 8, 8,
			String.Format("FIT  %s  %s hand", mWeaponMode ? mWpnClass : mAvatar,
				mRightHand ? "RIGHT" : "LEFT"),
			DTA_VirtualWidth, 640, DTA_VirtualHeight, 400);

		static const string names[] = { "x", "y", "z", "pitch", "yaw", "roll", "scale" };
		int nfields = mWeaponMode ? FIELDS : 6;
		for (int i = 0; i < nfields; i++)
		{
			string row = String.Format("%s %s  %.3f", (i == mField) ? ">" : " ",
				names[i], mVal[i]);
			Screen.DrawText(smallfont, (i == mField) ? Font.CR_WHITE : Font.CR_GREY,
				8, 22 + i * 10, row, DTA_VirtualWidth, 640, DTA_VirtualHeight, 400);
		}

		Screen.DrawText(smallfont, Font.CR_DARKGRAY, 8, 100,
			"turn stick: field   move stick: adjust   crouch: zero   fire: other hand",
			DTA_VirtualWidth, 640, DTA_VirtualHeight, 400);

		// WHERE THE SHOTS ACTUALLY GO.
		//
		// Aligning a weapon so it looks right in the hand is not the same as aligning it so
		// the barrel points where the bullets come out, and the second is the one that
		// matters. The playsim fires from AttackPos along AttackAngle whatever the model is
		// doing, so that line is drawn while fitting and the player lines the barrel up
		// with it. Without it this is guesswork that feels like precision.
		if (mWeaponMode)
		{
			Screen.DrawText(smallfont, Font.CR_ORANGE, 8, 88,
				"the line is where shots go -- point the barrel down it",
				DTA_VirtualWidth, 640, DTA_VirtualHeight, 400);
		}
	}

	//==========================================================================
	//
	// vr_fitmode hand | off   (KEYCONF turns these into net events)
	//
	//==========================================================================

	override void NetworkProcess(ConsoleEvent e)
	{
		if (e.Name == "rsa_fit_hand") Begin(e.Player, 0);
		else if (e.Name == "rsa_fit_weapon") Begin(e.Player, 1);
		else if (e.Name == "rsa_fit_body") Begin(e.Player, 2);
		else if (e.Name == "rsa_fit_off" && e.Player == mPlayer) Finish();
	}
}

// THE BODY HOLSTERS: THE LOOK AND THE FEEL (first build, 2026-11-12).
//
// This machine's own player only. Drawing, pulses and sounds: nothing here is read by the game's
// rules, so it may use consoleplayer. It writes nothing to the sim. It is registered AFTER RAG_Rules
// (MAPINFO.txt), so in one tic it sees what the rules just did (GEAR_CONTRACT.md section 8, step 3).
//
// What is shown is RSQ TacticalRig's, rule for rule ("rig.zs:N" is rsq_ubqseries/TacticalRig/zscript/
// rsqtr/rig.zs, "Fxx" the item in UZDXREMA docs/plans/holsters/TACTICALRIG_FLOOR.md).
// [GEARFIX 2026-11-13] The owner, in the headset: "get the layout like the tactical rig ... why are then neon and
// brighter than the sun i can't look at them". So the rings are TacticalRig's again, exactly: NOTHING shows until a
// hand comes within 2.5 radii of a spot it could use, the nearest such spot full and the rest at 0.35, 0.35 at the
// edge rising to 0.70 inside (Holster Rings: Hand Nearby, rig.zs RingMode / HandAlpha / RingAlpha, 3370-3398). The
// 11-12 "faintly always" ring (0.25 on every spot, all the time) and its 0.70 edge are gone. And they are drawn
// TRANSLUCENT, not additive: TacticalRig's additive wire was soft on QuestZDoom, but this engine blooms anything
// additive and fullbright (gl_bloom is on by default), so eight additive spheres of three crossing rings read as neon.
// Translucent at the same alpha gives the same colour over a dark wall and never goes past the texture's own colour.
// The wire is culled on its back faces as TacticalRig's was (its MODELDEF has no DONTCULLBACKFACES).
//
//   rings        gun holster = wire sphere, item spot = wire diamond (M1). Blue / magenta idle, green
//                with a hand inside and x1.15 (M2, M3). Red flash refused, white freed, green flash the
//                first time a holster becomes a gun's (D4, D5: the flash only, no picture). Only near a hand (M4-M6).
//   stored guns  exactly what was put there, as the model you hold, by the RAGFIT lump (M12-M15).
//   ammo light   in a full gun holster and at the grenade spot, while its ring shows (M9); round a gun's
//                light, the ammo arc: a thin wire arc as long as the magazine is full (M10, rig.zs:3268-3331).
//   the pouch    its model on the belt and the reserve light on its flap (M18).
//   the grenade  at the buckle while you have one and none is in a hand (M19).
//   pulses, sounds  from the rules' result events (D1, D2).
// Other players' rings, guns and lights are not drawn (S4; drawing their guns is addition 3, not built).

class RAG_Look : EventHandler
{
	const UPM = 34.0;              // map units a metre across the floor (contract section 1)

	// ---- the ring (rig.zs:3376-3398 HandAlpha / RingAlpha, 3358 RING_FAR, 3258 STOWED_SPHERE, 3600-3611) ----
	// [GEARFIX 2026-11-13] TacticalRig's own numbers, Holster Rings: Hand Nearby (its default, CVARINFO.txt:10).
	const RING_INSIDE  = 0.70;     // a hand inside (rig.zs:3381)
	const RING_EDGE    = 0.35;     // a hand at the sphere's edge, falling to nothing at 2.5 radii (rig.zs:3381)
	const RING_REACH   = 2.5;
	const RING_FAR     = 0.35;     // every usable ring but the nearest: this share of the hand's part (rig.zs:3090)
	const STOWED       = 0.40;     // a ring round a drawn item, so the wire does not wash it out (rig.zs:2981, 3298-3303)
	const INSIDE_SIZE  = 1.15;     // a size larger with a hand inside (rig.zs:3326)
	// ---- the rules' flashes (rig.zs:909-916, 2982-2984) ----
	const RULE_ASSIGN  = 1;
	const RULE_REFUSE  = 2;
	const RULE_FREE    = 3;
	const RULE_TICS    = 35;       // the whole show, 1 s
	const RULE_HOLD    = 8;        // tics at full strength before it fades
	// ---- the marker's frames (MODELDEF.gear) ----
	const FRAME_IDLE   = 0;        // blue
	const FRAME_IN     = 1;        // green
	const FRAME_RED    = 2;
	const FRAME_WHITE  = 3;
	const FRAME_UTIL   = 4;        // magenta: an item spot, idle (rig.zs:2975-2980)
	// ---- the ammo light (rig.zs:2985-2988, 3338-3371) ----
	const LIGHT_SIZE   = 0.26;     // of the spot's radius
	const LIGHT_EMPTY  = 0.18;     // the red one is smaller
	const PULSE_TICS   = 35;       // and swells and fades once a second
	// ---- the ammo arc (rig.zs:3268-3331 DrawAmmoArc, AmmoFrac, ArcStep) ----
	const ARC_R        = 0.40;     // the arc's radius, in holster radii (the light is 0.26, the ring 1.0)
	const ARC_STEPS    = 12;
	// ---- the pouch and the grenade (rig.zs:3516, 3572) ----
	const POUCH_LIGHT_M = 0.011;   // the light on the pouch's flap, radius in metres
	const NADE_M       = 0.13;     // the grenade's height on the belt, metres
	const SQUAT_M      = 0.25;     // a squat stored gun is never longer than this (rig.zs:4087-4089)

	// per spot, this machine's own player
	transient Array<RAG_Shell> shells;
	transient Array<RAG_Gun> guns;
	transient Array<RAG_Light> lights;
	transient Array<RAG_Arc> arcs;
	transient Array<RAG_Pouch> pouches;
	transient Array<RAG_Nade> nades;
	transient Array<int> ruleTic;      // level.maptime + 1 when a flash started, 0 none (rig.zs:917)
	transient Array<int> ruleKind;
	transient Array<int> pressHand;    // the hand of the last press event at this spot, and its tic
	transient Array<int> pressTic;
	transient Array<int> acts;         // [hand * spots + spot]: 1 = a press by that hand there would do something
	transient int nearSpot0, nearSpot1; // the nearest of those to each hand, -1 none

	transient RAG_Fit fit;
	transient bool fitLoaded;

	// [LAGD] the stick turn as last tic's WorldTick saw it, for the props' ride (Ride, below)
	transient double rideLastTurn;
	transient bool rideHave;
	const RIDE_MAX_TURN = 15.0;    // degrees in one tic: more is a snap or a reset, which is not extrapolated

	// events
	transient int lastSeq;
	transient bool seqInit;
	transient Array<int> seenTic;      // (tic, key) already played: a predicted tic may post an event twice
	transient Array<int> seenKey;
	// queued pulses
	transient Array<int> qHand;
	transient Array<int> qAt;
	transient Array<int> qTics;
	transient Array<double> qAmp;

	// rig.zs:2988 (EmptyPulse): smooth, never off: 0.25 .. 1 of its alpha.
	static double EmptyPulse()
	{
		return 0.625 + 0.375 * cos(level.maptime * 360.0 / PULSE_TICS);
	}

	// M5 (rig.zs:3098-3105, HandAlpha, the Hand Nearby rule): how bright one hand makes one ring.
	static double HandAlpha(double d, double rad, bool inside)
	{
		if (d >= rad * RING_REACH) return 0;
		if (inside) return RING_INSIDE;
		return RING_EDGE * (1.0 - (d - rad) / (rad * (RING_REACH - 1.0)));
	}

	// rig.zs:929-936 (RuleFade): how strong the flash at spot s is now: 1 at the start, fading to 0.
	private double RuleFade(int s)
	{
		if (ruleTic[s] <= 0) return 0;
		int age = level.maptime + 1 - ruleTic[s];
		if (age < 0 || age >= RULE_TICS) { ruleTic[s] = 0; return 0; }
		return age < RULE_HOLD ? 1.0 : 1.0 - double(age - RULE_HOLD) / double(RULE_TICS - RULE_HOLD);
	}

	// rig.zs:921-928 (ShowRule)
	private void ShowRule(int s, int kind)
	{
		if (s < 0 || s >= ruleTic.Size()) return;
		ruleTic[s] = level.maptime + 1;
		ruleKind[s] = kind;
	}

	// ---------------------------------------------------------------- pulses and sounds

	// D1 (rig.zs:860-879; TacticalRig body.zs:780-807): one feel per thing that happens. The pattern is
	// the VRGEAR lump's `feel` row: strength, tics, the gap before the next pulse.
	private void Feel(Name pattern, int hand)
	{
		int cnt = VRGear.FeelLength(pattern);
		int at = level.maptime;
		for (int i = 0; i < cnt; i++)
		{
			bool ok; double amp; int tics, gap;
			[ok, amp, tics, gap] = VRGear.FeelPulse(pattern, i);
			if (!ok) break;
			qHand.Push(hand);
			qAt.Push(at);
			qAmp.Push(clamp(amp, 0.05, 1.0));           // body.zs:806
			qTics.Push(clamp(tics, 1, 16));             // body.zs:807
			at += tics + gap;
		}
	}

	private void PlayPulses()
	{
		int now = level.maptime;
		for (int i = qAt.Size() - 1; i >= 0; i--)
		{
			if (qAt[i] > now) continue;
			// a tic is 1000 / 35 ms
			level.VRHapticEx(qHand[i], qAmp[i], qTics[i] * 1000.0 / 35.0, 0, 1);
			qHand.Delete(i);
			qAt.Delete(i);
			qAmp.Delete(i);
			qTics.Delete(i);
		}
	}

	// D2 (TacticalRig SNDINFO.txt:2-8; rig.zs:1133, 1266, 1275): local, on the presser's machine only.
	// VRGear.SoundOf gives the sound's NAME from the lump's `sound` row ("" if there is no row).
	private void PlaySnd(PlayerPawn pawn, Name which)
	{
		String snd = VRGear.SoundOf(which);
		if (snd == "") return;
		pawn.A_StartSound(snd, CHAN_AUTO, CHANF_LOCAL, 0.8);
	}

	// The hand to pulse for a result at `spot`: the hand that PRESSED there this tic (TacticalRig pulses
	// the pressing hand, rig.zs:2749, even when the grenade goes to the other one), else the event's hand.
	private int FeelHand(int spot, int evHand, int evTic)
	{
		if (spot >= 0 && spot < pressTic.Size() && pressTic[spot] == evTic && pressHand[spot] >= 0) return pressHand[spot];
		return evHand;
	}

	// Contract section 6: this machine's own player's events since last tic.
	private void ReadEvents(int me, PlayerPawn pawn, int n)
	{
		int seq = VRGear.EventSeq(me);
		// a new map or a loaded save: start at what has already happened; play nothing old
		if (!seqInit || seq < lastSeq) { lastSeq = seq; seqInit = true; }
		if (seq - lastSeq > 64) lastSeq = seq - 64;
		for (; lastSeq < seq; lastSeq++)
		{
			bool ok; int kind, hand, spot, arg, tic; Name cls;
			[ok, kind, hand, spot, cls, arg, tic] = VRGear.Event(me, lastSeq);
			if (!ok) continue;
			if (hand < 0 || hand > 1 || spot < 0 || spot >= n) continue;
			// a repeat of (tic, kind, hand, spot) is dropped
			int key = (kind * 2 + hand) * 64 + spot;
			bool seen = false;
			for (int k = 0; k < seenKey.Size(); k++)
				if (seenKey[k] == key && seenTic[k] == tic) { seen = true; break; }
			if (seen) continue;
			seenKey.Push(key);
			seenTic.Push(tic);
			if (seenKey.Size() > 32) { seenKey.Delete(0); seenTic.Delete(0); }

			int fh = FeelHand(spot, hand, tic);
			switch (kind)
			{
			case VRGear.EV_ENTER:                         // K6 (rig.zs:2172): one short light pulse
				Feel('enter', hand);
				break;
			case VRGear.EV_PRESS:                         // nothing to play; remembered for FeelHand
				pressHand[spot] = hand;
				pressTic[spot] = tic;
				break;
			case VRGear.EV_STORED:                        // rig.zs:871, 1921
				Feel('store', fh);
				PlaySnd(pawn, 'store');
				break;
			case VRGear.EV_DRAWN:                         // rig.zs:870, 1957
				Feel('draw', fh);
				PlaySnd(pawn, 'draw');
				break;
			case VRGear.EV_SWAPPED:                       // rig.zs:1908-1921: the store pulse, both sounds
				Feel('store', fh);
				PlaySnd(pawn, 'draw');
				PlaySnd(pawn, 'store');
				break;
			case VRGear.EV_WENT_HOME:                     // rig.zs:1862-1880: the store; the draw sound too if a gun came out
				Feel('store', fh);
				if (VRGear.DrawTic(me, 0) == level.maptime || VRGear.DrawTic(me, 1) == level.maptime) PlaySnd(pawn, 'draw');
				PlaySnd(pawn, 'store');
				break;
			case VRGear.EV_ASSIGNED:                      // D5 (rig.zs:843, 905-906): the ring flashes bright
				ShowRule(spot, RULE_ASSIGN);
				break;
			case VRGear.EV_FREED:                         // K10 (rig.zs:2337-2339): white flash, the store pulse
				ShowRule(spot, RULE_FREE);
				Feel('store', hand);
				break;
			case VRGear.EV_REFUSED:                       // D1, D4 (rig.zs:850-859, 873-879): double pulse, use-fail, red
				Feel('refuse', fh);
				PlaySnd(pawn, 'refuse');
				// [REVIEW W2] red only when a GUN may not enter (rig.zs:850-859). An empty hand at an empty holster and
				// "no grenades" get the double pulse and the sound only (rig.zs:2752, 2870, 2886-2890).
				if (arg == 1 || arg == 2 || arg == 5) ShowRule(spot, RULE_REFUSE);
				break;
			}
		}
	}

	// ---------------------------------------------------------------- what is drawn

	private void HideSpot(int s)
	{
		if (shells[s] != null) shells[s].Hide();
		if (guns[s] != null) guns[s].Hide();
		if (lights[s] != null) lights[s].Hide();
		if (arcs[s] != null) arcs[s].bInvisible = true;
		if (pouches[s] != null) pouches[s].bInvisible = true;
		if (nades[s] != null) nades[s].bInvisible = true;
	}

	// K1, O17 (rig.zs:2101-2106, HideAll rig.zs:3637): the rig stands down, everything hidden.
	private void HideAll()
	{
		for (int s = 0; s < shells.Size(); s++) HideSpot(s);
	}

	// M6 (rig.zs:3198-3262, ClutterPass): once a tic, before any ring is drawn: what each hand can act on,
	// and the nearest of those to each hand.
	private int ClutterHand(int me, PlayerPawn pawn, int n, int h, bool valid, Vector3 hp)
	{
		int nearest = -1;
		double best = 1e9;
		for (int s = 0; s < n; s++)
		{
			acts[h * n + s] = 0;
			if (!valid) continue;
			bool ok; Vector3 at; double rad;
			[ok, at, rad] = VRGear.SpotPose(me, s);
			if (!ok || !RAG_Rules.HandActs(me, pawn, h, s)) continue;
			acts[h * n + s] = 1;
			double d = VRGear.RoomMetres(hp, at);
			if (d < best) { best = d; nearest = s; }
		}
		return nearest;
	}

	// One hand's part of one ring: rules 1 and 2 of rig.zs:3068-3121 (RingAlpha rig.zs:3107-3121).
	private double RingPart(int n, int s, int h, bool valid, Vector3 hp, Vector3 at, double rad, bool inside, int nearest)
	{
		if (!valid || acts[h * n + s] == 0) return 0;
		double ah = HandAlpha(VRGear.RoomMetres(hp, at), rad, inside);
		if (nearest != s) ah *= RING_FAR;
		return ah;
	}

	private int recSeen;             // [REVIEW W3] the last VRTorso.RecenterCount seen
	private bool recPrimed;          // false until the first tic, so a count carried in by a load does not click

	// M10 (rig.zs:3268-3285, AmmoFrac / ArcStep): how full a gun's magazine is (its ammo for a gun without one), in
	// twelfths: 0 only when empty, 12 only when full.
	static double AmmoFrac(Weapon w)
	{
		if (w == null || w.Ammo1 == null) return -1;
		bool mag = w.Ammo2 != null && w.Ammo2 != w.Ammo1;
		Inventory lo = mag ? w.Ammo2 : w.Ammo1;
		return clamp(double(lo.Amount) / max(1, lo.MaxAmount), 0.0, 1.0);
	}
	static int ArcStep(double f)
	{
		if (f <= 0) return 0;
		if (f >= 1) return ARC_STEPS;
		return clamp(int(round(f * ARC_STEPS)), 1, ARC_STEPS - 1);
	}

	// M10 (rig.zs:3286-3331, DrawAmmoArc): the arc shows exactly when a gun holster's light shows green or yellow,
	// at the light's alpha, turned to the eyes and upright as you see it.
	private void DrawArc(PlayerInfo p, PlayerPawn pawn, int s, Vector3 at, double rad, Weapon pw, double ps)
	{
		let q = lights[s];
		double f = (pw != null && q != null && !q.bInvisible) ? AmmoFrac(pw) : -1;
		int step = f >= 0 ? ArcStep(f) : 0;
		bool show = f >= 0 && step > 0 && (q.frame == 0 || q.frame == 1);
		if (!show) { if (arcs[s] != null) arcs[s].bInvisible = true; return; }
		bool fresh = arcs[s] == null;
		if (fresh) arcs[s] = RAG_Arc(Actor.SpawnClientSide('RAG_Arc', at, NO_REPLACE));
		let c = arcs[s];
		if (c == null) return;
		// the eyes: the sim's head (the latched headset), else the view
		int hv; Vector3 eye;
		[hv, eye] = p.GetVRHead();
		if (hv == 0) eye = (pawn.pos.xy, p.viewz);
		double ha = pawn.angle, hpi = pawn.pitch;
		Vector3 hu = (sin(hpi) * cos(ha), sin(hpi) * sin(ha), cos(hpi));
		Vector3 d = eye - at;
		double yaw = atan2(d.y, d.x);
		double pit = -atan2(d.z * ps, max(0.001, d.xy.Length()));
		Vector3 nrm = (cos(pit) * cos(yaw), cos(pit) * sin(yaw), -sin(pit));
		Vector3 u0 = (sin(pit) * cos(yaw), sin(pit) * sin(yaw), cos(pit));
		Vector3 up = hu - nrm * (hu dot nrm);
		double rl = 0;
		if (up.Length() > 0.01) { up = up.Unit(); rl = atan2((u0 cross up) dot nrm, u0 dot up); }   // RULE_ROLL_SIGN 1 (rig.zs:1123)
		c.SetOrigin(at, true);
		c.Angle = yaw; c.Pitch = pit; c.Roll = rl;
		if (fresh) c.ClearInterpolation();
		c.frame = (q.frame == 1 ? ARC_STEPS : 0) + step - 1;     // MODELDEF.gear: A-L green, M-X yellow
		double sc = ARC_R * rad * UPM;
		c.Scale = (sc, sc);
		c.Alpha = q.Alpha;
		c.bInvisible = false;
	}

	// [LAGD] A spot's DRAWN place: turned about the pawn by `turn` degrees, then carried by `move`.
	static Vector3 Ride(Vector3 at, Vector2 pivot, double turn, Vector2 move)
	{
		Vector2 r = Actor.RotateVector(at.xy - pivot, turn);
		Vector2 p2 = pivot + r + move;
		Vector3 o = (p2, at.z);
		return o;
	}

	override void WorldTick()
	{
		int n = VRGear.SpotCount();
		if (n <= 0) return;
		while (shells.Size() < n)
		{
			shells.Push(null);
			guns.Push(null);
			lights.Push(null);
			arcs.Push(null);
			pouches.Push(null);
			nades.Push(null);
			ruleTic.Push(0);
			ruleKind.Push(0);
			pressHand.Push(-1);
			pressTic.Push(-1);
		}
		while (acts.Size() < n * 2) acts.Push(0);
		if (!fitLoaded) { fitLoaded = true; fit = RAG_Fit.Load(); }

		int me = consoleplayer;
		if (me < 0 || me >= MAXPLAYERS || !playeringame[me] || players[me].mo == null) { HideAll(); return; }
		PlayerPawn pawn = players[me].mo;
		PlayerInfo p = players[me];

		ReadEvents(me, pawn, n);
		PlayPulses();

		// K1, O17 (rig.zs:2101-2106): dead, or no headset pose has ever arrived: nothing is shown.
		if (pawn.health <= 0 || !VRTorso.Valid(me)) { HideAll(); return; }

		// [REVIEW W3] K19 (rig.zs:2582-2593): the torso was recentred by both hands at the chest: a click and a
		// short pulse in both hands, so he knows it fired.
		int rc = VRTorso.RecenterCount(me);
		if (recPrimed && rc != recSeen)
		{
			pawn.A_StartSound("switches/normbutn", CHAN_AUTO, CHANF_LOCAL, 0.3);
			level.VRHapticEx(0, 0.3, 3 * 1000.0 / 35.0, 0, 1);
			level.VRHapticEx(1, 0.3, 3 * 1000.0 / 35.0, 0, 1);
		}
		recSeen = rc; recPrimed = true;

		double bodyYaw = VRTorso.Yaw(me);
		bool mainLeft = VRGear.MainLeft(me);

		// [LAGD] THE PROPS RIDE WITH THE DRAWN BODY, NOT ONE TIC BEHIND IT. The spots are the sim's, built in
		// P_PlayerThink from the pawn's place at the START of this tic (p_vrtorso.cpp t.Anchor), and the pawn
		// only moves after this WorldTick (p_tick.cpp: player think, WorldTick, then the thinkers). The camera
		// is drawn from the pawn's tic start to its tic end, so props placed on the spots trailed it by one tic
		// of travel. The fix is the one the seated pose makes (vr_body.cpp, the seat point at this frame): carry
		// them by the pawn's coming move, its velocity this tic. And the drawn body turns with the stick turn
		// as the frame has it (vr_rig.cpp [LAGA]), one tic ahead of the sim torso's yaw, so the props are turned
		// about the pawn by the stick turn of the last tic, the same amount again. LOOKS ONLY: the spots the
		// hands are judged against (`at` below, the rings' brightness, the sim) are untouched.
		double turnNow = pawn.VRTurnYaw;
		double rideTurn = 0;
		if (rideHave)
		{
			rideTurn = Actor.deltaangle(rideLastTurn, turnNow);
			if (abs(rideTurn) > RIDE_MAX_TURN) rideTurn = 0;
		}
		rideLastTurn = turnNow;
		rideHave = true;
		Vector2 ridePivot = pawn.pos.xy;
		Vector2 rideMove = pawn.vel.xy;
		// [GEARFIX 2026-11-13] THE VIEW'S LEAN. With the body anchor on, the pawn stands on the room feet and the eyes and
		// the drawn hands are carried off it by the head's lean (up to 0.14 m; the owner's seated log: 0.07 m), while the
		// sim's hands and spots are both measured from the pawn without it. So the hit is right (head-relative, as in
		// TacticalRig) but a ring drawn at the sim's spot sat one lean away from where the drawn hand must go to hit it.
		// Everything drawn at a spot is carried by the same lean (VRTorso.ViewLean: what the renderer adds, else 0).
		Vector2 viewLean = VRTorso.ViewLean();
		rideMove += viewLean;
		double drawYaw = bodyYaw + rideTurn;
		double ps = level.pixelstretch > 0 ? level.pixelstretch : 1.2;

		// the hands (the sim's own latch)
		int hv0 = 0, hv1 = 0;
		Vector3 hp0, hp1;
		double hy, hpi, hr;
		[hv0, hp0, hy, hpi, hr] = p.GetVRHand(0);
		[hv1, hp1, hy, hpi, hr] = p.GetVRHand(1);
		bool ok0 = hv0 != 0, ok1 = hv1 != 0;
		int at0 = VRGear.HandAt(me, 0);
		int at1 = VRGear.HandAt(me, 1);

		nearSpot0 = ClutterHand(me, pawn, n, 0, ok0, hp0);
		nearSpot1 = ClutterHand(me, pawn, n, 1, ok1, hp1);

		for (int s = 0; s < n; s++)
		{
			bool ok; Vector3 at; double rad;
			[ok, at, rad] = VRGear.SpotPose(me, s);
			if (!ok || !VRGear.SpotLive(me, s)) { HideSpot(s); continue; }
			Vector3 dat = Ride(at, ridePivot, rideTurn, rideMove);   // [LAGD] where it is DRAWN

			int rule = VRGear.SpotRule(s);
			bool gunSpot = RAG_Rules.IsGunSpot(s);
			bool in0 = at0 == s, in1 = at1 == s;
			bool inside = in0 || in1;

			// ---- THE RING (M4-M6, rig.zs:3556-3611): TacticalRig's Hand Nearby. Nothing until a hand that could
			// USE this spot comes within 2.5 radii; the nearest such spot to that hand full, the others x0.35;
			// the stronger of the two hands.
			double a = 0;
			a = max(a, RingPart(n, s, 0, ok0, hp0, at, rad, in0, nearSpot0));
			a = max(a, RingPart(n, s, 1, ok1, hp1, at, rad, in1, nearSpot1));
			// M7 (rig.zs:3298-3303): a spot showing its item (last tic's) draws its ring at 0.4, so the item
			// is not washed out. Not the pouch: its sphere is far larger than the pouch and is meant to be seen.
			bool showsItem = rule != VRGear.RULE_ZONE
				&& ((guns[s] != null && !guns[s].bInvisible) || (nades[s] != null && !nades[s].bInvisible));
			if (showsItem) a *= STOWED;
			// D4, D5 (rig.zs:3304-3307): a refusal, a freed holster, a first fit flash the ring
			double rf = RuleFade(s);
			if (rf > 0) a = max(a, rf);

			// M1 (rig.zs:3311-3313): a gun holster is the wire sphere, an item spot the wire diamond
			if (shells[s] == null && a > 0.01)
			{
				if (gunSpot) shells[s] = RAG_Shell(Actor.SpawnClientSide('RAG_Shell', dat, NO_REPLACE));
				else shells[s] = RAG_Shell(Actor.SpawnClientSide('RAG_Diamond', dat, NO_REPLACE));
			}
			// rig.zs:3593-3614: the marker is drawn only while its alpha is above 0.01
			if (shells[s] != null && a <= 0.01) shells[s].Hide();
			else if (shells[s] != null)
			{
				// M3 (rig.zs:3326-3332): the marker's radius is the spot's; x1.15 with a hand inside;
				// x(1 + 0.25 x fade) during a flash. M2 (rig.zs:3327, 3331): the colours.
				double size = rad * UPM * (inside ? INSIDE_SIZE : 1.0);
				int fr = inside ? FRAME_IN : (gunSpot ? FRAME_IDLE : FRAME_UTIL);
				if (rf > 0)
				{
					size *= 1.0 + 0.25 * rf;
					if (ruleKind[s] == RULE_REFUSE) fr = FRAME_RED;
					else if (ruleKind[s] == RULE_FREE) fr = FRAME_WHITE;
					else fr = FRAME_IN;
				}
				shells[s].ShowAt(dat, size, a, fr);
			}

			// ---- THE POUCH (M18, rig.zs:3526-3556): its model facing out, and on its flap a light for the
			// main-hand gun's RESERVE.
			if (rule == VRGear.RULE_ZONE)
			{
				if (pouches[s] == null) pouches[s] = RAG_Pouch(Actor.SpawnClientSide('RAG_Pouch', dat, NO_REPLACE));
				if (pouches[s] != null)
				{
					pouches[s].SetOrigin(dat, true);
					pouches[s].Angle = drawYaw;
					pouches[s].Pitch = 0;
					pouches[s].Roll = 0;
					pouches[s].bInvisible = false;
				}
				int rst = RAG_Rules.ReserveState(p.ReadyWeapon);
				if (rst >= 0)
				{
					// on the flap, at its front top edge: 1.6 cm out, 5.8 cm up (rig.zs:3542-3544)
					Vector3 lp = dat + (cos(drawYaw) * 0.016 * UPM, sin(drawYaw) * 0.016 * UPM, 0.058 * UPM / ps);
					if (lights[s] == null) lights[s] = RAG_Light(Actor.SpawnClientSide('RAG_Light', lp, NO_REPLACE));
					if (lights[s] != null) lights[s].ShowAt(lp, POUCH_LIGHT_M * UPM, 0.95 * (rst == 2 ? EmptyPulse() : 1.0), rst);
				}
				else if (lights[s] != null) lights[s].Hide();
				continue;
			}

			// ---- THE AMMO LIGHT (M9, rig.zs:3338-3358): with the ring showing, a small sphere at the
			// middle of a full gun holster: green, yellow, or red (smaller, pulsing). The grenade spot:
			// green 2 or more, yellow 1, red none.
			Name put = gunSpot ? RAG_Rules.Held(me, pawn, s) : 'None';
			Weapon pw = RAG_Rules.Owned(pawn, put);
			int st = -1;
			if (rule == VRGear.RULE_SUMMON)
			{
				int cnt = RAG_Rules.Grenades(pawn, s);
				st = cnt >= 2 ? 0 : (cnt == 1 ? 1 : 2);
			}
			else if (pw != null) st = RAG_Rules.AmmoState(pw);
			if (st >= 0 && a > 0.01)
			{
				double la = clamp(a + 0.2, 0.0, 1.0);
				if (st == 2) la *= EmptyPulse();
				if (lights[s] == null) lights[s] = RAG_Light(Actor.SpawnClientSide('RAG_Light', dat, NO_REPLACE));
				if (lights[s] != null) lights[s].ShowAt(dat, rad * UPM * (st == 2 ? LIGHT_EMPTY : LIGHT_SIZE), la, st);
			}
			else if (lights[s] != null) lights[s].Hide();
			// M10 (rig.zs:3268-3331, DrawAmmoArc): round a GUN's light, green or yellow, as long as the magazine is full
			DrawArc(p, pawn, s, dat, rad, pw, ps);

			// ---- THE GRENADE AT THE BUCKLE (M19, rig.zs:3582-3595): while there is one and none is in a hand.
			if (rule == VRGear.RULE_SUMMON)
			{
				if (RAG_Rules.Grenades(pawn, s) > 0 && !RAG_Rules.NadeInHand(pawn, s))
				{
					if (nades[s] == null) nades[s] = RAG_Nade(Actor.SpawnClientSide('RAG_Nade', dat, NO_REPLACE));
					if (nades[s] != null) nades[s].Show(dat, drawYaw, NADE_M, RAG_Rules.NadeAmmo(s));
				}
				else if (nades[s] != null) nades[s].bInvisible = true;
				continue;
			}

			// ---- THE STORED GUN (M12, rig.zs:3375-3385, 3405-3422): exactly what was put there; hidden
			// while that gun is in either hand; ONLY a gun in the fit table is drawn.
			String shown = "";
			if (put != 'None')
			{
				shown = put;
				if (p.ReadyWeapon != null && RAG_Rules.HeldAs(pawn, p.ReadyWeapon) == put) shown = "";
				else if (p.OffhandWeapon != null && p.OffhandWeapon.GetClassName() == put) shown = "";
			}
			int row = (shown != "" && fit != null) ? fit.Find(shown) : -1;
			if (row >= 0)
			{
				// M12 (rig.zs:3411-3415): 0.25 m on the body, 0.70 m on the back: the spot's `length`.
				double metres = VRGear.SpotLength(s);
				// M13 (rig.zs:3605-3620, Hang): the spot's `hang`, mirrored for a left-handed layout.
				Vector3 hang = VRGear.SpotHang(s);
				double off = hang.X, pt = hang.Y, rl = hang.Z;
				if (mainLeft) { off = -off; rl = -rl; }
				// M14 (rig.zs:3625-3635, ShowAt): the spot's `show`: this far behind it and this share of
				// the gun's length below it, so the butt, not the middle, is where the hand reaches.
				Vector2 showBy = VRGear.SpotShow(s);
				Vector3 gunAt = dat - (cos(drawYaw) * showBy.X * UPM, sin(drawYaw) * showBy.X * UPM, showBy.Y * metres * UPM / ps);
				if (guns[s] == null) guns[s] = RAG_Gun(Actor.SpawnClientSide('RAG_Gun', gunAt, NO_REPLACE));
				if (guns[s] != null) guns[s].Show(shown, fit, row, gunAt, metres, drawYaw + off, pt, rl);
			}
			else if (guns[s] != null) guns[s].Hide();
		}
	}
}

// HOW BIG A STORED GUN IS AND WHICH WAY IT POINTS (the RAGFIT lump). RSQ TacticalRig's fit loader
// (rsq_ubqseries/TacticalRig/zscript/rsqtr/fit.zs:17-107: Load, Find, Compose, Basis), ported with its
// lump format unchanged:
//     <Class> <length in map units> <yaw> <pitch> <shown by> <centre x y z> <squat> <sprite> <frame>
// Every lump named RAGFIT is read; a later row wins for the same class. Drawing only.
class RAG_Fit
{
	Array<String> cls, holder, spr;
	Array<int> frn;
	Array<double> len, yaw, pitch, cx, cy, cz, squat;

	static RAG_Fit Load()
	{
		let f = new("RAG_Fit");
		int l = -1;
		while ((l = Wads.FindLump("RAGFIT", l + 1, Wads.AnyNamespace)) >= 0)
		{
			Array<String> lines;
			Wads.ReadLump(l).Split(lines, "\n");
			for (int i = 0; i < lines.Size(); i++)
			{
				String s = lines[i];
				s.StripRight();
				if (s.Length() == 0 || s.Left(2) == "//") continue;
				Array<String> t;
				s.Split(t, " ", TOK_SKIPEMPTY);
				if (t.Size() < 4) continue;
				String c = t[0];
				c = c.MakeLower();
				int at = f.cls.Find(c);
				if (at == f.cls.Size()) { f.cls.Push(c); f.len.Push(0); f.yaw.Push(0); f.pitch.Push(0); f.holder.Push(t[0]); f.cx.Push(0); f.cy.Push(0); f.cz.Push(0); f.squat.Push(0); f.spr.Push(""); f.frn.Push(0); }
				f.len[at] = t[1].ToDouble();
				f.yaw[at] = t[2].ToDouble();
				f.pitch[at] = t[3].ToDouble();
				f.holder[at] = t.Size() > 4 ? t[4] : t[0];
				if (t.Size() > 8) f.squat[at] = t[8].ToDouble();
				if (t.Size() > 10) { f.spr[at] = t[9]; f.frn[at] = t[10].ToInt(); }
				if (t.Size() > 7) { f.cx[at] = t[5].ToDouble(); f.cy[at] = t[6].ToDouble(); f.cz[at] = t[7].ToDouble(); }
			}
		}
		return f;
	}

	Vector3 Centre(int at) { return (cx[at], cy[at], cz[at]); }

	int Find(String c)
	{
		c = c.MakeLower();
		int at = cls.Find(c);
		return at < cls.Size() && len[at] > 0 ? at : -1;
	}

	// The actor angles that hang a measured gun as (a, p, r) hangs one pointing forward:
	// R = R(a, p, r) * Ry(pitch) * Rz(yaw), read back as angle, pitch, roll (the engine
	// turns a model by roll about its forward axis, then pitch, then yaw).
	static void Compose(double a, double p, double r, double cy, double cp,
		out double oa, out double op, out double orl)
	{
		// columns of R(a,p,r): forward, left, up
		Vector3 F, L, U;
		[F, L, U] = Basis(a, p, r);
		// the correction's columns in that frame: Ry(cp) * Rz(cy)
		Vector3 f2 = (cos(cy) * cos(cp), sin(cy), -cos(cy) * sin(cp));
		Vector3 l2 = (-sin(cy) * cos(cp), cos(cy), sin(cy) * sin(cp));
		Vector3 nF = F * f2.x + L * f2.y + U * f2.z;
		Vector3 nL = F * l2.x + L * l2.y + U * l2.z;
		oa = atan2(nF.y, nF.x);
		op = -asin(clamp(nF.z, -1.0, 1.0));
		// roll: the new left measured against the left of (oa, op) with no roll
		Vector3 F0, L0, U0;
		[F0, L0, U0] = Basis(oa, op, 0);
		orl = atan2(nL dot U0, nL dot L0);
	}

	// Forward, left and up of a body turned by yaw a (left +), pitch p (nose down +), roll r.
	static Vector3, Vector3, Vector3 Basis(double a, double p, double r)
	{
		double ca = cos(a), sa = sin(a), cp = cos(p), sp = sin(p), cr = cos(r), sr = sin(r);
		Vector3 F = (ca * cp, sa * cp, -sp);
		Vector3 L0 = (-sa, ca, 0);
		Vector3 U0 = (ca * sp, sa * sp, cp);
		Vector3 L = L0 * cr + U0 * sr;
		Vector3 U = U0 * cr - L0 * sr;
		return F, L, U;
	}
}

// A GUN HOLSTER'S MARKER: a wire sphere of radius 1 (MODELDEF.gear); the actor's Scale is the spot's
// radius in map units (TacticalRig's RSQTR_Marker, rig.zs:4215-4223). Fullbright as TacticalRig's; TRANSLUCENT,
// not TacticalRig's additive ([GEARFIX 2026-11-13]: additive blooms to neon in this engine, see the top). No angle:
// a sphere reads the same from every side.
class RAG_Shell : Actor
{
	Default
	{
		+CLIENTSIDE
		+NOBLOCKMAP
		+NOGRAVITY
		+NOINTERACTION
		+DONTSPLASH
		+NOTONAUTOMAP
		+BRIGHT
		RenderStyle "Translucent";
		Radius 1;
		Height 1;
	}

	void Hide()
	{
		bInvisible = true;
	}

	// size: the marker's radius in map units. look: the frame (RAG_Look.FRAME_*).
	void ShowAt(Vector3 pos, double size, double glow, int look)
	{
		bInvisible = false;
		SetOrigin(pos, true);
		Scale = (size, size);
		Alpha = clamp(glow, 0.0, 1.0);
		frame = look;
	}

	States
	{
	Spawn:
		RAGS A -1;
		Stop;
	}
}

// AN ITEM SPOT'S MARKER (M1, rig.zs:3949-3952): a wire DIAMOND, so it is not told from a gun holster
// by colour alone. Its own class because a model definition binds to the class exactly.
class RAG_Diamond : RAG_Shell
{
}

// THE AMMO LIGHT (TacticalRig's RSQTR_AmmoPip, rig.zs:4185-4192). Frame 0 green, 1 yellow, 2 red. Translucent,
// as the rings ([GEARFIX 2026-11-13]).
class RAG_Light : Actor
{
	Default
	{
		+CLIENTSIDE
		+NOBLOCKMAP
		+NOGRAVITY
		+NOINTERACTION
		+DONTSPLASH
		+NOTONAUTOMAP
		+BRIGHT
		RenderStyle "Translucent";
		Radius 1;
		Height 1;
	}

	void Hide()
	{
		bInvisible = true;
	}

	void ShowAt(Vector3 pos, double size, double glow, int look)
	{
		bInvisible = false;
		SetOrigin(pos, true);
		Scale = (size, size);
		Alpha = clamp(glow, 0.0, 1.0);
		frame = look;
	}

	States
	{
	Spawn:
		RAGS A -1;
		Stop;
	}
}

// THE AMMO ARC (TacticalRig's RSQTR_AmmoArc, rig.zs:4194-4197; MODELDEF.gear RAG_Arc): frames A-L green, M-X yellow,
// fill steps 1-12. Turned to the eyes by its angle, pitch and roll. Translucent, as the rings.
class RAG_Arc : Actor
{
	Default
	{
		+CLIENTSIDE
		+NOBLOCKMAP
		+NOGRAVITY
		+NOINTERACTION
		+DONTSPLASH
		+NOTONAUTOMAP
		+BRIGHT
		RenderStyle "Translucent";
		Radius 1;
		Height 1;
	}

	States
	{
	Spawn:
		RAGA A -1;
		Stop;
	}
}

// THE POUCH ON THE BELT (TacticalRig's RSQTR_PouchShow, rig.zs:3896-3905): its mesh, centred, facing
// out from the body.
class RAG_Pouch : Actor
{
	Default
	{
		+CLIENTSIDE
		+NOBLOCKMAP
		+NOGRAVITY
		+NOINTERACTION
		+DONTSPLASH
		+NOTONAUTOMAP
		Radius 1;
		Height 1;
	}

	States
	{
	Spawn:
		RAGN A -1;
		Stop;
	}
}

// THE GRENADE IN ITS SPOT (TacticalRig's RSQTR_NadeShow, rig.zs:3815-3893). The mesh by name, first
// found: the BD22 VR pack's grenade (models/bd/Grenade/nade.md3), else RSQ Grenade's
// (models/rsqgn/nade.md3), else the grenade ammo's own pickup sprite. Its own model (MODELDEF.gear:
// the wire sphere with an invisible skin) is only a carrier: A_ChangeModel swaps the mesh and skin in
// by path, so nothing is linked and a missing pk3 only means the next choice.
class RAG_Nade : Actor
{
	int how;                        // 0 not chosen yet, 1 the BD22 VR pack's mesh, 2 RSQ Grenade's, 3 a sprite, 4 nothing
	double sprH;                    // the sprite's height in pixels (3)
	const BODY_H = 17.01;           // the mesh's body height in model units, frame 2 (rig.zs:3826)
	const TILT = 35;                // degrees the top leans away from you (rig.zs:3827)

	Default
	{
		+CLIENTSIDE
		+NOBLOCKMAP
		+NOGRAVITY
		+NOINTERACTION
		+DONTSPLASH
		+NOTONAUTOMAP
		+BRIGHT
		Radius 1;
		Height 1;
	}

	States
	{
	Spawn:
		RAGN A -1;
		Stop;
	}

	// rig.zs:3834-3868 (Choose)
	private void Choose(Name ammo)
	{
		if (Wads.CheckNumForFullName("models/bd/Grenade/nade.md3") >= 0 && Wads.CheckNumForFullName("models/bd/Grenade/nade.png") >= 0)
		{
			A_ChangeModel(GetClassName(), 0, "models/bd/Grenade", 'nade.md3', 0, "models/bd/Grenade", 'nade.png');
			SetModelFlag(MDL_USEACTORPITCH);
			how = 1;
			return;
		}
		if (Wads.CheckNumForFullName("models/rsqgn/nade.md3") >= 0 && Wads.CheckNumForFullName("models/rsqgn/nade.png") >= 0)
		{
			A_ChangeModel(GetClassName(), 0, "models/rsqgn", 'nade.md3', 0, "models/rsqgn", 'nade.png');
			SetModelFlag(MDL_USEACTORPITCH);
			how = 2;
			return;
		}
		// no mesh: the ammo's pickup sprite, the first visible frame of its Spawn state
		class<Actor> c = (class<Actor>)(ammo);
		State st = null;
		if (c != null)
		{
			let d = GetDefaultByType(c);
			if (d != null) st = d.SpawnState;
		}
		int tnt = GetSpriteIndex('TNT1');
		for (int i = 0; i < 16 && st != null && st.sprite == tnt; i++) st = st.NextState;
		if (st != null && st.sprite != tnt)
		{
			sprite = st.sprite;
			frame = st.Frame;
			TextureID tx; bool flip; Vector2 tsc;
			[tx, flip, tsc] = st.GetSpriteTexture(0);
			int w, h;
			[w, h] = TexMan.GetSize(tx);
			sprH = max(1, h);
			how = 3;
			return;
		}
		how = 4;
	}

	// rig.zs:3869-3893 (Show)
	void Show(Vector3 at, double yaw, double metres, Name ammo)
	{
		if (how == 0) Choose(ammo);
		if (how == 4) { bInvisible = true; return; }
		if (how == 3)
		{
			double s = metres * RAG_Look.UPM / sprH;
			Scale = (s, s);
			SetOrigin(at - (0, 0, metres * RAG_Look.UPM * 0.5), true);   // a sprite stands on its origin
		}
		else
		{
			double s = metres * RAG_Look.UPM / BODY_H;
			Scale = (s, s);
			SetOrigin(at, true);                                          // centred by MODELDEF
			// ring and spoon toward you, its top leaning out from the belt: looking down at the buckle
			// you see its side, not just its top
			Angle = yaw + 180;
			Pitch = TILT;
		}
		bInvisible = false;
	}
}

// A STORED GUN (TacticalRig's RSQTR_Icon, rig.zs:4007-4105): the model you hold, by its RAGFIT row:
// the frame the row names, drawn by the class the row names, sized to `metres` by its measured length,
// turned by its measured yaw and pitch, and moved so its measured middle is on the spot. Solid.
// A gun with no row is not drawn (the look never calls Show for it).
class RAG_Gun : Actor
{
	String wearing;        // the weapon class shown
	bool usable;           // its row's holder class and sprite exist in this game

	Default
	{
		+CLIENTSIDE
		+NOBLOCKMAP
		+NOGRAVITY
		+NOINTERACTION
		+DONTSPLASH
		+NOTONAUTOMAP
		+BRIGHT
		Radius 1;
		Height 1;
	}

	States
	{
	Spawn:
		TNT1 A -1;
		Stop;
	}

	void Hide()
	{
		bInvisible = true;
	}

	// cls: the weapon class. row: its RAGFIT row (>= 0). at: where its middle goes. metres: its length.
	// (a, p, r): how it hangs: yaw, pitch nose-down, roll.
	void Show(String cls, RAG_Fit fit, int row, Vector3 at, double metres, double a, double p, double r)
	{
		if (cls != wearing)
		{
			// rig.zs:4037-4046 (Wear, the measured branch)
			wearing = cls;
			usable = false;
			class<Actor> hc = fit.holder[row];
			int si = GetSpriteIndex(Name(fit.spr[row]));
			if (fit.spr[row] != "" && hc != null && si >= 0)
			{
				usable = true;
				sprite = si;
				frame = fit.frn[row];
				A_ChangeModel(Name(fit.holder[row]));
				SetModelFlag(MDL_USEACTORPITCH | MDL_USEACTORROLL);
			}
		}
		if (!usable) { bInvisible = true; return; }
		bInvisible = false;
		// rig.zs:4087-4089: a squat thing (a missile pod, a box) never grows past a pistol's size
		if (fit.squat[row] > 0.7) metres = min(metres, RAG_Look.SQUAT_M);
		// rig.zs:4090-4091
		double s = metres * RAG_Look.UPM / fit.len[row];
		Scale = (s, s);
		// rig.zs:4093-4097
		double oa, op, orl;
		RAG_Fit.Compose(a, p, r, fit.yaw[row], fit.pitch[row], oa, op, orl);
		Angle = oa;
		Pitch = op;
		Roll = orl;
		// rig.zs:4098-4103: its middle, not its origin, on the spot
		Vector3 F, L, U;
		[F, L, U] = RAG_Fit.Basis(oa, op, orl);
		Vector3 c = fit.Centre(row) * s;
		SetOrigin(at - (F * c.X + L * c.Y + U * c.Z), true);
	}
}

// THE BODY HOLSTERS, RS_Avatar's half (engine core: UZDXREMA src/playsim/p_vrgear.cpp, ZScript
// VRGear; design: docs/plans/BODY_HOLSTERS_DESIGN.md, Phase 1; the rig: VRGEAR.txt).
//
// The engine decides, every tic, on every machine: where the mounts are, which one each hand is at
// or heading for, what a grip press means, when a draw clears. This file does the three things the
// engine leaves to the mod:
//   RAG_Rules  what an action does to the inventory. Play scope, every machine, in order: the same
//              inventory everywhere.
//   RAG_Feel   the haptic signatures and the hum, for this machine's own player only.
//   RAG_Look   the holster shells on your body and the guns in them. Client-side actors only.

// ---------------------------------------------------------------- the rules

class RAG_Rules : EventHandler
{
	// Into a hand at once: the engine's dual-wield routing, with the raise skipped.
	static void ToHand(PlayerPawn pawn, Weapon w, int hand)
	{
		if (pawn == null || w == null) return;
		bool off = hand == 1;
		w.bOffhandWeapon = off;
		if (w.SisterWeapon != null) w.SisterWeapon.bOffhandWeapon = off;
		bool was = (pawn.player.cheats & CF_INSTANTWEAPSWITCH) != 0;
		pawn.player.cheats |= CF_INSTANTWEAPSWITCH;
		pawn.MoveWeaponToHand(w, hand);
		if (!was) pawn.player.cheats &= ~CF_INSTANTWEAPSWITCH;
		if (pawn.player.PendingWeapon != WP_NOCHANGE) pawn.BringUpWeapon();
	}

	// The empty hand to put in this hand. A pack can name several (VRGEAR `emptyhand`: Doom's Fist; BD22's
	// Melee_Attacks and RSQ_Hands). One the player already carries is used first, in the lump's order, a
	// weapon made for this hand before any other; only a player who carries none is given the first class
	// that exists in this game.
	static Weapon EmptyHandWeapon(PlayerPawn pawn, int hand)
	{
		Weapon other = hand == 0 ? Weapon(pawn.player.OffhandWeapon) : Weapon(pawn.player.ReadyWeapon);
		Weapon spare = null;
		int n = VRGear.EmptyHandCount();
		for (int i = 0; i < n; i++)
		{
			class<Inventory> cls = (class<Inventory>)(VRGear.EmptyHandAt(i));
			if (cls == null) continue;
			for (Inventory it = pawn.Inv; it != null; it = it.Inv)
			{
				let w = Weapon(it);
				if (w == null || !(w is cls) || w == other) continue;
				if (w.bOffhandWeapon == (hand == 1)) return w;
				if (spare == null) spare = w;
			}
		}
		if (spare != null) return spare;
		// No empty hand to give this hand: give one.
		for (int i = 0; i < n; i++)
		{
			class<Inventory> cls = (class<Inventory>)(VRGear.EmptyHandAt(i));
			if (cls == null) continue;
			pawn.GiveInventoryType(cls);
			for (Inventory it = pawn.Inv; it != null; it = it.Inv)
			{
				let w = Weapon(it);
				if (w != null && w is cls && w != other) return w;
			}
		}
		return null;
	}

	static Weapon HeldIn(PlayerPawn pawn, int hand)
	{
		return hand == 0 ? Weapon(pawn.player.ReadyWeapon) : Weapon(pawn.player.OffhandWeapon);
	}

	override void WorldTick()
	{
		for (int i = 0; i < MAXPLAYERS; ++i)
		{
			if (!playeringame[i] || players[i].mo == null) continue;
			PlayerPawn pawn = players[i].mo;
			bool ok; int kind, hand, mount; bool quick;
			for (int guard = 0; guard < 16; ++guard)
			{
				[ok, kind, hand, mount, quick] = VRGear.PopAction(i);
				if (!ok) break;
				Apply(i, pawn, kind, hand, mount, quick);
			}
		}
	}

	private void Apply(int pnum, PlayerPawn pawn, int kind, int hand, int mount, bool quick)
	{
		Name owner = VRGear.MountItem(pnum, mount);
		Weapon stored = owner != 'None' ? Weapon(pawn.FindInventory((class<Inventory>)(owner))) : null;
		Weapon held = HeldIn(pawn, hand);

		switch (kind)
		{
		case VRGear.ACT_DRAW:
			if (stored != null && stored != pawn.player.ReadyWeapon && stored != pawn.player.OffhandWeapon)
			{
				ToHand(pawn, stored, hand);
				pawn.A_StartSound("rs_holster_fx_store", CHAN_AUTO, 0, 0.6);
			}
			break;

		case VRGear.ACT_SEAT:
		{
			if (held == null) break;
			let empty = EmptyHandWeapon(pawn, hand);
			if (empty == null) break;
			VRGear.SetMountItem(pnum, mount, held.GetClassName());   // this mount is now the gun's own
			ToHand(pawn, empty, hand);
			pawn.A_StartSound("rs_holster_fx_store", CHAN_AUTO);
			break;
		}

		case VRGear.ACT_SWAP:
			// That gun to this hand; yours is no longer in a hand, so it is home in its own mount.
			if (stored != null) { ToHand(pawn, stored, hand); pawn.A_StartSound("rs_holster_fx_store", CHAN_AUTO); }
			break;

		case VRGear.ACT_FREE:
			VRGear.SetMountItem(pnum, mount, 'None');
			pawn.A_StartSound("misc/i_pkup", CHAN_AUTO, 0, 0.5);
			break;
		}
	}
}

// ---------------------------------------------------------------- the feel (this machine's player)

class RAG_Feel : EventHandler
{
	int lastSeq;
	bool seqInit;
	// Queued pulses: hand, tic to play, intensity, ms, hz.
	Array<int> qHand, qTic, qMs, qHz;
	Array<double> qInt;
	double humWas[2];

	private void Queue(int hand, Name pattern, int startTic)
	{
		int n = VRGear.PatternLength(pattern);
		int at = startTic;
		for (int i = 0; i < n; ++i)
		{
			bool ok; double inten; int ms, hz, gap;
			[ok, inten, ms, hz, gap] = VRGear.PatternPulse(pattern, i);
			if (!ok) break;
			qHand.Push(hand); qTic.Push(at); qInt.Push(inten); qMs.Push(ms); qHz.Push(hz);
			at += max(1, (ms + gap + 28) / 29);   // a tic is ~28.6 ms
		}
	}

	override void WorldTick()
	{
		int me = consoleplayer;
		if (me < 0 || me >= MAXPLAYERS || !playeringame[me]) return;
		int now = level.maptime;

		// New events since last tic.
		int seq = VRGear.EventSeq(me);
		if (!seqInit || seq < lastSeq) { lastSeq = seq; seqInit = true; }
		for (; lastSeq < seq; ++lastSeq)
		{
			bool ok; int kind, hand, mount, tic; bool quick;
			[ok, kind, hand, mount, quick, tic] = VRGear.Event(me, lastSeq);
			if (!ok) continue;
			Name item = VRGear.MountItem(me, mount);
			switch (kind)
			{
			case VRGear.EV_ENTER:
				Queue(hand, VRGear.MountSignature(mount), now);
				// A full mount: the gun's own print right after the mount's.
				if (item != 'None' && players[me].mo != null && players[me].mo.FindInventory((class<Inventory>)(item)) != null)
					Queue(hand, VRGear.ItemPrint(item), now + 3);
				break;
			case VRGear.EV_RAIL:   Queue(hand, 'drag', now); break;
			case VRGear.EV_CLEAR:  Queue(hand, quick ? 'quick' : 'snap', now); break;
			case VRGear.EV_SEAT:
			case VRGear.EV_SWAP:   Queue(hand, 'seat', now); break;
			case VRGear.EV_REFUSE:
				Queue(hand, 'refuse', now);
				if (players[me].mo != null) players[me].mo.A_StartSound("*usefail", CHAN_AUTO, CHANF_LOCAL);
				break;
			case VRGear.EV_FREE:   Queue(hand, 'free', now); break;
			}
		}

		// Play what is due.
		for (int i = qTic.Size() - 1; i >= 0; --i)
		{
			if (qTic[i] > now) continue;
			level.VRHapticEx(qHand[i], qInt[i], qMs[i], qHz[i], 1);
			qHand.Delete(i); qTic.Delete(i); qInt.Delete(i); qMs.Delete(i); qHz.Delete(i);
		}

		// The hum: the mount a hand is heading for, stronger as it closes in. Nothing else hums.
		for (int h = 0; h < 2; ++h)
		{
			int at, heading, rail; double close;
			[at, heading, close, rail] = VRGear.HandState(me, h);
			double hum = (heading >= 0 && at < 0 && rail < 0 && close > 0.25) ? 0.08 + 0.22 * (close - 0.25) / 0.75 : 0.0;
			if (abs(hum - humWas[h]) > 0.02 || (hum == 0 && humWas[h] != 0))
			{
				level.VRHapticHold(h, hum, 140);
				humWas[h] = hum;
			}
		}
	}
}

// ---------------------------------------------------------------- the look (client-side only)
//
// WHAT YOU SEE (owner, 2026-11-12: "faintly always, bright near a hand"; UZDXREMA
// docs/plans/research/tacticalrig_code_read_2026-11-12.md, E.1). Drawing only: nothing here is read
// by the sim, so it may use this machine's own player (consoleplayer) freely.
//   rings        your own mounts only. A wire sphere the size of the mount's reach.
//   stored guns  every player's, as the model you hold, one size, hung as worn (the RAGFIT lump).
//   ammo lights  every player's, one at each mount that stores a gun.
//   teaching     the first-gun hint and the miss-three-times hint.

class RAG_Look : EventHandler
{
	// ---- the ring's numbers (TacticalRig rig.zs:3084-3118, 2978; the floor is the owner's) ----
	const RING_FLOOR   = 0.30;   // a ring a hand can use is never fainter than this
	const RING_UNUSED  = 0.15;   // a ring no hand can use right now: still there, fainter
	const RING_EDGE    = 0.35;   // a hand at the sphere's edge; falls to nothing at 2.5 radii
	const RING_HEADING = 0.55;   // added, by closeness, for the mount the sim says the hand heads for
	const RING_AT      = 0.90;   // a hand at the mount (green, and a size larger)
	const RING_AT_SIZE = 1.15;
	const RING_FAR     = 0.35;   // every usable ring but the nearest: this share of the hand's part
	const RING_STOWED  = 0.40;   // a ring round a drawn gun, so the wire does not wash the gun out
	const FLASH_TICS   = 35;     // red (refused), white (freed), bright green (a first seat)
	const FLASH_FULL   = 8;      // tics at full before it fades
	// ---- the stored gun (TacticalRig rig.zs:3417, Hang 3605-3620) ----
	// every gun is drawn 0.185 of the eye height long (0.25 m at 1.35 m): RAG_Gun.GUN_SHARE
	const NECK_TO_CHEST = 0.150; // the sim torso's own number (p_vrtorso.cpp): the eye height is read back from it
	// ---- the ammo light (TacticalRig rig.zs:3340-3371, 2987) ----
	const LIGHT_SIZE   = 0.26;   // of the mount's reach
	const LIGHT_EMPTY  = 0.18;
	const LIGHT_ALPHA  = 0.60;
	const LIGHT_NEAR   = 0.90;   // with a hand near
	const LIGHT_AHEAD  = 0.75;   // of the reach, toward the body's front, so the gun does not hide it
	const PULSE_TICS   = 35;
	// ---- the teaching (TacticalRig ghost.zs:27, rig.zs:2386-2516) ----
	const HINT_HOLD    = 70;     // a gun in the main hand this long, and no gun ever seated
	const MISS_WINDOW  = 210;    // three misses on one mount inside this
	const MISS_SHOW    = 105;    // light that ring this long
	const MISS_AGAIN   = 1050;   // not twice on one mount inside this
	const MISS_MAX     = 3;      // hints a map

	const LOOK_IDLE = 0;         // the ring's frames (MODELDEF.gear)
	const LOOK_HOT = 1;
	const LOOK_RED = 2;
	const LOOK_WHITE = 3;
	const LOOK_SEAT = 4;

	transient Array<RAG_Shell> shells;   // per player per mount
	transient Array<RAG_Gun> guns;
	transient Array<RAG_Light> lights;
	transient RAG_Fit fit;
	transient bool fitLoaded;

	// this machine's own player, per mount
	transient Array<int> flashLook, flashTic, missCount, missFirst, hintUntil, hintLast;
	transient Array<Name> ownerWas;
	transient int lastSeq;
	transient bool seqInit;
	transient Array<int> seenKey;     // (tic, hand, kind, mount) already seen, so a replayed tic is not counted twice
	transient int enteredAt[2];       // the mount + 1 each hand entered and has not acted in; 0 none
	transient int hintsThisMap;
	// kept with the game
	bool seatedOnce;                  // a gun has been seated by hand
	bool firstHintSaid;
	int gunHeldTics;

	static double Breath()
	{
		return 0.625 + 0.375 * cos(level.maptime * 360.0 / PULSE_TICS);
	}

	// Does this hand hold a gun (anything but the empty hand)?
	static bool HoldsGun(PlayerPawn pawn, int hand)
	{
		Weapon w = RAG_Rules.HeldIn(pawn, hand);
		if (w == null) return false;
		return !VRGear.IsEmptyHand(w);
	}

	// A stored gun's ammo: 0 green (half a magazine or more), 1 yellow (low, or empty with rounds
	// to reload), 2 red (nothing at all), -1 a gun with no ammo. A gun with a magazine counts its
	// magazine. (TacticalRig rig.zs AmmoState.)
	static int AmmoLook(Weapon w)
	{
		if (w == null || w.Ammo1 == null) return -1;
		bool mag = w.Ammo2 != null && w.Ammo2 != w.Ammo1;
		Inventory lo = mag ? w.Ammo2 : w.Ammo1;
		int have = lo.Amount;
		int cap = max(1, lo.MaxAmount);
		int spare = mag ? w.Ammo1.Amount : 0;
		if (have <= 0) return spare > 0 ? 1 : 2;
		return have * 2 >= cap ? 0 : 1;
	}

	// How bright one hand makes one ring, before "nearest" is counted.
	private static double HandPart(Vector3 handPos, Vector3 mountPos, double reach, bool heading, double closeness)
	{
		double d = (handPos - mountPos).Length();
		double part = 0;
		if (d <= reach) part = RING_EDGE;
		else if (d < 2.5 * reach) part = RING_EDGE * (1.0 - (d - reach) / (1.5 * reach));
		if (heading) part = max(part, RING_EDGE + RING_HEADING * closeness);
		return part;
	}

	private void Flash(int mount, int look, int now)
	{
		flashLook[mount] = look;
		flashTic[mount] = now;
	}

	private void Missed(int mount, int now)
	{
		if (missCount[mount] == 0 || now - missFirst[mount] > MISS_WINDOW)
		{
			missCount[mount] = 1;
			missFirst[mount] = now;
			return;
		}
		missCount[mount] = missCount[mount] + 1;
		if (missCount[mount] < 3) return;
		missCount[mount] = 0;
		if (hintsThisMap >= MISS_MAX) return;
		if (hintLast[mount] != 0 && now - hintLast[mount] < MISS_AGAIN) return;
		hintsThisMap++;
		hintLast[mount] = now;
		hintUntil[mount] = now + MISS_SHOW;
		Console.Printf("Grip inside the ring.");
	}

	// This machine's player's holster events: the ring flashes and the misses.
	private void ReadEvents(int me, int n, int now)
	{
		int seq = VRGear.EventSeq(me);
		if (!seqInit || seq < lastSeq) { lastSeq = seq; seqInit = true; }
		for (; lastSeq < seq; ++lastSeq)
		{
			bool ok; int kind, hand, mount, tic; bool quick;
			[ok, kind, hand, mount, quick, tic] = VRGear.Event(me, lastSeq);
			if (!ok) continue;
			if (mount < 0 || mount >= n || hand < 0 || hand > 1) continue;
			int key = (((tic % 500000) * 2 + hand) * 16 + kind) * 64 + (mount % 64);
			if (seenKey.Find(key) != seenKey.Size()) continue;
			seenKey.Push(key);
			if (seenKey.Size() > 32) seenKey.Delete(0);

			switch (kind)
			{
			case VRGear.EV_ENTER:
				enteredAt[hand] = mount + 1;
				break;
			case VRGear.EV_LEAVE:
				if (enteredAt[hand] == mount + 1) Missed(mount, now);
				enteredAt[hand] = 0;
				break;
			case VRGear.EV_RAIL:
			case VRGear.EV_CLEAR:
			case VRGear.EV_CANCEL:
			case VRGear.EV_SWAP:
				enteredAt[hand] = 0;
				break;
			case VRGear.EV_SEAT:
				enteredAt[hand] = 0;
				// Bright green when this seat made the mount the gun's own, or was the first ever.
				if (!seatedOnce || ownerWas[mount] != VRGear.MountItem(me, mount)) Flash(mount, LOOK_SEAT, now);
				seatedOnce = true;
				break;
			case VRGear.EV_REFUSE:
				enteredAt[hand] = 0;
				Flash(mount, LOOK_RED, now);
				break;
			case VRGear.EV_FREE:
				enteredAt[hand] = 0;
				Flash(mount, LOOK_WHITE, now);
				break;
			}
		}
	}

	override void WorldTick()
	{
		int n = VRGear.MountCount();
		if (n <= 0) return;
		while (shells.Size() < n * MAXPLAYERS) shells.Push(null);
		while (guns.Size() < n * MAXPLAYERS) guns.Push(null);
		while (lights.Size() < n * MAXPLAYERS) lights.Push(null);
		while (flashLook.Size() < n)
		{
			flashLook.Push(0); flashTic.Push(0); missCount.Push(0); missFirst.Push(0);
			hintUntil.Push(0); hintLast.Push(0); ownerWas.Push('None');
		}
		if (!fitLoaded) { fitLoaded = true; fit = RAG_Fit.Load(); }

		int now = level.maptime;
		int me = consoleplayer;
		bool meOk = me >= 0 && me < MAXPLAYERS && playeringame[me] && players[me].mo != null;
		if (meOk) ReadEvents(me, n, now);

		for (int i = 0; i < MAXPLAYERS; ++i)
		{
			PlayerPawn pawn = playeringame[i] ? players[i].mo : null;
			if (pawn == null)
			{
				// Nobody here: put away what was drawn for this seat.
				for (int m = 0; m < n; ++m)
				{
					int kk = i * n + m;
					if (shells[kk] != null) shells[kk].Hide();
					if (guns[kk] != null) guns[kk].Hide();
					if (lights[kk] != null) lights[kk].Hide();
				}
				continue;
			}
			bool mine = meOk && i == me;

			// The body: which way it faces, and the eye height everything is sized from.
			bool tok; double tyaw; Vector3 neck, chest, pelvis;
			[tok, tyaw, neck, chest, pelvis] = VRTorso.Get(i);
			double eyeH = pawn.ViewHeight;
			if (tok) eyeH = max(8.0, (neck.Z - chest.Z) / NECK_TO_CHEST);
			else { tyaw = pawn.Angle; chest = pawn.Pos; pelvis = pawn.Pos; }
			Vector3 front = (cos(tyaw), sin(tyaw), 0);
			Vector2 right = (sin(tyaw), -cos(tyaw));

			// The hands.
			int hv0 = 0, hv1 = 0; Vector3 hp0, hp1; double hyaw, hpitch, hroll;
			[hv0, hp0, hyaw, hpitch, hroll] = players[i].GetVRHand(0);
			[hv1, hp1, hyaw, hpitch, hroll] = players[i].GetVRHand(1);
			int at0 = -1, at1 = -1, hd0 = -1, hd1 = -1, rail0 = -1, rail1 = -1; double cl0 = 0, cl1 = 0;
			[at0, hd0, cl0, rail0] = VRGear.HandState(i, 0);
			[at1, hd1, cl1, rail1] = VRGear.HandState(i, 1);
			bool gun0 = false, gun1 = false;
			int near0 = -1, near1 = -1, hintMount = -1;

			if (mine)
			{
				gun0 = HoldsGun(pawn, 0);
				gun1 = HoldsGun(pawn, 1);
				// The nearest ring each hand can use; the hip the first-gun hint points at; has a
				// gun ever been given a home.
				bool anyOwned = false;
				double nd0 = 1e30, nd1 = 1e30, hintD = 1e30;
				bool hintHip = false;
				for (int m = 0; m < n; ++m)
				{
					bool pok; Vector3 ppos, pmouth; double pradius;
					[pok, ppos, pradius, pmouth] = VRGear.MountPose(i, m);
					if (!pok) continue;
					bool owned = VRGear.MountItem(i, m) != 'None';
					if (owned) anyOwned = true;
					double d0 = (hp0 - ppos).Length();
					double d1 = (hp1 - ppos).Length();
					if (hv0 != 0 && (gun0 || owned) && d0 < nd0) { nd0 = d0; near0 = m; }
					if (hv1 != 0 && (gun1 || owned) && d1 < nd1) { nd1 = d1; near1 = m; }
					String mname = VRGear.MountName(m);
					mname = mname.MakeLower();
					bool hip = mname.Left(3) == "hip";
					double hd = (hv0 != 0) ? d0 : double(m);
					if ((hip && !hintHip) || (hip == hintHip && hd < hintD)) { hintMount = m; hintD = hd; hintHip = hip; }
				}
				// The first-gun hint, until a gun has been seated.
				if (seatedOnce || anyOwned) { gunHeldTics = 0; hintMount = -1; }
				else
				{
					if (gun0 && hv0 != 0) gunHeldTics++; else gunHeldTics = 0;
					if (gunHeldTics < HINT_HOLD) hintMount = -1;
					else if (!firstHintSaid)
					{
						firstHintSaid = true;
						Console.Printf("Push the gun into your hip, or grip there.");
					}
				}
			}

			for (int m = 0; m < n; ++m)
			{
				int k = i * n + m;
				bool ok = false; Vector3 pos, mouth; double radius = 0;
				[ok, pos, radius, mouth] = VRGear.MountPose(i, m);
				Name item = VRGear.MountItem(i, m);
				bool owned = item != 'None';

				// The gun stored here: carried, and in neither hand.
				Weapon w = null;
				if (ok && owned)
				{
					w = Weapon(pawn.FindInventory((class<Inventory>)(item)));
					if (w == pawn.player.ReadyWeapon || w == pawn.player.OffhandWeapon) w = null;
				}

				// ---- the ring: your own only ----
				if (mine && ok)
				{
					bool use0 = hv0 != 0 && (gun0 || owned);
					bool use1 = hv1 != 0 && (gun1 || owned);
					double ring = RING_UNUSED;
					int look = LOOK_IDLE;
					double size = radius;
					if (use0 || use1)
					{
						double part = 0;
						if (use0)
						{
							double p0 = HandPart(hp0, pos, radius, hd0 == m, cl0);
							if (m != near0) p0 *= RING_FAR;
							part = max(part, p0);
						}
						if (use1)
						{
							double p1 = HandPart(hp1, pos, radius, hd1 == m, cl1);
							if (m != near1) p1 *= RING_FAR;
							part = max(part, p1);
						}
						ring = max(RING_FLOOR, part);
					}
					if (at0 == m || at1 == m)
					{
						ring = RING_AT;
						look = LOOK_HOT;
						size = radius * RING_AT_SIZE;
					}
					if (w != null) ring *= RING_STOWED;

					// The rules' flashes: red refused, white freed, bright green a first seat.
					int since = now - flashTic[m];
					if (flashLook[m] != 0 && since >= 0 && since < FLASH_TICS)
					{
						look = flashLook[m];
						double fl = (since < FLASH_FULL) ? 1.0 : 1.0 - double(since - FLASH_FULL) / double(FLASH_TICS - FLASH_FULL);
						ring = max(ring, RING_AT * fl);
					}
					else flashLook[m] = 0;

					// The teaching: this is the ring.
					if (m == hintMount)
					{
						ring = RING_AT * Breath();
						size = radius * (1.0 + 0.25 * Breath());
					}
					if (hintUntil[m] > now) ring = 1.0;

					if (shells[k] == null) shells[k] = RAG_Shell(Actor.SpawnClientSide('RAG_Shell', pos, NO_REPLACE));
					if (shells[k] != null) shells[k].ShowAt(pos, size, ring, look);
				}
				else if (shells[k] != null) shells[k].Hide();

				// ---- the gun in it: every player's ----
				bool isChest = tok && (pos - chest).Length() < (pos - pelvis).Length();
				bool isLeft = ((pos.XY - pelvis.XY) dot right) < 0;
				if (w != null && guns[k] == null) guns[k] = RAG_Gun(Actor.SpawnClientSide('RAG_Gun', pos, NO_REPLACE));
				if (guns[k] != null) guns[k].ShowAt(w, pos, radius, mouth, fit, eyeH, tyaw, isChest, isLeft);

				// ---- its ammo light: every player's ----
				int ammo = AmmoLook(w);
				if (w != null && ammo >= 0)
				{
					bool handNear = (hv0 != 0 && (hp0 - pos).Length() < 2.5 * radius)
						|| (hv1 != 0 && (hp1 - pos).Length() < 2.5 * radius);
					double la = handNear ? LIGHT_NEAR : LIGHT_ALPHA;
					if (ammo == 2) la *= Breath();
					double ls = radius * (ammo == 2 ? LIGHT_EMPTY : LIGHT_SIZE);
					if (lights[k] == null) lights[k] = RAG_Light(Actor.SpawnClientSide('RAG_Light', pos, NO_REPLACE));
					if (lights[k] != null) lights[k].ShowAt(pos + front * (radius * LIGHT_AHEAD), ls, la, ammo);
				}
				else if (lights[k] != null) lights[k].Hide();

				if (mine) ownerWas[m] = item;
			}
		}
	}
}

// How big a stored gun is and which way it points (the RAGFIT lump). This is RSQ TacticalRig's
// fit loader (rsq_ubqseries/TacticalRig/zscript/rsqtr/fit.zs: Load, Find, Compose, Basis), ported
// with its lump format unchanged:
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

// The ring: a wire sphere, the size of the mount's reach (MODELDEF.gear). No angle, no pitch: a
// sphere reads the same from every side.
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
		RenderStyle "Add";
		Radius 1;
		Height 1;
	}

	void Hide()
	{
		bInvisible = true;
	}

	// size: the sphere's radius in map units. look: the frame (RAG_Look.LOOK_*).
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

// The ammo light: a small bright ball (MODELDEF.gear). Frame 0 green, 1 yellow, 2 red.
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
		RenderStyle "Add";
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

class RAG_Gun : Actor
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

	String wearing;        // the weapon class shown
	int fitRow;            // its RAGFIT row, or -1
	bool plainOk;          // no row: the old way found something to draw
	double plainScale;

	void Hide()
	{
		bInvisible = true;
	}

	// The weapon as you hold it, hung in the mount as worn.
	//   with a RAGFIT row: the row's model and frame, GUN_SHARE of the eye height long, pitched and
	//     rolled for a hip or a chest mount on that side, its middle on the mount;
	//   without one: the weapon's own MODELDEF, sized to the mount, muzzle down into the mouth (as before).
	void ShowAt(Weapon w, Vector3 pos, double radius, Vector3 mouth, RAG_Fit fit, double eyeH, double bodyYaw, bool isChest, bool isLeft)
	{
		if (w == null) { bInvisible = true; return; }
		String cn = w.GetClassName();
		if (cn != wearing)
		{
			wearing = cn;
			fitRow = -1;
			plainOk = false;
			int row = (fit != null) ? fit.Find(cn) : -1;
			if (row >= 0 && fit.spr[row] != "")
			{
				// The class whose MODELDEF draws it must be loaded, and the sprite must exist.
				class<Actor> hc = fit.holder[row];
				int si = GetSpriteIndex(Name(fit.spr[row]));
				if (hc != null && si >= 0)
				{
					fitRow = row;
					sprite = si;
					frame = fit.frn[row];
					A_ChangeModel(Name(fit.holder[row]));
					SetModelFlag(MDL_USEACTORPITCH | MDL_USEACTORROLL);
				}
			}
			if (fitRow < 0)
			{
				class<Actor> want = level.GetActorModelClass(w);
				State rs = w.FindState("Ready");
				if (want != null && rs != null)
				{
					plainOk = true;
					sprite = rs.sprite;
					frame = rs.Frame;
					ClearModelFlag(MDL_USEACTORPITCH | MDL_USEACTORROLL);
					A_ChangeModel(want.GetClassName());
					bool found; double rad;
					[found, rad] = level.GetModelBoundsHint(want, sprite, frame);
					plainScale = (found && rad > 0) ? (radius * 2.2) / rad : 0.18;
				}
			}
		}

		if (fitRow >= 0)
		{
			bInvisible = false;
			double s = GUN_SHARE * eyeH / fit.len[fitRow];
			Scale = (s, s);
			// Hips: muzzle down. Chest: cross-draw, butt toward the breastbone. Mirrored by side.
			double pt = isChest ? 70.0 : 80.0;
			double rl = isChest ? (isLeft ? 35.0 : -35.0) : (isLeft ? -10.0 : 10.0);
			double oa, op, orl;
			RAG_Fit.Compose(bodyYaw, pt, rl, fit.yaw[fitRow], fit.pitch[fitRow], oa, op, orl);
			Angle = oa;
			Pitch = op;
			Roll = orl;
			// Its middle, not its origin, on the mount.
			Vector3 F, L, U;
			[F, L, U] = RAG_Fit.Basis(oa, op, orl);
			Vector3 c = fit.Centre(fitRow) * s;
			SetOrigin(pos - (F * c.X + L * c.Y + U * c.Z), true);
			return;
		}

		if (!plainOk) { bInvisible = true; return; }
		bInvisible = false;
		Scale = (plainScale, plainScale);
		Roll = 0;
		SetOrigin(pos, true);
		// Muzzle INTO the mount: along minus the mouth. Pitch is down-positive.
		Angle = atan2(-mouth.Y, -mouth.X);
		Pitch = asin(clamp(mouth.Z, -1.0, 1.0));
	}

	const GUN_SHARE = 0.185;   // every stored gun is this share of the eye height long (TacticalRig: 0.25 m)

	States
	{
	Spawn:
		TNT1 A -1;
		Stop;
	}
}

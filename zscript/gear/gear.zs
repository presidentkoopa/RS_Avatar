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

	static Weapon EmptyHandWeapon(PlayerPawn pawn, int hand)
	{
		class<Inventory> cls = (class<Inventory>)(VRGear.EmptyHand());
		if (cls == null) return null;
		Weapon other = hand == 0 ? Weapon(pawn.player.OffhandWeapon) : Weapon(pawn.player.ReadyWeapon);
		Weapon spare = null;
		for (Inventory it = pawn.Inv; it != null; it = it.Inv)
		{
			let w = Weapon(it);
			if (w == null || !(w is cls) || w == other) continue;
			if (w.bOffhandWeapon == (hand == 1)) return w;
			if (spare == null) spare = w;
		}
		if (spare != null) return spare;
		// No empty hand to give this hand: give one.
		pawn.GiveInventoryType(cls);
		for (Inventory it = pawn.Inv; it != null; it = it.Inv)
		{
			let w = Weapon(it);
			if (w != null && w is cls && w != other) return w;
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

class RAG_Look : EventHandler
{
	transient Array<RAG_Shell> shells;   // per player per mount
	transient Array<RAG_Gun> guns;

	override void WorldTick()
	{
		int n = VRGear.MountCount();
		while (shells.Size() < n * MAXPLAYERS) shells.Push(null);
		while (guns.Size() < n * MAXPLAYERS) guns.Push(null);
		for (int i = 0; i < MAXPLAYERS; ++i)
		{
			PlayerPawn pawn = playeringame[i] ? players[i].mo : null;
			int atM = -1, atO = -1, hdM = -1, hdO = -1; double clM = 0, clO = 0; int rl;
			if (pawn != null)
			{
				[atM, hdM, clM, rl] = VRGear.HandState(i, 0);
				[atO, hdO, clO, rl] = VRGear.HandState(i, 1);
			}
			for (int m = 0; m < n; ++m)
			{
				int k = i * n + m;
				bool ok = false; Vector3 pos, mouth; double radius = 0;
				if (pawn != null) [ok, pos, radius, mouth] = VRGear.MountPose(i, m);

				// The shell: always on the body, faint; brighter as your hand heads for it; lit with
				// a hand in it. Other players' shells stay faint.
				double glow = 0.18; bool hot = false;
				if (i == consoleplayer)
				{
					if (m == atM || m == atO) { glow = 0.9; hot = true; }
					else if (m == hdM) glow = max(glow, 0.18 + 0.5 * clM);
					else if (m == hdO) glow = max(glow, 0.18 + 0.5 * clO);
				}
				if (ok && shells[k] == null) shells[k] = RAG_Shell(Actor.SpawnClientSide('RAG_Shell', pos, NO_REPLACE));
				if (shells[k] != null) shells[k].ShowAt(ok, pos, radius, mouth, glow, hot);

				// The gun in it.
				Name item = VRGear.MountItem(i, m);
				Weapon w = null;
				if (ok && item != 'None')
				{
					w = Weapon(pawn.FindInventory((class<Inventory>)(item)));
					if (w == pawn.player.ReadyWeapon || w == pawn.player.OffhandWeapon) w = null;
				}
				if (w != null && guns[k] == null) guns[k] = RAG_Gun(Actor.SpawnClientSide('RAG_Gun', pos, NO_REPLACE));
				if (guns[k] != null) guns[k].ShowAt(w, pos, radius, mouth);
			}
		}
	}
}

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

	void ShowAt(bool ok, Vector3 pos, double radius, Vector3 mouth, double glow, bool hot)
	{
		if (!ok) { bInvisible = true; return; }
		bInvisible = false;
		SetOrigin(pos, true);
		double k = radius / 3.0;   // the bracket mesh is radius 3 at Scale 1 (MODELDEF.gear)
		Scale = (k, k);
		Alpha = glow;
		// Open along the mouth.
		Angle = atan2(mouth.Y, mouth.X);
		Pitch = -asin(clamp(mouth.Z, -1.0, 1.0)) + 90;
		if (hot) SetStateLabel("Hot"); else SetStateLabel("Idle");
	}

	States
	{
	Spawn:
	Idle:
		RSHM A -1;
		Stop;
	Hot:
		RSHM B -1;
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

	class<Actor> shown;

	// The weapon's own 3D model, sized to the mount, muzzle down into the mouth.
	void ShowAt(Weapon w, Vector3 pos, double radius, Vector3 mouth)
	{
		let want = (w != null) ? level.GetActorModelClass(w) : null;
		if (want == null) { bInvisible = true; shown = null; return; }
		if (want != shown)
		{
			State rs = w.FindState("Ready");
			if (rs == null) { bInvisible = true; return; }
			shown = want;
			sprite = rs.sprite;
			frame  = rs.Frame;
			A_ChangeModel(want.GetClassName());
			bool found; double rad;
			[found, rad] = level.GetModelBoundsHint(want, sprite, frame);
			double k = (found && rad > 0) ? (radius * 2.2) / rad : 0.18;
			Scale = (k, k);
		}
		bInvisible = false;
		SetOrigin(pos, true);
		// Muzzle INTO the mount: along minus the mouth. Pitch is down-positive.
		Angle = atan2(-mouth.Y, -mouth.X);
		Pitch = asin(clamp(mouth.Z, -1.0, 1.0));
	}

	States
	{
	Spawn:
		TNT1 A -1;
		Stop;
	}
}

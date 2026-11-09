// BODY HOLSTERS -- the new holster system (owner, 2026-11-09). Design: UZDXREMA
// docs/plans/HOLSTER2_DESIGN.md, built from the survey of VR holster systems and QuakeVR.
//
// WHAT IT DOES
//   - Spots on your body (VRSLOTS lumps), hung on the SIM's torso frame (VRTorso, engine
//     p_vrtorso.cpp): they ride your body, turn with stick and room turns, and stay put when
//     you look around, look down or reach.
//   - The spot your hand fits best wins (lowest distance / reach), and keeps the hand until it
//     really leaves (QuakeVR). Rule out wrong grabs by fit, not by which was listed first.
//   - Grip, read from the command: put the weapon in your hand away, draw the one in the spot, or
//     swap them. A weapon owns the spot it was first put in (Tactical Rig). Hold grip about a
//     second at an empty spot to free it.
//   - Spots over the shoulders are "blind": always felt, and a grip counts for a moment after the
//     controller loses tracking there (Oculus/H3VR tracking loss behind the head).
//   - While a hand is at a spot the torso is held still, so a reach never turns the body away.
//   - Feel: a tick on finding a spot (stronger when it holds something), a thump on holster or
//     draw, a buzz and Doom's "no" when nothing can happen.
//   - Look: rings only near your hands, the best one bright; holstered weapons hang on your body
//     with their own 3D model. Drawn client-side: no part of the look is in the game state.
//
// NETPLAY. Every decision is made in the sim, every tic, for every player, from the command
// (hand latch, VRTorso, the grip bits) and the shared VRSLOTS table, so every machine decides
// the same thing on the same tic and no event is sent. The per-player state rides an inventory
// item, so it is saved, travels between levels and resyncs with the player.
//
// NOT HERE, on purpose: reloading, ammo pouches and how a weapon sits in the hand. Those are the
// weapons step of the roadmap.

// ---------------------------------------------------------------- the spots

class RSBH_Slot : Object
{
	Name   slotName;
	bool   onChest;                 // else the pelvis
	double side, fwd, up, radius;   // fractions of standing eye height
	bool   blind;
}

class RSBH_Table : Object
{
	Array<RSBH_Slot> slots;

	static RSBH_Table Load()
	{
		let t = new('RSBH_Table');
		int lump = -1;
		while ((lump = Wads.FindLump("VRSLOTS", lump + 1)) != -1)
			t.ParseLump(Wads.ReadLump(lump));
		return t;
	}

	int Find(Name n) const
	{
		for (int i = 0; i < slots.Size(); ++i) if (slots[i].slotName == n) return i;
		return -1;
	}

	private void ParseLump(String text)
	{
		Array<String> lines;
		text.Replace("\r", "");
		text.Split(lines, "\n");
		for (int li = 0; li < lines.Size(); ++li)
		{
			String line = lines[li];
			int c = line.IndexOf("//");
			if (c >= 0) line = line.Left(c);
			line.Replace("\t", " ");
			Array<String> w;
			line.Split(w, " ", TOK_SKIPEMPTY);
			if (w.Size() == 0) continue;
			String verb = w[0].MakeLower();
			if (verb == "remove" && w.Size() >= 2)
			{
				int at = Find(w[1]);
				if (at >= 0) slots.Delete(at);
				continue;
			}
			if (verb != "slot" || w.Size() < 7)
			{
				Console.Printf("\cgVRSLOTS: line %d not understood: %s", li + 1, lines[li]);
				continue;
			}
			let s = new('RSBH_Slot');
			s.slotName = w[1];
			s.onChest  = w[2].MakeLower() == "chest";
			s.side     = w[3].ToDouble();
			s.fwd      = w[4].ToDouble();
			s.up       = w[5].ToDouble();
			s.radius   = w[6].ToDouble();
			for (int k = 7; k < w.Size(); ++k)
				if (w[k].MakeLower() == "blind") s.blind = true;
			if (s.radius <= 0) continue;
			int old = Find(s.slotName);
			if (old >= 0) slots[old] = s; else slots.Push(s);
		}
	}
}

// ---------------------------------------------------------------- one player's rig (game state)

class RSBH_Rig : Inventory
{
	Default
	{
		Inventory.MaxAmount 1;
		+INVENTORY.UNDROPPABLE
		+INVENTORY.UNTOSSABLE
	}

	// Which weapon class owns which spot, by the spot's name (so a layout change keeps the rest).
	Array<Name> ownSlot;
	Array<Name> ownClass;
	// The tallest eye height seen: the standing height the spots scale with.
	double standEye;

	// Per hand, 0 main 1 off.
	int  claim[2];        // the spot this hand is at, -1 none
	int  heldTics[2];     // tics at that spot
	int  upTics[2];       // tics the grip has been up
	bool gripWas[2];
	int  freeTics[2];     // tics of grip held at an empty owned spot (free it at 35)
	int  lostTics[2];     // tics since the controller lost tracking
	Vector3 lastHand[2];  // the hand where it was last tracked

	Name OwnerOf(Name slot) const
	{
		for (int i = 0; i < ownSlot.Size(); ++i) if (ownSlot[i] == slot) return ownClass[i];
		return 'None';
	}

	void SetOwner(Name slot, Name cls)
	{
		// A weapon owns one spot at most.
		for (int i = ownSlot.Size() - 1; i >= 0; --i)
			if (ownSlot[i] == slot || (cls != 'None' && ownClass[i] == cls)) { ownSlot.Delete(i); ownClass.Delete(i); }
		if (cls != 'None') { ownSlot.Push(slot); ownClass.Push(cls); }
	}
}

// ---------------------------------------------------------------- the handler

class RSBH_Handler : EventHandler
{
	RSBH_Table table;

	// The look, this machine's only.
	transient Array<RSBH_Ring> rings;      // per spot, the local player's
	transient Array<RSBH_Gun>  guns;       // per player per spot

	const DWELL_TICS  = 3;     // at a spot this long before a grip counts
	const UP_TICS     = 3;     // grip up this long before the next press counts
	const FREE_TICS   = 35;    // hold grip this long at an empty owned spot to free it
	const LATCH_TICS  = 10;    // a blind spot keeps a lost hand this long
	const KEEP_FACTOR = 1.15;  // the held spot keeps the hand out to this much more reach

	override void OnRegister()
	{
		table = RSBH_Table.Load();
	}

	// ---- small helpers ----

	static bool IsEmptyHand(Weapon w)
	{
		if (w == null) return true;
		String cn = w.GetClassName();
		if (cn.IndexOf("Fist") >= 0) return true;
		class<Actor> repl = Actor.GetReplacement((class<Actor>)("Fist"));
		return repl != null && w.GetClass() == repl;
	}

	static Weapon InHand(PlayerPawn pawn, int hand)
	{
		return hand == 0 ? pawn.player.ReadyWeapon : pawn.player.OffhandWeapon;
	}

	// The weapon owning this spot, if the player has it and neither hand holds it: it is in
	// the holster. Null otherwise.
	static Weapon Stored(PlayerPawn pawn, Name cls)
	{
		if (cls == 'None') return null;
		let w = Weapon(pawn.FindInventory((class<Inventory>)(cls)));
		if (w == null) return null;
		if (w == pawn.player.ReadyWeapon || w == pawn.player.OffhandWeapon) return null;
		return w;
	}

	static Weapon FindEmptyHand(PlayerPawn pawn, int hand)
	{
		Weapon spare = null;
		Weapon other = hand == 0 ? pawn.player.OffhandWeapon : pawn.player.ReadyWeapon;
		for (Inventory it = pawn.Inv; it != null; it = it.Inv)
		{
			let w = Weapon(it);
			if (w == null || !IsEmptyHand(w) || w == other) continue;
			if (w.bOffhandWeapon == (hand == 1)) return w;
			if (spare == null) spare = w;
		}
		return spare;
	}

	// Into a hand, at once (the engine's dual-wield routing).
	static void ToHand(PlayerPawn pawn, Weapon w, int hand)
	{
		bool off = hand == 1;
		w.bOffhandWeapon = off;
		if (w.SisterWeapon != null) w.SisterWeapon.bOffhandWeapon = off;
		bool was = (pawn.player.cheats & CF_INSTANTWEAPSWITCH) != 0;
		pawn.player.cheats |= CF_INSTANTWEAPSWITCH;
		pawn.MoveWeaponToHand(w, hand);
		if (!was) pawn.player.cheats &= ~CF_INSTANTWEAPSWITCH;
		if (pawn.player.PendingWeapon != WP_NOCHANGE) pawn.BringUpWeapon();
	}

	Vector3 SlotPos(RSBH_Slot s, double yaw, Vector3 chest, Vector3 pelvis, double e) const
	{
		Vector3 base = s.onChest ? chest : pelvis;
		double fx = cos(yaw), fy = sin(yaw);
		double rx = sin(yaw), ry = -cos(yaw);   // the torso's right
		return (base.X + (rx * s.side + fx * s.fwd) * e,
		        base.Y + (ry * s.side + fy * s.fwd) * e,
		        base.Z + s.up * e);
	}

	private void Feel(int pnum, int hand, double strength, double ms)
	{
		if (pnum == consoleplayer) level.VRHaptic(hand, strength, ms);
	}

	// ---- the sim, every tic, every player ----

	override void WorldTick()
	{
		if (table == null) table = RSBH_Table.Load();
		for (int i = 0; i < MAXPLAYERS; ++i)
		{
			if (!playeringame[i] || players[i].mo == null) continue;
			PlayerPawn pawn = players[i].mo;
			let rig = RSBH_Rig(pawn.FindInventory('RSBH_Rig'));
			if (rig == null)
			{
				pawn.GiveInventoryType('RSBH_Rig');
				rig = RSBH_Rig(pawn.FindInventory('RSBH_Rig'));
				if (rig == null) continue;
				rig.claim[0] = rig.claim[1] = -1;
			}
			TickPlayer(i, pawn, rig);
		}
		UpdateLook();
	}

	private void TickPlayer(int pnum, PlayerPawn pawn, RSBH_Rig rig)
	{
		// Standing eye height: the tallest head height seen (the command's, so it is the same on
		// every machine).
		if (pawn.HmdPos.Length() > 0)
		{
			double eye = pawn.HmdPos.Z - pawn.Pos.Z;
			if (eye > rig.standEye) rig.standEye = eye;
		}
		bool ok; double yaw; Vector3 neck, chest, pelvis;
		[ok, yaw, neck, chest, pelvis] = VRTorso.Get(pnum);
		double e = rig.standEye;
		if (!ok || e < 10 || table.slots.Size() == 0)
		{
			rig.claim[0] = rig.claim[1] = -1;
			pawn.HolsterClaimMain = pawn.HolsterClaimOff = false;
			return;
		}

		for (int hand = 0; hand < 2; ++hand)
			TickHand(pnum, pawn, rig, hand, yaw, chest, pelvis, e);

		if (rig.claim[0] >= 0 || rig.claim[1] >= 0) VRTorso.Freeze(pnum, 3);
		pawn.HolsterClaimMain = rig.claim[0] >= 0;
		pawn.HolsterClaimOff  = rig.claim[1] >= 0;
	}

	private void TickHand(int pnum, PlayerPawn pawn, RSBH_Rig rig, int hand,
		double yaw, Vector3 chest, Vector3 pelvis, double e)
	{
		int valid; Vector3 hp; double ha, hpi, hr;
		[valid, hp, ha, hpi, hr] = players[pnum].GetVRHand(hand);
		int g, t, bits, tx, ty;
		[g, t, bits, tx, ty] = players[pnum].GetVRHandInput(hand);
		bool tracked = valid && (bits & 1) != 0;   // VRHB_VALID
		bool grip = (bits & 2) != 0 || g >= 160;   // VRHB_GRIP, or most of the way in

		if (tracked) { rig.lastHand[hand] = hp; rig.lostTics[hand] = 0; }
		else rig.lostTics[hand]++;

		Weapon held = InHand(pawn, hand);
		bool empty = IsEmptyHand(held);
		int prev = rig.claim[hand];

		// ---- which spot: the best fit of those that could do something ----
		int best = -1; double bestR = 1.0;
		for (int s = 0; s < table.slots.Size(); ++s)
		{
			RSBH_Slot sl = table.slots[s];
			Name owner = rig.OwnerOf(sl.slotName);
			// An empty hand only cares about a spot that holds or owns something.
			if (empty && owner == 'None') continue;
			Vector3 at = SlotPos(sl, yaw, chest, pelvis, e);
			Vector3 from;
			if (tracked) from = hp;
			else if (s == prev && sl.blind && rig.lostTics[hand] <= LATCH_TICS) from = rig.lastHand[hand];
			else continue;
			double reach = sl.radius * e * (s == prev ? KEEP_FACTOR : 1.0);
			double r = (from - at).Length() / reach;
			if (r < bestR) { bestR = r; best = s; }
		}

		// ---- feel on entering ----
		if (best != prev)
		{
			rig.heldTics[hand] = 0;
			rig.freeTics[hand] = 0;
			if (best >= 0)
			{
				RSBH_Slot bs = table.slots[best];
				bool full = Stored(pawn, rig.OwnerOf(bs.slotName)) != null;
				Feel(pnum, hand, full ? 0.45 : (bs.blind ? 0.4 : 0.25), full ? 30 : 20);
			}
		}
		rig.claim[hand] = best;
		if (best >= 0) rig.heldTics[hand]++;

		// ---- the grip ----
		bool press = grip && !rig.gripWas[hand] && rig.upTics[hand] >= UP_TICS;
		if (best >= 0 && press && rig.heldTics[hand] >= DWELL_TICS)
			Act(pnum, pawn, rig, hand, best, held, empty);

		// Free a spot: empty hand, grip held, the spot owned but holding nothing.
		if (best >= 0 && grip && empty)
		{
			Name sn = table.slots[best].slotName;
			Name owner = rig.OwnerOf(sn);
			if (owner != 'None' && Stored(pawn, owner) == null)
			{
				if (++rig.freeTics[hand] == FREE_TICS)
				{
					rig.SetOwner(sn, 'None');
					Feel(pnum, hand, 0.8, 80);
					pawn.A_StartSound("misc/i_pkup", CHAN_AUTO, CHANF_LOCAL);
				}
			}
		}
		else rig.freeTics[hand] = 0;

		rig.upTics[hand] = grip ? 0 : min(rig.upTics[hand] + 1, 1000);
		rig.gripWas[hand] = grip;
	}

	// Holster, draw or swap. Every machine runs this on the same tic.
	private void Act(int pnum, PlayerPawn pawn, RSBH_Rig rig, int hand, int s, Weapon held, bool empty)
	{
		if (pawn.player.PendingWeapon != WP_NOCHANGE) { Refuse(pnum, pawn, hand); return; }
		Name sn = table.slots[s].slotName;
		Name owner = rig.OwnerOf(sn);
		Weapon stored = Stored(pawn, owner);

		if (empty)
		{
			// Draw.
			if (stored == null) { Refuse(pnum, pawn, hand); return; }
			ToHand(pawn, stored, hand);
			Done(pnum, pawn, hand);
			return;
		}

		Name mine = held.GetClassName();
		bool ownerHeldElsewhere = owner != 'None' && owner != mine && stored == null
			&& pawn.FindInventory((class<Inventory>)(owner)) != null;
		if (ownerHeldElsewhere) { Refuse(pnum, pawn, hand); return; }   // its weapon is in your other hand

		if (stored != null && owner != mine)
		{
			// Swap: that weapon to this hand; yours goes home (to its own spot, if it has one).
			ToHand(pawn, stored, hand);
			Done(pnum, pawn, hand);
			return;
		}

		// Holster: this spot becomes (or already is) the weapon's own.
		let fist = FindEmptyHand(pawn, hand);
		if (fist == null) { Refuse(pnum, pawn, hand); return; }
		rig.SetOwner(sn, mine);
		ToHand(pawn, fist, hand);
		Done(pnum, pawn, hand);
	}

	private void Done(int pnum, PlayerPawn pawn, int hand)
	{
		Feel(pnum, hand, 0.9, 60);
		pawn.A_StartSound("rs_holster_fx_store", CHAN_AUTO);
	}

	private void Refuse(int pnum, PlayerPawn pawn, int hand)
	{
		Feel(pnum, hand, 0.7, 140);
		pawn.A_StartSound("*usefail", CHAN_AUTO, CHANF_LOCAL);
	}

	// ---- the look: this machine's, client-side actors only ----

	private void UpdateLook()
	{
		int n = table != null ? table.slots.Size() : 0;
		while (rings.Size() < n) rings.Push(null);
		while (guns.Size() < n * MAXPLAYERS) guns.Push(null);

		for (int i = 0; i < MAXPLAYERS; ++i)
		{
			PlayerPawn pawn = playeringame[i] ? players[i].mo : null;
			let rig = pawn != null ? RSBH_Rig(pawn.FindInventory('RSBH_Rig')) : null;
			bool ok = false; double yaw; Vector3 neck, chest, pelvis;
			if (rig != null) { [ok, yaw, neck, chest, pelvis] = VRTorso.Get(i); }
			double e = rig != null ? rig.standEye : 0;
			bool live = ok && e >= 10;

			for (int s = 0; s < n; ++s)
			{
				RSBH_Slot sl = table.slots[s];
				Vector3 at = live ? SlotPos(sl, yaw, chest, pelvis, e) : (0, 0, 0);

				// The weapon hanging there.
				int gi = i * n + s;
				Weapon w = live ? Stored(pawn, rig.OwnerOf(sl.slotName)) : null;
				if (w != null && guns[gi] == null)
					guns[gi] = RSBH_Gun(Actor.SpawnClientSide('RSBH_Gun', at, NO_REPLACE));
				if (guns[gi] != null)
					guns[gi].ShowAt(w, at, yaw, sl, e);

				// The rings: the local player's, near a hand only.
				if (i != consoleplayer) continue;
				double vis = 0; bool hot = false;
				if (live)
				{
					for (int h = 0; h < 2; ++h)
					{
						if (rig.claim[h] == s) { vis = 1.0; hot = true; }
						int valid; Vector3 hp; double a, p, r;
						[valid, hp, a, p, r] = players[i].GetVRHand(h);
						if (!valid) continue;
						double d = (hp - at).Length() / (sl.radius * e);
						if (d < 2.5) vis = max(vis, 0.35 * (2.5 - d) / 1.5);
					}
				}
				if (vis > 0 && rings[s] == null)
					rings[s] = RSBH_Ring(Actor.SpawnClientSide('RSBH_Ring', at, NO_REPLACE));
				if (rings[s] != null)
					rings[s].ShowAt(at, sl.radius * e, min(vis, 1.0), hot);
			}
		}
	}
}

// ---------------------------------------------------------------- the look's actors

class RSBH_Ring : Actor
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

	void ShowAt(Vector3 at, double radius, double vis, bool hot)
	{
		if (vis <= 0.01) { bInvisible = true; return; }
		bInvisible = false;
		SetOrigin(at, true);
		double k = radius / 3.0;   // the mesh is radius 3 at scale 1 (MODELDEF.bodyholsters)
		Scale = (k, k);
		Alpha = vis * 0.85;
		SetState(ResolveState(hot ? "Hot" : "Idle"));
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

class RSBH_Gun : Actor
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

	// The weapon's own 3D model (level.GetActorModelClass, A_ChangeModel), sized to the spot and
	// hung by where it is: muzzle down at the hips and chest, slung up across the back from the
	// shoulders.
	void ShowAt(Weapon w, Vector3 at, double yaw, RSBH_Slot sl, double e)
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
			double k = (found && rad > 0) ? (sl.radius * e * 1.6) / rad : 0.18;
			Scale = (k, k);
		}
		bInvisible = false;
		SetOrigin(at, true);
		bool shoulder = sl.blind;
		Angle = yaw + (shoulder ? 180 : 0);
		Pitch = shoulder ? -60 : 85;
		Roll  = 0;
	}

	States
	{
	Spawn:
		TNT1 A -1;
		Stop;
	}
}

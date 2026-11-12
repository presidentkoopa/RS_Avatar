// THE BODY HOLSTERS: THE RULES (first build, 2026-11-12).
//
// Three parts, one contract (UZDXREMA docs/plans/holsters/GEAR_CONTRACT.md):
//   the SIM    the engine (p_vrtorso, p_vrgear). Every tic, for every player, on every machine, from the
//              tic command alone: where each spot is, which spot each hand is in, when a grip or Use press
//              counts. It queues ONE thing: "this hand pressed in this spot". It never touches the inventory.
//   the RULES  this file. They take the presses off the queue and decide what each one means: store,
//              draw, swap, go home, refuse. Play scope, every machine, players in index order.
//   the LOOK   zscript/gear/look.zs. Rings, stored guns, lights, pulses, sounds. This machine only.
//
// The behaviour is RSQ TacticalRig's, ported rule for rule. Every rule below carries the line it comes
// from: "rig.zs:N" is rsq_ubqseries/TacticalRig/zscript/rsqtr/rig.zs (commit 2ecc7c42), "Fxx" is the
// item in docs/plans/holsters/TACTICALRIG_FLOOR.md.
//
// What is NOT TacticalRig's here, and why:
//   - nothing reads consoleplayer or a cvar: TacticalRig decided on one machine and sent events
//     (rig.zs:16-19); here every machine runs the same rules from the same queue.
//   - contents and assignment are the engine's two saved records per player per spot (VRGear.Content,
//     VRGear.Assigned), not handler fields (rig.zs:132-141).
//   - classes are found through the VRGEAR lump (emptyhand, item..as, ownhome, holds), not by names in code.

class RAG_Rules : EventHandler
{
	// ---- the off-hand raise that waits for the main hand (rig.zs:142-143, QueueOff rig.zs:2013-2018) ----
	// Sim state: written only here, in WorldTick, the same on every machine. Saved with the level's handlers.
	Name offNext[MAXPLAYERS];
	int offWait[MAXPLAYERS];

	// =====================================================================================
	// What is what
	// =====================================================================================

	static bool IsGunSpot(int spot)
	{
		return VRGear.SpotType(spot) == VRGear.ST_GUN && VRGear.SpotRule(spot) == VRGear.RULE_HOLSTER;
	}

	// The weapon of that class the player carries, or null. A class that is not loaded is null, quietly.
	static Weapon Owned(PlayerPawn pawn, Name cls)
	{
		if (pawn == null || cls == 'None') return null;
		class<Weapon> wc = (class<Weapon>)(cls);
		if (wc == null) return null;
		return Weapon(pawn.FindInventory(wc));
	}

	// H1 (rig.zs:1469-1479): what is in gun holster `spot`: what was put there by hand, only while the
	// player still owns that weapon. So after a death or a pistol start a holster reads empty until he has
	// the gun again, "then it is back where you kept it" (N2, rig.zs:3716-3719).
	static Name Held(int pnum, PlayerPawn pawn, int spot)
	{
		if (!IsGunSpot(spot)) return 'None';
		Name c = VRGear.Content(pnum, spot);
		if (c == 'None') return 'None';
		return Owned(pawn, c) != null ? c : 'None';
	}

	// B1 (rig.zs:484-506, HeldAs): Brutal Doom's "Dual..." weapons are filed as the single gun they pair:
	// the owned gun whose class name ends in the Dual's name minus "Dual" and a plural s, else the owned
	// gun with the same SelectionOrder. An off-hand weapon keeps its own name here (rig.zs:488).
	static Name HeldAs(PlayerPawn pawn, Weapon w)
	{
		if (w == null) return 'None';
		Name cn = w.GetClassName();
		if (w.bOffhandWeapon) return cn;
		String low = cn;
		low = low.MakeLower();
		if (low.IndexOf("dual") != 0) return cn;
		String stem = low.Mid(4);
		if (stem.Length() > 1 && stem.Mid(stem.Length() - 1) == "s") stem = stem.Left(stem.Length() - 1);
		Weapon bySel = null;
		for (Inventory it = pawn.Inv; it != null; it = it.Inv)
		{
			Weapon o = Weapon(it);
			if (o == null || o == w || o.bCheatNotWeapon || o.bOffhandWeapon) continue;
			String ol = o.GetClassName();
			ol = ol.MakeLower();
			if (ol.IndexOf("dual") == 0) continue;
			if (stem.Length() > 0 && ol.Length() >= stem.Length() && ol.Mid(ol.Length() - stem.Length()) == stem) return o.GetClassName();
			if (bySel == null && o.SelectionOrder == w.SelectionOrder) bySel = o;
		}
		if (bySel != null) return bySel.GetClassName();
		return cn;
	}

	// J1a (rig.zs:1973-2003, SingleOf): the single gun of Brutal Doom's combined two-gun weapon
	// ("DualPistols" -> "BrutalPistol"), or 'None' if cls is not one. Found, not named: the parent of an
	// off-hand copy the player owns whose name ends the same way, else a weapon class (not an off-hand
	// one, not CHEATNOTWEAPON) whose name ends in the Dual name's stem.
	static Name SingleOf(PlayerPawn pawn, Name cls)
	{
		String low = cls;
		low = low.MakeLower();
		if (low.IndexOf("dual") != 0) return 'None';
		String stem = low.Mid(4);
		if (stem.Length() > 1 && stem.Mid(stem.Length() - 1) == "s") stem = stem.Left(stem.Length() - 1);
		if (stem.Length() < 3) return 'None';
		for (Inventory it = pawn.Inv; it != null; it = it.Inv)
		{
			Weapon w = Weapon(it);
			if (w == null || !w.bOffhandWeapon) continue;
			class<Weapon> pc = (class<Weapon>)(w.GetParentClass());
			if (pc == null) continue;
			Name pn = pc.GetClassName();
			String pl = pn;
			pl = pl.MakeLower();
			if (pl.IndexOf("dual") != 0 && pl.Length() >= stem.Length() && pl.Mid(pl.Length() - stem.Length()) == stem) return pn;
		}
		for (int i = 0; i < AllActorClasses.Size(); i++)
		{
			class<Weapon> c = (class<Weapon>)(AllActorClasses[i]);
			if (c == null) continue;
			let d = GetDefaultByType(c);
			if (d == null || d.bOffhandWeapon || d.bCheatNotWeapon) continue;
			Name cn = c.GetClassName();
			String cl = cn;
			cl = cl.MakeLower();
			if (cl.IndexOf("dual") == 0 || cl.Length() < stem.Length() || cl.Mid(cl.Length() - stem.Length()) != stem) continue;
			return cn;
		}
		return 'None';
	}

	// B3 (rig.zs:538-544, IsSeriesTool) and the saber (rig.zs:529-534): never an "empty hand".
	static bool NeverEmptyHand(Weapon w)
	{
		String n = w.GetClassName();
		n = n.MakeLower();
		return n.IndexOf("rsqwp_") == 0 || n.IndexOf("ssq_") == 0 || n.IndexOf("rsqgr_") == 0
			|| n.IndexOf("rsqgn_") == 0 || n.IndexOf("rsq_grenade") == 0 || n.IndexOf("ubqs_saber") == 0;
	}

	// B4 (rig.zs:624-647, EmptyHand): the weapon the MAIN hand holds when it holds nothing.
	// First the VRGEAR lump's `emptyhand` list, in its order (it stands where TacticalRig's rsqtr_empty
	// cvar stood, rig.zs:626-633: the rules read no cvar): a weapon of a listed class that the player
	// carries and that is not an off-hand weapon. If the list gives none, TacticalRig's own search: the
	// carried slot-1 weapon with the highest SelectionOrder (the fist rather than the chainsaw).
	static Weapon EmptyMain(PlayerPawn pawn)
	{
		int n = VRGear.EmptyHandCount();
		for (int i = 0; i < n; i++)
		{
			class<Weapon> wc = (class<Weapon>)(VRGear.EmptyHandAt(i));
			if (wc == null) continue;
			let d = GetDefaultByType(wc);
			if (d == null || d.bOffhandWeapon) continue;
			for (Inventory it = pawn.Inv; it != null; it = it.Inv)
			{
				Weapon w = Weapon(it);
				if (w != null && w is wc && w != pawn.player.OffhandWeapon) return w;
			}
		}
		Weapon best = null;
		for (Inventory it = pawn.Inv; it != null; it = it.Inv)
		{
			Weapon w = Weapon(it);
			if (w == null || w.bOffhandWeapon || NeverEmptyHand(w)) continue;
			bool found; int slot, idx;
			[found, slot, idx] = pawn.player.weapons.LocateWeapon(w.GetClass());
			if (!found || slot != 1) continue;
			if (best == null || w.SelectionOrder > best.SelectionOrder) best = w;
		}
		return best;
	}

	// H5 (rig.zs:2005-2011, OffEmptyName): what the OFF hand holds when it is empty: the weapon pack's own
	// hands. TacticalRig names the class ("RSQ_Hands"); here it is the first class in the lump's
	// `emptyhand` list that is loaded and is an off-hand weapon by default, which is that class with the
	// BD22 VR pack and nothing with plain Doom.
	static Name OffEmptyName()
	{
		int n = VRGear.EmptyHandCount();
		for (int i = 0; i < n; i++)
		{
			Name en = VRGear.EmptyHandAt(i);
			class<Weapon> wc = (class<Weapon>)(en);
			if (wc == null) continue;
			let d = GetDefaultByType(wc);
			if (d != null && d.bOffhandWeapon) return en;
		}
		return 'None';
	}

	// H4 (rig.zs:1521-1534, IsMovedGun): a gun the rig moves. A BD22 VR off-hand copy (the lump files it
	// `as` its gun) counts; else only a weapon whose class is not an off-hand weapon by default. A thing
	// with a home of its own (the saber, the whip, the cigarette: rig.zs:1523) is not a gun.
	static bool IsMovedGun(Weapon w)
	{
		if (w == null) return false;
		Name cn = w.GetClassName();
		if (VRGear.OwnHome(cn)) return false;
		if (VRGear.FiledAs(cn) != cn) return true;
		let d = GetDefaultByType(w.GetClass());
		return d != null && !d.bOffhandWeapon;
	}

	// What a hand holds (rig.zs:1720-1737, HandKind; H3 rig.zs:1511-1519, HoldsGun):
	// HK_EMPTY its empty-hand weapon or nothing, HK_GUN a gun, HK_OTHER anything else.
	// B5 (rig.zs:823-829): a thing with a home of its own is HK_OTHER, never a gun.
	static int MainKind(PlayerPawn pawn)
	{
		Weapon w = pawn.player.ReadyWeapon;
		if (w == null || VRGear.IsEmptyHand(w) || w == EmptyMain(pawn)) return VRGear.HK_EMPTY;
		if (VRGear.OwnHome(w.GetClassName())) return VRGear.HK_OTHER;
		return VRGear.HK_GUN;
	}

	static int OffKind(PlayerPawn pawn)
	{
		Weapon o = pawn.player.OffhandWeapon;
		if (o == null || VRGear.IsEmptyHand(o)) return VRGear.HK_EMPTY;
		Name on = o.GetClassName();
		if (on == OffEmptyName()) return VRGear.HK_EMPTY;
		return IsMovedGun(o) ? VRGear.HK_GUN : VRGear.HK_OTHER;
	}

	static int HandKind(PlayerPawn pawn, int hand)
	{
		return hand == 0 ? MainKind(pawn) : OffKind(pawn);
	}

	// The name the gun in that hand is filed under at a holster: the main hand's as HeldAs and, for Brutal
	// Doom's two-gun weapon, its single gun if that class is loaded (rig.zs:887-892); the off hand's
	// copy as its gun (rig.zs:894-897, MainOf rig.zs:1536-1544 = the lump's `item .. as`).
	static Name FiledGun(PlayerPawn pawn, int hand)
	{
		if (hand == 1)
		{
			Weapon o = pawn.player.OffhandWeapon;
			if (o == null) return 'None';
			return VRGear.FiledAs(o.GetClassName());
		}
		Weapon w = pawn.player.ReadyWeapon;
		if (w == null) return 'None';
		Name cls = HeldAs(pawn, w);
		Name single = SingleOf(pawn, cls);
		if (single != 'None' && single != cls)
		{
			class<Weapon> sc = (class<Weapon>)(single);
			if (sc != null) cls = single;
		}
		return VRGear.FiledAs(cls);
	}

	// =====================================================================================
	// Assignment (B6, B7)
	// =====================================================================================

	// B7 (rig.zs:810-815, LockedTo): the gun holster cls is assigned to, or -1.
	static int LockedTo(int pnum, Name cls)
	{
		if (cls == 'None') return -1;
		int n = VRGear.SpotCount();
		for (int r = 0; r < n; r++) if (VRGear.Assigned(pnum, r) == cls) return r;
		return -1;
	}

	// B6 (rig.zs:830-837, MayEnter): may gun cls go into gun holster r by hand? Not a thing with its own
	// home (B5); the holster is unassigned or this gun's; the holster is empty or already holds this gun.
	static bool MayEnter(int pnum, PlayerPawn pawn, Name cls, int r)
	{
		if (VRGear.OwnHome(cls)) return false;
		Name asg = VRGear.Assigned(pnum, r);
		if (asg != 'None' && asg != cls) return false;
		Name c = Held(pnum, pawn, r);
		return c == 'None' || c == cls;
	}

	// D3 (rig.zs:882-901, WouldRefuse): the gun in that hand would be refused at gun holster r.
	static bool WouldRefuse(int pnum, PlayerPawn pawn, int hand, int r)
	{
		Name cls = FiledGun(pawn, hand);
		if (cls == 'None') return false;
		return LockedTo(pnum, cls) < 0 && !MayEnter(pnum, pawn, cls, r);
	}

	// B7 (rig.zs:840-846, Assign): cls is assigned to gun holster r and to no other.
	// Returns true when the holster had no owner before: the first time it becomes a gun's (EV_ASSIGNED).
	private bool Assign(int pnum, Name cls, int r)
	{
		if (cls == 'None' || !IsGunSpot(r) || VRGear.OwnHome(cls)) return false;
		bool first = VRGear.Assigned(pnum, r) == 'None';
		int n = VRGear.SpotCount();
		for (int j = 0; j < n; j++) if (VRGear.Assigned(pnum, j) == cls) VRGear.SetAssigned(pnum, j, 'None');
		VRGear.SetAssigned(pnum, r, cls);
		return first;
	}

	// "One gun, one place" (rig.zs:1895-1897): cls leaves every spot but `keep`.
	private void ClearContentOf(int pnum, Name cls, int keep)
	{
		int n = VRGear.SpotCount();
		for (int k = 0; k < n; k++)
			if (k != keep && VRGear.Content(pnum, k) == cls) VRGear.SetContent(pnum, k, 'None');
	}

	// E4 (rig.zs:1169-1190, LockedHome): gun cls, held at gun holster r, is assigned to holster `home`
	// (not r). cls goes into home; r's gun, if any and not cls, comes out to that hand; a gun that was
	// sitting in home moves into r, "so no holstered gun is lost". Returns the gun that comes out, or null.
	private Weapon LockedHome(int pnum, PlayerPawn pawn, Name cls, int r, int home)
	{
		Name atR = Held(pnum, pawn, r);
		Name atHome = VRGear.Content(pnum, home);
		Weapon outW = (atR != 'None' && atR != cls) ? Owned(pawn, atR) : null;
		ClearContentOf(pnum, cls, -1);
		VRGear.SetContent(pnum, home, cls);
		VRGear.SetContent(pnum, r, (atHome != 'None' && atHome != cls) ? atHome : 'None');
		return outW;
	}

	// =====================================================================================
	// The hands
	// =====================================================================================

	// A weapon into the MAIN hand, the engine's own way: PendingWeapon (rig.zs:1866-1867, 1907-1908).
	private void ToMain(PlayerPawn pawn, Weapon w)
	{
		if (IsMovedGun(w)) w.bOffhandWeapon = false;
		pawn.player.PendingWeapon = w;
	}

	// The MAIN hand goes empty (rig.zs:1875-1876, 1915-1916). `was` is what it held.
	private void MainEmpty(PlayerPawn pawn, Weapon was)
	{
		Weapon empty = EmptyMain(pawn);
		if (empty != null && empty != was) pawn.player.PendingWeapon = empty;
	}

	// J3 (rig.zs:2013-2018, QueueOff): the weapon to raise into the OFF hand once the main hand has
	// finished switching. One PendingWeapon is all the engine has, so the off hand's turn is queued.
	private void QueueOff(int pnum, Name cls)
	{
		if (cls == 'None') return;
		offNext[pnum] = cls;
		offWait[pnum] = 70;
	}

	// H5 (rig.zs:1548-1556, EmptyOff): the OFF hand goes empty: the pack's hands if it has them, else nothing.
	private void EmptyOff(int pnum, PlayerPawn pawn)
	{
		Name en = OffEmptyName();
		if (en != 'None') { QueueOff(pnum, en); return; }
		pawn.player.SetPsprite(PSP_OFFHANDWEAPON, null);
		pawn.player.OffhandWeapon = null;
	}

	// J3 (rig.zs:2023-2080, TickPairs): every player, every tic. Once the main hand has finished switching,
	// the queued weapon is raised into the off hand (an off-hand-flagged weapon raised through
	// PendingWeapon goes to the off hand; the BD22 VR pack then swaps in the right version of the gun,
	// its dual.zs "THE OFF-HAND RULE"). WHILE THE ENGINE IS STEADYING A TWO-HANDED GUN THE RAISE WAITS and
	// the 70-tic timer does not run (rig.zs:2038-2071): the gun arrives when the grip is let go.
	private void TickPairs()
	{
		for (int n = 0; n < MAXPLAYERS; n++)
		{
			if (offNext[n] == 'None') continue;
			if (!playeringame[n] || players[n].mo == null || players[n].mo.health <= 0) { offNext[n] = 'None'; continue; }
			PlayerInfo p = players[n];
			if ((p.WeaponState & WF_TWOHANDSTABILIZED) != 0) continue;
			offWait[n] = offWait[n] - 1;
			if (offWait[n] <= 0) { offNext[n] = 'None'; continue; }
			if (p.PendingWeapon != WP_NOCHANGE) continue;          // the main hand is still switching
			class<Weapon> c = (class<Weapon>)(offNext[n]);
			offNext[n] = 'None';
			if (c == null) continue;
			Weapon w = Weapon(p.mo.FindInventory(c));
			if (w == null) { p.mo.GiveInventory(c, 1); w = Weapon(p.mo.FindInventory(c)); }
			if (w != null && IsMovedGun(w) && w != p.ReadyWeapon) w.bOffhandWeapon = true;
			if (w != null && p.OffhandWeapon != w) p.PendingWeapon = w;
		}
	}

	// =====================================================================================
	// The grenade spot (F1-F3) and the pouch (B11)
	// =====================================================================================

	// F2 (rig.zs:1207-1233, NadeWeapon): the hand grenade a summon spot hands out: the first `holds` row
	// whose weapon class is loaded. -1: none. Looked up at run time, so a missing pk3 breaks nothing.
	// (TacticalRig's yield to RSQ Grenade by two cvars, rig.zs:1219-1227, is not here: the rules read no
	// cvar. The lump's row order decides.)
	static int NadeRow(int spot)
	{
		int n = VRGear.SpotHoldCount(spot);
		for (int i = 0; i < n; i++)
		{
			class<Weapon> wc = (class<Weapon>)(VRGear.SpotHoldWeapon(spot, i));
			if (wc != null) return i;
		}
		return -1;
	}

	static Name NadeWeapon(int spot)
	{
		int row = NadeRow(spot);
		return row >= 0 ? VRGear.SpotHoldWeapon(spot, row) : 'None';
	}

	static Name NadeAmmo(int spot)
	{
		int row = NadeRow(spot);
		return row >= 0 ? VRGear.SpotHoldAmmo(spot, row) : 'None';
	}

	// rig.zs:1241-1246 (Grenades): how many the player carries.
	static int Grenades(PlayerPawn pawn, int spot)
	{
		class<Inventory> ac = (class<Inventory>)(NadeAmmo(spot));
		return ac != null ? pawn.CountInv(ac) : 0;
	}

	// rig.zs:3573-3581 (NadeInHand): the grenade is in a hand, or on its way into one.
	static bool NadeInHand(PlayerPawn pawn, int spot)
	{
		class<Weapon> wc = (class<Weapon>)(NadeWeapon(spot));
		if (wc == null) return false;
		PlayerInfo p = pawn.player;
		if (p.ReadyWeapon != null && p.ReadyWeapon is wc) return true;
		if (p.OffhandWeapon != null && p.OffhandWeapon is wc) return true;
		return p.PendingWeapon != WP_NOCHANGE && p.PendingWeapon != null && p.PendingWeapon is wc;
	}

	// M9 (rig.zs:2962-2973, AmmoState): a stored gun's ammo. 0 half a magazine or more, 1 low or empty with
	// rounds to reload, 2 nothing at all, -1 a gun with no ammo. A gun with a magazine counts its magazine.
	static int AmmoState(Weapon w)
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

	// M18 (rig.zs:3517-3525, ReserveState): the RESERVE of a gun, what a reload takes: 0 two magazines or
	// more (no magazine: a quarter of the carry), 1 less, 2 none, -1 a gun with no ammo.
	static int ReserveState(Weapon w)
	{
		if (w == null || w.Ammo1 == null) return -1;
		bool mag = w.Ammo2 != null && w.Ammo2 != w.Ammo1;
		int have = w.Ammo1.Amount;
		int need = mag ? 2 * max(1, w.Ammo2.MaxAmount) : max(1, w.Ammo1.MaxAmount / 4);
		if (have <= 0) return 2;
		return have >= need ? 0 : 1;
	}

	// B11 (rig.zs:609-612, PouchOn): the pouch exists while the weapon pack with the hand reloads is loaded:
	// TacticalRig tests for that pack's hands class; so does this (OffEmptyName).
	static bool PouchLive()
	{
		return OffEmptyName() != 'None';
	}

	// rig.zs:2314: the pouch "holds something" while the gun in the main hand has reserve.
	static bool PouchHolds(PlayerPawn pawn)
	{
		int st = ReserveState(pawn.player.ReadyWeapon);
		return st == 0 || st == 1;
	}

	// The two bits the sim reads next tic (contract section 5; SpotHolds rig.zs:2297-2316, RegionLive
	// rig.zs:2713-2723).
	static bool SpotLiveNow(PlayerPawn pawn, int spot)
	{
		int rule = VRGear.SpotRule(spot);
		if (rule == VRGear.RULE_SUMMON) return NadeRow(spot) >= 0;      // the pack has a hand grenade (rig.zs:2716)
		if (rule == VRGear.RULE_ZONE) return PouchLive();
		return true;                                                    // gun holsters always (rig.zs:2721)
	}

	static bool SpotHoldsNow(int pnum, PlayerPawn pawn, int spot)
	{
		int rule = VRGear.SpotRule(spot);
		if (rule == VRGear.RULE_SUMMON) return Grenades(pawn, spot) > 0 && !NadeInHand(pawn, spot);   // rig.zs:2300
		if (rule == VRGear.RULE_ZONE) return PouchHolds(pawn);                                        // rig.zs:2314
		return Held(pnum, pawn, spot) != 'None';                                                      // rig.zs:2299
	}

	// M6 (rig.zs:3129-3196, HandActs): would a press by hand h at spot r do something now? Press's own
	// tests, in Press's order. A refusal is not "doing something". The look uses it for ring brightness.
	static bool HandActs(int pnum, PlayerPawn pawn, int h, int r)
	{
		if (!VRGear.SpotLive(pnum, r)) return false;
		int rule = VRGear.SpotRule(r);
		if (rule == VRGear.RULE_SUMMON)
		{
			Name wn = NadeWeapon(r);
			Weapon rw = pawn.player.ReadyWeapon;
			bool inHand = wn != 'None' && rw != null && rw.GetClassName() == wn;
			return inHand || Grenades(pawn, r) > 0;                      // rig.zs:3142-3147
		}
		if (rule == VRGear.RULE_ZONE) return PouchHolds(pawn);           // rig.zs:3151-3153
		if (!IsGunSpot(r)) return false;
		int kind = HandKind(pawn, h);
		if (kind == VRGear.HK_GUN) return !WouldRefuse(pnum, pawn, h, r);   // rig.zs:3185
		Weapon inHandW = h == 0 ? pawn.player.ReadyWeapon : pawn.player.OffhandWeapon;
		if (kind == VRGear.HK_OTHER && inHandW != null && VRGear.OwnHome(inHandW.GetClassName())) return false;
		if (Held(pnum, pawn, r) != 'None') return true;                  // a draw (rig.zs:3186)
		return kind == VRGear.HK_EMPTY && VRGear.Assigned(pnum, r) != 'None';   // free by hand (rig.zs:3188)
	}

	// =====================================================================================
	// The result events. Exactly one outcome per press (contract section 6; L9 rig.zs:2850-2856).
	// =====================================================================================

	// D4 (rig.zs:850-859, Refused): the refusal names the gun to show: the one the holster is assigned
	// to, else the one in it. why: 1 another gun's, 2 full, 3 empty holster + empty hand, 4 no grenades,
	// 5 a thing with its own home, 6 other.
	private void PostRefuse(int pnum, PlayerPawn pawn, int hand, int r, int why)
	{
		Name owner = 'None';
		if (IsGunSpot(r))
		{
			owner = VRGear.Assigned(pnum, r);
			if (owner == 'None') owner = Held(pnum, pawn, r);
		}
		VRGear.Post(pnum, VRGear.EV_REFUSED, hand, r, owner, why);
	}

	// A gun that failed MayEnter: which of its three reasons (rig.zs:830-837).
	private void RefuseGun(int pnum, PlayerPawn pawn, int hand, int r, Name cls)
	{
		Name asg = VRGear.Assigned(pnum, r);
		int why = 2;
		if (VRGear.OwnHome(cls)) why = 5;
		else if (asg != 'None' && asg != cls) why = 1;
		PostRefuse(pnum, pawn, hand, r, why);
	}

	// =====================================================================================
	// Holster and draw, the main hand (J1, J2)
	// =====================================================================================

	// J1 (rig.zs:1826-1922, Holster): the main hand's gun onto gun holster r.
	private void HolsterMain(int pnum, PlayerPawn pawn, int r)
	{
		PlayerInfo p = pawn.player;
		Weapon w = p.ReadyWeapon;
		if (w == null) { PostRefuse(pnum, pawn, 0, r, 6); return; }
		Name cls = HeldAs(pawn, w);
		// J1a (rig.zs:1835-1857): Brutal Doom's combined two-gun weapon goes in as ONE single gun. The single
		// is given if missing, with no ammo of its own, as Brutal Doom's own switch to single gives it.
		Name single = SingleOf(pawn, cls);
		if (single != 'None' && single != cls)
		{
			class<Weapon> sc = (class<Weapon>)(single);
			if (sc != null && pawn.FindInventory(sc) == null)
			{
				Weapon g = Weapon(Actor.Spawn(sc, pawn.Pos, NO_REPLACE));
				if (g != null)
				{
					g.AmmoGive1 = 0;
					g.AmmoGive2 = 0;
					if (!g.CallTryPickup(pawn)) g.Destroy();
				}
			}
			if (sc != null && pawn.FindInventory(sc) != null) cls = single;
		}
		cls = VRGear.FiledAs(cls);
		int home = LockedTo(pnum, cls);
		// J1c (rig.zs:1861): a gun with no home enters only a holster MayEnter allows. Refused first,
		// before anything is stored (L9).
		if (home < 0 && !MayEnter(pnum, pawn, cls, r)) { RefuseGun(pnum, pawn, 0, r, cls); return; }
		// J1d, E4 (rig.zs:1862-1880): a gun with a home elsewhere goes home; r's gun comes to the hand.
		if (home >= 0 && home != r)
		{
			Weapon outGun = LockedHome(pnum, pawn, cls, r, home);
			if (outGun != null && outGun != w)
			{
				ToMain(pawn, outGun);
				VRGear.SetDraw(pnum, 0, outGun.GetClassName());         // C4 (rig.zs:1868-1869)
			}
			else MainEmpty(pawn, w);
			VRGear.Post(pnum, VRGear.EV_WENT_HOME, 0, r, cls, home);
			return;
		}
		// J1f (rig.zs:1887-1921): "one gun, one place": it leaves wherever else it was; stored; assigned;
		// what was there comes out to the hand (a swap), else the hand goes empty. "The off hand is never
		// touched here" (rig.zs:1903-1904).
		Name was = Held(pnum, pawn, r);
		Weapon incoming = null;
		if (was != 'None' && was != cls) incoming = Owned(pawn, was);
		ClearContentOf(pnum, cls, r);
		VRGear.SetContent(pnum, r, cls);
		bool first = Assign(pnum, cls, r);
		if (incoming != null)
		{
			ToMain(pawn, incoming);
			VRGear.SetDraw(pnum, 0, incoming.GetClassName());           // C4 (rig.zs:1909-1910)
			VRGear.Post(pnum, VRGear.EV_SWAPPED, 0, r, was, 0);
		}
		else
		{
			MainEmpty(pawn, w);
			VRGear.Post(pnum, VRGear.EV_STORED, 0, r, cls, 0);
		}
		if (first) VRGear.Post(pnum, VRGear.EV_ASSIGNED, 0, r, cls, 0);   // D5 (rig.zs:843)
	}

	// J2 (rig.zs:1924-1958, Draw): gun holster r's one gun into the MAIN hand. "One gun, in the hand
	// that drew it": the off-hand copy is never brought along. Not if it is already in the off hand.
	private void DrawMain(int pnum, PlayerPawn pawn, int r)
	{
		PlayerInfo p = pawn.player;
		Name c = Held(pnum, pawn, r);
		Weapon w = Owned(pawn, c);
		if (w == null || w == p.OffhandWeapon) { PostRefuse(pnum, pawn, 0, r, 6); return; }   // rig.zs:1945
		if (IsMovedGun(w)) w.bOffhandWeapon = false;
		if (p.ReadyWeapon != w) p.PendingWeapon = w;
		VRGear.SetContent(pnum, r, 'None');                              // the holster is emptied (rig.zs:1951)
		VRGear.SetDraw(pnum, 0, w.GetClassName());                       // C4 (rig.zs:1952-1953)
		VRGear.Post(pnum, VRGear.EV_DRAWN, 0, r, c, 0);
	}

	// =====================================================================================
	// Holster and draw, the off hand (H6, H7)
	// =====================================================================================

	// H6 (rig.zs:1558-1641, HolsterOff): the OFF hand's gun onto gun holster r.
	private void HolsterOff(int pnum, PlayerPawn pawn, int r)
	{
		PlayerInfo p = pawn.player;
		Weapon w = p.OffhandWeapon;
		if (!IsMovedGun(w)) { PostRefuse(pnum, pawn, 1, r, 6); return; }
		Name offCn = w.GetClassName();
		Name cls = VRGear.FiledAs(offCn);            // the off-hand copy goes in under its gun's name (rig.zs:1565)
		int home = LockedTo(pnum, cls);
		if (home < 0 && !MayEnter(pnum, pawn, cls, r)) { RefuseGun(pnum, pawn, 1, r, cls); return; }   // rig.zs:1568
		// BD22 VR DUAL WIELD (rig.zs:1570-1617): the off hand holds gun G's off-hand copy while the main
		// hand holds G itself. Put away, the copy takes G with it: G goes home to its own holster, and
		//   A. at G's own holster (or a free one): both hands go to their fists;
		//   B. at a holster of another gun X with X in it: the off hand goes to its fist and the MAIN hand takes X.
		// An unassigned G at a free holster (MayEnter passed above): that holster becomes G's, then as A.
		bool dualCopy = cls != offCn && p.ReadyWeapon != null
			&& VRGear.FiledAs(HeldAs(pawn, p.ReadyWeapon)) == cls;         // rig.zs:1579
		bool first = false;
		if (dualCopy && home < 0) { first = Assign(pnum, cls, r); home = r; }   // rig.zs:1581
		if (home >= 0 && dualCopy)
		{
			Weapon outW = null;
			if (home != r) outW = LockedHome(pnum, pawn, cls, r, home);
			else
			{
				ClearContentOf(pnum, cls, r);
				VRGear.SetContent(pnum, r, cls);
			}
			EmptyOff(pnum, pawn);
			if (outW != null && outW != p.ReadyWeapon)
			{
				outW.bOffhandWeapon = false;                               // case B: the MAIN hand takes X
				p.PendingWeapon = outW;
				VRGear.SetDraw(pnum, 0, outW.GetClassName());             // rig.zs:1601-1602
			}
			else MainEmpty(pawn, p.ReadyWeapon);                           // case A: the main hand to its fist
			if (home != r) VRGear.Post(pnum, VRGear.EV_WENT_HOME, 1, r, cls, home);
			else VRGear.Post(pnum, VRGear.EV_STORED, 1, r, cls, 0);
			if (first) VRGear.Post(pnum, VRGear.EV_ASSIGNED, 1, r, cls, 0);
			return;
		}
		// A gun with a home elsewhere goes home and r's gun comes to the OFF hand (rig.zs:1618-1625).
		if (home >= 0 && home != r)
		{
			Weapon outGun = LockedHome(pnum, pawn, cls, r, home);
			if (outGun != null && outGun != p.ReadyWeapon)
			{
				outGun.bOffhandWeapon = true;
				QueueOff(pnum, outGun.GetClassName());
			}
			else EmptyOff(pnum, pawn);
			VRGear.Post(pnum, VRGear.EV_WENT_HOME, 1, r, cls, home);
			return;
		}
		// Otherwise the gun goes in, is assigned, and what was there comes to the off hand (rig.zs:1626-1640).
		Name was = Held(pnum, pawn, r);
		ClearContentOf(pnum, cls, r);
		VRGear.SetContent(pnum, r, cls);
		bool firstHere = Assign(pnum, cls, r);
		Weapon incoming = (was != 'None' && was != cls) ? Owned(pawn, was) : null;
		if (incoming != null && incoming != p.ReadyWeapon)
		{
			incoming.bOffhandWeapon = true;
			QueueOff(pnum, was);
			VRGear.Post(pnum, VRGear.EV_SWAPPED, 1, r, was, 0);
		}
		else
		{
			EmptyOff(pnum, pawn);
			VRGear.Post(pnum, VRGear.EV_STORED, 1, r, cls, 0);
		}
		if (firstHere) VRGear.Post(pnum, VRGear.EV_ASSIGNED, 1, r, cls, 0);
	}

	// H7 (rig.zs:1663-1678, DrawOff): gun holster r's gun into the OFF hand: flagged off-hand, the raise
	// queued, the holster emptied. Not if the main hand already holds that weapon.
	private void DrawOff(int pnum, PlayerPawn pawn, int r)
	{
		PlayerInfo p = pawn.player;
		Name c = Held(pnum, pawn, r);
		Weapon w = Owned(pawn, c);
		if (w == null || w == p.ReadyWeapon) { PostRefuse(pnum, pawn, 1, r, 6); return; }   // rig.zs:1670
		w.bOffhandWeapon = true;
		VRGear.SetContent(pnum, r, 'None');
		QueueOff(pnum, c);
		VRGear.SetDraw(pnum, 1, w.GetClassName());                       // C4 (rig.zs:1674-1675)
		VRGear.Post(pnum, VRGear.EV_DRAWN, 1, r, c, 0);
	}

	// =====================================================================================
	// The grenade spot (F1, F3, L2)
	// =====================================================================================

	// F1 (rig.zs:1251-1276, Nade; L2 rig.zs:2745-2756): either hand grips it and the pack's hand grenade
	// comes to the MAIN hand; gripped again with the grenade in the hand, the gun he had comes back
	// (else the empty hand). F3: none is handed out with zero grenades.
	private void NadePress(int pnum, PlayerPawn pawn, int hand, int r)
	{
		PlayerInfo p = pawn.player;
		Name wn = NadeWeapon(r);
		class<Weapon> wc = (class<Weapon>)(wn);
		if (wc == null) { VRGear.Post(pnum, VRGear.EV_REFUSED, hand, r, 'None', 6); return; }
		if (p.ReadyWeapon != null && p.ReadyWeapon is wc)
		{
			// back: the gun he had (rig.zs:1259-1267)
			Weapon back = Owned(pawn, VRGear.PrevWeapon(pnum));
			if (back == null) back = EmptyMain(pawn);
			if (back != null) p.PendingWeapon = back;
			VRGear.Post(pnum, VRGear.EV_STORED, 0, r, wn, 0);
			return;
		}
		Weapon w = Weapon(pawn.FindInventory(wc));
		if (w == null || Grenades(pawn, r) <= 0)                           // F3 (rig.zs:1269; L2 rig.zs:2750-2754)
		{
			VRGear.Post(pnum, VRGear.EV_REFUSED, hand, r, 'None', 4);
			return;
		}
		Name prev = 'None';
		if (p.ReadyWeapon != null) prev = p.ReadyWeapon.GetClassName();
		VRGear.SetPrevWeapon(pnum, prev);                                 // rig.zs:1270-1271
		p.PendingWeapon = w;
		VRGear.SetDraw(pnum, 0, w.GetClassName());                        // F3: counts as a draw (rig.zs:1273-1274)
		VRGear.Post(pnum, VRGear.EV_DRAWN, 0, r, wn, 0);
	}

	// =====================================================================================
	// A press, and a free
	// =====================================================================================

	// What a press does (rig.zs:2732-2908, Press), in the code's order, for the spots of this build.
	// L1 (cigarette), L3 (lit flare), L4 (ShieldSaw), the whip, the flare and the sabers (L5-L8, L12) are
	// not in this build: their mods are not in the weapon set.
	private void DoPress(int pnum, PlayerPawn pawn, int hand, int r)
	{
		int rule = VRGear.SpotRule(r);
		// L2 (rig.zs:2745-2756): the grenade spot, either hand.
		if (rule == VRGear.RULE_SUMMON) { NadePress(pnum, pawn, hand, r); return; }
		// L5 (rig.zs:2773): the pouch is the reload's; a press there does nothing of the rig's own. No event.
		if (rule == VRGear.RULE_ZONE) return;
		if (!IsGunSpot(r)) return;

		PlayerInfo p = pawn.player;
		int kind = HandKind(pawn, hand);
		Weapon inHandW = hand == 0 ? p.ReadyWeapon : p.OffhandWeapon;
		// L10 (rig.zs:2857-2871) the off hand, L11 (rig.zs:2872-2891) the main hand: holds a gun -> it goes
		// in (or is refused, swapped, sent home: HolsterMain / HolsterOff decide, refusing first, L9).
		if (kind == VRGear.HK_GUN)
		{
			if (hand == 0) HolsterMain(pnum, pawn, r);
			else HolsterOff(pnum, pawn, r);
			return;
		}
		// B5 (rig.zs:823-829): a thing with a home of its own never enters a gun holster.
		if (kind == VRGear.HK_OTHER && inHandW != null && VRGear.OwnHome(inHandW.GetClassName()))
		{
			PostRefuse(pnum, pawn, hand, r, 5);
			return;
		}
		// else a full holster -> draw into the hand that pressed
		if (Held(pnum, pawn, r) != 'None')
		{
			if (hand == 0) DrawMain(pnum, pawn, r);
			else DrawOff(pnum, pawn, r);
			return;
		}
		// else refuse: an empty holster and nothing to put in it (rig.zs:2870, 2886-2890)
		PostRefuse(pnum, pawn, hand, r, 3);
	}

	// K10 (rig.zs:2324-2341, FreeTick; rig.zs:1157-1168, WebUnassign): the sim saw an empty hand pressed and
	// held 35 tics in an empty, assigned gun holster. Checked again here; then no holster is assigned to
	// that gun and it is in none.
	private void DoFree(int pnum, PlayerPawn pawn, int hand, int r)
	{
		if (!IsGunSpot(r)) return;
		Name owner = VRGear.Assigned(pnum, r);
		if (owner == 'None' || Held(pnum, pawn, r) != 'None' || HandKind(pawn, hand) != VRGear.HK_EMPTY) return;
		int n = VRGear.SpotCount();
		for (int k = 0; k < n; k++)
		{
			if (VRGear.Assigned(pnum, k) == owner) VRGear.SetAssigned(pnum, k, 'None');
			if (IsGunSpot(k) && VRGear.Content(pnum, k) == owner) VRGear.SetContent(pnum, k, 'None');
		}
		VRGear.Post(pnum, VRGear.EV_FREED, hand, r, owner, 0);
	}

	// =====================================================================================
	// One tic (contract section 8, step 2)
	// =====================================================================================

	override void WorldTick()
	{
		TickPairs();                                                       // rig.zs:2088

		int spots = VRGear.SpotCount();
		for (int i = 0; i < MAXPLAYERS; i++)
		{
			if (!playeringame[i] || players[i].mo == null) continue;
			PlayerPawn pawn = players[i].mo;
			bool alive = pawn.health > 0;
			bool ok; int act, hand, spot;
			for (int guard = 0; guard < 64; guard++)
			{
				[ok, act, hand, spot] = VRGear.PopAction(i);
				if (!ok) break;
				// C3 (rig.zs:723): a dead player's actions are ignored.
				if (!alive || spot < 0 || spot >= spots || hand < 0 || hand > 1) continue;
				if (act == VRGear.ACT_PRESS) DoPress(i, pawn, hand, spot);
				else if (act == VRGear.ACT_FREE) DoFree(i, pawn, hand, spot);
			}
		}

		// THEN the bits the sim's hover reads next tic, for every player, every spot.
		for (int i = 0; i < MAXPLAYERS; i++)
		{
			if (!playeringame[i] || players[i].mo == null) continue;
			PlayerPawn pawn = players[i].mo;
			for (int s = 0; s < spots; s++)
				VRGear.SetSpotBits(i, s, SpotLiveNow(pawn, s), SpotHoldsNow(i, pawn, s));
		}
	}
}

// B11, P2 (TacticalRig hooks.zs:76-143, RSQTR_RigService). The BD22 VR pack's hand reloads ask a
// service whose class name CONTAINS "RSQTR_RigService" (its src/zscript/rsr/vreload.zs:98-108;
// ServiceIterator.Find matches part of a name) for "pouch.at": 1 that hand is in the pouch, 0 it is
// not, -1 no pouch. TacticalRig's pk3 is not loaded, so this answers it, from the sim: per player, the
// same on every machine (TacticalRig could answer for the local player only, hooks.zs:99).
// It also answers the three other things a mod may ask about a hand: "rig.busy" (C5, hooks.zs:108-125:
// the hand is INSIDE a spot), "rig.drawtic" and "rig.drawn" (C4, hooks.zs:102-107, 203-206).
// Anything else: -1 or "", as TacticalRig answers a request it does not know.
class RAG_RSQTR_RigService : Service
{
	override int GetInt(String request, String stringArg, int intArg, double doubleArg, Object objectArg, Name nameArg)
	{
		PlayerPawn who = PlayerPawn(objectArg);
		if (who == null || who.player == null) return -1;
		int pnum = who.PlayerNumber();
		if (pnum < 0 || pnum >= MAXPLAYERS) return -1;
		int h = intArg & 1;
		if (request == "pouch.at") return VRGear.HandInSpot(pnum, h, 'Pouch');
		if (request == "rig.busy") return VRGear.HandBusy(pnum, h) ? 1 : 0;
		if (request == "rig.drawtic") return VRGear.DrawTic(pnum, h);
		return -1;
	}

	override String GetString(String request, String stringArg, int intArg, double doubleArg, Object objectArg, Name nameArg)
	{
		PlayerPawn who = PlayerPawn(objectArg);
		if (who == null || who.player == null || request != "rig.drawn") return "";
		int pnum = who.PlayerNumber();
		if (pnum < 0 || pnum >= MAXPLAYERS) return "";
		Name cls = VRGear.DrawClass(pnum, intArg & 1);
		if (cls == 'None') return "";
		String s = cls;
		return s;
	}
}

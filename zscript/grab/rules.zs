// THE DISTANCE GRAB, RS_Avatar's half: the rules (engine core: UZDXREMA src/playsim/p_vrgrab.cpp,
// ZScript VRGrab; the contract: UZDXREMA docs/plans/VRGRAB_API.md; numbers: the VRGRAB and MASSDEF lumps).
//
// The engine decides, every tic, on every machine: what a hand points at, when it locks, when the
// flick pulls, when the thing is caught, when it is let go and how fast. This file does what the
// engine leaves to the mod: it MOVES THE WORLD. RAB_Rules runs in WorldTick on every machine, for
// every player in player order, and reads only VRGrab and the world. It reads no cvar and never asks
// who is at this machine: the same objects move the same way everywhere.
//
// The motion is RSQ DistanceGrab's (presidentkoopa rsq_ubqseries/DistanceGrab): the arc path of
// flight.zs (StartPath, MeasureArc, StepPath, PathE, ArcE), the release of hold.zs, the air gravity,
// settle, impact and barrel rule of throw.zs. The carry is RS_WorldHands' (rs_held.zs CarryOne):
// written to the palm by TryMove, so a held thing stops at walls.
//
// UNITS (RSQ reach.zs:482-495): 34 map units are one metre across the floor; height is stretched
// 1.2, so 28.33 map units are one metre up. A tic is 1/35 s. So a speed in metres a second is
//     map units a tic = m/s x 34 / 35        (22 m/s = 21.37 map units a tic)
// Weights are kg (VRGrab.Mass). Impact energy is joules: half kg times (m/s) squared.

class RAB_Rules : EventHandler
{
	const RM_NONE = 0;          // this hand has nothing
	const RM_FLY  = 1;          // it is flying to this hand
	const RM_HELD = 2;          // it is in this hand

	const UPM          = 34.0;  // map units in a metre across the floor
	const STRETCH      = 1.2;   // a map unit of height is this much taller than one across
	const THIN_RADIUS  = 2.0;   // a flying or carried thing is this thin (RSQ rsqdg_flight_radius; WorldHands HELD_RADIUS)
	const ORPHAN_TICS  = 3;     // a record the core no longer stands behind is dropped after this
	const BREAK_UNITS  = 51.0;  // 1.5 m: a carried thing left this far behind the palm ...
	const BREAK_TICS   = 18;    // ... for this long is let go (RSQ hold.zs:114)
	const THROW_MPS    = 0.5;   // slower than this out of the hand is a set-down (RSQ hold.zs:359)
	const SETTLE_TICS  = 10;    // a thrown thing passes through bodies at least this long (RSQ hold.zs:366)
	const SETTLE_GIVEUP = 70;   // then its own size and flags come back whatever is in the way (RSQ throw.zs:82)
	const WATCH_TICS   = 105;   // a throw can hurt for this long (RSQ throw.zs:38)
	const STILL_TICS   = 6;     // or until it has lain still this long
	const AIR_TICS     = 1400;  // the soft fall is kept at most this long (RSQ rsqdg_air_maxtics)
	const HIT_MPS      = 3.0;   // nothing is hurt below this (RSQ rsqdg_throw_min)
	const EXPLODE_MPS  = 4.0;   // a barrel thrown this hard goes off where it lands (RSQ rsqdg_throw_explode)
	const JOULES_PER_DAMAGE = 15.0;   // RSQ rsqdg_throw_j
	const STUN_DAMAGE  = 20;    // a hit this hard forces Pain and shoves (RSQ rsqdg_throw_stun)
	const MAX_VICTIMS  = 4;
	const PATH_V0      = 0.25;  // the speed it leaves the floor at, against the cruise (RSQ flight.zs)
	const PATH_V1      = 0.15;  // and arrives in the hand at
	const PATH_RAMP    = 0.15;  // the share of the flight spent picking up (RSQ: rsqdg_path_accel 1.6)
	const PATH_SETTLE  = 0.30;  // and settling into the hand (RSQ: rsqdg_path_smooth 0.6)
	const ARC_N        = 24;

	// ---- one record per (player, hand): index pnum * 2 + hand. Saved with the game. ----
	Array<Actor>  obj;
	Array<int>    mode, age, total, orphan, strain;
	Array<double> fromX, fromY, fromZ, arcH;
	// what the thing was before the hand borrowed it
	Array<int>    sNoGrav, sThru, sSpecial, sShoot;
	Array<double> sRadius, sHeight;

	// ---- everything let go, until it has settled and landed. Saved with the game. ----
	Array<Actor>  lA, lBy, lHit;
	Array<int>    lAge, lMin, lThru, lSpecial, lSettled, lWatch, lStill, lRest, lHits;
	Array<double> lRadius, lHeight, lRel, lLastMps, lLastSpeed, lBodyX, lBodyY;

	private void Ensure()
	{
		int n = MAXPLAYERS * 2;
		while (obj.Size() < n)
		{
			obj.Push(null);
			mode.Push(RM_NONE); age.Push(0); total.Push(1); orphan.Push(0); strain.Push(0);
			fromX.Push(0); fromY.Push(0); fromZ.Push(0); arcH.Push(0);
			sNoGrav.Push(0); sThru.Push(0); sSpecial.Push(0); sShoot.Push(0);
			sRadius.Push(0); sHeight.Push(0);
		}
	}

	// ---------------------------------------------------------------- small helpers

	static Vector3 MidOf(Actor a)
	{
		return (a.Pos.X, a.Pos.Y, a.Pos.Z + a.Height * 0.5);
	}

	// The true length of a map-space vector, in metres.
	static double Metres(Vector3 v)
	{
		double z = v.Z * STRETCH;
		return sqrt(v.X * v.X + v.Y * v.Y + z * z) / UPM;
	}

	// How far a thing's body reaches from its middle. A pickup's radius is its touch zone, far wider
	// than what is drawn, so a pickup is never wider than half its height (RSQ throw.zs BodyRadius).
	static double BodyRadius(Actor a, double radius, double height)
	{
		if (a is "Inventory") return min(radius, height * 0.5);
		return radius;
	}

	private void Clear(int k)
	{
		obj[k] = null;
		mode[k] = RM_NONE;
		age[k] = 0; total[k] = 1; orphan[k] = 0; strain[k] = 0;
	}

	// The hand borrows the thing: no gravity, passes through bodies, cannot be picked up by walking
	// into it, carried thin. What it was is remembered.
	private void Borrow(int k, Actor a)
	{
		sNoGrav[k]  = a.bNoGravity ? 1 : 0;
		sThru[k]    = a.bThruActors ? 1 : 0;
		sSpecial[k] = a.bSpecial ? 1 : 0;
		sShoot[k]   = (a.bShootable && a.Health > 0) ? 1 : 0;
		sRadius[k]  = a.Radius;
		sHeight[k]  = a.Height;
		a.bSpecial = false;
		a.bThruActors = true;
		a.bNoGravity = true;
		if (a.Radius > THIN_RADIUS) a.A_SetSize(THIN_RADIUS, a.Height);
		a.Vel = (0, 0, 0);
	}

	// Everything back at once (before a pickup is used).
	private void GiveBack(int k, Actor a)
	{
		a.bNoGravity  = sNoGrav[k] != 0;
		a.bThruActors = sThru[k] != 0;
		a.bSpecial    = sSpecial[k] != 0;
		if (a.Radius != sRadius[k] || a.Height != sHeight[k]) a.A_SetSize(sRadius[k], sHeight[k]);
	}

	// The hand lets go. Gravity comes back now; its size, its solidity against bodies and its
	// pickup flag come back when it fits where it is (TickLoose), so a barrel let go inside a body
	// does not trap anyone. thrower and relMps are set for a throw: it can then hurt what it hits.
	private void Loosen(int k, Actor a, int minTics, Actor thrower, double relMps, Vector3 v)
	{
		a.bNoGravity = sNoGrav[k] != 0;
		a.bThruActors = true;
		a.bSpecial = false;
		a.Vel = v;

		lA.Push(a); lBy.Push(thrower); lHit.Push(null);
		lAge.Push(0); lMin.Push(minTics);
		lThru.Push(sThru[k]); lSpecial.Push(sSpecial[k]);
		lSettled.Push(0); lWatch.Push(thrower != null && relMps > 0 ? 1 : 0);
		lStill.Push(0); lRest.Push(0); lHits.Push(0);
		lRadius.Push(sRadius[k]); lHeight.Push(sHeight[k]);
		lRel.Push(relMps); lLastMps.Push(relMps); lLastSpeed.Push(v.Length());
		double bx = 0, by = 0;
		if (thrower != null) { bx = thrower.Vel.X; by = thrower.Vel.Y; }
		lBodyX.Push(bx); lBodyY.Push(by);
		Clear(k);
	}

	// End a flight or a hold: the thing falls where it is. tell: the core does not know yet.
	private void EndRecord(int pnum, int hand, bool tell)
	{
		int k = pnum * 2 + hand;
		Actor a = obj[k];
		if (mode[k] != RM_NONE && a != null && !a.bDestroyed) Loosen(k, a, 0, null, 0, (0, 0, 0));
		Clear(k);
		if (tell) VRGrab.Abort(pnum, hand);
	}

	private void LooseDelete(int i)
	{
		lA.Delete(i); lBy.Delete(i); lHit.Delete(i);
		lAge.Delete(i); lMin.Delete(i); lThru.Delete(i); lSpecial.Delete(i);
		lSettled.Delete(i); lWatch.Delete(i); lStill.Delete(i); lRest.Delete(i); lHits.Delete(i);
		lRadius.Delete(i); lHeight.Delete(i); lRel.Delete(i); lLastMps.Delete(i); lLastSpeed.Delete(i);
		lBodyX.Delete(i); lBodyY.Delete(i);
	}

	// Its own size and flags back. force: whatever is in the way.
	private void FinishLoose(int i, bool force)
	{
		Actor a = lA[i];
		lSettled[i] = 1;
		if (a == null || a.bDestroyed) return;
		a.bThruActors = lThru[i] != 0;
		if (a.Radius != lRadius[i] || a.Height != lHeight[i]) a.A_SetSize(lRadius[i], lHeight[i], !force);
		a.bSpecial = lSpecial[i] != 0;
	}

	// A thing that is taken again while it is still settling gets its own flags back first, so the
	// new borrow remembers the right ones.
	private void Unloose(Actor a)
	{
		for (int i = lA.Size() - 1; i >= 0; --i)
		{
			if (lA[i] != a) continue;
			if (lSettled[i] == 0) FinishLoose(i, true);
			LooseDelete(i);
		}
	}

	private bool Recorded(Actor a)
	{
		for (int j = 0; j < obj.Size(); ++j)
		{
			if (mode[j] != RM_NONE && obj[j] == a) return true;
		}
		return false;
	}

	// ---------------------------------------------------------------- the tic

	override void WorldTick()
	{
		Ensure();
		for (int i = 0; i < MAXPLAYERS; ++i)
		{
			if (!playeringame[i] || players[i].mo == null)
			{
				// A player who left: what the hands had falls.
				if (mode[i * 2] != RM_NONE) EndRecord(i, 0, false);
				if (mode[i * 2 + 1] != RM_NONE) EndRecord(i, 1, false);
				continue;
			}
			PlayerPawn pawn = players[i].mo;
			bool ok; int kind, hand; Actor a; Vector3 vel;
			for (int guard = 0; guard < 16; ++guard)
			{
				[ok, kind, hand, a, vel] = VRGrab.PopAction(i);
				if (!ok) break;
				if (hand < 0 || hand > 1) continue;
				Apply(i, pawn, kind, hand, a, vel);
			}
			for (int h = 0; h < 2; ++h)
			{
				if (mode[i * 2 + h] == RM_NONE) continue;
				if (pawn.Health <= 0) EndRecord(i, h, true);
				else TickRecord(i, h);
			}
		}
		TickLoose();
	}

	private void Apply(int pnum, PlayerPawn pawn, int kind, int hand, Actor a, Vector3 vel)
	{
		switch (kind)
		{
		case VRGrab.ACT_PULL:
			StartFlight(pnum, hand, a);
			break;
		case VRGrab.ACT_CATCH:
			Catch(pnum, pawn, hand, a);
			break;
		case VRGrab.ACT_DROP:
		case VRGrab.ACT_MISS:
			EndRecord(pnum, hand, false);
			break;
		case VRGrab.ACT_RELEASE:
			Release(pnum, pawn, hand, vel);
			break;
		}
	}

	// ---------------------------------------------------------------- the pull (RSQ flight.zs, the Arc path)

	private void StartFlight(int pnum, int hand, Actor a)
	{
		int k = pnum * 2 + hand;
		if (mode[k] != RM_NONE) EndRecord(pnum, hand, false);
		if (a == null || a.bDestroyed || Recorded(a))
		{
			VRGrab.Abort(pnum, hand);
			return;
		}
		bool ok; Vector3 palm, nrm, dir;
		[ok, palm, nrm, dir] = VRGrab.Palm(pnum, hand);
		if (!ok)
		{
			VRGrab.Abort(pnum, hand);
			return;
		}
		Unloose(a);
		Borrow(k, a);
		obj[k] = a;
		mode[k] = RM_FLY;
		age[k] = 0; orphan[k] = 0; strain[k] = 0;

		Vector3 mid0 = MidOf(a);
		double dist = (mid0 - palm).Length();
		// pathspeed is metres a second: x 34 map units a metre, / 35 tics a second.
		double upt = max(0.1, VRGrab.Tune('pathspeed') * UPM / TICRATE);
		double lo = max(1.0, VRGrab.Tune('tmin'));
		double hi = max(lo, VRGrab.Tune('tmax'));
		total[k] = int(clamp(dist / upt, lo, hi));
		fromX[k] = mid0.X; fromY[k] = mid0.Y; fromZ[k] = mid0.Z;
		double want = dist * VRGrab.Tune('arc');
		double cap = MeasureArc(a, mid0, palm);
		arcH[k] = (cap < 0.0) ? want : min(want, cap);
	}

	// How high this pull can arc without meeting a ceiling: the straight line sampled every 24
	// units (4..48 samples), the lowest ceiling and highest floor over the route, an 8-unit margin.
	// -1 when nothing was sampled: keep the arc wanted.
	private static double MeasureArc(Actor a, Vector3 from, Vector3 to)
	{
		double span = (to - from).Length();
		int samples = clamp(int(span / 24.0), 4, 48);
		double minCeil = 1e30, maxFloor = -1e30;
		for (int i = 0; i <= samples; i++)
		{
			double t = double(i) / double(samples);
			Vector2 pt = (from.X + (to.X - from.X) * t, from.Y + (to.Y - from.Y) * t);
			Sector sec = level.PointInSector(pt);
			if (sec == null) continue;
			double c = sec.ceilingplane.ZatPoint(pt);
			double f = sec.floorplane.ZatPoint(pt);
			if (c < minCeil) minCeil = c;
			if (f > maxFloor) maxFloor = f;
		}
		if (minCeil > 1e29 || maxFloor < -1e29) return -1.0;
		double margin = 8.0;
		double room = minCeil - maxFloor - a.Height - margin;
		double avail = (minCeil - a.Height - margin) - max(from.Z, to.Z);
		double cap = min(room, avail);
		return cap > 0.0 ? cap : 0.0;
	}

	// How far along the arc's LENGTH at time t (0..1): a short pick-up, an even cruise, a settle
	// into the hand.
	private static double PathI(double t, double r, double f)
	{
		double s = 0.0;
		if (r > 0.0)
		{
			double a = min(t, r);
			s += PATH_V0 * a + (1.0 - PATH_V0) * a * a / (2.0 * r);
		}
		if (t > r) s += min(t, 1.0 - f) - r;
		if (f > 0.0 && t > 1.0 - f)
		{
			double u = t - (1.0 - f);
			s += u - (1.0 - PATH_V1) * u * u / (2.0 * f);
		}
		return s;
	}

	static double PathE(double t)
	{
		return PathI(clamp(t, 0.0, 1.0), PATH_RAMP, PATH_SETTLE) / PathI(1.0, PATH_RAMP, PATH_SETTLE);
	}

	// The e at which the arc from a to b with hump hgt has covered the share s of its length.
	static double ArcE(Vector3 a, Vector3 b, double hgt, double s)
	{
		if (s <= 0.0) return 0.0;
		if (s >= 1.0) return 1.0;
		Vector3 d = b - a;
		double len[25];   // ARC_N + 1
		len[0] = 0.0;
		Vector3 prev = a;
		for (int i = 1; i <= ARC_N; i++)
		{
			double e = double(i) / ARC_N;
			Vector3 q = a + d * e;
			q.Z += 4.0 * hgt * e * (1.0 - e);
			len[i] = len[i - 1] + (q - prev).Length();
			prev = q;
		}
		if (len[ARC_N] < 0.001) return s;
		double want = s * len[ARC_N];
		for (int i = 1; i <= ARC_N; i++)
		{
			if (len[i] < want) continue;
			double seg = len[i] - len[i - 1];
			double kk = seg > 0.0 ? (want - len[i - 1]) / seg : 0.0;
			return (i - 1 + kk) / ARC_N;
		}
		return 1.0;
	}

	// One tic of the path. False when the thing could not move: it met a wall.
	private bool StepFlight(int k, Actor a, Vector3 palm)
	{
		double t = min(1.0, double(age[k]) / double(max(1, total[k])));
		Vector3 from = (fromX[k], fromY[k], fromZ[k]);
		double e = ArcE(from, palm, arcH[k], PathE(t));
		// Homes on where the hand is NOW.
		Vector3 pos = from + (palm - from) * e;
		pos.Z += 4.0 * arcH[k] * e * (1.0 - e);

		// Z first, clamped to the room, then XY by TryMove: a real move that stops at walls.
		double flyZ = pos.Z - a.Height * 0.5;
		double lo = a.floorz;
		double hi = max(lo, a.ceilingz - a.Height);
		a.SetZ(clamp(flyZ, lo, hi));
		bool moved = a.TryMove((pos.X, pos.Y), 1);

		// Lift it out before dragging it sideways: a pickup in an alcove is boxed in where it lies.
		if (!moved)
		{
			double keepZ = a.Pos.Z;
			for (int lift = 1; lift <= 3 && !moved; lift++)
			{
				double tryZ = keepZ + lift * 6.0;
				if (tryZ + a.Height > a.ceilingz) break;
				a.SetZ(tryZ);
				moved = a.TryMove((pos.X, pos.Y), 1);
			}
			if (!moved) a.SetZ(keepZ);
		}
		a.Vel = (0, 0, 0);
		return moved;
	}

	// ---------------------------------------------------------------- the catch

	private void Catch(int pnum, PlayerPawn pawn, int hand, Actor a)
	{
		int k = pnum * 2 + hand;
		if (a == null || a.bDestroyed)
		{
			EndRecord(pnum, hand, true);
			return;
		}
		if (mode[k] == RM_NONE || obj[k] != a)
		{
			// Caught without a flight of ours behind it: take it as it is.
			if (mode[k] != RM_NONE) EndRecord(pnum, hand, false);
			if (Recorded(a))
			{
				VRGrab.Abort(pnum, hand);
				return;
			}
			Unloose(a);
			Borrow(k, a);
			obj[k] = a;
		}

		// A pickup is used, the engine's own way: it is touched by the pawn, on every machine.
		Inventory inv = Inventory(a);
		if (inv != null && sSpecial[k] != 0)
		{
			GiveBack(k, a);
			inv.Touch(pawn);
			if (inv.bDestroyed || inv.Owner != null || !inv.bSpecial)
			{
				// Taken (in the inventory, used up, or hidden until it respawns).
				Clear(k);
				VRGrab.Abort(pnum, hand);
				return;
			}
			// Not taken (you are full, or it stays for the others): it is carried.
			Borrow(k, a);
		}

		mode[k] = RM_HELD;
		age[k] = 0; orphan[k] = 0; strain[k] = 0;
	}

	// ---------------------------------------------------------------- flying and carrying, each tic

	private void TickRecord(int pnum, int hand)
	{
		int k = pnum * 2 + hand;
		Actor a = obj[k];
		if (a == null || a.bDestroyed)
		{
			Clear(k);
			VRGrab.Abort(pnum, hand);
			return;
		}
		// It died in the air or in the hand (a barrel that was shot).
		if (sShoot[k] != 0 && a.Health <= 0)
		{
			EndRecord(pnum, hand, true);
			return;
		}

		int ph, pt; Actor pa;
		[ph, pa, pt] = VRGrab.HandState(pnum, hand);
		int wantPhase = (mode[k] == RM_FLY) ? VRGrab.PH_PULL : VRGrab.PH_HELD;
		if (ph != wantPhase)
		{
			// The core has moved on and no action said so (it should not happen): do not leave a
			// thing hanging in the air with its flags borrowed.
			orphan[k] = orphan[k] + 1;
			if (orphan[k] > ORPHAN_TICS)
			{
				EndRecord(pnum, hand, false);
				return;
			}
		}
		else orphan[k] = 0;

		bool ok; Vector3 palm, nrm, dir;
		[ok, palm, nrm, dir] = VRGrab.Palm(pnum, hand);
		if (!ok) return;

		if (mode[k] == RM_FLY)
		{
			age[k] = age[k] + 1;
			if (!StepFlight(k, a, palm)) EndRecord(pnum, hand, true);   // a wall
			return;
		}

		// HELD: its middle sits one body radius out of the palm. Z first, then XY by TryMove, so it
		// stops at walls (RS_WorldHands rs_held.zs CarryOne).
		double br = BodyRadius(a, sRadius[k], sHeight[k]);
		Vector3 want = palm + nrm * br;
		double z = want.Z - a.Height * 0.5;
		double lo = a.floorz;
		double hi = a.ceilingz - a.Height;
		if (hi < lo) hi = lo;
		a.Vel = (0, 0, 0);
		a.SetZ(clamp(z, lo, hi));
		a.TryMove((want.X, want.Y), 1);

		// Left behind a wall for too long: the hand lets go.
		if ((MidOf(a) - want).Length() > BREAK_UNITS) strain[k] = strain[k] + 1;
		else strain[k] = 0;
		if (strain[k] >= BREAK_TICS) EndRecord(pnum, hand, true);
	}

	// ---------------------------------------------------------------- the release (RSQ hold.zs Release)

	private void Release(int pnum, PlayerPawn pawn, int hand, Vector3 vel)
	{
		int k = pnum * 2 + hand;
		Actor a = obj[k];
		if (mode[k] == RM_NONE || a == null || a.bDestroyed)
		{
			Clear(k);
			return;
		}
		// The hand's velocity (map units a tic), weakened by weight, times the boost.
		double kg = max(0.0, VRGrab.Mass(a));
		double arm = max(1.0, VRGrab.Tune('arm'));
		double boost = max(0.0, VRGrab.Tune('boost'));
		Vector3 v = vel * (arm / (arm + kg)) * boost;
		double mps = Metres(v) * TICRATE;
		if (mps > THROW_MPS)
		{
			// A throw: the body's own motion goes with it.
			v += pawn.Vel;
			Loosen(k, a, SETTLE_TICS, pawn, mps, v);
		}
		else
		{
			// A set-down: it is just let go.
			Loosen(k, a, 0, null, 0, (0, 0, 0));
		}
	}

	// ---------------------------------------------------------------- after the hand (RSQ throw.zs)

	// A thrown thing's speed in metres a second, as its target feels it: the thrower's own run
	// taken out, and the fall scaled back to real gravity where the soft fall is still faster.
	static double ImpactMps(Actor a, Vector3 v, double bodyX, double bodyY, double gscale)
	{
		double vx = v.X - bodyX;
		double vy = v.Y - bodyY;
		double gDoom = a.GetGravity() * gscale * TICRATE * TICRATE / (UPM / STRETCH);
		double f = (gDoom > 9.81) ? sqrt(9.81 / gDoom) : 1.0;
		double h = sqrt(vx * vx + vy * vy) / UPM;
		double z = v.Z * STRETCH / UPM * f;
		return sqrt(h * h + z * z) * TICRATE;
	}

	// Damage = kinetic energy over 15 joules: 0.5 x kg x (m/s)^2 / 15, at least 1.
	static int DamageFor(double kg, double mps)
	{
		double j = 0.5 * kg * mps * mps;
		return max(1, int(min(j / JOULES_PER_DAMAGE, 1000000.0)));
	}

	private static bool CanHurt(Actor t, Actor a, Actor thrower)
	{
		if (t == null || t == a || t == thrower) return false;
		if (!t.bShootable || t.Health <= 0 || t.bDormant) return false;
		// another mod's helper actor riding on something
		if (t.master != null && !t.bSolid && t.master != t) return false;
		return true;
	}

	private static bool Touching(Actor a, double bodyR, Actor t, double pad)
	{
		Vector2 d = t.Pos.XY - a.Pos.XY;
		if (d.Length() > bodyR + t.Radius + pad) return false;
		return a.Pos.Z <= t.Pos.Z + t.Height + pad && t.Pos.Z <= a.Pos.Z + a.Height + pad;
	}

	private void Strike(int i, Actor t, double mps)
	{
		Actor a = lA[i];
		Actor thrower = lBy[i];
		if (a == null || t == null) return;
		double kg = max(0.0, VRGrab.Mass(a));
		Vector2 dir = a.Vel.XY;
		int dmg = DamageFor(kg, mps);
		lHit[i] = t;
		lHits[i] = lHits[i] + 1;
		t.DamageMobj(a, thrower, dmg, 'Melee');
		// A hard hit staggers a monster and shoves it.
		if (t == null || t.bDestroyed || t.Health <= 0 || !t.bIsMonster || dmg < STUN_DAMAGE) return;
		State pain = t.FindState("Pain");
		if (pain != null && !t.InStateSequence(t.CurState, pain)) t.SetState(pain);
		double push = min(12.0, kg * mps / max(50.0, double(t.Mass)) * 2.0);
		double dl = dir.Length();
		if (dl > 0.01 && !t.bDontThrust)
		{
			t.Vel.X += dir.X / dl * push;
			t.Vel.Y += dir.Y / dl * push;
		}
	}

	// It landed, or hit a wall: what stands there is hurt, and a barrel thrown hard goes off.
	private void Impact(int i, double mps)
	{
		Actor a = lA[i];
		Actor thrower = lBy[i];
		if (a == null || a.bDestroyed) return;
		double bodyR = BodyRadius(a, lRadius[i], lHeight[i]);
		Array<Actor> victims;
		BlockThingsIterator it = BlockThingsIterator.Create(a, bodyR + 16);
		while (it.Next() && victims.Size() < MAX_VICTIMS)
		{
			Actor t = it.thing;
			if (!CanHurt(t, a, thrower) || t == lHit[i]) continue;
			if (!Touching(a, bodyR, t, 16)) continue;
			victims.Push(t);
		}
		for (int v = 0; v < victims.Size(); v++)
		{
			a = lA[i];
			if (a == null || a.bDestroyed) return;   // the thing itself went (a barrel hit a barrel)
			Actor t = victims[v];
			if (t != null && !t.bDestroyed && t.Health > 0) Strike(i, t, mps);
		}
		a = lA[i];
		if (a == null || a.bDestroyed) return;

		a.A_StartSound("RAB/thud", CHAN_AUTO, CHANF_OVERLAP, min(1.0, 0.3 + mps / 8.0));

		// An explosive barrel thrown at 4 m/s or more: killed by its thrower, so it goes off here
		// and what it kills is his.
		if (lRel[i] >= EXPLODE_MPS && (a is "ExplosiveBarrel") && a.bShootable && a.Health > 0)
			a.DamageMobj(thrower, thrower, a.Health, 'None', DMG_FORCED);
	}

	// One thrown thing, one tic: does it hit a body, has it stopped dead.
	private void WatchOne(int i, double gscale)
	{
		Actor a = lA[i];
		Actor thrower = lBy[i];
		double speed = a.Vel.Length();
		double mps = ImpactMps(a, a.Vel, lBodyX[i], lBodyY[i], gscale);
		double lastMps = lLastMps[i];

		// Passing through a body at speed: that body is hit, and the thing loses most of its speed.
		if ((!a.bSolid || a.bThruActors) && mps >= HIT_MPS && lHits[i] < MAX_VICTIMS)
		{
			double bodyR = BodyRadius(a, lRadius[i], lHeight[i]);
			Actor hitT = null;
			BlockThingsIterator it = BlockThingsIterator.Create(a, bodyR + 8);
			while (it.Next())
			{
				Actor t = it.thing;
				if (!CanHurt(t, a, thrower) || t == lHit[i]) continue;
				if (!Touching(a, bodyR, t, 0)) continue;
				hitT = t;
				break;
			}
			if (hitT != null)
			{
				Strike(i, hitT, mps);
				a = lA[i];
				if (a == null || a.bDestroyed) return;
				a.Vel *= 0.25;
				speed = a.Vel.Length();
				mps = ImpactMps(a, a.Vel, lBodyX[i], lBodyY[i], gscale);
			}
		}

		// Lost half its speed in one tic while it was fast: it hit the floor or a wall.
		if (lAge[i] > 1 && lastMps >= HIT_MPS && speed < lLastSpeed[i] * 0.5)
		{
			Impact(i, lastMps);
			lWatch[i] = 0;
			return;
		}

		lLastSpeed[i] = speed;
		lLastMps[i] = mps;
		if (mps < 0.6) lStill[i] = lStill[i] + 1;
		else lStill[i] = 0;
		if (lStill[i] >= STILL_TICS || lAge[i] >= WATCH_TICS) lWatch[i] = 0;
	}

	// Its own size and flags come back once it fits where it is with them.
	private void TrySettle(int i)
	{
		Actor a = lA[i];
		if (lAge[i] >= SETTLE_GIVEUP) { FinishLoose(i, true); return; }
		if (lAge[i] < lMin[i]) return;
		if (a.Radius != lRadius[i] || a.Height != lHeight[i])
		{
			bool wasThru = a.bThruActors;
			a.bThruActors = lThru[i] != 0;
			bool fits = a.A_SetSize(lRadius[i], lHeight[i], true);
			a.bThruActors = wasThru;
			if (!fits) return;
		}
		a.bThruActors = lThru[i] != 0;
		if (!a.TestMobjLocation())
		{
			a.bThruActors = true;
			return;
		}
		FinishLoose(i, false);
	}

	private void TickLoose()
	{
		if (lA.Size() == 0) return;
		// Everything let go falls at `airgravity` of Doom's gravity, by adding the rest back each
		// tic; the thing's own Gravity is never touched (RSQ throw.zs TickAir).
		double gscale = clamp(VRGrab.Tune('airgravity'), 0.0, 1.0);
		for (int i = lA.Size() - 1; i >= 0; --i)
		{
			Actor a = lA[i];
			if (a == null || a.bDestroyed) { LooseDelete(i); continue; }
			lAge[i] = lAge[i] + 1;

			if (lSettled[i] == 0) TrySettle(i);

			if (gscale < 1.0 && a.Pos.Z > a.floorz + 2 && !a.bNoGravity && a.waterlevel == 0)
				a.Vel.Z += a.GetGravity() * (1.0 - gscale);

			if (lWatch[i] != 0) WatchOne(i, gscale);
			a = lA[i];
			if (a == null || a.bDestroyed) { LooseDelete(i); continue; }

			bool resting = a.Pos.Z <= a.floorz + 1.0 && a.Vel.Length() < 1.0;
			if (resting) lRest[i] = lRest[i] + 1;
			else lRest[i] = 0;
			if (lAge[i] > AIR_TICS)
			{
				if (lSettled[i] == 0) FinishLoose(i, true);
				LooseDelete(i);
			}
			else if (lSettled[i] != 0 && lWatch[i] == 0 && lRest[i] > 4)
			{
				LooseDelete(i);
			}
		}
	}
}

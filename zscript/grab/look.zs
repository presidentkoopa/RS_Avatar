// THE DISTANCE GRAB: what you see. This machine's own player only, client-side actors and
// particles only; nothing here touches the world and nothing is drawn for other players.
//
//   amber wire sphere   the thing this hand could take (AIM)            RSQ tell.zs: "could" FFB030
//   green wire sphere   the thing this hand has locked or is pulling    RSQ tell.zs: "have"  40FF70
//   a thin beam         from the palm along the way the hand points, while aiming or locked
// A held thing needs no marker: it is in the hand.

class RAB_Look : EventHandler
{
	const BEAM_DOTS  = 14;
	const BEAM_UNITS = 96.0;    // how long the beam is with nothing to point at

	transient RAB_Mark mark0, mark1;   // one marker per hand

	override void WorldTick()
	{
		int me = consoleplayer;
		bool on = me >= 0 && me < MAXPLAYERS && playeringame[me] && players[me].mo != null;
		for (int h = 0; h < 2; ++h)
		{
			int ph = VRGrab.PH_IDLE, pt = 0; Actor a = null;
			if (on) [ph, a, pt] = VRGrab.HandState(me, h);
			bool aiming = ph == VRGrab.PH_AIM || ph == VRGrab.PH_LOCKED;
			bool show = a != null && (aiming || ph == VRGrab.PH_PULL);

			RAB_Mark mk = (h == 0) ? mark0 : mark1;
			if (show && mk == null)
			{
				mk = RAB_Mark(Actor.SpawnClientSide('RAB_Mark', a.Pos, NO_REPLACE));
				if (h == 0) mark0 = mk; else mark1 = mk;
			}
			if (mk != null) mk.ShowOn(show ? a : null, ph != VRGrab.PH_AIM);

			if (on && aiming) Beam(me, h, a, ph == VRGrab.PH_LOCKED);
		}
	}

	// A row of short-lived bright dots from the palm along the cone's direction, as far as the
	// thing pointed at.
	private void Beam(int pnum, int hand, Actor a, bool have)
	{
		bool ok; Vector3 palm, nrm, dir;
		[ok, palm, nrm, dir] = VRGrab.Palm(pnum, hand);
		if (!ok) return;
		double reach = BEAM_UNITS;
		if (a != null) reach = max(8.0, (RAB_Rules.MidOf(a) - palm).Length());

		FSpawnParticleParams pp;
		pp.color1 = have ? 0x40FF70 : 0xFFB030;
		pp.style = STYLE_Add;
		pp.flags = SPF_FULLBRIGHT;
		pp.lifetime = 2;
		pp.size = 1.5;
		pp.sizestep = 0;
		pp.vel = (0, 0, 0);
		pp.accel = (0, 0, 0);
		pp.startalpha = have ? 0.7 : 0.45;
		pp.fadestep = -1;
		pp.startroll = 0;
		pp.rollvel = 0;
		pp.rollacc = 0;
		for (int j = 1; j <= BEAM_DOTS; ++j)
		{
			pp.pos = palm + dir * (reach * j / BEAM_DOTS);
			level.SpawnParticle(pp);
		}
	}
}

// The marker: a wire sphere round the thing, sized to it (MODELDEF.grab).
class RAB_Mark : Actor
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

	void ShowOn(Actor a, bool have)
	{
		if (a == null) { bInvisible = true; return; }
		bInvisible = false;
		SetOrigin(RAB_Rules.MidOf(a), true);
		// A pickup's radius is its touch zone, far wider than what is drawn.
		double half = a.Height * 0.5;
		double r = (a is "Inventory") ? min(max(a.Radius, 4.0), max(half, 4.0)) : max(a.Radius, half);
		r = max(5.0, r * 1.2);
		Scale = (r, r);
		frame = have ? 1 : 0;
		// "have" is steady; "could" breathes, so the two are told apart by more than colour.
		Alpha = have ? 0.85 : 0.45 + 0.2 * cos(level.maptime * 360.0 / 24.0);
	}

	States
	{
	Spawn:
		RABM A -1;
		Stop;
	}
}

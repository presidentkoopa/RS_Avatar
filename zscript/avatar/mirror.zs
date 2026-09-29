// RS_Avatar -- THE MIRROR.
//
// TAKEN FROM RS_VRBody, at the owner's instruction, because the one I wrote was worse and he
// was right about why. The design below is his; the only changes are the names and that it
// is driven from this mod's own cvar instead of a keybind.
//
// You cannot see your own body. You are inside its head: the legs are under you, the back is
// behind you, and craning your neck to check whether a knee bent is both awkward and a bad
// way to judge anything. So: a panel you walk up to and look at, showing you from the front.
//
// IT IS A MONITOR, NOT A REFLECTION, AND THAT IS THE WHOLE POINT.
//
// A true mirror reflects the viewpoint through the panel's plane, which is what I built
// first. It is correct and it is useless: step aside and your reflection leaves the frame,
// exactly when you were trying to look at yourself. This camera STANDS at the panel and
// TRACKS you, so you stay in shot while you walk, crouch and lean. For checking a body that
// is strictly better than being accurate.
//
// WHY NOT A THIRD-PERSON CAMERA. GZDoom has chasecam and nothing in the VR path handles it.
// Its offset rides your VIEW DIRECTION, so turning your head swings the camera through an arc
// rather than pivoting at your neck -- your inner ear reports a head turn and your eyes
// report a sideways sweep, and that mismatch is what makes people ill. It is the same rule
// that cancelled the recoil view jolt: NOTHING WE COMPUTE MAY MOVE THE CAMERA. A mirror moves
// nothing at all. Your head still drives your view.
//
// ON DEMAND ONLY. A camera texture renders the whole scene a second time, and in VR the scene
// is already drawn twice. Switch it on to look at something and switch it off again.

// The viewpoint. Draws nothing; it exists to be a camera.
class RSA_MirrorCam : Actor
{
	Default
	{
		+NOINTERACTION;
		+NOBLOCKMAP;
		+NOGRAVITY;
		+INVISIBLE;
		RenderStyle "None";
		Radius 1;
		Height 1;
	}
}

// The panel: one quad wearing the camera texture.
class RSA_MirrorPanel : Actor
{
	Default
	{
		+NOINTERACTION;
		+NOBLOCKMAP;
		+NOGRAVITY;
		+BRIGHT;
		Radius 1;
		Height 1;
	}
	States
	{
	Spawn:
		TRSO A -1;
		Stop;
	}
}

class RSA_MirrorHandler : EventHandler
{
	private Actor mPanel, mCam;
	private bool mOn;

	private double Cvf(string name, double def) const
	{
		CVar c = CVar.FindCVar(name);
		return c ? c.GetFloat() : def;
	}

	private bool Wanted() const
	{
		CVar c = CVar.FindCVar("vr_mirror");
		return c != null && c.GetBool();
	}

	override void WorldTick()
	{
		bool want = Wanted();
		if (!want)
		{
			if (mOn) TakeDown();
			return;
		}

		let pawn = players[consoleplayer].mo;
		if (pawn == null)
		{
			if (mOn) TakeDown();
			return;
		}

		if (!mOn) { PutUp(pawn); return; }
		Track(pawn);
	}

	override void WorldUnloaded(WorldEvent e) { TakeDown(); }

	private void PutUp(Actor pawn)
	{
		double dist = clamp(Cvf("vr_mirror_dist", 96.0), 32.0, 400.0);
		double yaw = pawn.angle;
		Vector3 at = (pawn.pos.X + cos(yaw) * dist,
			pawn.pos.Y + sin(yaw) * dist,
			pawn.pos.Z + Cvf("vr_mirror_up", 34.0));

		// THE CAMERA STANDS OFF THE PANEL, and this is not a detail.
		//
		// Spawned at the same point, the camera sits INSIDE its own quad -- and that quad is
		// double sided, so the camera stares at the back of the very surface it paints. The
		// panel and the scene behind it then win the depth test in alternate frames, which
		// looks like a fast grey flicker. A few units toward the player puts it clear.
		double back = clamp(Cvf("vr_mirror_standoff", 8.0), 2.0, 48.0);
		Vector3 camAt = (at.X - cos(yaw) * back, at.Y - sin(yaw) * back, at.Z);

		mPanel = Actor.Spawn("RSA_MirrorPanel", at);
		mCam = Actor.Spawn("RSA_MirrorCam", camAt);
		if (mPanel == null || mCam == null)
		{
			Console.Printf("\cgMirror: could not spawn.");
			TakeDown();
			CVar c = CVar.FindCVar("vr_mirror");
			if (c) c.SetBool(false);
			return;
		}

		// The panel faces back down the line it was placed along, so it is square to you the
		// moment it appears.
		mPanel.angle = yaw + 180;
		mCam.angle = yaw + 180;
		TexMan.SetCameraToTexture(mCam, "RSMIRROR", clamp(Cvf("vr_mirror_fov", 70.0), 30.0, 140.0));

		mOn = true;
		Console.Printf("\ccMirror up. Switch it off again when you are done -- it renders the "
			"whole scene a second time.");
	}

	private void TakeDown()
	{
		if (mPanel != null) { mPanel.Destroy(); mPanel = null; }
		if (mCam != null) { mCam.Destroy(); mCam = null; }
		mOn = false;
	}

	// The camera TRACKS you rather than staring straight ahead, so you stay in frame while
	// you walk about, crouch and lean -- which is the entire point of having it.
	private void Track(Actor pawn)
	{
		if (mCam == null) return;
		Vector3 head = pawn.HmdPos;
		if (head == (0, 0, 0))
			head = (pawn.pos.X, pawn.pos.Y, pawn.pos.Z + pawn.Height * 0.8);
		Vector3 d = (head.X - mCam.pos.X, head.Y - mCam.pos.Y, head.Z - mCam.pos.Z);
		double flat = sqrt(d.X * d.X + d.Y * d.Y);
		if (flat < 1.0) return;
		mCam.angle = atan2(d.Y, d.X);
		mCam.pitch = -atan2(d.Z, flat);
	}
}

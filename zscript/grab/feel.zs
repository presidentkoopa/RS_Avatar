// THE DISTANCE GRAB: what you feel and hear. This machine's own player only; nothing here touches
// the world. Read from the core's event ring (VRGrab.EventSeq / VRGrab.Event).
//
// The rhythm is RSQ DistanceGrab's (feel.zs:273-277, 408-411): lock 0.55 for 2 tics, launch and
// release 0.75 for 3, catch 1.00 for 3; a tic is about 29 ms. The pulses go through the engine's
// own haptic call (level.VRHapticEx), as RAG_Feel's do.

class RAB_Feel : EventHandler
{
	transient int lastSeq;
	transient bool seqInit;
	transient Array<int> seenKey;   // (tic, hand, kind) already played, so a replayed tic does not play twice

	private void Pulse(int hand, double strength, int ms, int priority)
	{
		level.VRHapticEx(hand, strength, ms, 0, priority);
	}

	private void Snd(PlayerPawn pawn, Sound snd, double vol, double pitch)
	{
		if (pawn != null) pawn.A_StartSound(snd, CHAN_AUTO, CHANF_LOCAL | CHANF_OVERLAP, vol, ATTN_NORM, pitch);
	}

	override void WorldTick()
	{
		int me = consoleplayer;
		if (me < 0 || me >= MAXPLAYERS || !playeringame[me]) return;
		PlayerPawn pawn = players[me].mo;

		int seq = VRGrab.EventSeq(me);
		if (!seqInit || seq < lastSeq) { lastSeq = seq; seqInit = true; }
		for (; lastSeq < seq; ++lastSeq)
		{
			bool ok; int kind, hand, tic; Actor a;
			[ok, kind, hand, a, tic] = VRGrab.Event(me, lastSeq);
			if (!ok) continue;
			if (hand < 0 || hand > 1) continue;
			int key = ((tic % 1000000) * 2 + hand) * 32 + kind;
			if (seenKey.Find(key) != seenKey.Size()) continue;
			seenKey.Push(key);
			if (seenKey.Size() > 32) seenKey.Delete(0);

			switch (kind)
			{
			case VRGrab.EV_LOCK:
				Pulse(hand, 0.55, 58, 2);
				Snd(pawn, "RAB/lock", 0.6, 1.0);
				break;
			case VRGrab.EV_PULL:
				Pulse(hand, 0.75, 87, 3);
				Snd(pawn, "RAB/whoosh", 0.6, 1.2);
				break;
			case VRGrab.EV_CATCH:
				Pulse(hand, 1.0, 87, 4);
				Snd(pawn, "RAB/catch", 0.5, 1.3);
				break;
			case VRGrab.EV_THROW:
				Pulse(hand, 0.75, 87, 3);
				Snd(pawn, "RAB/whoosh", 0.8, 0.9);
				break;
			case VRGrab.EV_SETDOWN:
			case VRGrab.EV_DROP:
			case VRGrab.EV_MISS:
				Pulse(hand, 0.30, 29, 1);
				break;
			case VRGrab.EV_GRIPHOLD:
				Pulse(hand, 0.40, 29, 2);
				break;
			}
		}
	}
}

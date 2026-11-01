class EnhancedTicker extends Info;

// A half-second heartbeat for the game class: GameInfo already uses its own timer, so the mod's periodic
// work (a waiting checkpoint, later the lobby) runs from here.

var EnhancedGame G;
var float FpsTime;
var int FpsFrames;
var int DtBucket[64];     // frame times in milliseconds (EnhFps)

event PostBeginPlay()
{
	Super.PostBeginPlay();
	SetTimer(0.5, true);
}

// Every frame: player two's camera follows the host's during cutscenes.
event Tick(float DeltaTime)
{
	FpsTime += DeltaTime;
	FpsFrames++;
	if (G != None && G.bFpsOpt)
	{
		DtBucket[Min(63, int(DeltaTime * 1000.0 + 0.5))]++;
	}
	if (FpsTime >= 2.0 && G != None && G.bFpsOpt)
	{
		Log("[FPS] t=" $ string(Level.TimeSeconds) $ " fps=" $ string(int(float(FpsFrames) / FpsTime)) $ " guests=" $ string(G.GPC.Length));
		DtLine();
		FpsTime = 0.0;
		FpsFrames = 0;
	}
	else if (FpsTime >= 2.0)
	{
		FpsTime = 0.0;
		FpsFrames = 0;
	}
	if (G != None)
	{
		if (!G.Off("smooth"))
		{
			G.GuestSmooth(DeltaTime);
		}
		if (!G.Off("mirror"))
		{
			G.MirrorCamera();
		}
		if (!G.Off("subs"))
		{
			G.SyncSubs();
		}
		G.GateTick(DeltaTime);
		G.GateTestTick(DeltaTime);
		G.ShowHostNote();
		G.DownFreeze();
		G.GuestGround();
		G.DeathTestTick(DeltaTime);
		G.JitterTick(DeltaTime);
		G.JumpTestTick(DeltaTime);
		G.GotoTick();
		G.GuestJumpTick(DeltaTime);
		G.HostTurnTick();
		G.SurveyTick();
		G.JoinSurveyTick();
		if (!G.Off("trace"))
		{
			G.GuestTrace(DeltaTime);
		}
		G.PivotTest();
	}
}

function DtLine()
{
	local int i;
	local string S;

	for (i = 0; i < 64; i++)
	{
		if (DtBucket[i] > 0)
		{
			S = S $ " " $ string(i) $ "ms:" $ string(DtBucket[i]);
			DtBucket[i] = 0;
		}
	}
	Log("[DT]" $ S);
}

event Timer()
{
	if (G != None)
	{
		G.Poll();
	}
}

defaultproperties
{
	bHidden=True
	RemoteRole=ROLE_None
}

class EnhancedAnimSync extends Actor;

// The engine replicates one animation channel of a pawn (SimAnim, channel 0) and the movement channels are worked out locally from the
// velocity; everything else a hero plays (attacks, jumps, pick-ups, hits, the face) stays on the machine that plays it, and the loop flag of
// SimAnim does not arrive. This actor carries the state of every channel of every hero pawn from the server to the clients and applies it
// there. Two natives of the engine layer (d3d8.dll proxy) help: EnhAnimExtra reads what scripts cannot (loop flag, blend alpha) and
// EnhAnimSyncOn switches the engine's own SimAnim replay off for hero pawns while this runs.

const MaxHeroes = 32;
const ChannelCount = 38;

var Actor Who[32];
var string Data[32];
var name TmpName;
var float Clock;
var string Applied[32];
var Actor AppliedWho[32];   // the pawn the record was applied to (the records of two idle heroes are the same text; a pawn that took over a slot must get it too)
var float ForceClock;
var float SelClock;
var Actor Pick[32];     // server: the pawns of the set
var float LogClock;
var float PrevF[1216];      // server: frame of every channel of every hero at the last sample (a drop of a one-shot = it was played again)
var int Epoch[1216];
var int AppliedEpoch[1216];
var Actor Fresh[24];        // client: pawns seen for the first time (a new pawn is hidden until it plays something, so it is never seen in the T pose)
var float FreshAge[24];
var array<Actor> Seen;      // client: every pawn looked at once
var float FreshClock;
var float ProbeClock;

native(3501) final function int EnhAnimExtra(Actor A, int Ch);
native(3502) final function EnhAnimSyncOn(int On);

replication
{
	reliable if (Role == ROLE_Authority)
		Who;
	unreliable if (Role == ROLE_Authority)
		Data;
}

event PostBeginPlay()
{
	Super.PostBeginPlay();
	EnhAnimSyncOn(1);
}

simulated event PostNetBeginPlay()
{
	Super.PostNetBeginPlay();
	EnhAnimSyncOn(1);
}

// "channel:sequence:rate*20:alpha/8:loop:epoch;" for every channel in use (the movement channels 4 to 11 are the engine's own work). The record
// changes only when the state does: the frame is not sent (it made the data change every tick and restart the animation on the clients); the
// epoch counts how often a one-shot was played again from its start.
function string Pack(Actor P, int Slot)
{
	local int C, E, Al, K, Lp;
	local name N;
	local float F, R;
	local string S;

	for (C = 0; C < ChannelCount; C++)
	{
		if (C >= 4 && C <= 11)
		{
			continue;
		}
		P.GetAnimParams(C, N, F, R);
		K = Slot * ChannelCount + C;
		if (N == 'None')
		{
			PrevF[K] = 0.0;
			continue;
		}
		E = EnhAnimExtra(P, C);
		Al = (E / 2) & 255;
		if (C > 0 && Al == 0)
		{
			continue;
		}
		Lp = E & 1;
		if (Lp == 0 && F + 0.05 < PrevF[K])
		{
			Epoch[K] = (Epoch[K] + 1) & 15;
		}
		PrevF[K] = F;
		S = S $ string(C) $ ":" $ string(N) $ ":" $ string(int(R * 20.0 + 0.5)) $ ":" $ string(Al / 8) $ ":" $ string(Lp) $ ":" $ string(Epoch[K]) $ ";";
	}
	return S;
}

simulated function string Field(out string S, string Sep)
{
	local int Pos;
	local string R;

	Pos = InStr(S, Sep);
	if (Pos < 0)
	{
		R = S;
		S = "";
		return R;
	}
	R = Left(S, Pos);
	S = Mid(S, Pos + 1);
	return R;
}

simulated function Apply(Actor P, string D, int Slot)
{
	local string Rec, Nm;
	local int C, Al, Loop, Ep, K;
	local float Rate, CF, CR, R1;
	local name CN;
	local byte bSeen[38];
	local int Guard;
	local bool bStart;

	while (D != "" && Guard < 64)
	{
		Guard++;
		Rec = Field(D, ";");
		if (Rec == "")
		{
			continue;
		}
		C = int(Field(Rec, ":"));
		Nm = Field(Rec, ":");
		Rate = float(Field(Rec, ":")) / 20.0;
		Al = int(Field(Rec, ":")) * 8;
		Loop = int(Field(Rec, ":"));
		Ep = int(Field(Rec, ":"));
		if (C < 0 || C >= ChannelCount)
		{
			continue;
		}
		bSeen[C] = 1;
		SetPropertyText("TmpName", Nm);
		if (!P.HasAnim(TmpName))
		{
			continue;
		}
		K = Slot * ChannelCount + C;
		P.GetAnimParams(C, CN, CF, CR);
		bStart = (CN != TmpName) || (Loop != 0 && !P.IsAnimating(C)) || (Loop == 0 && Ep != AppliedEpoch[K]);
		AppliedEpoch[K] = Ep;
		if (bStart)
		{
			R1 = Rate;
			if (R1 < 0.01)
			{
				R1 = 0.01;
			}
			if (Loop != 0)
			{
				P.LoopAnim(TmpName, R1, 0.08, C);
			}
			else
			{
				P.PlayAnim(TmpName, R1, 0.08, C);
			}
			P.GetAnimParams(C, CN, CF, CR);
		}
		// the rate asked for and the rate that comes out differ by the sequence's own scale: asked again with the ratio, only when the animation is started
		// (a one-shot played again here from its first frame, at every record or every two seconds, never came to its end)
		if (bStart && Rate > 0.02 && CR > 0.001 && Abs(CR - Rate) > 0.08 * Rate)
		{
			R1 = Rate * Rate / CR;
			if (Loop != 0)
			{
				P.LoopAnim(TmpName, R1, 0.0, C);
			}
			else
			{
				P.PlayAnim(TmpName, R1, 0.0, C);
			}
		}
		if (C > 0)
		{
			P.AnimBlendToAlpha(C, float(Al) / 255.0, 0.08);
		}
	}
	// a channel the server no longer plays fades out here too
	for (C = 1; C < ChannelCount; C++)
	{
		if (C >= 4 && C <= 11)
		{
			continue;
		}
		if (bSeen[C] == 0)
		{
			P.GetAnimParams(C, CN, CF, CR);
			if (CN != 'None')
			{
				P.AnimBlendToAlpha(C, 0.0, 0.1);
			}
		}
	}
}

// Tests only: the state of every actor of the level that can change (not the static ones), on this machine, one line each, every 10 s. The host writes it with
// EnhProbe, a test guest (bTestShots) writes the same lines; the two logs are compared by the actor's name to see what the guest does not get.
simulated function ProbeWorld()
{
	local Actor A;
	local Emitter E;
	local string S, Em, Nm;
	local int i, Act, Dis, W;
	local name N0;
	local float F, R;
	local int Cnt, C;
	local bool bOn;
	local PlayerController PC;

	if (Role == ROLE_Authority)
	{
		bOn = EnhancedGame(Level.Game) != None && EnhancedGame(Level.Game).bProbeOpt;
	}
	else
	{
		PC = Level.GetLocalPlayerController();
		bOn = EnhancedPlayerController(PC) != None && EnhancedPlayerController(PC).bTestShots;
	}
	if (!bOn)
	{
		return;
	}
	W = Level.Minute * 60 + Level.Second;
	Log("[WP] sample w=" $ string(W));
	foreach AllActors(Class'Engine.Actor', A)
	{
		if (A.bStatic || A == self)
		{
			continue;
		}
		E = Emitter(A);
		if (E == None && A.DrawType != DT_Mesh && A.DrawType != DT_StaticMesh && A.DrawType != DT_Sprite && Mover(A) == None && Light(A) == None)
		{
			continue;
		}
		Em = "";
		if (E != None)
		{
			Act = 0;
			Dis = 0;
			for (i = 0; i < E.Emitters.Length && i < 8; i++)
			{
				if (E.Emitters[i] != None)
				{
					Act += E.Emitters[i].ActiveParticles;
					if (E.Emitters[i].Disabled)
					{
						Dis = Dis | (1 << i);
					}
				}
			}
			Em = " em=" $ string(Act) $ "/" $ string(Dis);
		}
		Cnt = 0;
		N0 = 'None';
		if (A.Mesh != None)
		{
			A.GetAnimParams(0, N0, F, R);
			for (C = 0; C < 38; C++)
			{
				A.GetAnimParams(C, N0, F, R);
				if (N0 != 'None')
				{
					Cnt++;
				}
			}
			A.GetAnimParams(0, N0, F, R);
		}
		S = "[WP] " $ string(A.Name) $ " cls=" $ string(A.Class.Name) $ " hid=" $ string(int(A.bHidden)) $ " dt=" $ string(int(A.DrawType)) $ " ph=" $ string(int(A.Physics)) $ " rr=" $ string(int(A.RemoteRole));
		S = S $ " loc=" $ string(int(A.Location.X / 20.0)) $ "," $ string(int(A.Location.Y / 20.0)) $ "," $ string(int(A.Location.Z / 20.0));
		S = S $ " yaw=" $ string((A.Rotation.Yaw & 65535) / 2048) $ " rate=" $ string(A.RotationRate.Yaw) $ " fix=" $ string(int(A.bFixedRotationDir)) $ " a0=" $ string(N0) $ " na=" $ string(Cnt) $ " lt=" $ string(int(A.LightType)) $ "/" $ string(int(A.LightBrightness)) $ Em;
		if (Mover(A) != None)
		{
			S = S $ " key=" $ string(Mover(A).KeyNum);
		}
		Nm = string(A.GetStateName());
		Log(S $ " st=" $ Nm);
	}
}

// Tests only (a client whose controller has bTestShots, or the server with EnhJitter): what every pawn on this machine plays on channel 0.
simulated function LogState()
{
	local PlayerController PC;
	local KWPawn H;
	local name N0, N20, N21;
	local float F, R, A20, A21;
	local bool bOn;

	if (Role == ROLE_Authority)
	{
		bOn = EnhancedGame(Level.Game) != None && EnhancedGame(Level.Game).bJitterOpt;
	}
	else
	{
		PC = Level.GetLocalPlayerController();
		bOn = EnhancedPlayerController(PC) != None && EnhancedPlayerController(PC).bTestShots;
	}
	if (!bOn)
	{
		return;
	}
	foreach DynamicActors(Class'KWGame.KWPawn', H)
	{
		if (H.bHidden)
		{
			continue;
		}
		H.GetAnimParams(0, N0, F, R);
		H.GetAnimParams(20, N20, F, A20);
		H.GetAnimParams(21, N21, F, A21);
		Log("[AP] w=" $ string(Level.Second * 1000 + Level.Millisecond) $ " " $ string(H.Name) $ " ch0=" $ string(N0) $ " c20=" $ string(N20) $ " c21=" $ string(N21) $ " ing=" $ string(H.IsAnimating(0)) $ " rate=" $ string(int(R * 100.0)) $ " vel=" $ string(int(VSize(H.Velocity))));
	}
}

// The pawns whose animations are carried: the players' Shreks, every pawn a cutscene drives (it plays its animations on the channels 20 and 21, see
// KWCutController.PlayCutsceneAnim, and the engine replicates only channel 0), then the other pawns of the level (the creatures of the surroundings, the
// friends) nearest to the players and to the cameras of the guests, up to the size of the set. The pawns of the set have the engine's own one-channel
// replication switched off (bReplicateAnimations), the others keep it.
function SelectSet()
{
	local Actor A, Bestp;
	local KWPawn K;
	local Controller C;
	local EnhancedGame G;
	local array<Vector> Refs;
	local array<Actor> Rest;
	local float D, BestD;
	local int i, j, N;
	local bool bTaken;

	G = EnhancedGame(Level.Game);
	for (C = Level.ControllerList; C != None; C = C.NextController)
	{
		if (PlayerController(C) != None && C.Pawn != None)
		{
			Refs[Refs.Length] = C.Pawn.Location;
		}
	}
	if (G != None)
	{
		for (i = 0; i < G.GCam.Length; i++)
		{
			if (G.GCam[i] != None)
			{
				Refs[Refs.Length] = G.GCam[i].Location;
			}
		}
	}
	for (i = 0; i < MaxHeroes; i++)
	{
		Pick[i] = None;
	}
	// players' heroes and the pawns a cutscene drives first; then everything else that moves by an animation (the creatures, the lily pads, the friends)
	foreach DynamicActors(Class'Engine.Actor', A)
	{
		if (A.bHidden || A.bDeleteMe || A == self)
		{
			continue;
		}
		K = KWPawn(A);
		if (K != None && (PlayerController(K.Controller) != None || KWCutController(K.Controller) != None))
		{
			if (N < MaxHeroes)
			{
				Pick[N] = K;
				N++;
			}
		}
		else if (K != None)
		{
			Rest[Rest.Length] = A;
		}
		else if (Pawn(A) == None && A.DrawType == DT_Mesh && A.Mesh != None && A.RemoteRole != ROLE_None && !A.bStatic && !A.bNetTemporary)
		{
			Rest[Rest.Length] = A;
		}
	}
	while (N < MaxHeroes && Rest.Length > 0)
	{
		Bestp = None;
		BestD = 4000.0;
		for (i = 0; i < Rest.Length; i++)
		{
			D = 99999.0;
			for (j = 0; j < Refs.Length; j++)
			{
				D = FMin(D, VSize(Rest[i].Location - Refs[j]));
			}
			if (D < BestD)
			{
				BestD = D;
				Bestp = Rest[i];
			}
		}
		if (Bestp == None)
		{
			break;
		}
		Pick[N] = Bestp;
		N++;
		for (i = 0; i < Rest.Length; i++)
		{
			if (Rest[i] == Bestp)
			{
				Rest.Remove(i, 1);
				break;
			}
		}
	}
	// the engine's own replication of channel 0 is off for the set and on for the others (pawns only: the other actors have no such switch)
	foreach DynamicActors(Class'KWGame.KWPawn', K)
	{
		bTaken = false;
		for (i = 0; i < N; i++)
		{
			if (Pick[i] == K)
			{
				bTaken = true;
			}
		}
		if (bTaken)
		{
			if (K.GetPropertyText("bReplicateAnimations") ~= "True" && Shrek(K) == None)
			{
				K.SetPropertyText("bReplicateAnimations", "False");
			}
		}
		else if (K.GetPropertyText("bReplicateAnimations") ~= "False")
		{
			K.SetPropertyText("bReplicateAnimations", "True");
		}
	}
}

simulated function bool Listed(Actor P)
{
	local int i;

	for (i = 0; i < MaxHeroes; i++)
	{
		if (Who[i] == P)
		{
			return true;
		}
	}
	return false;
}

simulated function ClearPawn(Actor P)
{
	local int C;
	local name CN;
	local float CF, CR;

	for (C = 1; C < ChannelCount; C++)
	{
		if (C >= 4 && C <= 11)
		{
			continue;
		}
		P.GetAnimParams(C, CN, CF, CR);
		if (CN != 'None')
		{
			P.AnimBlendToAlpha(C, 0.0, 0.2);
		}
	}
}

// Client: a pawn that has just appeared plays nothing yet and stands in the reference pose (T pose) until its first record arrives. It is kept out of sight
// for that moment (at most a second and a half) and shown as soon as it plays something on any of its channels.
simulated function bool Posed(Actor P)
{
	local name N;
	local float F, R;
	local int C;

	for (C = 0; C < ChannelCount; C++)
	{
		if (C >= 4 && C <= 11)
		{
			continue;
		}
		P.GetAnimParams(C, N, F, R);
		if (N != 'None')
		{
			return true;
		}
	}
	return false;
}

simulated function HideUnposed(float DeltaTime)
{
	local KWPawn K;
	local int i, Free;
	local bool bKnown;

	FreshClock += DeltaTime;
	for (i = 0; i < 24; i++)
	{
		if (Fresh[i] != None)
		{
			FreshAge[i] += DeltaTime;
			if (Fresh[i].bDeleteMe)
			{
				Fresh[i] = None;
			}
			else if (Posed(Fresh[i]) || FreshAge[i] > 1.5)
			{
				Fresh[i].bHidden = false;
				Fresh[i] = None;
			}
		}
	}
	if (FreshClock < 0.1)
	{
		return;
	}
	FreshClock = 0.0;
	if (Seen.Length > 300)
	{
		for (i = Seen.Length - 1; i >= 0; i--)
		{
			if (Seen[i] == None)
			{
				Seen.Remove(i, 1);
			}
		}
	}
	foreach DynamicActors(Class'KWGame.KWPawn', K)
	{
		bKnown = false;
		for (i = 0; i < Seen.Length; i++)
		{
			if (Seen[i] == K)
			{
				bKnown = true;
				break;
			}
		}
		if (bKnown)
		{
			continue;
		}
		Seen[Seen.Length] = K;
		if (K.bHidden || K.Mesh == None || K.bDeleteMe || Posed(K))
		{
			continue;
		}
		Free = -1;
		for (i = 0; i < 24; i++)
		{
			if (Fresh[i] == None)
			{
				Free = i;
				break;
			}
		}
		if (Free >= 0)
		{
			Fresh[Free] = K;
			FreshAge[Free] = 0.0;
			K.bHidden = true;
		}
	}
}

simulated event Tick(float DeltaTime)
{
	local Actor K;
	local int i, N;

	Clock += DeltaTime;
	LogClock += DeltaTime;
	if (LogClock > 1.0)
	{
		LogClock = 0.0;
		LogState();
		ProbeClock += 1.0;
		if (ProbeClock >= 10.0)
		{
			ProbeClock = 0.0;
			ProbeWorld();
		}
	}
	if (Role == ROLE_Authority)
	{
		if (Clock < 0.04)
		{
			return;
		}
		Clock = 0.0;
		// Twice a second the set is chosen again (SelectSet); the records are made every 0.04 s for the pawns of the set.
		SelClock += 0.04;
		if (SelClock > 0.2)
		{
			SelClock = 0.0;
			SelectSet();
		}
		for (i = 0; i < MaxHeroes; i++)
		{
			K = Pick[i];
			if (K != None && !K.bDeleteMe && !K.bHidden)
			{
				Who[N] = K;
				Data[N] = Pack(K, N);
				N++;
			}
		}
		for (i = N; i < MaxHeroes; i++)
		{
			Who[i] = None;
			Data[i] = "";
		}
		return;
	}
	HideUnposed(DeltaTime);
	// again every two seconds whatever the record says: a pawn that came into the game later (a guest's Shrek made after the first ones, one that was
	// hidden for a cutscene) must not stay in the reference pose (T pose) because his record read the same as the last one applied
	ForceClock += DeltaTime;
	for (i = 0; i < MaxHeroes; i++)
	{
		// a pawn that is no longer in the set (a cutscene is over) lets go of the channels the sync gave him
		if (AppliedWho[i] != None && AppliedWho[i] != Who[i])
		{
			if (!Listed(AppliedWho[i]))
			{
				ClearPawn(AppliedWho[i]);
			}
			AppliedWho[i] = None;
			Applied[i] = "";
		}
		if (Who[i] != None && (Data[i] != Applied[i] || Who[i] != AppliedWho[i] || ForceClock > 2.0))
		{
			Applied[i] = Data[i];
			AppliedWho[i] = Who[i];
			Apply(Who[i], Data[i], i);
		}
	}
	if (ForceClock > 2.0)
	{
		ForceClock = 0.0;
	}
}

defaultproperties
{
	RemoteRole=ROLE_SimulatedProxy
	bAlwaysRelevant=True
	bHidden=True
	NetUpdateFrequency=30.0
	NetPriority=3.0
	DrawType=DT_None
}

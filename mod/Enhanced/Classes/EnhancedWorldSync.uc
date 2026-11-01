class EnhancedWorldSync extends Actor;

// The level places a lot of things for itself that the engine never sends to a client, because the game was made without a network: the torches, the pollen, the
// fires, the sparkles of the coins, the gnats and dragonflies (RemoteRole none), and a client does not keep them from his own copy of the map. This actor
// carries them: the host picks the nearest of them (up to MaxTwins, around the players), tells the clients which class stands where, and every client makes a
// local twin of each (a simulated copy: the class' own defaults bring the particle emitters or the mesh with them) and keeps its place, visibility, animation and
// emitters in line with the original. A twin that is not in the list any more is destroyed.
// Rec[i] = "key|Package.Class" (changes when the slot is given to another actor), Pos[i] = "x,y,z,yaw,hidden,animation,emitters,scale" (changes with the actor).

const MaxTwins = 80;

var string Rec[80];
var string Pos[80];
var float Clock, StampClock;
var int Stamp;
var int Part;                          // host: this actor carries the actors whose name hashes to Part (0..3); a replicated array of more than about a hundred entries does not get through, so there are four of these

// host
var array<string> SlotKey;            // slot -> the actor's name (the same index space as Rec)
var array<Actor> SlotActor;
var float PosTime[80];                // host: when the record of a creature was last made
var array<Actor> WideSet;             // actors made always relevant because the players are near; let go of when they are not

// client
var Actor Twin[80];
var string TwinRec[80];
var string TwinPos[80];
var Vector Target[80];
var float LastApply[80];              // client: when the record of a twin was last applied and how long the one before took (the twin drifts to its place in about that time)
var float Interval[80];
var int Moving[80];                  // the twin is still on its way to its record's place (only these are moved every frame)
var float SlotClock;                  // the records are looked through ten times a second, not every frame
var string Tried[80];
var name TmpAnim;
var float SpinClock;                  // client: when the pickups to turn were last collected
var int SpinFixed;
var Actor SpinWatch[5];               // pickups the player can see, watched for half a second after they were given their rotation, to see that they turn
var int SpinYaw0[5];
var float SpinWatchClock;
var bool bSpinWatching;
var int SpinWatchRuns;

replication
{
	reliable if (Role == ROLE_Authority)
		Rec;
	unreliable if (Role == ROLE_Authority)
		Pos;
}

simulated function string Field(out string S, string Sep)
{
	local int P;
	local string R;

	P = InStr(S, Sep);
	if (P < 0)
	{
		R = S;
		S = "";
		return R;
	}
	R = Left(S, P);
	S = Mid(S, P + 1);
	return R;
}

function int HashOf(Actor A)
{
	local string N;
	local int i, H;

	N = string(A.Name);
	for (i = 0; i < Len(N) && i < 16; i++)
	{
		H += Asc(Mid(N, i, 1)) * (i + 1);
	}
	return H;
}

function bool Twinnable(Actor A)
{
	if (A == None || A == self || A.bStatic || A.bDeleteMe || A.RemoteRole != ROLE_None || A.bNetTemporary)
	{
		return false;
	}
	if (Left(string(A.Class), 8) ~= "Enhanced" || Controller(A) != None || Info(A) != None)
	{
		return false;
	}
	if (Pawn(A) != None && Pawn(A).Controller != None && PlayerController(Pawn(A).Controller) != None)
	{
		return false;
	}
	if ((HashOf(A) % 4) != Part)
	{
		return false;
	}
	if (Emitter(A) != None)
	{
		return true;
	}
	return A.DrawType == DT_Mesh && A.Mesh != None && !A.bHidden;
}

// The stamp at the end of a record makes the text change now and then, so a record that was lost is sent again. A record that does not change is not sent at
// all (the engine compares with what it sent last), so a torch or a fire costs nothing between two stamps. It used to be one counter for all records, changing
// every 2 s: ~100 records were sent again every 2 s (~2.4 KB/s of the ~3 KB/s the host sent). Now every record has its own stamp with its own phase: scenery
// repeats every StampStatic seconds (a lost record is a torch that appears late), a creature every StampMoving seconds, the repeats spread over the period.
const StampStatic = 40.0;
const StampMoving = 6.0;

function int StampFor(int Slot, bool bMoving)
{
	local float Period;

	Period = StampStatic;
	if (bMoving)
	{
		Period = StampMoving;
	}
	return int((Level.TimeSeconds + float(Slot) * (Period / float(MaxTwins))) / Period) & 255;
}

function string PosOf(Actor A, int Slot)
{
	local string S, Em, An;
	local Emitter E;
	local int i, Dis;
	local name N0;
	local float F, R;

	E = Emitter(A);
	if (E != None)
	{
		for (i = 0; i < E.Emitters.Length && i < 16; i++)
		{
			if (E.Emitters[i] != None && E.Emitters[i].Disabled)
			{
				Dis = Dis | (1 << i);
			}
		}
		Em = string(Dis);
	}
	else if (A.Mesh != None)
	{
		A.GetAnimParams(0, N0, F, R);
		An = string(N0);
	}
	S = string(int(A.Location.X)) $ "," $ string(int(A.Location.Y)) $ "," $ string(int(A.Location.Z)) $ "," $ string(A.Rotation.Yaw & 65535) $ "," $ string(int(A.bHidden)) $ "," $ An $ "," $ Em $ "," $ string(int(A.DrawScale * 100.0)) $ "," $ string(StampFor(Slot, Pawn(A) != None));
	return S;
}

function Refresh()
{
	local Actor A;
	local Controller C;
	local array<Vector> Refs;
	local array<Actor> Cand;
	local array<float> Dist;
	local array<Actor> Pick;
	local float D, BestD;
	local int i, j, k, Best, Free;
	local bool bKeep, bNoWide, bNoTwin;
	local string ClsName;

	// tests: ?EnhOff=wide (the engine's own actors are not made always relevant) and ?EnhOff=twin (no twins): what each costs in traffic
	bNoWide = EnhancedGame(Level.Game) != None && EnhancedGame(Level.Game).Off("wide");
	bNoTwin = EnhancedGame(Level.Game) != None && EnhancedGame(Level.Game).Off("twin");
	for (C = Level.ControllerList; C != None; C = C.NextController)
	{
		if (PlayerController(C) != None && C.Pawn != None)
		{
			Refs[Refs.Length] = C.Pawn.Location;
		}
	}
	if (Refs.Length == 0)
	{
		return;
	}
	for (i = WideSet.Length - 1; Part == 0 && i >= 0; i--)
	{
		bKeep = false;
		if (WideSet[i] != None && !WideSet[i].bDeleteMe)
		{
			for (j = 0; j < Refs.Length; j++)
			{
				if (VSize(WideSet[i].Location - Refs[j]) < 4500.0)
				{
					bKeep = true;
					break;
				}
			}
		}
		if (!bKeep)
		{
			if (WideSet[i] != None)
			{
				WideSet[i].bAlwaysRelevant = false;
			}
			WideSet.Remove(i, 1);
		}
	}
	foreach DynamicActors(Class'Engine.Actor', A)
	{
		if (Part == 0 && !bNoWide && A.RemoteRole > ROLE_None && !A.bAlwaysRelevant && !A.bStatic && !A.bDeleteMe && (Pawn(A) != None || Mover(A) != None) && Controller(A) == None)
		{
			// the engine sends an actor to a client only while it can be seen from the client's viewpoint; enemies and objects around the players are
			// wanted whether or not the wall in front of them hides them, so they are sent always while the players are near (see WideSet). Only creatures and moving
			// constructions: every actor made always relevant has to be received and processed by the guest (~7 fps for the whole 3500-unit ball of props).
			for (j = 0; j < Refs.Length; j++)
			{
				if (VSize(A.Location - Refs[j]) < 3500.0)
				{
					A.bAlwaysRelevant = true;
					WideSet[WideSet.Length] = A;
					break;
				}
			}
		}
		if (bNoTwin || !Twinnable(A))
		{
			continue;
		}
		D = 999999.0;
		for (j = 0; j < Refs.Length; j++)
		{
			D = FMin(D, VSize(A.Location - Refs[j]));
		}
		if (D < 7000.0)
		{
			Cand[Cand.Length] = A;
			Dist[Dist.Length] = D;
		}
	}
	// the nearest MaxTwins of them
	for (k = 0; k < MaxTwins && Cand.Length > 0; k++)
	{
		Best = 0;
		BestD = Dist[0];
		for (i = 1; i < Cand.Length; i++)
		{
			if (Dist[i] < BestD)
			{
				BestD = Dist[i];
				Best = i;
			}
		}
		Pick[Pick.Length] = Cand[Best];
		Cand.Remove(Best, 1);
		Dist.Remove(Best, 1);
	}
	// slots: an actor keeps its slot while it is picked
	while (SlotKey.Length < MaxTwins)
	{
		SlotKey[SlotKey.Length] = "";
		SlotActor[SlotActor.Length] = None;
	}
	for (i = 0; i < MaxTwins; i++)
	{
		bKeep = false;
		if (SlotActor[i] != None && !SlotActor[i].bDeleteMe)
		{
			for (j = 0; j < Pick.Length; j++)
			{
				if (Pick[j] == SlotActor[i])
				{
					bKeep = true;
					break;
				}
			}
		}
		if (!bKeep)
		{
			SlotActor[i] = None;
			SlotKey[i] = "";
			Rec[i] = "";
			Pos[i] = "";
		}
	}
	for (j = 0; j < Pick.Length; j++)
	{
		bKeep = false;
		Free = -1;
		for (i = 0; i < MaxTwins; i++)
		{
			if (SlotActor[i] == Pick[j])
			{
				bKeep = true;
				break;
			}
			if (SlotActor[i] == None && Free < 0)
			{
				Free = i;
			}
		}
		if (!bKeep && Free >= 0)
		{
			SlotActor[Free] = Pick[j];
			SlotKey[Free] = string(Pick[j].Name);
			ClsName = string(Pick[j].Class);
			if (Pawn(Pick[j]) != None && Pick[j].Mesh != None)
			{
				// a creature's twin is a plain actor wearing its mesh: a copy of the creature itself would run its own brain and destroy itself
				ClsName = "Enhanced.EnhancedTwin|" $ string(Pick[j].Mesh);
			}
			Rec[Free] = SlotKey[Free] $ "|" $ ClsName;
		}
	}
	for (i = 0; i < MaxTwins; i++)
	{
		if (SlotActor[i] != None)
		{
			// a creature (the gnats and dragonflies of the swamp: 13 of them, each record ~50 bytes) moves all the time, so its record changes at every look; the guest
			// needs no more than a place to drift to, a record a second is enough (~2.6 KB/s of the host's ~2.7 KB/s were these records at four a second)
			if (Pawn(SlotActor[i]) == None || Pos[i] == "" || Level.TimeSeconds - PosTime[i] >= 1.0)
			{
				Pos[i] = PosOf(SlotActor[i], i);
				PosTime[i] = Level.TimeSeconds;
			}
		}
	}
}

simulated function KillTwin(int i)
{
	if (Twin[i] != None)
	{
		Twin[i].Destroy();
	}
	Twin[i] = None;
	TwinRec[i] = "";
	TwinPos[i] = "";
	Moving[i] = 0;
	LastApply[i] = 0.0;
}

simulated function MakeTwin(int i)
{
	local string R, Key, Path;
	local Class<Actor> C;
	local Actor T;
	local string P, X, Y, Z, MeshPath;
	local Vector V;
	local Mesh M;

	P = Pos[i];
	X = Field(P, ",");
	Y = Field(P, ",");
	Z = Field(P, ",");
	V.X = float(X);
	V.Y = float(Y);
	V.Z = float(Z);
	R = Rec[i];
	Key = Field(R, "|");
	Path = Field(R, "|");
	MeshPath = R;
	if (Tried[i] == Rec[i])
	{
		return;
	}
	Tried[i] = Rec[i];
	C = Class<Actor>(DynamicLoadObject(Path, Class'Core.Class'));
	if (C == None)
	{
		Log("[WSY] twin " $ string(i) $ " " $ Key $ ": class " $ Path $ " not found");
		return;
	}
	T = Spawn(C,,, V, rot(0, 0, 0));
	if (T == None)
	{
		T = Spawn(C,,, V + vect(0, 0, 40), rot(0, 0, 0));
	}
	if (T == None)
	{
		Log("[WSY] twin " $ string(i) $ " " $ Key $ ": spawn of " $ Path $ " failed at " $ string(V));
		return;
	}
	if (MeshPath != "")
	{
		M = Mesh(DynamicLoadObject(MeshPath, Class'Engine.Mesh'));
		if (M != None)
		{
			T.LinkMesh(M);
			T.SetDrawType(DT_Mesh);
		}
		else
		{
			Log("[WSY] twin " $ string(i) $ " " $ Key $ ": mesh " $ MeshPath $ " not found");
		}
	}
	Log("[WSY] twin " $ string(i) $ " " $ Key $ ": " $ string(T) $ " " $ MeshPath);
	T.SetCollision(false, false, false);
	T.bCollideWorld = false;
	T.SetPhysics(PHYS_None);
	Twin[i] = T;
	TwinRec[i] = Rec[i];
	TwinPos[i] = "";
}

simulated function ApplyPos(int i)
{
	local string P, X, Y, Z, Yaw, Hid, An, Em, Sc;
	local Vector V;
	local Emitter E;
	local int k, Dis;
	local name Cur;
	local float F, R;
	local Actor T;

	T = Twin[i];
	if (T == None || T.bDeleteMe)
	{
		return;
	}
	P = Pos[i];
	X = Field(P, ",");
	Y = Field(P, ",");
	Z = Field(P, ",");
	Yaw = Field(P, ",");
	Hid = Field(P, ",");
	An = Field(P, ",");
	Em = Field(P, ",");
	Sc = Field(P, ",");
	V.X = float(X);
	V.Y = float(Y);
	V.Z = float(Z);
	Target[i] = V;
	if (LastApply[i] == 0.0)
	{
		Interval[i] = 1.0;
	}
	else
	{
		Interval[i] = FClamp(Level.TimeSeconds - LastApply[i], 0.2, 3.0);
	}
	LastApply[i] = Level.TimeSeconds;
	if (TwinPos[i] == "" || VSize(T.Location - V) > 600.0)
	{
		T.SetLocation(V);
	}
	T.SetRotation(rot(0, 0, 0) + MakeRot(int(Yaw)));
	T.bHidden = (Hid == "1");
	if (Sc != "" && float(Sc) > 0.0)
	{
		T.SetDrawScale(float(Sc) / 100.0);
	}
	E = Emitter(T);
	if (E != None && Em != "")
	{
		Dis = int(Em);
		for (k = 0; k < E.Emitters.Length && k < 16; k++)
		{
			if (E.Emitters[k] != None)
			{
				E.Emitters[k].Disabled = ((Dis & (1 << k)) != 0);
			}
		}
	}
	if (An != "" && An != "None" && T.Mesh != None)
	{
		T.GetAnimParams(0, Cur, F, R);
		SetPropertyText("TmpAnim", An);
		if (Cur != TmpAnim && T.HasAnim(TmpAnim))
		{
			T.LoopAnim(TmpAnim);
		}
	}
}

simulated function Rotator MakeRot(int Yaw)
{
	local Rotator R;

	R.Yaw = Yaw;
	return R;
}

// The pickups (coins, money bags, energy bars and kegs, potions of health) turn on the host: the stock script gives them Physics = PHYS_Rotating, a
// rotation rate and a fixed direction when the level starts, and the server replicates them as dumb proxies (ROLE_DumbProxy): a dumb proxy is not
// simulated on the client, which stayed at PHYS_None and never turned them. The way the engine means it (Replication Roles): the server makes them
// simulated proxies (see Refresh), and the client, which gets the initial location, rotation and rate, runs the rotation itself; the angle need not be the
// host's at every moment, only the place. A pickup on the client that has a rate and no physics is given PHYS_Rotating here.
simulated function FixSpinners()
{
	local Pickup P;
	local Rotator R;
	local int N;

	foreach DynamicActors(Class'Engine.Pickup', P)
	{
		if (P.Physics == PHYS_None && P.RotationRate.Yaw != 0 && P.bFixedRotationDir)
		{
			if (P.Rotation.Yaw == 0)
			{
				R = P.Rotation;
				R.Yaw = int(Abs(P.Location.X * 7.0 + P.Location.Y * 13.0)) & 65535;   // the host gave every pickup its own start angle; the replicated one is zero
				P.SetRotation(R);
			}
			P.Role = ROLE_SimulatedProxy;   // the client's own copy of a map actor keeps the class's role; only a simulated proxy is simulated
			P.SetPhysics(PHYS_Rotating);
			if (!bSpinWatching && SpinWatchRuns < 3 && Level.TimeSeconds - P.LastRenderTime < 1.0 && N < 5)
			{
				SpinWatch[N] = P;
				SpinYaw0[N] = P.Rotation.Yaw & 65535;
				N++;
			}
			SpinFixed++;
		}
	}
	if (N > 0)
	{
		bSpinWatching = true;
		SpinWatchClock = 0.0;
		SpinWatchRuns++;
	}
}

simulated event Tick(float DeltaTime)
{
	local int i;
	local Vector D;
	local float Alpha;

	if (Role == ROLE_Authority)
	{
		Clock += DeltaTime;
		if (Clock >= 0.25)
		{
			Clock = 0.0;
			Refresh();
		}
		return;
	}
	if (bSpinWatching)
	{
		SpinWatchClock += DeltaTime;
		if (SpinWatchClock >= 0.5)
		{
			bSpinWatching = false;
			for (i = 0; i < 5; i++)
			{
				if (SpinWatch[i] != None)
				{
					Log("[SPIN] check " $ string(SpinWatchRuns) $ ": " $ string(SpinWatch[i].Name) $ " yaw " $ string(SpinYaw0[i]) $ " -> " $ string(SpinWatch[i].Rotation.Yaw & 65535) $ " in " $ string(SpinWatchClock) $ " s, physics " $ string(int(SpinWatch[i].Physics)) $ " role " $ string(int(SpinWatch[i].Role)) $ " rendered " $ string(Level.TimeSeconds - SpinWatch[i].LastRenderTime) $ " s ago");
					SpinWatch[i] = None;
				}
			}
		}
	}
	SpinClock += DeltaTime;
	if (SpinClock >= 1.0)
	{
		SpinClock = 0.0;
		FixSpinners();
	}
	SlotClock += DeltaTime;
	if (SlotClock >= 0.1)
	{
		SlotClock = 0.0;
		for (i = 0; i < MaxTwins; i++)
		{
			if (Rec[i] == "" && Twin[i] == None)
			{
				continue;
			}
			if (Rec[i] != TwinRec[i])
			{
				KillTwin(i);
				if (Rec[i] != "" && Pos[i] != "")
				{
					MakeTwin(i);
				}
				else
				{
					Tried[i] = "";
				}
			}
			if (Twin[i] == None && Rec[i] != "" && Pos[i] != "" && Tried[i] != Rec[i])
			{
				MakeTwin(i);
			}
			if (Twin[i] != None && Pos[i] != TwinPos[i] && Pos[i] != "")
			{
				ApplyPos(i);
				TwinPos[i] = Pos[i];
				if (VSize(Target[i] - Twin[i].Location) > 1.0)
				{
					Moving[i] = 1;
				}
			}
		}
	}
	for (i = 0; i < MaxTwins; i++)
	{
		if (Moving[i] != 0 && Twin[i] != None)
		{
			Alpha = FMin(1.0, DeltaTime * 2.0 / FMax(Interval[i], 0.2));
			D = Target[i] - Twin[i].Location;
			if (VSize(D) > 1.0)
			{
				Twin[i].SetLocation(Twin[i].Location + D * Alpha);
			}
			else
			{
				Moving[i] = 0;
			}
		}
	}
}

defaultproperties
{
	RemoteRole=ROLE_SimulatedProxy
	bAlwaysRelevant=True
	bHidden=True
	NetUpdateFrequency=10.0
	DrawType=DT_None
}

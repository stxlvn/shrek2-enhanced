class EnhancedDebug extends Info;

// Debug layer for the co-op mod (the Shrek 2 counterpart of the MW2 mod's scrdebug).
// All output goes to the game log with the tag [SDBG], so it can be grepped:
//   [SDBG] trace lines written by the mod's own code,
//   [SDBG] STATE dumps of controllers, pawns and cameras every DumpInterval seconds,
//   [SDBG] CMD results of console commands placed in sdbg_cmd_<n>.txt next to Game.exe.

var float DumpInterval;
var int NextCmd;
var bool bPollCommands;

// Late-join repair: a game save detaches the level package's loader, and the engine then crashes
// when a client joins (UPackageMap::Compute asserts List(i).Linker). The check below notices the
// missing loader and reloads the level package.
var bool bRepairLinker;
var bool bLinkerKnownGood;
var int LinkerChecks;
var int LastLen;
var bool bIterTested;
var bool bCaptureTested;
var bool bBenchTested;
var bool bMutated;
var bool bCounted;
var bool bMutateTest;
var int RulePhase;
var float RuleT;
var Vector HomeLoc;
var Vector StartSpot;
var Rotator StartRot;
var bool FindSpot;
var float CaptureAt;
var bool bSubTest;
var bool bSubShown;
var bool bTexLogged;
var string LastVT[2];
var bool bFFTest;
var bool bFFDone;
var bool bTravelTest;
var bool bTravelDone;
var float TravelStart;
var float FFStart;

event PostBeginPlay()
{
	Super.PostBeginPlay();
	SetTimer(1.0, true);
	NextCmd = 1;
	Out("EnhancedDebug up, interval=" $ string(DumpInterval));
}

static function Say(Actor Context, string S)
{
	Context.Log("[SDBG] " $ S);
}

function Out(string S)
{
	Log("[SDBG] t=" $ string(Level.TimeSeconds) $ " " $ S);
}

function string GetPropertyTextOf(Actor A, string PropName)
{
	if (A == None)
	{
		return "none";
	}
	return A.GetPropertyText(PropName);
}

function string PawnInfo(Pawn P)
{
	if (P == None)
	{
		return "none";
	}
	// Fields whose type differs between the editor's engine and the game's engine are read as text.
	return string(P) $ " loc=" $ string(P.Location)
		$ " ctrl=" $ string(P.Controller)
		$ " role=" $ GetPropertyTextOf(P, "Role") $ "/" $ GetPropertyTextOf(P, "RemoteRole")
		$ " main=" $ GetPropertyTextOf(P, "bIsMainPlayer")
		$ " state=" $ string(P.GetStateName())
		$ " vel=" $ string(int(VSize(P.Velocity)))
		$ " hp=" $ GetPropertyTextOf(P, "Health");
}

function Dump(string Tag)
{
	local Controller C;
	local PlayerController PC;
	local int n;

	Out("STATE " $ Tag $ " netmode=" $ string(Level.NetMode) $ " players=" $ string(Level.Game.NumPlayers)
		$ " pauser=" $ string(Level.Pauser) $ " heroActor=" $ Level.GetPropertyText("PlayerHeroActor"));
	for (C = Level.ControllerList; C != None; C = C.NextController)
	{
		PC = PlayerController(C);
		if (PC != None)
		{
			Out("  PC " $ string(PC) $ " player=" $ string(PC.Player) $ " state=" $ string(PC.GetStateName())
				$ " viewTarget=" $ string(PC.ViewTarget) $ " pawn: " $ PawnInfo(PC.Pawn));
		}
		n++;
	}
	Out("  controllers total=" $ string(n));
}

function string LevelPackageName()
{
	local string S;

	S = string(Level);
	return Left(S, InStr(S, "."));
}

// Observation only. Printing the whole listing crashed the engine (a long string in Log), so only its
// length and a few exact-name probes are logged when the length changes.
// Experiment: do iterators work in code compiled by the editor? (A foreach crashed the host once.)
function TestIterators()
{
	local Actor A;
	local Triggers T;
	local int n, nTrig;

	Out("ITER test: start AllActors(Actor)");
	foreach AllActors(Class'Engine.Actor', A)
	{
		n++;
	}
	Out("ITER test: AllActors(Actor) counted " $ string(n));
	foreach AllActors(Class'Engine.Triggers', T)
	{
		nTrig++;
	}
	Out("ITER test: AllActors(Triggers) counted " $ string(nTrig));
}

// Load test: how many breakable crates and coins exist after the level start and the restore pass.
// Switched on by the URL option ?EnhTest=1: the experiments of the development builds (state mutations, a
// test checkpoint at 20 s, counts, a cost benchmark). Off in normal play.
function EnableTests()
{
	bMutateTest = true;
	CaptureAt = 20.0;
	bCounted = false;
	bBenchTested = false;
	bIterTested = false;
	Out("tests enabled");
}

function CountThings()
{
	local BreakableCrate Cr;
	local BreakableDoorBlock Bd;
	local Coin Cn;
	local int nCr, nBd, nCn;

	foreach AllActors(Class'ShGame.BreakableCrate', Cr)
	{
		nCr++;
	}
	foreach AllActors(Class'ShGame.BreakableDoorBlock', Bd)
	{
		nBd++;
	}
	foreach AllActors(Class'ShGame.Coin', Cn)
	{
		nCn++;
	}
	Out("COUNT crates=" $ string(nCr) $ " doorblocks=" $ string(nBd) $ " coins=" $ string(nCn));
}

// Save test: mark one crate as destroyed, as if the player had broken it.
function MutateHero()
{
	local KWPawn H;
	local Controller C;
	local PlayerController PC;
	local int have;

	for (C = Level.ControllerList; C != None; C = C.NextController)
	{
		PC = PlayerController(C);
		if (PC != None && PC.Pawn != None && KWPawn(PC.Pawn) != None)
		{
			H = KWPawn(PC.Pawn);
			EnhancedGame(Level.Game).PlaceNear(H, H.Location, H.Rotation);
			H.SetPropertyText("Health", "37");
			have = H.GetInventoryCount('Coin');
			H.AddToInventoryCollection(Class'ShGame.CoinCollection', 25);
			Out("MUTATE hero " $ string(H) $ " moved to " $ string(H.Location) $ ", health 37, coins " $ string(have) $ " -> " $ string(H.GetInventoryCount('Coin')));
			return;
		}
	}
	Out("MUTATE hero: no player pawn found");
}

function MutateOneCrate()
{
	local BreakableCrate Cr;

	foreach AllActors(Class'ShGame.BreakableCrate', Cr)
	{
		Cr.SetPropertyText("WasDestroyed", "1");
		Out("MUTATE crate " $ string(Cr.Name) $ " marked destroyed");
		break;
	}
}

// A real place of the level that is far from a point: the farthest navigation point (those lie on walkable
// ground). The tests used to invent coordinates, and some lay outside the level, so a pawn fell under the map.
function Vector FarNavPoint(Vector From)
{
	local NavigationPoint N;
	local Vector Best;
	local float BestD, D;

	Best = From;
	for (N = Level.NavigationPointList; N != None; N = N.nextNavigationPoint)
	{
		D = VSize(N.Location - From);
		if (D > BestD)
		{
			BestD = D;
			Best = N.Location;
		}
	}
	Best.Z += 60.0;
	return Best;
}

// Test of the both-players rule: two players with pawns are needed (the host and the joined client).
function TestRule()
{
	local Controller C;
	local PlayerController PC, Host, Partner;
	local EnhancedGame G;

	for (C = Level.ControllerList; C != None; C = C.NextController)
	{
		PC = PlayerController(C);
		if (PC != None && PC.Pawn != None)
		{
			if ((PC.IsA('EnhancedHeroController') || PC.IsA('EnhancedDonkeyController')))
			{
				Host = PC;
			}
			else
			{
				Partner = PC;
			}
		}
	}
	if (Host == None || Partner == None)
	{
		return;
	}
	if (RulePhase == 0)
	{
		RulePhase = 1;
		RuleT = Level.TimeSeconds;
		EnhancedGame(Level.Game).PlaceNear(Partner.Pawn, Host.Pawn.Location, Host.Pawn.Rotation);
		Out("RULE both players present: " $ string(Host.Pawn) $ " and " $ string(Partner.Pawn));
		return;
	}
	G = EnhancedGame(Level.Game);
	if (RulePhase == 1 && Level.TimeSeconds > RuleT + 3.0)
	{
		RulePhase = 2;
		Out("RULE phase 1: partner next to the host, a checkpoint is requested (expect: counts at once)");
		G.LastCheckpointTime = 0.0;
		G.OnCheckpointRequest(Host, "rule-near");
		HomeLoc = Host.Pawn.Location;
	}
	if (RulePhase == 2 && Level.TimeSeconds > RuleT + 8.0)
	{
		RulePhase = 3;
		Partner.Pawn.SetLocation(FarNavPoint(HomeLoc));
		Out("RULE phase 2: partner on a far real place of the level, the host reaches a checkpoint (expect: waits; then the leash returns the partner to the checkpoint and the checkpoint counts)");
		G.LastCheckpointTime = 0.0;
		G.OnCheckpointRequest(Host, "rule-far");
	}
	if (RulePhase == 3 && Level.TimeSeconds > RuleT + 22.0)
	{
		RulePhase = 4;
		FindSpot = G.FindStartSpot(StartSpot, StartRot);
		Host.Pawn.SetLocation(G.Exits[0].Location + vect(0.0, 0.0, 100.0));
		Partner.Pawn.SetLocation(StartSpot + vect(0.0, 0.0, 100.0));
		Out("RULE phase 3: host at exit 0, partner at the level start, far from each other (expect: the leash brings the runaway to his partner after the grace time)");
	}
	if (RulePhase == 4 && Level.TimeSeconds > RuleT + 34.0)
	{
		RulePhase = 5;
		G.LeashDistance = 100000000.0;
		Host.Pawn.SetLocation(G.Exits[1].Location + vect(0.0, 0.0, 100.0));
		Partner.Pawn.SetLocation(HomeLoc + vect(0.0, 0.0, 50.0));
		Out("RULE phase 4: the host stands at exit 1, the partner is elsewhere (expect: the exit is closed)");
	}
	if (RulePhase == 5 && Level.TimeSeconds > RuleT + 41.0)
	{
		RulePhase = 6;
		G.PlaceNear(Partner.Pawn, G.Exits[1].Location, Partner.Pawn.Rotation);
		Out("RULE phase 5: the partner arrives at exit 1 (expect: the exit opens)");
	}
}

function CheckLevelLinker()
{
	local string Res, U, Pkg;

	Res = ConsoleCommand("obj linkers");
	LinkerChecks++;
	if (Len(Res) != LastLen)
	{
		LastLen = Len(Res);
		U = Caps(Res);
		Pkg = Caps(LevelPackageName());
		Out("LINKERS len=" $ string(LastLen)
			$ " level=" $ string(InStr(U, "(PACKAGE " $ Pkg $ ")") >= 0)
			$ " levelSM=" $ string(InStr(U, "(PACKAGE " $ Pkg $ "_SM)") >= 0)
			$ " shgame=" $ string(InStr(U, "(PACKAGE SHGAME)") >= 0)
			$ " kwgame=" $ string(InStr(U, "(PACKAGE KWGAME)") >= 0)
			$ " ambient=" $ string(InStr(U, "(PACKAGE AMBIENTCREATURES)") >= 0)
			$ " pkg=" $ string(InStr(U, "(PACKAGE ENHANCED)") >= 0)
			$ " ambAnims=" $ string(InStr(U, "(PACKAGE AMBCREATUREANIMS)") >= 0));
	}
}

// A frame that took long: shows how much a checkpoint costs.
// Logs every change of what each player's camera looks at (a camera that two things fight over flips often).
function WatchViews()
{
	local EnhancedGame G;
	local PlayerController H;
	local string V;

	G = EnhancedGame(Level.Game);
	if (G == None)
	{
		return;
	}
	H = G.HostController();
	if (H != None)
	{
		V = string(H.ViewTarget) $ " ctrl=" $ string(H.Pawn) $ " state=" $ string(H.GetStateName());
		if (V != LastVT[0])
		{
			LastVT[0] = V;
			Out("VIEW host: " $ V);
		}
	}
	if (G.PendingPC != None)
	{
		V = string(G.PendingPC.ViewTarget) $ " pawn=" $ string(G.PendingPC.Pawn) $ " state=" $ string(G.PendingPC.GetStateName());
		if (V != LastVT[1])
		{
			LastVT[1] = V;
			Out("VIEW p2: " $ V);
		}
	}
}

event Tick(float DeltaTime)
{
	Super.Tick(DeltaTime);
	WatchViews();
	if (DeltaTime > 0.05)
	{
		Out("HITCH frame took " $ string(DeltaTime) $ " s");
	}
}

// A hit from one Shrek on the other: with friendly fire off nothing may change, with 0.5 the damage is halved.
function TestFF()
{
	local EnhancedGame G;
	local Pawn H, P;
	local float Save;

	G = EnhancedGame(Level.Game);
	P = G.P2Pawn;
	H = G.HostController().Pawn;
	Save = G.FriendlyFire;
	Out("FF test: scale " $ string(G.FriendlyFire) $ ", health before " $ P.GetPropertyText("Health"));
	P.TakeDamage(10, H, P.Location, vect(0.0, 0.0, 0.0), Class'ShGame.RegularAttackDamage');
	Out("FF test: after a hit of 10: " $ P.GetPropertyText("Health"));
	G.FriendlyFire = 0.5;
	P.TakeDamage(10, H, P.Location, vect(0.0, 0.0, 0.0), Class'ShGame.RegularAttackDamage');
	Out("FF test: scale 0.5, after a hit of 10: " $ P.GetPropertyText("Health"));
	G.FriendlyFire = Save;
}

function string StripTag(string S)
{
	local int P;

	P = InStr(S, "]");
	if (P >= 0)
	{
		return Mid(S, P + 1);
	}
	return S;
}

function LogTex(string N)
{
	local Texture T;

	T = Texture(DynamicLoadObject(N, Class'Engine.Texture'));
	if (T == None)
	{
		Out("texture " $ N $ " not found");
	}
	else
	{
		Out("texture " $ N $ " " $ string(T.USize) $ "x" $ string(T.VSize) $ " format=" $ T.GetPropertyText("Format"));
	}
}

event Timer()
{
	local int Secs;
	local string Res;
	local PlayerController PC;

	Secs = int(Level.TimeSeconds);
	if (DumpInterval > 0.0 && (Secs % int(DumpInterval)) == 0)
	{
		Dump("periodic");
	}
	if (!bCaptureTested && CaptureAt > 0.0 && Level.TimeSeconds > CaptureAt)
	{
		bCaptureTested = true;
		Out("CAPTURE test begins");
		EnhancedGame(Level.Game).CaptureCheckpoint("test", "debug");
		Out("CAPTURE test ends");
		EnhancedGame(Level.Game).VerifyCheckpoint("test");
	}
	if (bFFTest && !bFFDone && EnhancedGame(Level.Game).P2Pawn != None)
	{
		if (FFStart == 0.0)
		{
			FFStart = Level.TimeSeconds;
		}
		if (Level.TimeSeconds > FFStart + 4.0)
		{
			bFFDone = true;
			TestFF();
		}
	}
	if (bTravelTest && !bTravelDone && LevelPackageName() ~= "1_Shreks_Swamp" && EnhancedGame(Level.Game).P2Pawn != None && !EnhancedGame(Level.Game).bP2Hidden)
	{
		if (TravelStart == 0.0)
		{
			TravelStart = Level.TimeSeconds;
		}
		if (Level.TimeSeconds > TravelStart + 20.0)
		{
			bTravelDone = true;
			Out("travel test: ServerTravel to 2_Carriage_Hijack");
			Level.ServerTravel("2_Carriage_Hijack", true);
		}
	}
	if (bSubTest && !bTexLogged && Level.TimeSeconds > 8.0)
	{
		bTexLogged = true;
		LogTex("1_Shreks_Swamp_Tex.tree_5");
		LogTex("1_Shreks_Swamp_Tex.plant_purp");
		LogTex("1_Shreks_Swamp_Tex.water_base");
		LogTex("1_Shreks_Swamp_Tex.grass_tall");
	}
	if (bSubTest && !bSubShown && Level.TimeSeconds > 25.0)
	{
		bSubShown = true;
		foreach AllActors(Class'Engine.PlayerController', PC)
		{
			if (KWHud(PC.myHUD) != None)
			{
				KWHud(PC.myHUD).SetSubtitleText(StripTag(Localize("All", "pc_nar_StoryBook1_16", "HpDialog")), 30.0);
				Out("subtitle test shown");
			}
		}
	}
	if (bMutateTest && RulePhase < 6)
	{
		TestRule();
	}
	if (!bCounted && Level.TimeSeconds > 6.0)
	{
		bCounted = true;
		CountThings();
	}
	if (bMutateTest && !bMutated && Level.TimeSeconds > 12.0)
	{
		bMutated = true;
		MutateOneCrate();
		MutateHero();
	}
	if (!bBenchTested && Level.TimeSeconds > 32.0)
	{
		bBenchTested = true;
		Out("BENCH 20 captures in one frame (no file) starts");
		EnhancedGame(Level.Game).BenchCapture(20);
		Out("BENCH ends; the next HITCH line is the frame time of the 20 captures");
	}
	if (!bIterTested && Level.TimeSeconds > 10.0)
	{
		bIterTested = true;
		TestIterators();
	}
	if ((int(Level.TimeSeconds) % 3) == 0)
	{
		CheckLevelLinker();
	}
	if (bPollCommands)
	{
		// exec runs the commands of one file; the next file name is tried every second.
		Res = ConsoleCommand("exec sdbg_cmd_" $ string(NextCmd) $ ".txt");
		if (Res != "")
		{
			Out("CMD " $ string(NextCmd) $ " -> " $ Res);
		}
	}
}

defaultproperties
{
	DumpInterval=5.0
	bPollCommands=False
	bRepairLinker=False
	CaptureAt=0.0
	bMutateTest=False
	bIterTested=True
	bBenchTested=True
	bCounted=True
	bHidden=True
	RemoteRole=ROLE_None
}

class EnhancedPlayBot extends Object;

// The play test (owner, 2026-11-21: "play the whole game yourself with a clone of yourself, the way players do, menus too"). A test game is started like
// a player's (Game.exe alone) with the environment variable SHREK2_BOT; its "play=1" part makes this bot drive the player's hero every frame through the
// same inputs a keyboard gives (forward, the view's direction, jump, attack):
// - the host walks the level's path network (Controller.FindPathToward) to the level's exit, the one that leads on in the story, and waits there for
//   the guests (the mod opens an exit only when everybody is near it);
// - a guest follows the host's hero;
// - both jump when they make no headway, hit an enemy in front of them, and wait while a cutscene, a menu or a fade has the controls.
// What the bot cannot do (a puzzle, a jump the path network does not know) shows as "[PLAY] stuck" in the log: after a while the host is put on the next
// node of his path, and a level that is not over in fifteen minutes is left through its exit by the host's hand. Both are the bot's limits, not the mod's,
// and are logged as such. Everything else that happens on the way is the game and the mod as players get them.

var bool bHost;
var Actor Goal;                  // host: the exit; guest: the host's hero
var Actor Node;                  // the next point of the path to Goal (or Goal itself)
var string GoalName;
var float Clock, GoalClock, NodeClock, LogClock, ProgClock, FireClock, LevelClock, JumpClock;
var Vector ProgPos;              // where the hero was when headway was last measured
var float StuckFor;              // seconds without headway while walking
var int Jumps, Teleports, Hits;
var bool bWaiting;               // the controls are not the player's (cutscene, menu, fade)
var string WaitWhy;
var bool bLeftByHand;

var int OutYaw;                  // what the controller applies this frame
var float OutForward;
var float OutHangX, OutHangY;    // while the hero hangs (a vine, a ledge): sideways (+ = towards the vine's next node) and up (+ climb, - let go)
var bool bOutJump, bOutFire, bOutTurn;

// the story's levels in order (the exit taken is the one that leads to the next of these)
var array<string> Story;

// The level's path network, read once per level (Controller.FindPathToward found no way for a player's hero, test b4: the bot walked straight at the
// exit into a wall): the points, and for each its neighbours (indices into Nodes, NbrFirst[i]..NbrFirst[i]+NbrCount[i]-1 in Nbr)
var array<NavigationPoint> Nodes;
var array<int> NbrFirst, NbrCount, Nbr;
var bool bNetRead;
var array<int> Route;            // indices into Nodes, from the hero to the goal
var int RouteAt;
var float RouteClock;
var Actor RouteFor;
// The host's way through a level: the level's own breadcrumbs (owner, 2026-11-22: "can you build its route yourself?"). The path network of these
// levels is a handful of cutscene marks (the swamp: 19 points), so the way is made of what the level puts along the player's way: the pickups
// (coins, health), the story's triggers (cutscenes, gates), the save points, and the exit last. They are chained from the start: every next one
// is the nearest that does not lead much farther from the exit. Coins are picked up on the way, as a player does.
var array<Actor> Crumbs;
var int CrumbAt;
var bool bCrumbsMade;
var Vector HeadLoc;              // the point the headway below is measured to
// the walkthrough of this level (EnhancedPlayRoutes)
var array<string> MySteps;
var int StepAt, StepTries;
var float StepClock, NoFoeFor;
var bool bStepsRead;
var string LastClassName;
var Class<Actor> LastClass;
var float HeadBest;              // the nearest the hero came to it
var int StepHops;                // the hero was put somewhere during this step (the bot's limit): a point counts as reached across the map's guessed heights
// the host's map of the walkable ground (EnhancedNav) and the way on it to the point the bot heads for
var EnhancedNav Nav;
var Pawn NavPawn;                // the hero the map was made for (a hero change makes it again)
var Vector NavFor;
var int NavState;                // 0 no way yet, 1 searching, 2 following, 3 none found
var int NavAt;
var float NavClock, NavLogClock, NavBest, NavSince, NavDJ, LastBake;
var string NavWhat;
var int NavBlocks;               // ways blocked since the map was made
// the height of the hero's jumps (the bot's jumps are logged with how high they went)
var float JumpZ0, JumpPeak, JumpWatch;
var bool bJumpDouble;
var bool bOutJumpLast;
var float HangFor, HangStill;      // seconds the hero hangs, and without moving along
var Vector HangLast;
var int SpecAt;                    // the special way being taken (EnhancedNav.SFrom index), -1 none
var float SpecClock;
var bool bSpecFlew;               // the special way's flight or hang has begun (its end is the landing)
var int ClimbFor, ClimbPhase, ClimbTries;
var float ClimbClock, ClimbTotal;
var int SpecPhase, SpecTries;
var float SpecPhaseClock;
// a climb the hero makes is learned (EnhancedPlayLearn): where he walked last before it, his yaw, and where it ended
var bool bClimbSeen;
var Vector ClimbFrom;
var int ClimbYaw;
var int JumpLogs;
var int Shots;
var int Pictures;                // maps of the cells around the hero written to the log on this level                   // the game's own screenshots taken by the bot on this level (System\ShotNNNN.bmp)
// a guest walks the host's own trail (where the host walked, a hero can walk)
var array<Vector> Trail;
var Vector TrailLast;
var float GuestHopClock;
var bool bStepSaw;
var bool bFromDone;
var bool bAtGate;
var float HostStill;             // guest: seconds the host's hero has not moved (he waits: come right up to him)
var Vector HostLast;
var float FaceClock, LastDelta;
var float AirFire;
var Pawn Foe, EngagedWith, Ignored;
var float EngageScan, EngageClock, IgnoredUntil;
var int EngageHits;               // a jump attack: the attack key this long after the jump
var int FaceLogs;
var int GapFor;                  // the way's cell whose gap jump is done (one jump per gap)
var bool bGapJumped;              // the test option from=N (SHREK2_BOT) was applied
var int StepNode, StepNodeFor, StepNodeSize;                // the map's cell a goto step heads for               // the step's actor was seen (a pickup that is gone afterwards was picked up)
var float NearOverride;          // how near DriveToLoc goes this frame (0 = its own default)
var float HeadSince;             // seconds without coming nearer by 50 units
var float NavMove;               // how far the goal may move before the way to it is searched again (the guest's goal, the host, walks)
var bool bGuestNav;              // guest: walks to the host on the map of the level (a vine, a ledge, a pad, a gap: what the trail cannot do)
var bool bLilyRead, bLilyHop;     // tests only (the guest's SHREK2_BOT lilyhop=1): the guest jumps from lily pad to lily pad (the T pose report)
var Actor LilyOn, LilyTo;
var float LilyClock, LilySince;
var int LilyHops;
var Vector GuestAnchor;          // guest: where his hero was when he last moved 150 units
var float GuestStuck;            // guest: seconds his hero has stayed within 150 units of GuestAnchor while far from the host
var float GuestBest, GuestSince; // guest: the nearest he came to the host, and the seconds since he came 150 nearer

function Init(bool bIsHost)
{
	bHost = bIsHost;
	SpecAt = -1;
	NavMove = 120.0;
	if (!bHost)
	{
		NavMove = 400.0;
	}
	GuestBest = 100000.0;
	Story[0] = "1_Shreks_Swamp";
	Story[1] = "2_Carriage_Hijack";
	Story[2] = "3_The_Hunt_Part1";
	Story[3] = "3_The_Hunt_Part2";
	Story[4] = "3_The_Hunt_Part3";
	Story[5] = "3_The_Hunt_Part4";
	Story[6] = "4_FGM_Office";
	Story[7] = "4_FGM_PIB";
	Story[8] = "5_FGM_Donkey";
	Story[9] = "6_Hamlet";
	Story[10] = "6_Hamlet_Mine";
	Story[11] = "6_Hamlet_End";
	Story[12] = "7_Prison_Donkey";
	Story[13] = "8_Prison_PIB";
	Story[14] = "9_Prison_Shrek";
	Story[15] = "10_Castle_Siege";
	Story[16] = "11_FGM_Battle";
}

// enhnative.log is written at once (Game.log through a buffer): the play test is followed there
native(3546) final function EnhLog(string S);

function string MapOf(Actor A)
{
	local string S;

	S = string(A.Level);
	return Left(S, InStr(S, "."));
}

function int StoryIndex(string M)
{
	local int i;

	for (i = 0; i < Story.Length; i++)
	{
		if (Story[i] ~= M)
		{
			return i;
		}
	}
	return -1;
}

function Say(PlayerController PC, string S)
{
	local string Who;

	Who = "guest";
	if (bHost)
	{
		Who = "host";
	}
	Log("[PLAY] t=" $ string(int(PC.Level.TimeSeconds)) $ " " $ Who $ ": " $ S);
	EnhLog("[PLAY] " $ MapOf(PC) $ " t=" $ string(int(PC.Level.TimeSeconds)) $ " " $ Who $ ": " $ S);
}

// host: the exit that leads on in the story; failing that, any exit that does not lead back
function Actor FindExit(PlayerController PC)
{
	local Trigger T;
	local string M, To, Here;
	local int Me, Best, k;
	local Actor Found;

	Here = MapOf(PC);
	Me = StoryIndex(Here);
	Best = 1000;
	foreach PC.AllActors(Class'Engine.Trigger', T)
	{
		if (!T.IsA('ChangeLevelTrigger'))
		{
			continue;
		}
		To = T.GetPropertyText("NewMapName");
		M = To;
		if (InStr(M, "?") >= 0)
		{
			M = Left(M, InStr(M, "?"));
		}
		if (InStr(M, ".") >= 0)
		{
			M = Left(M, InStr(M, "."));
		}
		k = StoryIndex(M);
		if (Me >= 0 && k > Me && k < Best)
		{
			Best = k;
			Found = T;
			GoalName = string(T.Name) $ " to " $ To;
		}
		else if (Found == None && (Me < 0 || k < 0 || k > Me))
		{
			Found = T;
			GoalName = string(T.Name) $ " to " $ To;
		}
	}
	return Found;
}

function Pawn HostHero(PlayerController PC)
{
	local Pawn Q;

	foreach PC.DynamicActors(Class'Pawn', Q)
	{
		if (Q != PC.Pawn && Q.IsA('ShHeroPawn') && !Q.bHidden && Q.PlayerReplicationInfo != None)
		{
			return Q;
		}
	}
	return None;
}

// whether the controls are the player's now (the controller tells its own reasons through Busy)
function bool Free(PlayerController PC, string Busy)
{
	local string W;

	// the controller tells why the controls are not the player's (a cutscene, a menu, a pause, no hero): reading the menu here, from an object that is
	// not an actor, ended the game in the script engine (test b2)
	W = Busy;
	if (W != "")
	{
		if (!bWaiting || W != WaitWhy)
		{
			Say(PC, "waits: " $ W);
		}
		bWaiting = true;
		WaitWhy = W;
		return false;
	}
	if (bWaiting)
	{
		Say(PC, "plays again (" $ WaitWhy $ " is over)");
		bWaiting = false;
		ProgPos = PC.Pawn.Location;
		ProgClock = 0.0;
		StuckFor = 0.0;
	}
	return true;
}

function Pawn EnemyInFront(PlayerController PC)
{
	local Pawn Q;
	local Vector D;

	foreach PC.Pawn.VisibleCollidingActors(Class'Pawn', Q, 260.0)
	{
		if (Q != PC.Pawn && Q.IsA('ShEnemy') && !Q.bHidden && float(Q.GetPropertyText("Health")) > 0.0)
		{
			D = Q.Location - PC.Pawn.Location;
			D.Z = 0;
			if (Normal(D) dot Vector(PC.Pawn.Rotation) > 0.3)
			{
				return Q;
			}
		}
	}
	return None;
}

// a point of the route counts as reached within 90 units across and 160 up or down
function bool Reached(Vector P, Vector L)
{
	local Vector D;

	D = P - L;
	if (Abs(D.Z) >= 160.0)
	{
		return false;
	}
	D.Z = 0;
	return VSize(D) < 90.0;
}

function int NodeIndex(NavigationPoint N)
{
	local int i;

	for (i = 0; i < Nodes.Length; i++)
	{
		if (Nodes[i] == N)
		{
			return i;
		}
	}
	return -1;
}

function ReadNet(PlayerController PC)
{
	local NavigationPoint N;
	local int i, k, j, Links;

	bNetRead = true;
	for (N = PC.Level.NavigationPointList; N != None && Nodes.Length < 1500; N = N.nextNavigationPoint)
	{
		Nodes[Nodes.Length] = N;
	}
	for (i = 0; i < Nodes.Length; i++)
	{
		NbrFirst[i] = Nbr.Length;
		NbrCount[i] = 0;
		for (k = 0; k < Nodes[i].PathList.Length; k++)
		{
			if (Nodes[i].PathList[k] == None || Nodes[i].PathList[k].End == None)
			{
				continue;
			}
			j = NodeIndex(Nodes[i].PathList[k].End);
			if (j >= 0)
			{
				Nbr[Nbr.Length] = j;
				NbrCount[i] = NbrCount[i] + 1;
				Links++;
			}
		}
	}
	Say(PC, "path network: " $ string(Nodes.Length) $ " points, " $ string(Links) $ " links");
}

function int NearestNode(Vector L)
{
	local int i, Best;
	local float D, BestD;

	Best = -1;
	BestD = 1000000.0;
	for (i = 0; i < Nodes.Length; i++)
	{
		D = VSize(Nodes[i].Location - L);
		if (D < BestD)
		{
			BestD = D;
			Best = i;
		}
	}
	return Best;
}

// a breadth-first search over the links, from the point nearest the hero to the point nearest the goal
function BuildRoute(PlayerController PC, Actor To)
{
	local array<int> Queue, From;
	local int S, E, i, q, n, k;

	Route.Length = 0;
	RouteAt = 0;
	RouteFor = To;
	S = NearestNode(PC.Pawn.Location);
	E = NearestNode(To.Location);
	if (S < 0 || E < 0)
	{
		return;
	}
	for (i = 0; i < Nodes.Length; i++)
	{
		From[i] = -2;
	}
	From[S] = -1;
	Queue[0] = S;
	for (q = 0; q < Queue.Length && From[E] == -2; q++)
	{
		n = Queue[q];
		for (k = NbrFirst[n]; k < NbrFirst[n] + NbrCount[n]; k++)
		{
			if (From[Nbr[k]] == -2)
			{
				From[Nbr[k]] = n;
				Queue[Queue.Length] = Nbr[k];
			}
		}
	}
	if (From[E] == -2)
	{
		Say(PC, "no way on the path network from " $ string(Nodes[S].Name) $ " to " $ string(Nodes[E].Name) $ " (" $ string(Queue.Length) $ " points reachable)");
		return;
	}
	for (n = E; n >= 0; n = From[n])
	{
		Route.Insert(0, 1);
		Route[0] = n;
	}
	Say(PC, "route of " $ string(Route.Length) $ " points to " $ string(To.Name));
}

function MakeCrumbs(PlayerController PC, Actor Exit)
{
	local Actor A;
	local array<Actor> Pool;
	local Vector Here;
	local float Cost, Best, Ahead, Now;
	local int i, k, Pick, Coins, Story, Saves;

	bCrumbsMade = true;
	Crumbs.Length = 0;
	CrumbAt = 0;
	foreach PC.DynamicActors(Class'Engine.Actor', A)
	{
		if (A.bHidden && !A.IsA('Trigger'))
		{
			continue;
		}
		if (A.IsA('SHPickup'))
		{
			Pool[Pool.Length] = A;
			Coins++;
		}
		else if (A.IsA('CutSceneTrigger'))
		{
			Pool[Pool.Length] = A;
			Story++;
		}
		else if (A.IsA('SHSavePoint'))
		{
			Pool[Pool.Length] = A;
			Saves++;
		}
	}
	Here = PC.Pawn.Location;
	for (k = 0; k < 400 && Pool.Length > 0; k++)
	{
		Now = VSize(Exit.Location - Here);
		Pick = -1;
		Best = 1000000.0;
		for (i = 0; i < Pool.Length; i++)
		{
			if (Pool[i] == None)
			{
				continue;
			}
			// a step back from the exit costs twice its length; points far behind are not taken at all
			Ahead = VSize(Exit.Location - Pool[i].Location) - Now;
			if (Ahead > 2500.0)
			{
				continue;
			}
			Cost = VSize(Pool[i].Location - Here) + 2.0 * FMax(0.0, Ahead);
			if (Cost < Best)
			{
				Best = Cost;
				Pick = i;
			}
		}
		if (Pick < 0)
		{
			break;
		}
		Crumbs[Crumbs.Length] = Pool[Pick];
		Here = Pool[Pick].Location;
		Pool.Remove(Pick, 1);
	}
	Crumbs[Crumbs.Length] = Exit;
	Say(PC, "way made of the level's breadcrumbs: " $ string(Crumbs.Length) $ " points (pickups " $ string(Coins) $ ", story triggers " $ string(Story)
		$ ", save points " $ string(Saves) $ ", left out " $ string(Pool.Length) $ ")");
}

// One frame of the bot. Busy: the controller's own reason why the controls are not the player's ("" = they are).
function Drive(PlayerController PC, float DeltaTime, string Busy)
{
	local Actor N;

	LastDelta = DeltaTime;
	bOutJumpLast = bOutJump;
	bOutJump = false;
	bOutFire = false;
	OutForward = 0.0;
	OutHangX = 0.0;
	OutHangY = 0.0;
	bOutTurn = false;
	Clock += DeltaTime;
	if (!Free(PC, Busy))
	{
		return;
	}
	LevelClock += DeltaTime;

	// the goal
	GoalClock -= DeltaTime;
	if (Goal == None || Goal.bDeleteMe || GoalClock <= 0.0)
	{
		GoalClock = 3.0;
		if (bHost)
		{
			N = FindExit(PC);
		}
		else
		{
			N = HostHero(PC);
			GoalName = "the host's hero";
		}
		if (N != Goal)
		{
			Goal = N;
			if (Goal == None)
			{
				Say(PC, "no goal on this level (no exit found)");
			}
			else
			{
				Say(PC, "goal: " $ GoalName $ " at " $ string(Goal.Location));
			}
		}
	}
	if (Goal == None)
	{
		return;
	}

	WatchJump(PC, DeltaTime);
	if (bHost && PC.Pawn != None)
	{
		WatchClimb(PC);
	}
	if (bHost && LevelBudget(PC))
	{
		return;
	}
	if (bHost && AtGate(PC, DeltaTime))
	{
		return;
	}
	// enemies near come first, as a player fights them before he walks on (h4: Donkey and his partner died three times to the Hunt's peasants)
	if (Engage(PC, DeltaTime))
	{
		return;
	}
	if (bHost && !MakeMap(PC, DeltaTime))
	{
		return;
	}
	if (!bHost)
	{
		MakeMap(PC, DeltaTime);
	}
	if (bHost && RunSteps(PC, DeltaTime))
	{
		return;
	}
	if (bHost)
	{
		if (!bCrumbsMade || (Crumbs.Length > 0 && Crumbs[Crumbs.Length - 1] != Goal))
		{
			MakeCrumbs(PC, Goal);
		}
		// a crumb that is gone (a coin picked up) or reached is passed
		while (CrumbAt < Crumbs.Length - 1 && (Crumbs[CrumbAt] == None || Crumbs[CrumbAt].bDeleteMe || (Crumbs[CrumbAt].bHidden && !Crumbs[CrumbAt].IsA('Trigger'))
			|| Reached(Crumbs[CrumbAt].Location, PC.Pawn.Location)))
		{
			CrumbAt++;
		}
		Node = Crumbs[CrumbAt];
		DriveTo(PC, DeltaTime, Node);
		return;
	}
	// a guest walks straight to the host's hero (the mod's leash brings him back when he is far behind); the path network is not used (it rebuilt
	// its route every frame for a guest, play run p12)
	FollowTrail(PC, DeltaTime, Pawn(Goal));
}

// guest: the points where the host's hero has been, every 64 units; he walks them in order and stops near the host. A jump of the host's hero (a
// cutscene puts him elsewhere, or a HOP) starts the trail again from there.
function FollowTrail(PlayerController PC, float DeltaTime, Pawn Host)
{
	local Vector L, D;
	local float Gap;

	if (!bLilyRead)
	{
		bLilyRead = true;
		bLilyHop = EnhancedPlayerController(PC) != None && InStr(EnhancedPlayerController(PC).EnhBotEnv(0), "lilyhop=1") >= 0;
	}
	if (bLilyHop && LilyHop(PC, DeltaTime))
	{
		return;
	}
	if (Host == None)
	{
		return;
	}
	L = Host.Location;
	Gap = VSize(L - TrailLast);
	if (Gap > 64.0)
	{
		if (Gap > 700.0)
		{
			Trail.Length = 0;
		}
		if (Trail.Length < 600)
		{
			Trail[Trail.Length] = L;
		}
		TrailLast = L;
	}
	// points behind are dropped: reached, or the next one is nearer
	while (Trail.Length > 0)
	{
		D = Trail[0] - PC.Pawn.Location;
		if (Abs(D.Z) < 90.0)
		{
			D.Z = 0;
			if (VSize(D) < 50.0)
			{
				Trail.Remove(0, 1);
				continue;
			}
		}
		if (Trail.Length > 1 && VSize(Trail[1] - PC.Pawn.Location) < VSize(Trail[0] - PC.Pawn.Location))
		{
			Trail.Remove(0, 1);
			continue;
		}
		break;
	}
	Node = Host;
	// progress: the guest's hero moving at all (GuestStuck), and coming nearer to the host (GuestSince)
	Gap = VSize(L - PC.Pawn.Location);
	if (VSize(PC.Pawn.Location - GuestAnchor) > 150.0)
	{
		GuestAnchor = PC.Pawn.Location;
		GuestStuck = 0.0;
	}
	else if (Gap > 400.0)
	{
		GuestStuck += DeltaTime;
	}
	else
	{
		GuestStuck = 0.0;
	}
	if (Gap < GuestBest - 150.0 || Gap < 400.0)
	{
		GuestBest = Gap;
		GuestSince = 0.0;
	}
	else if (Gap > 900.0)
	{
		// only far behind: a guest who walks after the host a few hundred units back is following, not lost
		GuestSince += DeltaTime;
	}
	// stuck behind for long (a way the guest's bot cannot do, a sewer): the server puts him near the host (play test only). Only for a hero that
	// stays put 25 s, or comes no nearer in 120 s: a guest on his own way to the host (the map of the level, a vine, a pad) is not put anywhere.
	// Checked first: a host who is down waits still, and the guest must come to help him up (t1 tour: the host lay 400 s, the guest's bot was
	// stuck 1800 units away and this check came after the "he waits" branch's return)
	GuestHopClock -= DeltaTime;
	if ((GuestStuck > 25.0 || GuestSince > 120.0) && GuestHopClock <= 0.0 && Gap > 400.0 && EnhancedPlayerController(PC) != None)
	{
		GuestHopClock = 20.0;
		Teleports++;
		Trail.Length = 0;
		Say(PC, "HOP (bot limit): " $ string(int(GuestStuck)) $ " s in place, " $ string(int(GuestSince)) $ " s no nearer, at " $ string(PC.Pawn.Location)
			$ ", " $ string(int(Gap)) $ " from the host: asks the server to be put near him. " $ Where(PC));
		TakeShot(PC, "guest");
		StuckFor = 0.0;
		HeadSince = 0.0;
		GuestStuck = 0.0;
		GuestSince = 0.0;
		GuestBest = 100000.0;
		bGuestNav = false;
		NavState = 0;
		EnhancedPlayerController(PC).ServerBotHop(L);
		return;
	}
	if (GuestNav(PC, DeltaTime, L))
	{
		return;
	}
	if (VSize(L - HostLast) > 10.0)
	{
		HostLast = L;
		HostStill = 0.0;
	}
	else
	{
		HostStill += DeltaTime;
	}
	// a host who stands still waits (at a cutscene's gate the mod holds him on its trigger until his partner passes it): right up to him
	if (HostStill > 3.0 && VSize(L - PC.Pawn.Location) > 30.0)
	{
		NearOverride = 15.0;
		DirectTo(PC, DeltaTime, L, "the host's hero (he waits)");
		NearOverride = 0.0;
		return;
	}
	if (VSize(L - PC.Pawn.Location) < 260.0 || Trail.Length == 0)
	{
		// near the host: stand (a few steps behind him)
		if (VSize(L - PC.Pawn.Location) >= 260.0)
		{
			DirectTo(PC, DeltaTime, L, "the host's hero");
		}
		return;
	}
	if (Trail[0].Z > PC.Pawn.Location.Z + 30.0 && int(PC.Pawn.Physics) == 1 && JumpClock <= 0.0)
	{
		D = Trail[0] - PC.Pawn.Location;
		D.Z = 0;
		if (VSize(D) < 110.0)
		{
			bOutJump = true;
			JumpClock = 0.8;
		}
	}
	NearOverride = 20.0;
	DirectTo(PC, DeltaTime, Trail[0], "the host's trail (" $ string(Trail.Length) $ " points)");
	NearOverride = 0.0;
}

// Tests only (lilyhop=1): from lily pad to lily pad near the hero, a running jump onto each (a double jump for a far one), 1.5 s on it, the next.
// The lead's friend's hero stood in a T pose after the swamp's lily pads (2026-11-21); the animation watch (EnhancedPlayerController.AnimWatch)
// logs it on both machines if the hero's movement animation is left off.
function bool LilyHop(PlayerController PC, float DeltaTime)
{
	local Actor A, Best;
	local Vector D, L;
	local float Dist, BestD;

	L = PC.Pawn.Location;
	LilyClock += DeltaTime;
	if (LilyTo == None)
	{
		if (LilyClock < 1.5)
		{
			return true;
		}
		BestD = 100000.0;
		foreach PC.AllActors(Class'Engine.Actor', A)
		{
			if ((A.IsA('AmbientLily') || A.IsA('BounceLili')) && A != LilyOn)
			{
				D = A.Location - L;
				Dist = VSize(D);
				if (Dist > 120.0 && Dist < 900.0 && Dist < BestD)
				{
					BestD = Dist;
					Best = A;
				}
			}
		}
		if (Best == None)
		{
			return false;
		}
		LilyTo = Best;
		LilyClock = 0.0;
		LilySince = 0.0;
		Say(PC, "LILY test: on to " $ string(LilyTo.Name) $ " " $ string(int(BestD)) $ " away");
	}
	D = LilyTo.Location - L;
	D.Z = 0.0;
	Dist = VSize(D);
	if (int(PC.Pawn.Physics) == 1 && Dist < LilyTo.CollisionRadius && L.Z > LilyTo.Location.Z)
	{
		LilyHops++;
		Say(PC, "LILY test: on " $ string(LilyTo.Name) $ " (hop " $ string(LilyHops) $ "), state " $ string(PC.Pawn.GetStateName()) $ ", anim "
			$ PC.Pawn.GetPropertyText("AnimSequence") $ ", physics anim " $ string(PC.Pawn.bPhysicsAnimUpdate));
		LilyOn = LilyTo;
		LilyTo = None;
		LilyClock = 0.0;
		return true;
	}
	LilySince += DeltaTime;
	if (LilySince > 12.0)
	{
		Say(PC, "LILY test: " $ string(LilyTo.Name) $ " not reached in 12 s at " $ string(L) $ ", another one");
		LilyOn = LilyTo;
		LilyTo = None;
		LilyClock = 0.0;
		return true;
	}
	OutYaw = rotator(D).Yaw;
	bOutTurn = true;
	OutForward = 1.0;
	JumpClock -= DeltaTime;
	if (int(PC.Pawn.Physics) == 1 && Dist < LilyTo.CollisionRadius + 140.0 && JumpClock <= 0.0)
	{
		bOutJump = true;
		JumpClock = 1.0;
		Jumps++;
		if (Dist > LilyTo.CollisionRadius + 40.0)
		{
			NavDJ = 0.2;
		}
	}
	if (NavDJ > 0.0)
	{
		NavDJ -= DeltaTime;
		if (NavDJ <= 0.0)
		{
			bOutJump = true;
		}
	}
	return true;
}

// guest: far behind the host, or the host is above or below him (a ledge, a vine, a pad), or the trail has no headway: he walks to the host on
// his own map of the level, as the host's bot walks to its steps; near the host again (level with him) he follows the trail. false = the trail.
function bool GuestNav(PlayerController PC, float DeltaTime, Vector L)
{
	local float Dist, DZ;

	if (Nav == None || !Nav.bBaked)
	{
		return false;
	}
	Dist = VSize(L - PC.Pawn.Location);
	DZ = Abs(L.Z - PC.Pawn.Location.Z);
	if (!bGuestNav)
	{
		if (Dist > 700.0 || (Dist > 300.0 && (DZ > 120.0 || StuckFor > 4.0)) || IsHanging(PC))
		{
			bGuestNav = true;
			NavState = 0;
			Say(PC, "to the host on the map: " $ string(int(Dist)) $ " away, " $ string(int(DZ)) $ " above/below, trail headway " $ string(int(StuckFor)) $ " s");
		}
		else
		{
			return false;
		}
	}
	else if (Dist < 260.0 && DZ < 80.0 && int(PC.Pawn.Physics) == 1)
	{
		bGuestNav = false;
		NavState = 0;
		SpecAt = -1;
		Trail.Length = 0;
		Say(PC, "with the host again at " $ string(PC.Pawn.Location) $ ": the trail from here");
		return false;
	}
	return NavDrive(PC, DeltaTime, L, "the host's hero");
}

// the way's cells in the log: x y floor and how each is reached (w walk, j jump, J double jump, d drop, c climb, g gap jump, ~ water cell,
// S a special way), at most 40 cells
function LogWay(PlayerController PC)
{
	local string Line, KS;
	local int i, k, sp;

	Line = "";
	for (i = 0; i < Nav.Path.Length && i < 40; i++)
	{
		KS = "";
		if (i > 0)
		{
			k = Nav.KindOf(Nav.Path[i - 1], Nav.Path[i]);
			sp = Nav.SpecialOf(Nav.Path[i - 1], Nav.Path[i]);
			if (sp >= 0 && k < 0)
			{
				KS = "S" $ string(Nav.SKind[sp]);
			}
			else
			{
				KS = Mid("wjJdc???g", Clamp(k, 0, 8), 1);
			}
		}
		if (Nav.NWater[Nav.Path[i]] != 0)
		{
			KS = KS $ "~";
		}
		Line = Line $ " " $ KS $ string(int(Nav.NX[Nav.Path[i]])) $ "," $ string(int(Nav.NY[Nav.Path[i]])) $ "," $ string(int(Nav.NZ[Nav.Path[i]]));
	}
	EnhLog("[WAY]" $ Line);
}

// the cells around the hero as text in the log (EnhancedNav.Picture), a few per level
function Picture(PlayerController PC, Vector Goal)
{
	local array<string> Rows;
	local int i;

	if (Nav == None || !Nav.bBaked || Pictures >= 6)
	{
		return;
	}
	Pictures++;
	Rows.Length = 0;
	Nav.Picture(PC.Pawn.Location, Goal, 20, Rows);
	Say(PC, "MAP around " $ string(PC.Pawn.Location) $ " (cell " $ string(int(Nav.Cell)) $ ", +Y up, +X right; ~ water, letters = height per 20 units, n = the hero's floor, H hero, T goal):");
	for (i = 0; i < Rows.Length; i++)
	{
		EnhLog("[MAP] |" $ Rows[i] $ "|");
	}
}

// the hero faces Yaw (within 20 degrees): true; else a short step that way turns him (he turns the way he walks; nav19 punched the air beside a
// crate for minutes)
function bool Face(PlayerController PC, int Yaw)
{
	local Rotator R;

	OutYaw = Yaw;
	bOutTurn = true;
	if (Abs(float(((PC.Pawn.Rotation.Yaw - Yaw) & 65535) - 32768)) < 29100.0)
	{
		FaceClock += LastDelta;
		OutForward = 0.6;
		if (FaceClock > 0.6)
		{
			// a step did not turn him (pressed against the thing, nav20): turned by hand, as a tap of the key would
			R = PC.Pawn.Rotation;
			R.Yaw = Yaw;
			PC.Pawn.SetRotation(R);
			if (FaceLogs < 5)
			{
				FaceLogs++;
				Say(PC, "the hero is turned to yaw " $ string(Yaw & 65535) $ " by hand (a step did not turn him)");
			}
			FaceClock = 0.0;
			return true;
		}
		return false;
	}
	FaceClock = 0.0;
	return true;
}

// what the hero stands on and does (for the log when he is stuck)
function string Where(PlayerController PC)
{
	local string B;

	B = "nothing";
	if (PC.Pawn.Base != None)
	{
		B = string(PC.Pawn.Base.Name) $ " (" $ string(PC.Pawn.Base.Class.Name) $ ")";
	}
	return "Stands on " $ B $ ", physics " $ string(int(PC.Pawn.Physics)) $ ", state " $ string(PC.Pawn.GetStateName()) $ ", velocity " $ string(PC.Pawn.Velocity);
}

// the game's own screenshot of this window (a few per level), named in the log
function TakeShot(PlayerController PC, string Why)
{
	if (Shots >= 8)
	{
		return;
	}
	Shots++;
	Say(PC, "SHOT " $ string(Shots) $ " (" $ Why $ ") at " $ string(PC.Pawn.Location));
	PC.ConsoleCommand("shot");
}

// how high the bot's jumps go (the previous frame's jump key, then 1.2 s of the hero's height)
function WatchJump(PlayerController PC, float DeltaTime)
{
	if (bOutJumpLast && JumpWatch <= 0.0)
	{
		JumpWatch = 1.2;
		JumpZ0 = PC.Pawn.Location.Z;
		JumpPeak = JumpZ0;
		bJumpDouble = false;
	}
	bOutJumpLast = false;
	if (JumpWatch > 0.0)
	{
		JumpWatch -= DeltaTime;
		JumpPeak = FMax(JumpPeak, PC.Pawn.Location.Z);
		if (PC.Pawn.GetPropertyText("bDoingDoubleJump") ~= "True")
		{
			bJumpDouble = true;
		}
		if (JumpWatch <= 0.0 && JumpLogs < 40)
		{
			JumpLogs++;
			Say(PC, "jump at " $ string(PC.Pawn.Location) $ ": rose " $ string(int(JumpPeak - JumpZ0)) $ " units, double jump " $ string(bJumpDouble));
		}
	}
}

// host: the mod holds him at a cutscene's gate until his partner passes its trigger too (GateNoteHost; n5: the bot took the hold for walls and
// blocked its own ways). He stands on the trigger, so the partner who comes to him passes it (h1: the guest's bot stopped short, the gate waited
// its full 90 s every time).
function bool AtGate(PlayerController PC, float DeltaTime)
{
	local EnhancedGame G;
	local Vector D;

	G = EnhancedGame(PC.Level.Game);
	if (G == None || G.GateNoteHost == "")
	{
		if (bAtGate)
		{
			bAtGate = false;
			Say(PC, "the gate is open");
		}
		return false;
	}
	if (!bAtGate)
	{
		bAtGate = true;
		Say(PC, "waits at a gate for the partner, on its trigger at " $ string(G.GateWaitAt));
	}
	D = G.GateWaitAt - PC.Pawn.Location;
	D.Z = 0;
	if (VSize(D) > 20.0)
	{
		OutYaw = rotator(D).Yaw;
		bOutTurn = true;
		OutForward = FMin(1.0, VSize(D) / 100.0 + 0.15);
	}
	return true;
}

// the nearest live enemy within 380 units: walk up to it, face it, hit it (every fourth blow from a jump). One enemy is given 25 s, then left
// alone for 20 s (one the hero cannot reach).
function bool Engage(PlayerController PC, float DeltaTime)
{
	local Pawn E;
	local float D, BestD;
	local Vector V;

	EngageScan -= DeltaTime;
	if (EngageScan <= 0.0)
	{
		EngageScan = 0.3;
		Foe = None;
		BestD = 380.0;
		foreach PC.Pawn.VisibleCollidingActors(Class'Pawn', E, 380.0)
		{
			if (E == PC.Pawn || !E.IsA('ShEnemy') || E.bHidden || E.bDeleteMe || float(E.GetPropertyText("Health")) <= 0.0)
			{
				continue;
			}
			if (E == Ignored && PC.Level.TimeSeconds < IgnoredUntil)
			{
				continue;
			}
			D = VSize(E.Location - PC.Pawn.Location);
			if (D < BestD)
			{
				BestD = D;
				Foe = E;
			}
		}
	}
	if (Foe == None || Foe.bDeleteMe || Foe.bHidden || float(Foe.GetPropertyText("Health")) <= 0.0)
	{
		if (EngagedWith != None)
		{
			Say(PC, "fight with " $ string(EngagedWith.Name) $ " over after " $ string(int(EngageClock)) $ " s");
			EngagedWith = None;
		}
		return false;
	}
	if (Foe != EngagedWith)
	{
		EngagedWith = Foe;
		EngageClock = 0.0;
		EngageHits = 0;
		Say(PC, "fights " $ string(Foe.Name) $ " (" $ string(Foe.Class.Name) $ ") " $ string(int(VSize(Foe.Location - PC.Pawn.Location))) $ " away");
	}
	EngageClock += DeltaTime;
	if (EngageClock > 25.0)
	{
		Say(PC, "leaves " $ string(Foe.Name) $ " alone for 20 s (not beaten in 25 s, " $ string(EngageHits) $ " blows)");
		Ignored = Foe;
		IgnoredUntil = PC.Level.TimeSeconds + 20.0;
		Foe = None;
		EngagedWith = None;
		return false;
	}
	V = Foe.Location - PC.Pawn.Location;
	V.Z = 0;
	if (AirFire > 0.0)
	{
		AirFire -= DeltaTime;
		if (AirFire <= 0.0)
		{
			bOutFire = true;
		}
	}
	if (VSize(V) > 95.0)
	{
		OutYaw = rotator(V).Yaw;
		bOutTurn = true;
		OutForward = 1.0;
		return true;
	}
	if (Face(PC, rotator(V).Yaw))
	{
		FireClock -= DeltaTime;
		if (FireClock <= 0.0)
		{
			FireClock = 0.4;
			EngageHits++;
			Hits++;
			if (EngageHits % 4 == 0 && int(PC.Pawn.Physics) == 1)
			{
				bOutJump = true;
				AirFire = 0.3;
				FireClock = 1.1;
			}
			else
			{
				bOutFire = true;
			}
		}
	}
	return true;
}

// host: a level that is not over in its time (SHREK2_BOT budget=<s>, 900 by default) is left through its exit by the bot's hand, as the
// level's own end would (the exit's Trigger, what a cutscene's "Trigger EndLevel" does). Logged as the bot's limit; the co-op travel after it
// is the game's and the mod's own.
function bool LevelBudget(PlayerController PC)
{
	local string Env;
	local int i;
	local float Budget;

	if (bLeftByHand || Goal == None)
	{
		return bLeftByHand;
	}
	Budget = 900.0;
	if (EnhancedGame(PC.Level.Game) != None)
	{
		Env = EnhancedGame(PC.Level.Game).EnhBotEnv(0);
		i = InStr(Env, "budget=");
		if (i >= 0)
		{
			Budget = float(Mid(Env, i + 7));
		}
	}
	if (Budget <= 0.0 || LevelClock < Budget)
	{
		return false;
	}
	bLeftByHand = true;
	Say(PC, "LEVEL BUDGET (bot limit): not over in " $ string(int(Budget)) $ " s, at step " $ string(StepAt + 1) $ "/" $ string(MySteps.Length) $ ", hops "
		$ string(Teleports) $ ": the host leaves through " $ GoalName);
	Goal.Trigger(PC.Pawn, PC.Pawn);
	return true;
}

// host: the map of the walkable ground, made once per level and hero (false while it is being made: the hero stands)
function bool MakeMap(PlayerController PC, float DeltaTime)
{
	if (Nav == None || NavPawn != PC.Pawn)
	{
		if (Nav == None)
		{
			Nav = new Class'Enhanced.EnhancedNav';
		}
		NavPawn = PC.Pawn;
		Nav.StartBake(PC);
		LastBake = LevelClock;
		NavState = 0;
		NavBlocks = 0;
		NavLogClock = 0.0;
		Say(PC, "map of the walkable ground: made from " $ string(PC.Pawn.Location) $ " for " $ string(PC.Pawn.Class.Name) $ " (radius " $ string(int(Nav.R))
			$ ", height " $ string(int(Nav.H)) $ ")");
	}
	if (!Nav.bBaking)
	{
		return true;
	}
	if (Nav.BakeStep(PC, DeltaTime, 15000))
	{
		Say(PC, "map of the walkable ground: " $ string(Nav.NX.Length) $ " cells, " $ string(Nav.ETo.Length) $ " ways, " $ string(Nav.Traces) $ " traces, "
			$ string(int(Nav.BakeTime * 10.0) / 10.0) $ " s");
		return true;
	}
	NavLogClock -= DeltaTime;
	if (NavLogClock <= 0.0)
	{
		NavLogClock = 5.0;
		Say(PC, "map of the walkable ground: " $ string(Nav.Expanded) $ "/" $ string(Nav.NX.Length) $ " cells so far");
	}
	return false;
}

// the hero hangs (KWPawn state MountHanging: a vine, or a ledge he ran into): sideways keys move him along a vine, forward climbs a ledge up, back
// lets go (ShPlayerInput: ShimmyControlRight = aStrafe, ShimmyControlUp = aBaseY). On a vine the bot goes towards its next node and lets go
// when he stops moving at its end; on a ledge it climbs up.
function bool Hanging(PlayerController PC, float DeltaTime)
{
	if (!IsHanging(PC))
	{
		if (HangFor > 0.0)
		{
			Say(PC, "hanging over after " $ string(int(HangFor * 10.0) / 10.0) $ " s at " $ string(PC.Pawn.Location) $ ". " $ Where(PC));
			// a vine or a ledge is done: a new way from where the hero is now
			SpecAt = -1;
			NavState = 0;
		}
		HangFor = 0.0;
		return false;
	}
	if (HangFor == 0.0)
	{
		Say(PC, "hangs at " $ string(PC.Pawn.Location) $ " on " $ PC.Pawn.GetPropertyText("MountBase"));
		HangLast = PC.Pawn.Location;
		HangStill = 0.0;
	}
	HangFor += DeltaTime;
	if (VSize(PC.Pawn.Location - HangLast) > 8.0)
	{
		HangLast = PC.Pawn.Location;
		HangStill = 0.0;
	}
	else
	{
		HangStill += DeltaTime;
	}
	if (SpecAt >= 0 && SpecAt < Nav.SKind.Length && Nav.SKind[SpecAt] == 6)
	{
		// a vine: along it, and down at its end
		OutHangX = 1.0;
		if (HangStill > 2.0 && HangFor > 3.0)
		{
			OutHangX = 0.0;
			OutHangY = -1.0;
		}
	}
	else
	{
		// a ledge: up
		OutHangY = 1.0;
		if (HangFor > 8.0)
		{
			OutHangY = -1.0;
		}
	}
	return true;
}

// a learned climb (EnhancedPlayLearn): to the place it began, facing the way it faced, forward into the ledge (a jump after a moment); the game
// takes the hero up. Three failed tries block it.
function bool LearnedClimb(PlayerController PC, float DeltaTime, int k)
{
	local Vector D;
	local float Dist;

	NavSince = 0.0;
	if (PC.Pawn.IsInState('Mounting') || PC.Pawn.IsInState('MountFinish') || IsHanging(PC))
	{
		bSpecFlew = true;
		return true;
	}
	if (bSpecFlew)
	{
		Say(PC, "learned climb done, the hero is at " $ string(PC.Pawn.Location));
		SpecAt = -1;
		NavState = 0;
		return true;
	}
	D = Nav.SPos[k] - PC.Pawn.Location;
	D.Z = 0;
	Dist = VSize(D);
	if (SpecPhase == 0)
	{
		if (Dist > 12.0)
		{
			OutYaw = rotator(D).Yaw;
			bOutTurn = true;
			OutForward = FMin(1.0, Dist / 80.0 + 0.12);
			SpecPhaseClock += DeltaTime;
			if (SpecPhaseClock < 8.0)
			{
				return true;
			}
		}
		SpecPhase = 1;
		SpecPhaseClock = 0.0;
	}
	SpecPhaseClock += DeltaTime;
	OutYaw = Nav.SYaw[k];
	bOutTurn = true;
	OutForward = 1.0;
	if (SpecPhaseClock > 1.2 && SpecPhaseClock - DeltaTime <= 1.2 && int(PC.Pawn.Physics) == 1)
	{
		bOutJump = true;
		Jumps++;
	}
	if (SpecPhaseClock > 3.0)
	{
		SpecTries++;
		Say(PC, "learned climb try " $ string(SpecTries) $ " from " $ string(Nav.SPos[k]) $ " yaw " $ string(Nav.SYaw[k]) $ " did not take the hero up. " $ Where(PC));
		SpecPhase = 0;
		SpecPhaseClock = 0.0;
		if (SpecTries >= 3)
		{
			Nav.Block(Nav.Path[NavAt - 1], Nav.Path[NavAt]);
			NavBlocks++;
			TakeShot(PC, "learned climb");
			NavState = 0;
		}
	}
	return true;
}

// a climb the hero makes is remembered for the next runs (a climb up more than 100 units, ended on his feet)
function WatchClimb(PlayerController PC)
{
	local EnhancedPlayLearn LP;
	local string Line, M;
	local int i;
	local Vector S, E;
	local int Yaw;

	if (PC.Pawn.IsInState('Mounting') || PC.Pawn.IsInState('MountFinish') || IsHanging(PC))
	{
		bClimbSeen = true;
		return;
	}
	if (!bClimbSeen)
	{
		if (int(PC.Pawn.Physics) == 1)
		{
			ClimbFrom = PC.Pawn.Location;
			ClimbYaw = PC.Pawn.Rotation.Yaw & 65535;
		}
		return;
	}
	bClimbSeen = false;
	if (PC.Pawn.Location.Z - ClimbFrom.Z < 100.0 || int(PC.Pawn.Physics) != 1 || Nav == None)
	{
		return;
	}
	// known already?
	for (i = 0; Nav.Learned(i, S, Yaw, E); i++)
	{
		if (VSize(S - ClimbFrom) < 60.0)
		{
			return;
		}
	}
	M = MapOf(PC);
	Line = M $ ": " $ string(int(ClimbFrom.X)) $ " " $ string(int(ClimbFrom.Y)) $ " " $ string(int(ClimbFrom.Z)) $ " " $ string(ClimbYaw) $ " "
		$ string(int(PC.Pawn.Location.X)) $ " " $ string(int(PC.Pawn.Location.Y)) $ " " $ string(int(PC.Pawn.Location.Z));
	LP = new Class'Enhanced.EnhancedPlayLearn';
	LP.Climbs[LP.Climbs.Length] = Line;
	LP.SaveConfig();
	Class'Enhanced.EnhancedPlayLearn'.default.Climbs[Class'Enhanced.EnhancedPlayLearn'.default.Climbs.Length] = Line;
	Say(PC, "LEARNED a climb: " $ Line);
}

// a ledge to climb (the game's Mount): a run at it and a jump from about 100 units away, a second jump in the air; the game takes the hero up
// (Mounting, MountFinish) or he hangs and climbs (Hanging). A try that fails backs off for a new run-up; after four the way is blocked.
// (nav6: jumps from right at the stump's foot never mounted)
function bool Climb(PlayerController PC, float DeltaTime, Vector P, float Dist)
{
	local Vector D;

	if (Nav.Path[NavAt] != ClimbFor)
	{
		ClimbFor = Nav.Path[NavAt];
		ClimbPhase = 0;
		ClimbTries = 0;
		ClimbClock = 0.0;
		ClimbTotal = 0.0;
	}
	ClimbTotal += DeltaTime;
	if (ClimbTotal > 16.0)
	{
		ClimbTries = 4;
	}
	NavSince = 0.0;
	if (PC.Pawn.IsInState('Mounting') || PC.Pawn.IsInState('MountFinish'))
	{
		return true;
	}
	ClimbClock += DeltaTime;
	D = P - PC.Pawn.Location;
	D.Z = 0;
	OutYaw = rotator(D).Yaw;
	bOutTurn = true;
	OutForward = 1.0;
	if (ClimbPhase == 0)
	{
		if (Dist < 125.0 && Dist > 50.0 && VSize(PC.Pawn.Velocity * vect(1, 1, 0)) > 120.0 && int(PC.Pawn.Physics) == 1)
		{
			bOutJump = true;
			NavDJ = 0.22;
			ClimbPhase = 1;
			ClimbClock = 0.0;
			Jumps++;
		}
		else if (Dist <= 70.0 || ClimbClock > 4.0)
		{
			// too near for a run: back off first
			ClimbPhase = 2;
			ClimbClock = 0.0;
		}
	}
	else if (ClimbPhase == 1)
	{
		if (ClimbClock > 2.0)
		{
			ClimbTries++;
			Say(PC, "climb try " $ string(ClimbTries) $ " at " $ string(PC.Pawn.Location) $ " towards " $ string(P) $ " did not take the hero up. " $ Where(PC));
			ClimbPhase = 2;
			ClimbClock = 0.0;
		}
	}
	else
	{
		OutYaw = rotator(-D).Yaw;
		if (ClimbClock > 0.8)
		{
			ClimbPhase = 0;
			ClimbClock = 0.0;
		}
	}
	if (NavDJ > 0.0)
	{
		NavDJ -= DeltaTime;
		if (NavDJ <= 0.0)
		{
			bOutJump = true;
		}
	}
	if (ClimbTries >= 2 || ClimbTotal > 16.0)
	{
		Nav.Block(Nav.Path[NavAt - 1], Nav.Path[NavAt]);
		NavBlocks++;
		Say(PC, "the climb to " $ string(P) $ " failed four times: that way is blocked");
		TakeShot(PC, "climb");
		NavState = 0;
		ClimbFor = -1;
	}
	return true;
}

// a special way (EnhancedNav: a lily pad, a bounce pad, a vine) from the cell the hero is at to the cell P; true when it drives this frame
function bool Special(PlayerController PC, float DeltaTime, int k, Vector P)
{
	local Actor Via;
	local byte Kind;
	local Vector D, L;
	local float Dist, Rise, Edge;

	if (k < 0)
	{
		SpecAt = -1;
		return false;
	}
	if (k != SpecAt)
	{
		SpecAt = k;
		SpecClock = 0.0;
		bSpecFlew = false;
		SpecPhase = 0;
		SpecTries = 0;
		SpecPhaseClock = 0.0;
		Say(PC, "special way (kind " $ string(Nav.SKind[k]) $ ", " $ string(Nav.SVia[k].Name) $ ") to " $ string(P));
	}
	SpecClock += DeltaTime;
	Kind = Nav.SKind[k];
	Via = Nav.SVia[k];
	L = PC.Pawn.Location;
	if (Kind == 7)
	{
		return LearnedClimb(PC, DeltaTime, k);
	}
	if (Via == None)
	{
		return false;
	}
	if (Kind == 1)
	{
		// onto a lily pad: run at it and jump from near its rim (a double jump for a long one)
		D = Via.Location - L;
		D.Z = 0;
		Dist = VSize(D);
		OutYaw = rotator(D).Yaw;
		bOutTurn = true;
		OutForward = 1.0;
		JumpClock -= DeltaTime;
		if (Dist < Via.CollisionRadius + 100.0 && Dist > Via.CollisionRadius * 0.5 && int(PC.Pawn.Physics) == 1 && JumpClock <= 0.0)
		{
			bOutJump = true;
			JumpClock = 0.9;
			Jumps++;
			if (Dist > Via.CollisionRadius + 50.0)
			{
				NavDJ = 0.2;
			}
		}
		if (NavDJ > 0.0)
		{
			NavDJ -= DeltaTime;
			if (NavDJ <= 0.0)
			{
				bOutJump = true;
			}
		}
		if (SpecClock > 8.0)
		{
			Nav.Block(Nav.Path[NavAt - 1], Nav.Path[NavAt]);
			NavBlocks++;
			Say(PC, "the jump onto " $ string(Via.Name) $ " did not work in 8 s: that way is blocked. " $ Where(PC));
			TakeShot(PC, "lily");
			NavState = 0;
		}
		return true;
	}
	if (Kind == 5 && Via.IsA('JumpingMushroom'))
	{
		// a jumping mushroom: a running double jump onto its top, then still on it until it throws the hero (a red one 0.5 s after the landing, a
		// green one when it turns red)
		if (VSize(PC.Pawn.Velocity) > 450.0 && SpecClock > 0.3)
		{
			bSpecFlew = true;
		}
		if (bSpecFlew)
		{
			if (int(PC.Pawn.Physics) == 1)
			{
				Say(PC, "thrown by the mushroom " $ string(Via.Name) $ ", landed at " $ string(L));
				SpecAt = -1;
				NavState = 0;
			}
			return true;
		}
		D = Via.Location - L;
		D.Z = 0;
		Dist = VSize(D);
		if (Dist < Via.CollisionRadius + 10.0 && L.Z > Via.Location.Z + Via.CollisionHeight * 0.5 && int(PC.Pawn.Physics) == 1)
		{
			if (SpecPhase != 3)
			{
				SpecPhase = 3;
				Say(PC, "on top of the mushroom " $ string(Via.Name) $ " at " $ string(L) $ ": waits to be thrown");
			}
			if (SpecClock > 14.0)
			{
				Nav.Block(Nav.Path[NavAt - 1], Nav.Path[NavAt]);
				NavBlocks++;
				Say(PC, "the mushroom " $ string(Via.Name) $ " did not throw the hero in 14 s: that way is blocked. " $ Where(PC));
				TakeShot(PC, "mushroom");
				NavState = 0;
			}
			return true;
		}
		OutYaw = rotator(D).Yaw;
		bOutTurn = true;
		OutForward = 1.0;
		JumpClock -= DeltaTime;
		if (Dist < Via.CollisionRadius + 110.0 && Dist > Via.CollisionRadius * 0.6 && int(PC.Pawn.Physics) == 1 && JumpClock <= 0.0)
		{
			bOutJump = true;
			NavDJ = 0.2;
			JumpClock = 1.2;
			Jumps++;
		}
		else if (Dist <= Via.CollisionRadius * 0.6 && int(PC.Pawn.Physics) == 1)
		{
			// at its foot: back off for a run-up
			OutYaw = rotator(-D).Yaw;
		}
		if (NavDJ > 0.0)
		{
			NavDJ -= DeltaTime;
			if (NavDJ <= 0.0)
			{
				bOutJump = true;
			}
		}
		if (SpecClock > 14.0)
		{
			Nav.Block(Nav.Path[NavAt - 1], Nav.Path[NavAt]);
			NavBlocks++;
			Say(PC, "no landing on the mushroom " $ string(Via.Name) $ " (radius " $ string(int(Via.CollisionRadius)) $ ", height " $ string(int(Via.CollisionHeight))
				$ ", top " $ string(int(Via.Location.Z + Via.CollisionHeight)) $ ") in 14 s: that way is blocked. " $ Where(PC));
			TakeShot(PC, "mushroom");
			NavState = 0;
		}
		return true;
	}
	if (Kind == 5)
	{
		// a bounce pad: onto it, then a jump on it (the landing fires it) and the flight
		if (VSize(PC.Pawn.Velocity) > 450.0)
		{
			bSpecFlew = true;
		}
		if (bSpecFlew)
		{
			if (int(PC.Pawn.Physics) == 1)
			{
				Say(PC, "bounced by " $ string(Via.Name) $ ", landed at " $ string(L));
				SpecAt = -1;
				NavState = 0;
			}
			return true;
		}
		D = Via.Location - L;
		D.Z = 0;
		Dist = VSize(D);
		JumpClock -= DeltaTime;
		Rise = Via.Location.Z - (L.Z - PC.Pawn.CollisionHeight);
		Edge = Via.CollisionRadius + PC.Pawn.CollisionRadius;
		if (SpecPhase == 4 || (int(PC.Pawn.Physics) == 1 && Abs(Rise) <= 25.0 && Dist < Edge))
		{
			// on the pad (on the mushroom's cap): stand and jump straight up, no forward or back, in the air too (the lead, 11:10: "the bot must
			// stand on the mushroom and jump, without moving forward or back"); the landing on it throws the hero
			if (SpecPhase != 4)
			{
				SpecPhase = 4;
				Say(PC, "on the bounce pad " $ string(Via.Name) $ " at " $ string(L) $ ": jumps on the spot");
			}
			if (int(PC.Pawn.Physics) == 1 && !(Abs(Rise) <= 25.0 && Dist < Edge))
			{
				// landed off it: back to the way onto it
				SpecPhase = 0;
			}
			else if (int(PC.Pawn.Physics) == 1 && JumpClock <= 0.0)
			{
				bOutJump = true;
				JumpClock = 1.2;
				Jumps++;
			}
		}
		else if (Rise > 25.0 && int(PC.Pawn.Physics) == 1)
		{
			// the pad lies on something higher (the Hunt's BouncePad12 is 80 units above the ground round it): it fires on a landing ON it, so a
			// running jump onto it, a double jump for a high one, as onto a lily pad (h4-h6, v-hunt: jumps beside it for 48 s, never thrown)
			// under its edge the hero only bumps his head on what it lies on (x-hunt: BouncePad12 lies on the cap of BounceFungus3, the jumps
			// from under the cap rose 13-26 units): out past the edge for a run-up, then the jump at the edge
			OutYaw = rotator(D).Yaw;
			bOutTurn = true;
			OutForward = 1.0;
			if (SpecPhase == 2)
			{
				SpecPhaseClock += DeltaTime;
				OutYaw = rotator(-D).Yaw;
				if (Dist > Edge + 70.0 || SpecPhaseClock > 2.0)
				{
					SpecPhase = 0;
				}
			}
			else if (Dist < Edge - 10.0)
			{
				SpecPhase = 2;
				SpecPhaseClock = 0.0;
			}
			else if (Dist < Edge + 70.0 && JumpClock <= 0.0)
			{
				bOutJump = true;
				JumpClock = 1.2;
				Jumps++;
				if (Rise > 50.0)
				{
					NavDJ = 0.2;
				}
			}
		}
		else
		{
			if (Dist > 40.0 && int(PC.Pawn.Physics) == 1 && VSize(PC.Pawn.Velocity) < 600.0)
			{
				OutYaw = rotator(D).Yaw;
				bOutTurn = true;
				OutForward = FMin(1.0, Dist / 120.0 + 0.25);
			}
			if (Dist < 60.0 && int(PC.Pawn.Physics) == 1 && JumpClock <= 0.0)
			{
				bOutJump = true;
				JumpClock = 1.5;
				Jumps++;
			}
		}
		if (int(PC.Pawn.Physics) == 2 && Dist > 10.0 && SpecPhase != 4)
		{
			// in the air (onto it): on towards the pad's middle
			OutYaw = rotator(D).Yaw;
			bOutTurn = true;
			OutForward = 1.0;
		}
		if (NavDJ > 0.0)
		{
			NavDJ -= DeltaTime;
			if (NavDJ <= 0.0)
			{
				bOutJump = true;
			}
		}
		if (SpecClock > 12.0)
		{
			Nav.Block(Nav.Path[NavAt - 1], Nav.Path[NavAt]);
			NavBlocks++;
			Say(PC, "the bounce pad " $ string(Via.Name) $ " (" $ string(Via.Class.Name) $ ", on " $ Via.GetPropertyText("bEnabled") $ ", " $ string(int(Rise))
				$ " above the hero's feet, at " $ string(Via.Location)
				$ ", radius " $ string(int(Via.CollisionRadius)) $ ", height " $ string(int(Via.CollisionHeight)) $ ", collides " $ string(Via.bCollideActors)
				$ ") did not throw the hero in 12 s: that way is blocked. " $ Where(PC));
			TakeShot(PC, "bounce");
			NavState = 0;
		}
		return true;
	}
	if (Kind == 6)
	{
		// a vine: a running double jump at its first node (the hanging part is in Hanging). From right under it the hero only jumps up and misses
		// (n5: ten jumps from 22 units): too near, he backs off first for a run-up
		D = Via.Location - L;
		D.Z = 0;
		Dist = VSize(D);
		OutYaw = rotator(D).Yaw;
		bOutTurn = true;
		OutForward = 1.0;
		if (SpecPhase == 0 && Dist < 70.0)
		{
			SpecPhase = 2;
			SpecPhaseClock = 0.0;
		}
		if (SpecPhase == 2)
		{
			SpecPhaseClock += DeltaTime;
			OutYaw = rotator(-D).Yaw;
			if (SpecPhaseClock > 0.7)
			{
				SpecPhase = 0;
			}
			return true;
		}
		JumpClock -= DeltaTime;
		if (Dist < 120.0 && Dist >= 60.0 && VSize(PC.Pawn.Velocity * vect(1, 1, 0)) > 100.0 && int(PC.Pawn.Physics) == 1 && JumpClock <= 0.0)
		{
			bOutJump = true;
			NavDJ = 0.2;
			JumpClock = 1.5;
			Jumps++;
		}
		if (NavDJ > 0.0)
		{
			NavDJ -= DeltaTime;
			if (NavDJ <= 0.0)
			{
				bOutJump = true;
			}
		}
		if (SpecClock > 15.0)
		{
			Nav.Block(Nav.Path[NavAt - 1], Nav.Path[NavAt]);
			NavBlocks++;
			Say(PC, "the vine " $ string(Via.Name) $ " was not caught in 15 s: that way is blocked. " $ Where(PC));
			TakeShot(PC, "vine");
			NavState = 0;
		}
		return true;
	}
	return false;
}

// host: walks to T on the map (false = no way on the map, or its end is reached: the caller goes straight)
function bool NavDrive(PlayerController PC, float DeltaTime, Vector T, string What)
{
	local int s, g, r, Kind;
	local Vector P, D, L;
	local float Dist, Gap;
	local Vector Ahead;
	local Pawn E;

	if (Nav == None || !Nav.bBaked)
	{
		return false;
	}
	L = PC.Pawn.Location;
	NavClock += DeltaTime;
	// hanging with no way yet (caught a vine or a ledge off the way, the trail led there): the hanging keys first, the way after
	if (NavState != 2 && IsHanging(PC))
	{
		Hanging(PC, DeltaTime);
		return true;
	}
	if (NavState == 3 && (VSize(T - NavFor) > NavMove || NavClock > 20.0))
	{
		NavState = 0;
	}
	if (NavState == 0 || (NavState != 3 && VSize(T - NavFor) > NavMove && !InMove(PC)))
	{
		NavFor = T;
		NavWhat = What;
		NavClock = 0.0;
		s = Nav.NearestSeen(PC, L, 150.0, 150.0);
		g = Nav.NearestSeen(PC, T, 250.0, 300.0);
		if (g < 0)
		{
			g = Nav.Nearest(T, 250.0, 300.0);
		}
		if (s < 0 || g < 0)
		{
			NavState = 3;
			if (s < 0)
			{
				if (int(PC.Pawn.Physics) == 1)
				{
					Say(PC, "the hero at " $ string(L) $ " is off the map: the map grows from here");
					Nav.AddSeed(PC, L);
					NavState = 0;
					return true;
				}
				// in the air (a bounce, a fall): wait to land
				NavState = 0;
				return true;
			}
			else
			{
				Say(PC, "no walkable ground on the map near " $ What $ " " $ string(T) $ ": straight there");
			}
			return false;
		}
		Nav.StartSearch(s, g);
		NavState = 1;
	}
	if (NavState == 1)
	{
		r = Nav.SearchStep(1200);
		if (r == 0)
		{
			return true;
		}
		if (r < 0)
		{
			NavState = 3;
			Say(PC, "no way on the map from " $ string(L) $ " to " $ What $ " " $ string(T) $ " (" $ string(Nav.SPops) $ " cells tried, " $ string(NavBlocks)
				$ " ways blocked)");
			if (LevelClock - LastBake > 20.0 && NavBlocks == 0)
			{
				// a gate or a bridge may have opened since: the map is made again from here
				Nav.StartBake(PC);
				LastBake = LevelClock;
				NavState = 0;
				Say(PC, "map of the walkable ground: made again from here");
				return true;
			}
			return false;
		}
		NavState = 2;
		NavAt = 1;
		NavBest = 100000.0;
		NavSince = 0.0;
		Say(PC, "way to " $ What $ ": " $ string(Nav.Path.Length) $ " cells");
		LogWay(PC);
	}
	if (NavState != 2)
	{
		return false;
	}
	if (Hanging(PC, DeltaTime))
	{
		return true;
	}
	// the next cell of the way: cells reached or passed are left behind
	while (NavAt < Nav.Path.Length)
	{
		P = Nav.At(Nav.Path[NavAt]);
		D = P - L;
		if (Abs(D.Z) < 70.0)
		{
			D.Z = 0;
			if (VSize(D) < Nav.Cell * 0.75)
			{
				NavAt++;
				NavBest = 100000.0;
				NavSince = 0.0;
				continue;
			}
		}
		if (NavAt + 1 < Nav.Path.Length && VSize(Nav.At(Nav.Path[NavAt + 1]) - L) < VSize(P - L) && Abs(Nav.At(Nav.Path[NavAt + 1]).Z - L.Z) < 70.0)
		{
			NavAt++;
			NavBest = 100000.0;
			NavSince = 0.0;
			continue;
		}
		break;
	}
	if (NavAt >= Nav.Path.Length)
	{
		return false;
	}
	P = Nav.At(Nav.Path[NavAt]);
	if (Special(PC, DeltaTime, Nav.SpecialOf(Nav.Path[NavAt - 1], Nav.Path[NavAt]), P))
	{
		return true;
	}
	D = P - L;
	D.Z = 0;
	Dist = VSize(D);
	OutYaw = rotator(D).Yaw;
	bOutTurn = true;
	OutForward = 1.0;
	// a jump or a double jump where the way goes up
	Kind = Nav.KindOf(Nav.Path[NavAt - 1], Nav.Path[NavAt]);
	if (Kind == 4 && Climb(PC, DeltaTime, P, Dist))
	{
		return true;
	}
	if (Kind == 8)
	{
		// over a gap: full run at the far side, a jump at the edge (no floor a step ahead) or once the hero is past the near cell's middle, a
		// double jump for a long one. No wait after an earlier jump: nav10 walked off the edge while the jump key was resting
		Gap = VSize(Nav.At(Nav.Path[NavAt]) - Nav.At(Nav.Path[NavAt - 1]));
		Ahead = L + Normal(D) * (PC.Pawn.CollisionRadius + 12.0);
		if (GapFor != NavAt)
		{
			GapFor = NavAt;
			bGapJumped = false;
		}
		if (int(PC.Pawn.Physics) == 1 && !bGapJumped && VSize(Nav.At(Nav.Path[NavAt - 1]) - L) < Nav.Cell * 1.2
			&& (Dist < Gap - 16.0 || PC.FastTrace(Ahead - vect(0, 0, 1) * (PC.Pawn.CollisionHeight + 60.0), Ahead)))
		{
			bGapJumped = true;
			bOutJump = true;
			JumpClock = 1.0;
			Jumps++;
			if (Gap > 100.0 || Nav.At(Nav.Path[NavAt]).Z > L.Z + 20.0)
			{
				NavDJ = 0.2;
			}
		}
	}
	JumpClock -= DeltaTime;
	if ((Kind == 1 || Kind == 2) && Dist < Nav.Cell * 1.5 && int(PC.Pawn.Physics) == 1 && JumpClock <= 0.0)
	{
		bOutJump = true;
		JumpClock = 0.9;
		Jumps++;
		if (Kind == 2)
		{
			NavDJ = 0.18;
		}
	}
	if (NavDJ > 0.0)
	{
		NavDJ -= DeltaTime;
		if (NavDJ <= 0.0)
		{
			bOutJump = true;
		}
	}
	// headway to the cell: a jump after 3 s, a new way after 6 s, put there after 12 s (the bot's limit)
	if (Dist < NavBest - 15.0)
	{
		NavBest = Dist;
		NavSince = 0.0;
	}
	else
	{
		NavSince += DeltaTime;
	}
	StuckFor = NavSince;
	// a climb: the hero runs into the ledge and the game climbs it; a jump at it after a second (a mount from a jump)
	if (Kind == 4 && NavSince > 1.0 && JumpClock <= 0.0 && int(PC.Pawn.Physics) == 1)
	{
		bOutJump = true;
		JumpClock = 1.5;
		Jumps++;
	}
	if (NavSince > 3.0 && JumpClock <= 0.0)
	{
		bOutJump = true;
		JumpClock = 1.2;
		Jumps++;
	}
	if (NavSince > 6.0 && !(PC.Pawn.IsInState('Mounting') || PC.Pawn.IsInState('MountFinish') || IsHanging(PC)))
	{
		// this way between two cells is not walkable for the hero after all (a lip, a fence, water): it is not taken again
		Nav.Block(Nav.Path[NavAt - 1], Nav.Path[NavAt]);
		NavBlocks++;
		Say(PC, "no headway for 6 s at " $ string(L) $ " on the way (kind " $ string(Kind) $ ") to cell " $ string(P) $ ": that way is blocked, another one. "
			$ Where(PC));
		TakeShot(PC, "stuck");
		Picture(PC, P);
		NavState = 0;
		NavSince = 0.0;
	}
	// a fight on the way
	FireClock -= DeltaTime;
	E = EnemyInFront(PC);
	if (E != None && FireClock <= 0.0)
	{
		FireClock = 0.45;
		bOutFire = true;
		Hits++;
	}
	LogClock -= DeltaTime;
	if (LogClock <= 0.0)
	{
		LogClock = 5.0;
		Say(PC, "at " $ string(L) $ " -> " $ What $ " on the way, cell " $ string(NavAt) $ "/" $ string(Nav.Path.Length) $ " (step " $ string(StepAt + 1) $ "/"
			$ string(MySteps.Length) $ "), jumps " $ string(Jumps) $ ", put " $ string(Teleports) $ ", hits " $ string(Hits) $ ", level " $ string(int(LevelClock)) $ " s");
	}
	return true;
}

// the hero hangs: on the host his own pawn's state; a guest's hero hangs only on the server, which says so (EnhancedPlayerController.bHangSrv)
function bool IsHanging(PlayerController PC)
{
	if (PC.Pawn.IsInState('MountHanging'))
	{
		return true;
	}
	return EnhancedPlayerController(PC) != None && EnhancedPlayerController(PC).bHangSrv;
}

// the hero is in the middle of a move the way's search must not cut: hanging, climbing, thrown by a pad
function bool InMove(PlayerController PC)
{
	return IsHanging(PC) || PC.Pawn.IsInState('Mounting') || PC.Pawn.IsInState('MountFinish') || (SpecAt >= 0 && bSpecFlew)
		|| int(PC.Pawn.Physics) == 2;
}

function DriveTo(PlayerController PC, float DeltaTime, Actor N)
{
	Node = N;
	DriveToLoc(PC, DeltaTime, N.Location, string(N.Name));
}

// walks to the point T: the view's direction, forward, a jump or a sideways step on no headway, a hop after a long stall (host), an attack on an
// enemy in front
function DriveToLoc(PlayerController PC, float DeltaTime, Vector T, string What)
{
	if (bHost && NavDrive(PC, DeltaTime, T, What))
	{
		return;
	}
	DirectTo(PC, DeltaTime, T, What);
}

// straight to T (the end of a way on the map, a point off the map, a guest's next trail point)
function DirectTo(PlayerController PC, float DeltaTime, Vector T, string What)
{
	local Vector D;
	local float Dist, Near;
	local Pawn E;

	D = T - PC.Pawn.Location;
	D.Z = 0;
	Dist = VSize(T - PC.Pawn.Location);
	Near = 60.0;
	if (!bHost)
	{
		Near = 280.0;        // a guest stays a little behind the host instead of running into him
	}
	if (NearOverride > 0.0)
	{
		Near = NearOverride;
	}
	if (Dist > Near)
	{
		OutYaw = rotator(D).Yaw;
		bOutTurn = true;
		OutForward = 1.0;
	}

	// headway: coming nearer to the point it heads for (jumping on the spot or sliding along a wall is no headway)
	if (VSize(HeadLoc - T) > 100.0)
	{
		HeadLoc = T;
		HeadBest = Dist;
		HeadSince = 0.0;
	}
	if (Dist < HeadBest - 50.0)
	{
		HeadBest = Dist;
		HeadSince = 0.0;
	}
	else if (OutForward > 0.0)
	{
		HeadSince += DeltaTime;
	}
	StuckFor = HeadSince;
	JumpClock -= DeltaTime;
	if (StuckFor >= 2.0 && JumpClock <= 0.0)
	{
		JumpClock = 1.2;
		bOutJump = true;
		Jumps++;
	}
	if (StuckFor >= 4.0 && StuckFor < 7.0)
	{
		// sideways for a moment: around a post or a crate
		OutYaw += 16384;
	}
	if (bHost && StuckFor >= 10.0)
	{
		Teleports++;
		StepHops++;
		Say(PC, "HOP (bot limit): no headway for " $ string(int(StuckFor)) $ " s at " $ string(PC.Pawn.Location) $ " towards " $ What $ " " $ string(T) $ ": put there");
		if (bHost && StepAt >= MySteps.Length && CrumbAt < Crumbs.Length - 1)
		{
			CrumbAt++;
		}
		Hop(PC, T);
		StuckFor = 0.0;
		HeadSince = 0.0;
		HeadLoc = vect(0, 0, 0);
	}

	// a fight on the way
	FireClock -= DeltaTime;
	E = EnemyInFront(PC);
	if (E != None && FireClock <= 0.0)
	{
		FireClock = 0.45;
		bOutFire = true;
		Hits++;
	}

	LogClock -= DeltaTime;
	if (LogClock <= 0.0)
	{
		LogClock = 5.0;
		Say(PC, "at " $ string(PC.Pawn.Location) $ " state " $ string(PC.Pawn.GetStateName()) $ " -> " $ What $ " " $ string(int(Dist)) $ " away (step " $ string(StepAt + 1) $ "/"
			$ string(MySteps.Length) $ ", crumb " $ string(CrumbAt) $ "/" $ string(Crumbs.Length) $ "), stuck " $ string(int(StuckFor)) $ " s, jumps " $ string(Jumps)
			$ ", put " $ string(Teleports) $ ", hits " $ string(Hits) $ ", level " $ string(int(LevelClock)) $ " s");
	}
}

// puts the hero at T, or on the floor found right under T (a coin or a mark floats; the point itself may be inside a rock: play run p12 stood still)
function Hop(PlayerController PC, Vector T)
{
	local Vector HL, HN;
	local Actor A;

	if (PC.Pawn.SetLocation(T + vect(0, 0, 40)) || PC.Pawn.SetLocation(T + vect(0, 0, 90)))
	{
		return;
	}
	A = PC.Pawn.Trace(HL, HN, T - vect(0, 0, 600), T + vect(0, 0, 300), false);
	if (A != None && PC.Pawn.SetLocation(HL + vect(0, 0, 1) * (PC.Pawn.CollisionHeight + 5.0)))
	{
		return;
	}
	Say(PC, "HOP failed: no free place at " $ string(T));
}

// ---- The walkthrough steps of the level (EnhancedPlayRoutes, System\EnhancedPlay.ini) ----
function ReadSteps(PlayerController PC)
{
	local string M, L;
	local int i;

	bStepsRead = true;
	M = MapOf(PC);
	for (i = 0; i < Class'Enhanced.EnhancedPlayRoutes'.default.Steps.Length; i++)
	{
		L = Class'Enhanced.EnhancedPlayRoutes'.default.Steps[i];
		if (Left(L, Len(M) + 1) ~= (M $ ":"))
		{
			L = Mid(L, Len(M) + 1);
			while (Left(L, 1) == " ")
			{
				L = Mid(L, 1);
			}
			MySteps[MySteps.Length] = L;
		}
	}
	Say(PC, "walkthrough of " $ M $ ": " $ string(MySteps.Length) $ " steps");
	StartFrom(PC);
}

// test option from=N in SHREK2_BOT (the first level of a run only): the walkthrough starts at step N, the hero is put at the last goto point
// before it (a quick look at one part of a level; logged as a test start, never a game fact)
function StartFrom(PlayerController PC)
{
	local string Env, W, S, Cmd;
	local int i, N;
	local Vector V;
	local bool bFound;

	if (bFromDone || EnhancedGame(PC.Level.Game) == None)
	{
		return;
	}
	bFromDone = true;
	Env = EnhancedGame(PC.Level.Game).EnhBotEnv(0);
	i = InStr(Env, "from=");
	if (i < 0)
	{
		return;
	}
	W = Mid(Env, i + 5);
	N = int(W);
	if (N < 2 || N > MySteps.Length)
	{
		return;
	}
	for (i = N - 2; i >= 0 && !bFound; i--)
	{
		S = MySteps[i];
		Cmd = Word(S);
		if (Cmd ~= "goto")
		{
			V = ReadPoint(S);
			bFound = true;
		}
	}
	StepAt = N - 1;
	StepClock = 0.0;
	if (bFound)
	{
		Hop(PC, V);
		Say(PC, "TEST START at step " $ string(N) $ ": the hero is put at " $ string(V));
	}
	else
	{
		Say(PC, "TEST START at step " $ string(N));
	}
}

// the next word of S (words are parted by spaces); S keeps the rest
function string Word(out string S)
{
	local string W;
	local int i;

	while (Left(S, 1) == " ")
	{
		S = Mid(S, 1);
	}
	i = InStr(S, " ");
	if (i < 0)
	{
		W = S;
		S = "";
		return W;
	}
	W = Left(S, i);
	S = Mid(S, i + 1);
	return W;
}

function NextStep(PlayerController PC, string Why)
{
	Say(PC, "step " $ string(StepAt + 1) $ " '" $ MySteps[StepAt] $ "' " $ Why $ " after " $ string(int(StepClock)) $ " s");
	StepAt++;
	StepClock = 0.0;
	StepTries = 0;
	StepHops = 0;
	bStepSaw = false;
	NoFoeFor = 0.0;
	HeadLoc = vect(0, 0, 0);
}

function Actor FindNamed(PlayerController PC, string N)
{
	local Actor A;

	foreach PC.AllActors(Class'Engine.Actor', A)
	{
		if (string(A.Name) ~= N)
		{
			return A;
		}
	}
	return None;
}

// a class of the game by its short name (SHGame, KWGame or Engine), remembered once found
function Class<Actor> ClassFor(string Cls)
{
	if (Cls ~= LastClassName && LastClass != None)
	{
		return LastClass;
	}
	LastClassName = Cls;
	LastClass = Class<Actor>(DynamicLoadObject("SHGame." $ Cls, Class'Class', true));
	if (LastClass == None)
	{
		LastClass = Class<Actor>(DynamicLoadObject("KWGame." $ Cls, Class'Class', true));
	}
	if (LastClass == None)
	{
		LastClass = Class<Actor>(DynamicLoadObject("Engine." $ Cls, Class'Class', true));
	}
	return LastClass;
}

// the nearest live actor of a class (or a subclass), with a property of that text if one is given (Name=X: that actor), within Within units
function Actor FindFoe(PlayerController PC, string Cls, string Prop, string Value, optional float Within)
{
	local Actor A, Best;
	local float D, BestD;
	local Class<Actor> C;

	C = ClassFor(Cls);
	BestD = 3000.0;
	if (Within > 0.0)
	{
		BestD = Within;
	}
	foreach PC.DynamicActors(Class'Engine.Actor', A)
	{
		if (A == PC.Pawn || A.bHidden || A.bDeleteMe || C == None || !ClassIsChildOf(A.Class, C))
		{
			continue;
		}
		if (Pawn(A) != None && float(A.GetPropertyText("Health")) <= 0.0)
		{
			continue;
		}
		if (Prop ~= "Name")
		{
			if (!(string(A.Name) ~= Value))
			{
				continue;
			}
		}
		else if (Prop != "" && !(A.GetPropertyText(Prop) ~= Value))
		{
			continue;
		}
		D = VSize(A.Location - PC.Pawn.Location);
		if (D < BestD)
		{
			BestD = D;
			Best = A;
		}
	}
	return Best;
}

function Vector ReadPoint(string S)
{
	local Vector V;

	V.X = float(Word(S));
	V.Y = float(Word(S));
	V.Z = float(Word(S));
	return V;
}

// A switch that can be thrown (the game's ShHeroPawn.ThrowSwitchClosestObject takes one in StateOff only): the named one, else the nearest within Within
function Actor FindSwitch(PlayerController PC, string N, float Within)
{
	local Actor A, Best;
	local float D, BestD;
	local Class<Actor> C;

	if (N != "")
	{
		return FindNamed(PC, N);
	}
	C = Class<Actor>(DynamicLoadObject("SHGame.Switch", Class'Class', true));
	if (C == None)
	{
		return None;
	}
	BestD = Within;
	foreach PC.AllActors(C, A)
	{
		if (!A.IsInState('StateOff'))
		{
			continue;
		}
		D = VSize(A.Location - PC.Pawn.Location);
		if (D < BestD)
		{
			BestD = D;
			Best = A;
		}
	}
	return Best;
}

// Throws the switch S as a player does: the game takes a switch only when the hero faces the way the switch faces (cos >= 0.7), has it in front of
// him along that direction, stands within 30 units of it (plus both radii) and overlaps it in height (ShHeroPawn.ThrowSwitchClosestObject). So the bot
// walks to the spot in front of it, turns to the switch's own direction and presses the action key. True when it is thrown or given up.
function bool DoSwitch(PlayerController PC, float DeltaTime, Actor S)
{
	local Vector F, P, D;
	local Rotator R;

	if (!S.IsInState('StateOff'))
	{
		NextStep(PC, "done (" $ string(S.Name) $ " is thrown, state " $ string(S.GetStateName()) $ ")");
		return true;
	}
	R = S.Rotation;
	R.Pitch = 0;
	R.Roll = 0;
	F = Vector(R);
	P = S.Location - F * (S.CollisionRadius + PC.Pawn.CollisionRadius + 12.0);
	D = P - PC.Pawn.Location;
	D.Z = 0;
	if (VSize(D) > 22.0)
	{
		NearOverride = 12.0;
		DriveToLoc(PC, DeltaTime, P, string(S.Name));
		NearOverride = 0.0;
		FireClock = 0.5;
		return false;
	}
	OutYaw = R.Yaw;
	bOutTurn = true;
	// the hero turns the way he walks: a short step towards the switch turns him to it
	if (Abs(float(((PC.Pawn.Rotation.Yaw - R.Yaw) & 65535) - 32768)) < 30000.0)
	{
		OutForward = 0.2;
		return false;
	}
	FireClock -= DeltaTime;
	if (FireClock <= 0.0)
	{
		FireClock = 1.2;
		bOutFire = true;
		StepTries++;
		Say(PC, "switch " $ string(S.Name) $ ": action key (" $ string(StepTries) $ "), hero at " $ string(PC.Pawn.Location) $ " yaw " $ string(PC.Pawn.Rotation.Yaw & 65535)
			$ ", switch at " $ string(S.Location) $ " yaw " $ string(R.Yaw & 65535));
		if (StepTries > 6)
		{
			NextStep(PC, "FAILED: " $ string(S.Name) $ " was not thrown");
			return true;
		}
	}
	return false;
}

// Runs the current step; false when the steps are over (the breadcrumbs to the exit take over).
function bool RunSteps(PlayerController PC, float DeltaTime)
{
	local string S, Cmd, Arg, Prop, Value, W;
	local Actor A;
	local Vector V, D;
	local float Dist, Within;

	if (!bStepsRead)
	{
		ReadSteps(PC);
	}
	if (StepAt >= MySteps.Length)
	{
		return false;
	}
	if (StepClock == 0.0)
	{
		Say(PC, "step " $ string(StepAt + 1) $ "/" $ string(MySteps.Length) $ ": " $ MySteps[StepAt]);
	}
	StepClock += DeltaTime;
	if (StepClock > 240.0)
	{
		NextStep(PC, "TIMED OUT (4 min)");
		return true;
	}
	S = MySteps[StepAt];
	Cmd = Word(S);
	if (Cmd ~= "goto")
	{
		V = ReadPoint(S);
		if (Nav != None && Nav.bBaked)
		{
			// looked up once per step and map (every frame it cost frames in co-op, n5)
			if (StepNodeFor != StepAt + 1 || StepNodeSize != Nav.NX.Length)
			{
				StepNode = Nav.Nearest(V, 250.0, 300.0);
				StepNodeFor = StepAt + 1;
				StepNodeSize = Nav.NX.Length;
			}
			if (StepNode < 0 || StepNode >= Nav.NX.Length)
			{
				NextStep(PC, "SKIPPED: no walkable ground on the map near this point of the walkthrough (a guess)");
				return true;
			}
			V = Nav.At(StepNode);
			// no way on foot (a gap or a mechanism the map does not know): straight there, and after a long stall the hero is put there
			// (HOP, the bot's limit)
		}
		D = V - PC.Pawn.Location;
		D.Z = 0;
		if (Reached(V, PC.Pawn.Location))
		{
			NextStep(PC, "reached");
		}
		else if (StepHops > 0 && VSize(D) < 150.0)
		{
			NextStep(PC, "reached after a HOP (the height in the walkthrough is " $ string(int(V.Z)) $ ", the hero is at " $ string(int(PC.Pawn.Location.Z)) $ ")");
		}
		else
		{
			DriveToLoc(PC, DeltaTime, V, "point");
		}
	}
	else if (Cmd ~= "touch")
	{
		Arg = Word(S);
		A = FindNamed(PC, Arg);
		if (A == None)
		{
			NextStep(PC, "SKIPPED: no actor " $ Arg);
		}
		else if (Reached(A.Location, PC.Pawn.Location))
		{
			NextStep(PC, "reached");
		}
		else
		{
			DriveToLoc(PC, DeltaTime, A.Location, Arg);
		}
	}
	else if (Cmd ~= "fight")
	{
		Arg = Word(S);
		Prop = "";
		Within = 0.0;
		while (S != "")
		{
			W = Word(S);
			if (InStr(W, "=") > 0)
			{
				Value = Mid(W, InStr(W, "=") + 1);
				Prop = Left(W, InStr(W, "="));
			}
			else if (W ~= "within")
			{
				Within = float(Word(S));
			}
		}
		A = FindFoe(PC, Arg, Prop, Value, Within);
		if (A == None)
		{
			NoFoeFor += DeltaTime;
			if (NoFoeFor > 4.0)
			{
				NextStep(PC, "done (no " $ Arg $ " left near)");
			}
		}
		else
		{
			NoFoeFor = 0.0;
			D = A.Location - PC.Pawn.Location;
			D.Z = 0;
			Dist = VSize(D);
			if (Dist > 85.0 + A.CollisionRadius * 0.5)
			{
				DriveToLoc(PC, DeltaTime, A.Location, string(A.Name));
			}
			else if (Face(PC, rotator(D).Yaw))
			{
				// every fourth blow is the special one, an attack from a jump (Shrek's belly flop: some things break only from it,
				// BreakableObject.bSpecialAttackOnly; nav21 hit such a crate 71 times)
				if (AirFire > 0.0)
				{
					AirFire -= DeltaTime;
					if (AirFire <= 0.0)
					{
						bOutFire = true;
					}
				}
				FireClock -= DeltaTime;
				if (FireClock <= 0.0)
				{
					FireClock = 0.45;
					if (StepTries % 4 == 3 && int(PC.Pawn.Physics) == 1)
					{
						bOutJump = true;
						AirFire = 0.3;
						FireClock = 1.2;
					}
					else
					{
						bOutFire = true;
					}
					Hits++;
					StepTries++;
					if (StepTries % 10 == 1)
					{
						Say(PC, "hits " $ string(A.Name) $ " (" $ string(StepTries) $ " so far), " $ string(int(Dist)) $ " away, its state " $ string(A.GetStateName()));
					}
				}
			}
		}
	}
	else if (Cmd ~= "pick")
	{
		Arg = Word(S);
		if (!(PC.Pawn.GetPropertyText("aHolding") ~= "None"))
		{
			NextStep(PC, "done (holding " $ PC.Pawn.GetPropertyText("aHolding") $ ")");
			return true;
		}
		A = FindNamed(PC, Arg);
		if (A == None)
		{
			A = FindFoe(PC, Arg, "", "", 0.0);
		}
		if (A == None || A.bDeleteMe || (A.bHidden && bStepSaw))
		{
			if (bStepSaw)
			{
				NextStep(PC, "done (" $ Arg $ " is picked up)");
			}
			else
			{
				NextStep(PC, "SKIPPED: nothing called " $ Arg);
			}
			return true;
		}
		bStepSaw = true;
		D = A.Location - PC.Pawn.Location;
		D.Z = 0;
		if (A.IsA('Pickup'))
		{
			// a pickup is taken by touching it (coins, potions, posters, money bags): walk into it
			NearOverride = 5.0;
			DriveToLoc(PC, DeltaTime, A.Location, string(A.Name));
			NearOverride = 0.0;
		}
		else if (VSize(D) > 70.0 + A.CollisionRadius)
		{
			DriveToLoc(PC, DeltaTime, A.Location, string(A.Name));
		}
		else if (Face(PC, rotator(D).Yaw))
		{
			FireClock -= DeltaTime;
			if (FireClock <= 0.0)
			{
				FireClock = 1.0;
				bOutFire = true;
				StepTries++;
				if (StepTries > 6)
				{
					NextStep(PC, "FAILED: " $ string(A.Name) $ " was not picked up");
				}
			}
		}
	}
	else if (Cmd ~= "carry")
	{
		V = ReadPoint(S);
		if (Reached(V, PC.Pawn.Location))
		{
			bOutFire = true;
			NextStep(PC, "put down (holding " $ PC.Pawn.GetPropertyText("aHolding") $ ")");
		}
		else
		{
			DriveToLoc(PC, DeltaTime, V, "carry point");
		}
	}
	else if (Cmd ~= "use")
	{
		A = FindSwitch(PC, "", 350.0);
		if (A != None)
		{
			DoSwitch(PC, DeltaTime, A);
		}
		else
		{
			bOutFire = true;
			NextStep(PC, "pressed (no switch near)");
		}
	}
	else if (Cmd ~= "switch")
	{
		Arg = Word(S);
		A = FindSwitch(PC, Arg, 2500.0);
		if (A == None)
		{
			NextStep(PC, "SKIPPED: no switch " $ Arg);
		}
		else
		{
			DoSwitch(PC, DeltaTime, A);
		}
	}
	else if (Cmd ~= "picture")
	{
		Picture(PC, PC.Pawn.Location);
		NextStep(PC, "written");
	}
	else if (Cmd ~= "shot")
	{
		TakeShot(PC, "step");
		NextStep(PC, "taken");
	}
	else if (Cmd ~= "waitevent")
	{
		// a cutscene or a mover the step before started: the bot does not run while a cutscene has the controls, so a short wait is enough
		if (StepClock >= 3.0)
		{
			NextStep(PC, "waited");
		}
	}
	else if (Cmd ~= "jump")
	{
		bOutJump = true;
		NextStep(PC, "pressed");
	}
	else if (Cmd ~= "doublejump")
	{
		if (StepTries == 0)
		{
			bOutJump = true;
			StepTries = 1;
		}
		else if (StepClock > 0.35)
		{
			bOutJump = true;
			NextStep(PC, "pressed twice");
		}
	}
	else if (Cmd ~= "wait")
	{
		if (StepClock >= float(Word(S)))
		{
			NextStep(PC, "waited");
		}
	}
	else if (Cmd ~= "waitgone")
	{
		Arg = Word(S);
		A = FindNamed(PC, Arg);
		if (A == None || A.bHidden || A.bDeleteMe)
		{
			NextStep(PC, "gone");
		}
	}
	else if (Cmd ~= "exit")
	{
		NextStep(PC, "the rest is the way to the exit");
		StepAt = MySteps.Length;
		return false;
	}
	else
	{
		NextStep(PC, "SKIPPED: unknown step");
	}
	return true;
}

defaultproperties
{
}

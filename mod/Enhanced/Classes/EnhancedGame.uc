class EnhancedGame extends ShGame.ShGame;

// Co-op base layer. Everything here is the foundation for the larger mod.

// The first Login is the host's own local player and keeps the game's original path.
var bool bHostLoggedIn;

// Player two: the controller made in Login. His own Shrek (a second pawn of the same class as the host's, so the
// abilities are the same) is made only after the cutscenes, next to the host, and hidden while a cutscene runs.
// Possess needs the network connection, which the engine attaches only after Login returns.
var PlayerController PendingPC;
var array<PlayerController> GPC;      // the guests (see the section 'Guests')
var array<KWPawn> GPawn;
var array<bool> GHidden;
var array<float> GDead;
var array<EnhancedCam> GCam;

var KWPawn P2Pawn;
var bool bP2Hidden;

// Debug layer (see EnhancedDebug); spawned at game start.
var EnhancedDebug Dbg;

var bool bQuiet;
var float LastCheckpointTime;

// A checkpoint counts when every player is near it. A request made while a partner is far away waits here.
var() config float CheckpointRadius;
var bool bCkptPending;
var Vector CkptLoc;
var string CkptWhy;
var array<Controller> CkptPassed;   // the players that have been at the checkpoint since it was reached
var EnhancedTicker Ticker;
var Vector LastCheckpointLoc;       // where the last counted checkpoint was
var bool bHaveCheckpointLoc;
var bool bCkptAnchor;               // the waiting checkpoint is a place to come back to (a fairy or a level start), see CheckpointAnchor
const CkptStartWindow = 20.0;       // seconds after a level has started in which a save of the engine counts as the level's start
const FairyReach = 2500.0;          // a save this close to a save fairy belongs to that fairy
var float HudTestAt;                // URL option EnhHudTest=<seconds> (tests): the host's HUD is hidden by hand; it must come back by itself
var float CkptTestAt;               // URL option EnhCkptTest=<seconds> (tests): a save of a cutscene's end, then a save next to a fairy
var int CkptTestStep;
var Actor CkptTestFairy;

// The leash: players may not drift apart for good, and the exits of a level stay shut until everybody is there.
var() config float LeashDistance;   // maximum distance between two players
var() config float LeashGrace;      // seconds the distance may be exceeded before the runaway is brought back
var() config float ExitRadius;      // everybody must be this close to an exit for it to work
var float LeashSince;               // 0, or the time the distance was first exceeded
var array<Actor> Exits;             // the level-change triggers of the level
var array<int> ExitOpen;            // 1 when the exit at the same index is currently enabled
var float LastExitHint;

// Loading a checkpoint: started with the URL option ?EnhLoad=<slot>.
var EnhancedSaveData LoadRecord;
var bool bLoading;
var bool bSkipIntroOpt;
var bool bNoRingOpt;               // URL option EnhNoRing=1: the ring places are refused, so that the forced places in front of the host can be tested
var bool bTestOpt;
var bool bSubOpt;
var bool bFFTestOpt;
var bool bTravelTestOpt;
var EnhancedCam CutCam;
var bool bWaitOpt;        // URL option EnhWait: hold the opening cutscene until player two has joined
var bool bHold;           // the cutscene is being held now
var name HoldEvent;       // the event of the PlayerStart that starts the opening cutscene
var float MirrorLog;
var bool bSurveyInit, bSurveyBusy;
var Vector SurveyInitPos;
var float SurveyFreeSince;
var float HostH, RingS;              // the half height of the host's body and the scale of the rings of places around him (1 for a Shrek; the giant Mongo has a radius of 150 and a height of 300)
var Vector JoinCenter;               // the place a guest's Shrek is put around: the host, or the last checkpoint while the host is in a fight (see ChooseJoinCenter)
var bool bJoinSurveyOpt, bJoinSurveyDone;   // URL option EnhJoinSurvey: lists the checkpoints, the starts, the cutscene triggers and the enemies of the level (tests)
var string OffList;                 // URL option EnhOff=sync,mirror,subs,trace,smooth,idle: parts of the mod switched off one by one to see what each costs (tests)
var bool bProbeOpt;                    // URL option EnhProbe: the host writes the state of every changing actor of the level to its log, every 10 s (tests; compared with the guest's)
var bool bSurveyOpt, bSurveyDone;   // URL option EnhSurvey: lists the kinds of actors of the level and whether they are replicated (tests)
var string SubRawT, SubRawN, SubEncT, SubEncN;   // the host's subtitle as it was last seen and as it is sent to the guests
var int SpawnFails;                 // how many times in a row a guest's Shrek found no place around the host (after 40 the rules for a place are relaxed)
var float HostTurnAt;               // URL option EnhHostTurn=<seconds>: at that level time the host's camera is turned half a circle (tests: to see the guests behind him)
var bool bHostTurned;
var string HostNoteText;            // the last note the mod itself put on the host's subtitle line (the guests do not get it as a subtitle)
var float ReleaseAt;      // when the held opening cutscene was let go (the guests' Shreks are not made before it is over)
var float HoldSince;      // when player two joined while the cutscene was held
// The cutscene gates: a cutscene trigger fires only after every player has passed through it. The trigger's own collision is
// switched off (so it cannot fire by itself) and the game watches the players' positions against its volume. A player who got
// there first may not go further than GateLeash from it until the others have come.
var array<Actor> GateT;               // the cutscene triggers of the level
var array<Controller> PassCtl;        // players that have passed a gate and wait, with the gate's index in PassGate
var array<int> PassGate;
var array<float> PassTime;            // when each of them passed
var() config float GateTimeout;       // seconds a gate holds the first player; then the scene starts anyway (a partner who skips an optional trigger must not trap him)
var array<Controller> LatchCtl;       // players that have set a gate off and must leave its volume before they count again
var array<int> LatchGate;
var() config float GateLeash;         // how far from the trigger the player who came first may go
var string GroundWhy;                // why the last GroundAt said no (for the log)
var int IdleFixes;
var bool bRestarting;               // the host died and the level is being loaded again
var float P2DeadSince;
var float HostDeadSince;
var EnhancedLeavePrompt LeavePrompt;   // the host's question when the last guest has left
var string LeaveTestMode;           // URL option EnhLeaveTest=yes|no: the question is answered by itself (tests)

var float DownSince[4];             // when each player (0 = the host, 1.. = the guests) went down; 0 = on his feet
var float ReviveSince[4];           // since when a friend has been standing next to him
var float AllDownSince;             // since when everybody is down
var string DownNoteHost;            // what the host's HUD shows about a downed player

var string DeathTestMode;            // URL option EnhDeathTest (tests)
var float DeathTestClock;
var int DeathTestStep;
var() config float EnemyHealthPerPlayer;   // 0.6: two players, enemies with 1.6 times the health
var() config float EnemyDamagePerPlayer;   // 0.25: two players, hits that do 1.25 times the damage
var int EnemiesLogged;
var string ShotTimes;                // URL option EnhShot=20,35: the game takes its own screenshot (tests; also for windows larger than the screen)
var int ShotsTaken;
var EnhancedWorldSync WorldSync[4];   // carries the level's own effects and creatures, which the engine never sends, to the clients (host only)
var EnhancedAnimSync AnimSync;     // carries every animation channel of the heroes to the clients (host only)
var Vector GSmooth[4];            // where a guest's Shrek is drawn on the host (the smoothed position)
var byte GSInit[4];
var float GBaseX[4], GBaseY[4];   // PrePivot of the pawn without the draw offset
var bool bPivotCal, bNoSmooth;
var float DispX, DispY;
var int PivotLog;
var bool bFpsOpt;               // URL option EnhFps: the host's frame rate every two seconds (tests)
var float CursorTestX, CursorTestY;   // URL option EnhCursor=x,y: the menu cursor is put there every frame (tests of the hot spot)
var KWPawn CarrierCache;             // the pawn that holds the shared inventory (see InvOf)
var bool bBonusLeaving;              // the bonus level has been left: the way back is already started
var float BonusTestAt;               // URL option EnhBonusAt=<seconds> (tests): the exit of a bonus level is activated at that time
var bool bBonusTested;
var float ClimbTestAt;                // URL option EnhClimbTest=<seconds> (tests, swamp): a guest is put in front of the stump the owner's guest got stuck in
var bool bClimbTested;
var EnhancedPlayerController ClimbWatch;
var float ClimbWatchUntil, ClimbLogAt;
var float BagTestAt;                  // URL option EnhBagTest=<seconds> (tests): at that time the host's punching bags get a push (a blow of the host), 6 s later
                                      // a guest is put next to one and his attack is pressed four times (his blows), 8 s after that the bags still hanging are used
                                      // up; the bags' state goes to the log twice a second ([BAG]); the guest's copies log their poses ([BAG] client)
var int BagStep;
var float BagLogAt;
var KActor BagHit;
var float GotoAt;                    // URL option EnhGotoAt=<seconds> (with EnhGoto=<map>): in the front-end level the host's controller opens that map by itself (tests: the path from the main menu into a level)
var string GotoMap;
var bool bGotoDone;
var string HostMenuPage;           // URL option EnhHostMenuPage=options (tests): the pause menu's settings page is opened instead of the pause menu
var float HostMenuAt;               // URL option EnhHostMenu=<seconds>: the host's own pause menu is opened by itself at that level time (tests)
var bool bJumpTestOpt;           // URL option EnhJumpTest: the host's Shrek jumps and double jumps by the clock, the height and the air time are logged (tests of the frame rate)
var int JtState;
var float JtT, JtZ0, JtMaxZ;
var bool bJtDid2;
var float JtHold;
var bool bJtInput;               // EnhJumpTest=input: the host's jumps are made through the flag the Jump key sets (the real input path) instead of calling the pawn
var bool bJtGuestOnly;           // EnhJumpTest=guest: the host does not jump, only the guests' jumps are watched
var int GjState, GjCount;
var float GjAir, GjMax, GjZ0, GjPrevVz;
var bool bGjSecond;
var bool bPivotTest;           // URL option EnhPivotTest (tests only)
var bool bJitterOpt;                 // URL option EnhJitter: log the guests' pawns every 0.1 s (tests)
var float JitterClock;
var bool bResListDone;               // the resolution list of the Settings page has been filled
var float NoteTime;
var string GateNoteHost;              // what the host's HUD shows while he waits at a gate
var string LeashNoteHost;             // what the host's HUD shows while he is too far from the others (the seconds before he is brought back)
var PlayerController LeashWarned;     // the player who has the leash note now
var Vector LeashStart;                // the start of the level (the leash's anchor before the first checkpoint)
var int LeashStartState;              // 0 = not looked up yet, 1 = found, 2 = none
var array<KWCutScene> CutList;        // the level's cutscenes (made by its CutFactory at the start; looked up again now and then)
var float CutListAt;
var KWCutScene ActiveCut;             // the host's cutscene that is playing now
var float ActiveCutStart;
var int CutSerial;                    // a number for every cutscene the host plays (the guests answer with it)
var bool bHeroInit;                   // the engine layer's several-heroes hook has been set up for this level (see HeroTick)
var int HeroInitOk;
var Actor BossNow;                    // the boss every hero has as aBoss (MirrorBoss)
var string HopMode, HopMap, HopHost;   // a stop in the menu book on the way between two copies of the same level (see Hop)
var bool bHopGone;
var string IntroOnlyHost;              // a guest playing the level's opening by himself first (URL option EnhIntroOnly=<host address>): he joins the host after it
var bool bIntroSeen;                    // ... the opening began on this machine
var float IntroQuietSince;
var bool bIntroJoining;
var bool bLevelHadOpening;               // host: this level played an opening cutscene when it started (a guest who comes in later plays it by himself first)
var int OpeningSerial;                   // host: the number of that opening (CutSerial)
var bool bLocalCutOpt;                   // URL option EnhLocalCut: the guests rebuild the host's cutscenes in the middle of a level on their machines (off: the host's camera)
var array<string> AwayForIntro;          // host: the guests sent away to play the opening by themselves (their leaving asks nothing)
var array<string> IntroWait;             // host: the guests still playing this level's opening in their own game; the world waits for them (IntroWaitTick)
var float IntroWaitClock;                // host: seconds (frames, also while paused) since the last guest went away for an opening
var bool bIntroPaused;                   // host: the world is paused by IntroWaitTick
var float IntroPausedAt;                 // host: IntroWaitClock when that pause began
var bool bHostOpeningSeen;               // host: his own opening of this level is over (or the level has none): only then may the world wait for a guest
var bool bIntroShot;                     // tests (EnhShot): one picture of the waiting host is taken
var string IntroWaitNote;                // host: the note on the host's HUD while the world waits (EnhancedHud draws it)
var float TweakAt;                       // next time HeroTweaks runs
var array<Pawn> SavedHeroes;             // stock save game (PreSaveGame): the heroes and their health, put back after the load (MPatcher's fix)
var array<string> SavedHealth;
var float SaveTestAt;                    // tests (?EnhSaveTest=<s>): a stock save at that time with the hero's health at 37, then the load of it
var bool bSaveTestDone;                  // ... kept in the save: the loaded game does not start it again
var transient float SaveTestLoadAt;      // ... not kept in the save (transient): the load happens once
var float SaveTestShotAt;
var array<string> OpeningMaps;           // levels that start with an opening cutscene (the guests play it by themselves before they join)
var array<string> IntroEnd;              // per level: where the host's hero stands when the level's opening is over ("map=x,y,z", measured by the join survey)
var bool bPullAfterCut;                 // the host's cutscene is over: guests who came into the world early and stand far away are brought to him
var Vector CutStartHeroLoc;            // where the host's hero stood when the host's cutscene began (HostPlace)
var bool bCutStartLoc;
var Pawn LastHostHero;                // the host's hero as last seen with the host's controller (see HostHero)
var float HeroStatsAt, HeroSanityAt;
var string HostSongCmd;               // the host's song now (the last music change that started one), for a guest who comes in or comes back from his cutscene
var int HostSongHandle;
var int MusicLogs;
var float HudExtraAt;
var string HudExtraNow;
var string GateTestMode;              // URL option EnhGateTest: a script that walks the players to the first gate (tests)
var float GateTestClock;
var int GateTestStep;
var int GateTestIdx;
var int ExpectedPlayers;              // URL option EnhPlayers: how many players the lobby had; gates and the start wait for them
var EnhancedUpnp Upnp;
var string LobbyMode;            // URL option Lobby=host: this front-end level is a co-op lobby that others can join
var bool bLobbyUpnp;             // URL option Upnp=1: open the game port on the router
var float LobbyTimer;
var int GamePortDefault;
var int LobbyMin;                // fewest players to start a co-op game
var int LobbyMax;                // most players in a lobby (the game itself plays for two so far; 4 is planned)
const FirstMap = "1_Shreks_Swamp";
var EnhancedLanBeacon Beacon;   // LAN discovery: answers when hosting, searches in the menu
var bool bMenuDump;              // URL option EnhMenuDump (tests): the menu fitter logs every component's place on the screen ([MENUBOX])
var string MenuScript;           // URL option EnhMenu=coop;lan;...: tests press menu buttons one by one
var bool bLaunching;             // the host pressed Start: nobody else may join (a guest connecting while the level changes crashed his client)
var string SessionId;            // URL option EnhSession: the co-op game this level belongs to (its save slot is coop_<id>)
var string UpnpTarget;           // URL option EnhUpnpTarget: tests send the UPnP search to a fake router
var string NetTestMode;          // URL option EnhNet=host|find (tests of the network layer)
var float NetLogTime;
var float FriendlyFire;   // 0 = off (default); otherwise the scale of the damage one Shrek does to the other

// The mod's mutator joins the game's own mutator chain.
// Natives of the mod's engine layer (the proxy d3d8.dll, local/shrek2-native); they exist only when that layer is loaded.
native(3500) final function int EnhNativeVersion();
native(3510) final function int EnhHwInfo(int What);
native(3503) final function EnhDrawOffset(int Slot, Actor A, float X, float Y);
native(3504) final function int EnhPrePivotCalib(Actor A);
native(3530) final function int EnhHeroInit(Actor Probe, float X, float Y, float Z, Controller C, Pawn P);
native(3531) final function EnhHeroClear();
native(3532) final function EnhHeroAdd(Actor Hero);
native(3533) final function EnhHeroOwner(Object O, Actor Hero);
native(3534) final function int EnhHeroStats();
native(3535) final function EnhDeaf(PlayerController PC, int On);
native(3541) final function int EnhHeroHost(string Path);
native(3542) final function EnhNetClient(int On);
native(3543) final function string EnhListen();   // the loaded level becomes a listen server: "" or the engine's error (enhnative.c)
native(3536) final function EnhMusicWatch(int On);
native(3537) final function string EnhMusicPoll();

// The effects and creatures the level places for itself (torches, pollen, fire, the gnats) are not replicated: the server sends nothing of them and the client
// has to bring its own copies from the map file, but a client throws away every placed actor that is not "no delete" and not replicated, and these classes
// are not. Their class defaults are set here before a level is loaded (the host's game, and a guest's controller before he travels), so the copies stay.
static function PatchWorldDefaults(Actor Ctx)
{
	if (Ctx == None)
	{
		return;
	}
	Ctx.ConsoleCommand("set ShGame.Env_Torch bNoDelete True");
	Ctx.ConsoleCommand("set ShGame.Pollen_Ambient bNoDelete True");
	Ctx.ConsoleCommand("set ShGame.Small_Fire bNoDelete True");
}

event InitGame(string Options, out string Error)
{
	local string Slot;

	Super.InitGame(Options, Error);
	PatchWorldDefaults(self);
	AddMutator("Enhanced.EnhancedMutator", true);
	bSkipIntroOpt = ParseOption(Options, "EnhSkipIntro") != "";
	EnhNetClient(0);     // a level of this machine's own: its loading screens are drawn again
	IntroOnlyHost = ParseOption(Options, "EnhIntroOnly");
	HopMode = ParseOption(Options, "EnhHop");
	HopMap = ParseOption(Options, "EnhHopMap");
	HopHost = ParseOption(Options, "EnhHopHost");
	bLocalCutOpt = ParseOption(Options, "EnhLocalCut") != "";
	ReadAway(ParseOption(Options, "EnhAway"));
	SaveTestAt = float(ParseOption(Options, "EnhSaveTest"));
	bNoRingOpt = ParseOption(Options, "EnhNoRing") != "";
	bPivotTest = ParseOption(Options, "EnhPivotTest") != "";
	bFpsOpt = ParseOption(Options, "EnhFps") != "";
	bJumpTestOpt = ParseOption(Options, "EnhJumpTest") != "";
	HostMenuAt = float(ParseOption(Options, "EnhHostMenu"));
	HostMenuPage = ParseOption(Options, "EnhHostMenuPage");
	GotoAt = float(ParseOption(Options, "EnhGotoAt"));
	BonusTestAt = float(ParseOption(Options, "EnhBonusAt"));
	BagTestAt = float(ParseOption(Options, "EnhBagTest"));
	ClimbTestAt = float(ParseOption(Options, "EnhClimbTest"));
	CkptTestAt = float(ParseOption(Options, "EnhCkptTest"));
	HudTestAt = float(ParseOption(Options, "EnhHudTest"));
	GotoMap = ParseOption(Options, "EnhGoto");
	if (ParseOption(Options, "EnhCursor") != "")
	{
		CursorTestX = float(Left(ParseOption(Options, "EnhCursor"), InStr(ParseOption(Options, "EnhCursor"), ",")));
		CursorTestY = float(Mid(ParseOption(Options, "EnhCursor"), InStr(ParseOption(Options, "EnhCursor"), ",") + 1));
	}
	bJtGuestOnly = ParseOption(Options, "EnhJumpTest") ~= "guest";
	bJtInput = ParseOption(Options, "EnhJumpTest") ~= "input";
	// off: the PrePivot trick cost the host three quarters of its frame rate (37 to 12 fps in the test); only for experiments (URL option EnhSmooth)
	bNoSmooth = ParseOption(Options, "EnhSmooth") == "";
	bTestOpt = ParseOption(Options, "EnhTest") != "";
	bSubOpt = ParseOption(Options, "EnhSubTest") != "";
	bFFTestOpt = ParseOption(Options, "EnhFFTest") != "";
	bWaitOpt = ParseOption(Options, "EnhWait") != "";
	bTravelTestOpt = ParseOption(Options, "EnhTravelTest") != "";
	if (ParseOption(Options, "FriendlyFire") != "")
	{
		FriendlyFire = float(ParseOption(Options, "FriendlyFire"));
	}
	LobbyMode = ParseOption(Options, "Lobby");
	SessionId = ParseOption(Options, "EnhSession");
	MenuScript = ParseOption(Options, "EnhMenu");
	bMenuDump = ParseOption(Options, "EnhMenuDump") != "";
	bLobbyUpnp = ParseOption(Options, "Upnp") != "";
	NetTestMode = ParseOption(Options, "EnhNet");
	GateTestMode = ParseOption(Options, "EnhGateTest");
	ShotTimes = ParseOption(Options, "EnhShot");
	Log("[SDBG] native layer version " $ string(EnhNativeVersion()));
	Log("[SDBG] hardware: " $ string(EnhHwInfo(0)) $ " logical processors, " $ string(EnhHwInfo(1)) $ " MB RAM, " $ string(EnhHwInfo(2)) $ " MB video memory, display " $ string(EnhHwInfo(3)) $ "x" $ string(EnhHwInfo(4)) $ " at " $ string(EnhHwInfo(5)) $ " Hz");
	Log("[SDBG] renderer now: anisotropy " $ ConsoleCommand("get D3DDrv.D3DRenderDevice LevelOfAnisotropy") $ ", refresh " $ ConsoleCommand("get D3DDrv.D3DRenderDevice DesiredRefreshRate") $ ", cache " $ ConsoleCommand("get Engine.GameEngine CacheSizeMegs") $ " MB");
	bJitterOpt = ParseOption(Options, "EnhJitter") != "";
	DeathTestMode = ParseOption(Options, "EnhDeathTest");
	LeaveTestMode = ParseOption(Options, "EnhLeaveTest");
	bJoinSurveyOpt = ParseOption(Options, "EnhJoinSurvey") != "";
	OffList = "," $ ParseOption(Options, "EnhOff") $ ",";
	bSurveyOpt = ParseOption(Options, "EnhSurvey") != "";
	bProbeOpt = ParseOption(Options, "EnhProbe") != "";
	HostTurnAt = float(ParseOption(Options, "EnhHostTurn"));
	ExpectedPlayers = int(ParseOption(Options, "EnhPlayers"));
	UpnpTarget = ParseOption(Options, "EnhUpnpTarget");
	Slot = ParseOption(Options, "EnhLoad");
	if (Slot != "")
	{
		LoadRecord = new(None, Slot) Class'Enhanced.EnhancedSaveData';
		bLoading = LoadRecord.Map != "";
		Log("[SDBG] load: option EnhLoad=" $ Slot $ " record map='" $ LoadRecord.Map $ "' keys=" $ string(LoadRecord.Keys.Length)
			$ " state=" $ LoadRecord.GameState $ " usable=" $ string(bLoading));
	}
	Log("Enhanced: mutator added, base mutator is " $ string(BaseMutator));
}

event PostBeginPlay()
{
	Super.PostBeginPlay();
	Log("Enhanced: EnhancedGame is running, NetMode=" $ string(Level.NetMode));
	Ticker = Spawn(Class'Enhanced.EnhancedTicker');
	Ticker.G = self;
	Dbg = Spawn(Class'Enhanced.EnhancedDebug');
	if (bTestOpt)
	{
		Dbg.EnableTests();
	}
	Dbg.bSubTest = bSubOpt;
	Dbg.bFFTest = bFFTestOpt;
	Dbg.bTravelTest = bTravelTestOpt;
	if (!IsMenuLevel())
	{
		LobbyMode = "";
	}
	if (LobbyMode == "host")
	{
		StartHostLobby();
	}
	else if (NetTestMode == "upnp" || NetTestMode == "upnpmap")
	{
		Upnp = Spawn(Class'Enhanced.EnhancedUpnp');
		if (NetTestMode == "upnp")
		{
			Upnp.Start(0, UpnpTarget);
		}
		else
		{
			Upnp.Start(7777, UpnpTarget);
		}
	}
	else if (NetTestMode != "")
	{
		Beacon = Spawn(Class'Enhanced.EnhancedLanBeacon');
		if (NetTestMode == "host")
		{
			Beacon.StartHost("7777|TestHost|" $ MapName() $ "|1|2|test");
		}
		else
		{
			Beacon.StartSearch();
		}
	}

}

// With other players in the world, one player's window losing focus (or his pause menu) must not freeze the shared world. A single-player game
// pauses as the original does: the pause menu's book is placed for a camera that stands still while the game is paused; without the pause the camera
// kept following the hero, the book was behind it and the menu showed only the wooden board (while the world went on and the HUD stayed hidden).
function bool SetPause(bool bPause, PlayerController P)
{
	// a test guest alone in his opening (scripted input or pictures): the stock pause of a minimised window (ShrekController.ShowMininized) held his
	// opening for good, the test window is never restored (run lc9: the host waited 240 s). A player's own window pauses as in the stock game.
	if (IntroOnlyHost != "" && bPause && (Class'Enhanced.EnhancedPlayerController'.default.bTestBot || Class'Enhanced.EnhancedPlayerController'.default.bTestShots))
	{
		Log("[SDBG] Enhanced: pause request ignored in a test guest's opening");
		return false;
	}
	if ((Level.NetMode == NM_Standalone && !Off("nopause")) || Off("allowpause"))   // nopause: tests (the quiet test windows are never focused and the engine pauses them)
	{
		return Super.SetPause(bPause, P);
	}
	Log("Enhanced: pause request ignored, pause=" $ string(bPause));
	return false;
}

function T(string S)
{
	if (Dbg != None)
	{
		Dbg.Out("login: " $ S);
	}
	else
	{
		Log("[SDBG] login: " $ S);
	}
}

// Where the level really starts: the first PlayerStart that belongs to the current game state.
// Donkey is found at his cutscene staging spot, far from the playable area.
function bool FindStartSpot(out Vector Spot, out Rotator Rot)
{
	local NavigationPoint N;

	for (N = Level.NavigationPointList; N != None; N = N.nextNavigationPoint)
	{
		if (PlayerStart(N) != None && N.GetPropertyText("bInCurrentGameState") ~= "True")
		{
			Spot = N.Location;
			Rot = N.Rotation;
			T("start spot: " $ string(N) $ " at " $ string(Spot));
			return true;
		}
	}
	T("start spot: none found");
	return false;
}


// ---- Animations of the guests' Shreks ----

// A guest's pawn is driven by the stock hero code through a controller that is not a hero controller, so an animation that ends without a
// follow-up leaves the model in its reference pose (the T pose). Every half second a pawn whose animation channel is idle (not dying, not hidden)
// is given its idle loop again. The animation state is replicated to the other machines (bReplicateAnimations), so everybody sees the loop.
// The engine's own locomotion animation (bPhysicsAnimUpdate) does not run for a guest's pawn: while he ran at full speed his channel-0
// animation stayed a one-shot "lookaround" at a rate of 0.3, on the host's screen and on his own. The run animation is chosen here from the
// velocity against his facing (MovementAnims: forward, back, left, right) and its rate follows the speed; when he stops the idle loop returns.
function bool Off(string K)
{
	return InStr(OffList, "," $ K $ ",") >= 0;
}

function EnsureAnimSync()
{
	local int i;

	if (AnimSync == None && !Off("sync") && Level.NetMode == NM_ListenServer && !IsMenuLevel() && HostController() != None)
	{
		AnimSync = Spawn(Class'Enhanced.EnhancedAnimSync');
		T("animation sync: " $ string(AnimSync));
	}
	if (WorldSync[0] == None && !Off("world") && Level.NetMode == NM_ListenServer && !IsMenuLevel() && HostController() != None)
	{
		for (i = 0; i < 4; i++)
		{
			WorldSync[i] = Spawn(Class'Enhanced.EnhancedWorldSync');
			if (WorldSync[i] != None)
			{
				WorldSync[i].Part = i;
			}
		}
		T("world sync: " $ string(WorldSync[0]) $ " x 4");
	}
}

// ---- The host's music for the guests ----
// Music plays on the machine whose script calls PlayMusic: every change of the level's music (a fight, a potion, a trigger) was heard by the host only.
// The engine layer watches the host's audio (enhnative.c "The host's music") and every change goes to the guests, except to one who plays his own
// cutscene (it has its own music; he gets the host's song when he is back, see SendHostSong). ?EnhOff=music switches it off.
function MusicTick()
{
	local string S, R;
	local int i, Kind, Handle;

	if (Off("music") || Level.NetMode != NM_ListenServer || IsMenuLevel())
	{
		return;
	}
	if (GPC.Length == 0)
	{
		EnhMusicWatch(0);
		return;
	}
	EnhMusicWatch(1);
	for (i = 0; i < 8; i++)
	{
		S = EnhMusicPoll();
		if (S == "")
		{
			break;
		}
		R = S;
		Kind = int(NextBar(R));
		Handle = int(NextBar(R));
		if (Kind == 1)
		{
			HostSongCmd = S;
			HostSongHandle = Handle;
		}
		else if (Kind == 3 || (Kind == 2 && Handle == HostSongHandle))
		{
			HostSongCmd = "";
		}
		if (MusicLogs < 30)
		{
			MusicLogs++;
			T("music: " $ S);
		}
		SendMusic(S);
	}
}

function string NextBar(out string S)
{
	local int P;
	local string R;

	P = InStr(S, "|");
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

function SendMusic(string S)
{
	local int i;
	local EnhancedPlayerController PC;

	for (i = 0; i < GPC.Length; i++)
	{
		PC = EnhancedPlayerController(GPC[i]);
		if (PC != None && !PC.bLocalCutBusy)
		{
			PC.ClientMusic(S);
		}
	}
}

// the host's song now, for one guest (he came in, or came back from his own cutscene)
function SendHostSong(EnhancedPlayerController PC)
{
	if (PC == None || Off("music"))
	{
		return;
	}
	PC.ClientMusic("3|0|0.5|0|");
	if (HostSongCmd != "")
	{
		PC.ClientMusic(HostSongCmd);
	}
}

// ---- Several heroes ----
// The stock game reads LevelInfo.PlayerHeroActor, the host's hero, in about 1400 places: enemies fight only him, traps, fairies, pick-ups, bosses and
// triggers know only him, and the guests were invisible to all of it. The engine layer now answers that read with the hero who belongs to the code
// asking (the nearest hero for an enemy or a trap, the player's own hero for his controller, HUD and camera; see enhnative.c "Several heroes"). Here the
// lists are filled every frame: the heroes that can be fought (on their feet, not hidden) and the objects that belong to a player. Nothing is listed while
// the host plays alone, so a single-player game reads the real value everywhere. ?EnhOff=heroes switches it off.
function HeroTick()
{
	local PlayerController Host;
	local EnhancedCam Probe;
	local KWPawn P;
	local int i, n;

	if (Off("heroes") || Level.NetMode != NM_ListenServer || IsMenuLevel())
	{
		return;
	}
	Host = HostController();
	if (!bHeroInit && Host != None && Host.Pawn != None)
	{
		bHeroInit = true;
		Probe = Spawn(Class'Enhanced.EnhancedCam',,, Host.Pawn.Location + vect(0.0, 0.0, 300.0));
		if (Probe != None)
		{
			HeroInitOk = EnhHeroInit(Probe, Probe.Location.X, Probe.Location.Y, Probe.Location.Z, Host, Host.Pawn);
			Probe.Destroy();
		}
		if (HeroInitOk == 1)
		{
			HeroHostList();
		}
		T("several heroes: engine hook " $ string(HeroInitOk == 1));
	}
	EnhHeroClear();
	// while the host's hero is in a cutscene (the cutscene's controller has him, the host's controller has no pawn) every read gets the real value, as in
	// the stock game: the creatures and enemies check "is the hero in a cutscene" through it
	if (HeroInitOk != 1 || GPC.Length == 0 || Host == None || Host.Pawn == None)
	{
		return;
	}
	// what belongs to the host: his controller, his HUD, his camera and its target; and the game itself and the level (the stock
	// KWGame.GetHeroController finds "the" hero controller through Level.PlayerHeroActor, and 63 places rely on it being the host's)
	EnhHeroOwner(Self, Host.Pawn);
	EnhHeroOwner(Level, Host.Pawn);
	EnhHeroOwner(Host, Host.Pawn);
	EnhHeroOwner(Host.myHUD, Host.Pawn);
	if (KWHeroController(Host) != None && KWHeroController(Host).Camera != None)
	{
		EnhHeroOwner(KWHeroController(Host).Camera, Host.Pawn);
		EnhHeroOwner(KWHeroController(Host).Camera.CamTarget, Host.Pawn);
	}
	if (HeroUsable(Host.Pawn))
	{
		EnhHeroAdd(Host.Pawn);
		n++;
	}
	for (i = 0; i < GPC.Length; i++)
	{
		P = None;
		if (i < GPawn.Length)
		{
			P = GPawn[i];
		}
		if (GPC[i] != None)
		{
			EnhHeroOwner(GPC[i], P);
		}
		if (HeroUsable(P))
		{
			EnhHeroAdd(P);
			n++;
		}
	}
	if (Level.TimeSeconds - HeroStatsAt > 20.0)
	{
		HeroStatsAt = Level.TimeSeconds;
		T("several heroes: " $ string(n) $ " heroes listed, " $ string(EnhHeroStats()) $ " reads answered with another hero since the last line");
	}
	MirrorBoss(Host);
	if (Level.TimeSeconds - HeroSanityAt > 1.0)
	{
		HeroSanityAt = Level.TimeSeconds;
		RecountCombatants(Host);
	}
}

// A boss knows the heroes through KWPawn.aBoss, which the stock game sets on its one hero (the boss trigger, the boss meter) and clears there when the
// boss is beaten. With several heroes it was set on one of them only, and the bosses (BossFGM.WhatToDo, BossPib.WhatToDo, the bandit and fat knight
// controllers) stood idle while a hero without it was the nearest. Every hero gets the same boss: a change on any of them (set or cleared) goes to all.
function MirrorBoss(PlayerController Host)
{
	local int i;
	local Actor Cur;
	local KWPawn H;

	Cur = BossNow;
	for (i = -1; i < GPawn.Length; i++)
	{
		if (i < 0)
		{
			H = KWPawn(Host.Pawn);
		}
		else
		{
			H = GPawn[i];
		}
		if (H != None && H.aBoss != BossNow)
		{
			Cur = H.aBoss;
			break;
		}
	}
	if (Cur != None && Cur.bDeleteMe)
	{
		Cur = None;
	}
	if (Cur != BossNow)
	{
		T("boss: " $ string(BossNow) $ " -> " $ string(Cur) $ " for every hero");
	}
	BossNow = Cur;
	for (i = -1; i < GPawn.Length; i++)
	{
		if (i < 0)
		{
			H = KWPawn(Host.Pawn);
		}
		else
		{
			H = GPawn[i];
		}
		if (H != None && H.aBoss != BossNow)
		{
			H.aBoss = KWPawn(BossNow);
		}
	}
}

// Each hero counts the enemies fighting him (numCombatants: the stock limit of how many attack at once, 2). An enemy counts itself in on the hero it
// fights and out on whichever hero is the nearest when it stops; with several heroes one count grew for good and every enemy aiming at that hero went to
// cheer instead (CombatController.TooManyCombatants). The counts are made again every second: the enemies coming at or fighting a hero, by the nearest hero.
function RecountCombatants(PlayerController Host)
{
	local Controller C;
	local array<Pawn> Heroes;
	local array<int> Count;
	local int i, Best;
	local float D, BestD;

	if (HeroUsable(Host.Pawn))
	{
		Heroes[Heroes.Length] = Host.Pawn;
	}
	for (i = 0; i < GPawn.Length; i++)
	{
		if (HeroUsable(GPawn[i]))
		{
			Heroes[Heroes.Length] = GPawn[i];
		}
	}
	if (Heroes.Length < 2)
	{
		return;
	}
	Count.Length = Heroes.Length;
	for (C = Level.ControllerList; C != None; C = C.NextController)
	{
		if (C.Pawn == None || !C.Pawn.IsA('ShEnemy') || !(C.IsInState('MoveTowardHero') || C.IsInState('AttackHero') || C.IsInState('MoveTowardPile')))
		{
			continue;
		}
		Best = -1;
		for (i = 0; i < Heroes.Length; i++)
		{
			D = VSize(Heroes[i].Location - C.Pawn.Location);
			if (Best < 0 || D < BestD)
			{
				Best = i;
				BestD = D;
			}
		}
		Count[Best] = Count[Best] + 1;
	}
	for (i = 0; i < Heroes.Length; i++)
	{
		if (Heroes[i].GetPropertyText("numCombatants") != "" && int(Heroes[i].GetPropertyText("numCombatants")) != Count[i])
		{
			Heroes[i].SetPropertyText("numCombatants", string(Count[i]));
		}
	}
}

// The stock code that reads the hero only to reach the host's controller, HUD, camera, menus, movies or the shared purse keeps reading the host's
// hero under the several-heroes hook (classes first, then functions). Made by tools/hostfuncs.py from the decompiled scripts (the functions that use
// the hero only through .Controller or the HUD), plus the mixed ones decided by hand: the boss meter (the host's HUD shows it, the mod mirrors it to the
// guests), the potions' effects, movies, the purse (coins and money bags, the bonus-coin count), potion and poster pick-ups (the host's menus).
// Then from the review of every read (local/scratch/audit/review-heroes.md): the save points and fairies (a save through a guest's hero saved nothing and
// used the fairy up), the bonus coin game (its end timer went to a guest's missing HUD: players were stuck in the bonus level), the potions, the shops,
// the companions and their talk, movies, credits, the cutscene objects and the cutscene exit command that switches the host's hero.
function HeroHostList()
{
	EnhHeroHost("KWGame.KWHudItem");
	EnhHeroHost("KWGame.SavePoint");
	EnhHeroHost("SHGame.SHSavePoint");
	EnhHeroHost("SHGame.SavePointFairy");
	EnhHeroHost("SHGame.SavePointFairycontroller");
	EnhHeroHost("SHGame.SaveTimer");
	EnhHeroHost("SHGame.bonusLevelTransferTimer");
	EnhHeroHost("SHGame.SHSmartStart");
	EnhHeroHost("SHGame.CoinBonusGame");
	EnhHeroHost("SHGame.PotionBottles");
	EnhHeroHost("SHGame.ThrownPotion");
	EnhHeroHost("SHGame.PotionTimer");
	EnhHeroHost("SHGame.StaySmallTrigger");
	EnhHeroHost("SHGame.StrengthPotionMgr");
	EnhHeroHost("SHGame.BumpLineSpeaker");
	EnhHeroHost("SHGame.DriveThrough");
	EnhHeroHost("SHGame.SlotMachine");
	EnhHeroHost("SHGame.VendingWitchcontroller");
	EnhHeroHost("SHGame.SHCompanionController");
	EnhHeroHost("KWGame.CompanionCombatManager");
	EnhHeroHost("KWGame.KWInterestManager");
	EnhHeroHost("KWGame.ResolutionBasedMovieTrigger");
	EnhHeroHost("SHGame.CreditsTrigger");
	EnhHeroHost("SHGame.SHMenuBook");
	EnhHeroHost("SHGame.CrossHairActor");
	EnhHeroHost("KWGame.KWCutScene");
	EnhHeroHost("KWGame.KWCutController");
	EnhHeroHost("KWGame.KWPawn.OnCutExitCommand");
	EnhHeroHost("SHGame.Shrek.PostLoadGame");
	EnhHeroHost("KWGame.KWAIController.DoBumpLine");
	EnhHeroHost("KWGame.KWAIController.DoingBumpLine.Timer");
	EnhHeroHost("KWGame.KWHud");
	EnhHeroHost("KWGame.BaseCam");
	EnhHeroHost("KWGame.BaseCamTarget");
	EnhHeroHost("KWGame.SelectCursor");
	EnhHeroHost("KWGame.FadeViewDelegate");
	EnhHeroHost("KWGame.FOVController");
	EnhHeroHost("KWGame.MovieTrigger");
	EnhHeroHost("SHGame.SHMovieManager");
	EnhHeroHost("KWGame.PopupTrigger");
	EnhHeroHost("KWGame.KWMiniGame");
	EnhHeroHost("KWGame.KWHeroController.StopMoviePlayback");
	EnhHeroHost("KWGame.KWHeroController.EscHandler");
	EnhHeroHost("KWGame.KWMiniGame.AddScore");
	EnhHeroHost("KWGame.KWMiniGame.WaitingForMiniGameStart.InitMiniGame");
	EnhHeroHost("KWGame.KWMiniGame.PlayingMiniGame.BeginState");
	EnhHeroHost("KWGame.KWMiniGame.EndMiniGame.BeginState");
	EnhHeroHost("KWGame.KWPawn.KWGetWorldLoc");
	EnhHeroHost("KWGame.MovieTrigger.Activate");
	EnhHeroHost("KWGame.PopupTrigger.StatePopUp.Tick");
	EnhHeroHost("KWGame.TelePit.Activate");
	EnhHeroHost("KWGame.TelePit.stateFadeIn.BeginState");
	EnhHeroHost("KWGame.TelePit.stateFadeIn.EndState");
	EnhHeroHost("SHGame.AppleTree.ShakeTheGround");
	EnhHeroHost("SHGame.Batcontroller.AvoidActor.FlyFromActor");
	EnhHeroHost("SHGame.CatapultController.LaunchCatapult.CatapultLaunchRelease");
	EnhHeroHost("SHGame.CoinBonusGame.WaitforGameStart.Tick");
	EnhHeroHost("SHGame.CoinBonusGame.PlayMiniGame.Timer");
	EnhHeroHost("SHGame.CreditsTrigger.Activate");
	EnhHeroHost("SHGame.DriveThrough.ActivateVendor");
	EnhHeroHost("SHGame.DriveThrough.DriveThroughIdle.Timer");
	EnhHeroHost("SHGame.HudItemPotion.GetCount");
	EnhHeroHost("SHGame.HudItemPotion.DrawHudItem");
	EnhHeroHost("SHGame.PotionTimer.WaitforGameStart.Tick");
	EnhHeroHost("SHGame.PotionTimer.PlayMiniGame.Timer");
	EnhHeroHost("SHGame.SHHudItem.DrawCount");
	EnhHeroHost("SHGame.SHHudPotionTimer.PostLoadGame");
	EnhHeroHost("SHGame.SHHudPotionTimer.SHHudTimerActive.Tick");
	EnhHeroHost("SHGame.SHMenuBook.OpenBook");
	EnhHeroHost("SHGame.SHSavePoint.OnSaveGame");
	EnhHeroHost("SHGame.ShHeroPawn.TravelPreAccept");
	EnhHeroHost("SHGame.SlotMachine.TakeDamage");
	EnhHeroHost("SHGame.SlotMachine.SlotMachineInactive");
	EnhHeroHost("SHGame.SlotMachine.SlotMashineAccept.ShowSlotMachineAcceptanceMenu");
	EnhHeroHost("SHGame.SlotMachine.SlotMachineTakeCoins.CoinWorldLocationFromScreen");
	EnhHeroHost("SHGame.SlotMachine.SlotMachineTakeCoins.Tick");
	EnhHeroHost("SHGame.StaySmallTrigger.Activate");
	EnhHeroHost("SHGame.ThrownPotion.BlowUp");
	EnhHeroHost("SHGame.VendingWitchcontroller.WonSpin");
	EnhHeroHost("Engine.Actor.CM");
	EnhHeroHost("Engine.NavigationPoint.DrawLines");
	EnhHeroHost("SHGame.EnemyBoss.StartBossMeter");
	EnhHeroHost("SHGame.EnemyBoss.StopBossMeter");
	EnhHeroHost("SHGame.PotionBottles.BlowUp");
	EnhHeroHost("SHGame.SHMovieManager.Trigger");
	EnhHeroHost("KWGame.ResolutionBasedMovieTrigger.Activate");
	EnhHeroHost("SHGame.Coin.AnnouncePickup");
	EnhHeroHost("SHGame.CoinStack.AnnouncePickup");
	EnhHeroHost("SHGame.MoneyBag.AnnouncePickup");
	EnhHeroHost("SHGame.MicePotionStrong.AnnouncePickup");
	EnhHeroHost("SHGame.MicePotionWeak.AnnouncePickup");
	EnhHeroHost("SHGame.PixiePotionStrong.AnnouncePickup");
	EnhHeroHost("SHGame.PixiePotionWeak.AnnouncePickup");
	EnhHeroHost("SHGame.StrengthPotion.AnnouncePickup");
	EnhHeroHost("SHGame.CoinBonusGame.TimesUp.EndThisState");
	EnhHeroHost("SHGame.SlotMachine.SlotMashineIdle.Timer");
	EnhHeroHost("SHGame.ShrekPoster.AnnouncePickup");
	EnhHeroHost("SHGame.ShrekPoster2sh.AnnouncePickup");
	EnhHeroHost("SHGame.ShrekPoster3sh.AnnouncePickup");
	EnhHeroHost("SHGame.ShrekPoster4sh.AnnouncePickup");
	EnhHeroHost("SHGame.ShrekPoster5sh.AnnouncePickup");
	EnhHeroHost("SHGame.ShrekPoster6sh.AnnouncePickup");
	EnhHeroHost("SHGame.ShrekPoster7sh.AnnouncePickup");
	EnhHeroHost("SHGame.ShrekPoster8sh.AnnouncePickup");
	EnhHeroHost("SHGame.ShrekPoster9sh.AnnouncePickup");
	EnhHeroHost("SHGame.ShrekPoster10sh.AnnouncePickup");
	EnhHeroHost("SHGame.ShrekPoster11sh.AnnouncePickup");
	EnhHeroHost("SHGame.ShrekPoster12sh.AnnouncePickup");
}

function bool HeroUsable(Pawn P)
{
	return P != None && !P.bDeleteMe && !P.bHidden && !P.IsInState('stateHeroDying') && float(P.GetPropertyText("Health")) > 0.0;
}

// ---- The opening of a level: each guest plays it in his own game, then joins ----
// Owner's rule: the opening cutscene of a level runs on every player's machine as in the single-player game, and a guest joins the host only when his
// is over. A level change of the host (the lobby's start, a level exit) sends each guest to the new level ALONE first (ClientIntroFirst): he loads it
// as a single-player game with ?EnhIntroOnly=<host>, the stock opening plays exactly as it does for one player (its events, its moves, its camera),
// he can skip it as in the stock game, and then he connects to the host with ?EnhIntroDone=<level>; his hero comes into the host's world where the
// host's hero stands after the opening (IntroEnd), even if the host still watches his. A guest who comes into a level later plays its opening the
// same way first. The cutscenes in the middle of a level are seen through the host's camera. ?EnhOff=introfirst: the guests follow the host directly.
function ProcessServerTravel(string URL, bool bItems)
{
	local PlayerController P, LocalPlayer;
	local bool bIntro;
	local string M, Away;

	// a guest alone in the opening: a level change of his own game (a cutscene-only level ends with one) means the opening is over: he joins the host
	if (IntroOnlyHost != "")
	{
		JoinHostAfterIntro("the opening changes the level");
		return;
	}
	M = UrlMap(URL);
	bIntro = Level.NetMode == NM_ListenServer && !Off("introfirst") && HasOpening(M) && InStr(URL, "EnhLoad=") < 0 && InStr(URL, "EnhSkipIntro=1") < 0;
	BaseMutator.ServerTraveling(URL, bItems);
	Log("ProcessServerTravel: " $ URL $ " (guests play the opening first: " $ string(bIntro) $ ")");
	foreach DynamicActors(Class'Engine.PlayerController', P)
	{
		if (NetConnection(P.Player) != None)
		{
			if (bIntro && EnhancedPlayerController(P) != None)
			{
				T("travel: " $ P.PlayerReplicationInfo.PlayerName $ " plays the opening of " $ M $ " by himself first");
				EnhancedPlayerController(P).ClientIntroFirst(M);
				if (Away != "")
				{
					Away = Away $ ".";
				}
				Away = Away $ Class'Enhanced.EnhancedText'.static.Encode(P.PlayerReplicationInfo.PlayerName);
			}
			else
			{
				P.ClientTravel(URL, TRAVEL_Relative, bItems);
			}
			continue;
		}
		LocalPlayer = P;
		P.PreClientTravel();
	}
	if (Level.NetMode == NM_ListenServer && LocalPlayer != None)
	{
		Level.NextURL = Level.NextURL $ "?Team=" $ LocalPlayer.GetDefaultURL("Team") $ "?Name=" $ LocalPlayer.GetDefaultURL("Name") $ "?Class=" $ LocalPlayer.GetDefaultURL("Class") $ "?Character=" $ LocalPlayer.GetDefaultURL("Character");
	}
	// the new level waits for these guests once the host's opening is over (always named: an old URL's options are kept unless the new one names them)
	if (Level.NetMode == NM_ListenServer)
	{
		Level.NextURL = Level.NextURL $ "?EnhAway=" $ Away;
	}
	if (Level.NetMode != NM_DedicatedServer && Level.NetMode != NM_ListenServer)
	{
		Level.NextSwitchCountdown = 0.0;
	}
}

function bool WentForIntro(string Nick)
{
	local int i;

	for (i = 0; i < AwayForIntro.Length; i++)
	{
		if (AwayForIntro[i] == Nick)
		{
			AwayForIntro.Remove(i, 1);
			return true;
		}
	}
	return false;
}

// ---- The host waits for the guests who still play the opening ----
// Owner's rule: while a guest still plays a level's opening in his own game, the host whose opening is over waits for him: the world is paused (for
// the guests already in it as well) and they read "wait for <name>: he is still watching the opening". The pause ends when every guest sent away
// is back (Login with EnhIntroDone), or after four minutes without news (a guest whose game was closed meanwhile never comes back).
// The names come with a level change (?EnhAway, hex-coded, dot-separated) or from PostLogin (a late guest sent to the opening).
function ReadAway(string S)
{
	local int k;
	local string N;

	IntroWait.Length = 0;
	while (S != "")
	{
		k = InStr(S, ".");
		if (k < 0)
		{
			N = S;
			S = "";
		}
		else
		{
			N = Left(S, k);
			S = Mid(S, k + 1);
		}
		if (N != "")
		{
			IntroAway(Class'Enhanced.EnhancedText'.static.Decode(N));
		}
	}
}

function IntroAway(string Nick)
{
	local int i;

	IntroWaitClock = 0.0;
	for (i = 0; i < IntroWait.Length; i++)
	{
		if (IntroWait[i] == Nick)
		{
			return;
		}
	}
	IntroWait[IntroWait.Length] = Nick;
	T("intro wait: " $ Nick $ " plays the opening by himself, the world waits for him once the host's opening is over");
}

function IntroBack(string Nick)
{
	local int i;

	if (IntroWait.Length == 0)
	{
		return;
	}
	for (i = 0; i < IntroWait.Length; i++)
	{
		if (IntroWait[i] == Nick)
		{
			IntroWait.Remove(i, 1);
			T("intro wait: " $ Nick $ " is back, still waited for: " $ string(IntroWait.Length));
			return;
		}
	}
	// back under another name: one of the waited is back all the same
	T("intro wait: " $ Nick $ " is back (not on the list, " $ IntroWait[0] $ " is taken off it)");
	IntroWait.Remove(0, 1);
}

function string IntroWaitNames()
{
	local int i;
	local string S;

	for (i = 0; i < IntroWait.Length; i++)
	{
		if (i > 0)
		{
			S = S $ ", ";
		}
		S = S $ IntroWait[i];
	}
	return S;
}

// Every frame (EnhancedTicker, which ticks also while the world is paused).
function IntroWaitTick(float DeltaTime)
{
	local PlayerController Host;
	local Controller C;
	local bool bWait;
	local string S, E;

	if (IntroWait.Length == 0 && !bIntroPaused)
	{
		return;
	}
	IntroWaitClock += DeltaTime;
	if (Level.NetMode != NM_ListenServer || Off("introwait"))
	{
		IntroWait.Length = 0;
	}
	else if (IntroWait.Length > 0 && IntroWaitClock > 240.0)
	{
		T("intro wait: " $ IntroWaitNames() $ " did not come back in 240 s, the game goes on");
		IntroWait.Length = 0;
	}
	Host = HostController();
	// The host's own opening comes first: at the level's start no cutscene runs yet, and the world was paused before the host's opening had begun (owner's
	// log of 2026-11-21: paused at t=0.5, the host's opening played only after the guest was back). Over = a cutscene of the host has started and ended,
	// or the level has no opening, or none began within eight seconds.
	if (!bHostOpeningSeen && IntroWait.Length > 0)
	{
		if (CutSerial > 0 && ActiveCut == None)
		{
			bHostOpeningSeen = true;
			T("intro wait: the host's opening is over");
		}
		else if (!HasOpening(MapName()) || ShouldSkipIntro())
		{
			bHostOpeningSeen = true;
			T("intro wait: the level has no opening for the host");
		}
		else if (CutSerial == 0 && Level.TimeSeconds > 8.0)
		{
			bHostOpeningSeen = true;
			T("intro wait: no opening began on the host within 8 s");
		}
	}
	bWait = IntroWait.Length > 0 && bHostOpeningSeen && Host != None && Host.Pawn != None && Host.PlayerReplicationInfo != None && ActiveCut == None && !bRestarting && !IsMenuLevel() && !IsCutsceneLevel();
	if (bWait && !bIntroPaused)
	{
		bIntroPaused = true;
		IntroPausedAt = IntroWaitClock;
		Level.Pauser = Host.PlayerReplicationInfo;
		Level.PauseDelay = Level.TimeSeconds;   // paused at once; the stock big "paused" line is left out (the note says it)
		T("intro wait: the host's opening is over, the world is paused for " $ IntroWaitNames());
	}
	else if (!bWait && bIntroPaused)
	{
		StopIntroWait();
		return;
	}
	if (!bIntroPaused)
	{
		return;
	}
	if (IntroWait.Length == 1)
	{
		S = FillName(Localize("Lobby", "IntroWait1", "Enhanced"), IntroWaitNames());
	}
	else
	{
		S = FillName(Localize("Lobby", "IntroWaitN", "Enhanced"), IntroWaitNames());
	}
	if (S != IntroWaitNote)
	{
		IntroWaitNote = S;
		E = Class'Enhanced.EnhancedText'.static.Encode(S);
		for (C = Level.ControllerList; C != None; C = C.NextController)
		{
			if (EnhancedPlayerController(C) != None)
			{
				EnhancedPlayerController(C).WaitNote = E;
			}
		}
	}
	// tests: one picture of the waiting host, three seconds into the pause (the level's clock stands still, EnhShot's times do not come)
	if (ShotTimes != "" && !bIntroShot && IntroWaitClock - IntroPausedAt > 3.0)
	{
		bIntroShot = true;
		Host.ConsoleCommand("shot");
		T("intro wait: shot taken during the pause");
	}
}

function StopIntroWait()
{
	local Controller C;

	T("intro wait: the pause ends after " $ string(int(IntroWaitClock - IntroPausedAt)) $ " s, still away: " $ string(IntroWait.Length));
	bIntroPaused = false;
	IntroWaitNote = "";
	if (Level.Pauser != None)
	{
		Level.Pauser = None;
	}
	for (C = Level.ControllerList; C != None; C = C.NextController)
	{
		if (EnhancedPlayerController(C) != None)
		{
			EnhancedPlayerController(C).WaitNote = "";
		}
	}
}

function string UrlMap(string URL)
{
	local int P;

	P = InStr(URL, "?");
	if (P >= 0)
	{
		URL = Left(URL, P);
	}
	P = InStr(Caps(URL), ".UNR");
	if (P >= 0)
	{
		URL = Left(URL, P);
	}
	return URL;
}

function bool HasOpening(string M)
{
	local int i;

	for (i = 0; i < OpeningMaps.Length; i++)
	{
		if (OpeningMaps[i] ~= M)
		{
			return true;
		}
	}
	return false;
}

// a guest alone in the level's opening: when it is over (no cutscene runs and his hero is his again) he joins the host; a level whose opening never
// begins within eight seconds joins at once
function IntroOnlyTick()
{
	local PlayerController PC;
	local KWCutScene CS;
	local bool bAny;

	if (bIntroJoining)
	{
		return;
	}
	foreach DynamicActors(Class'KWGame.KWCutScene', CS)
	{
		if (CS.bInCutScene)
		{
			bAny = true;
		}
	}
	if (bAny)
	{
		if (!bIntroSeen)
		{
			T("opening: begins on this machine, the host " $ IntroOnlyHost $ " is joined after it");
		}
		bIntroSeen = true;
		IntroQuietSince = 0.0;
		return;
	}
	if (!bIntroSeen && Level.TimeSeconds < 8.0)
	{
		return;
	}
	PC = HostController();
	if (PC == None || PC.Pawn == None)
	{
		return;
	}
	if (IntroQuietSince == 0.0)
	{
		IntroQuietSince = Level.TimeSeconds;
		return;
	}
	if (Level.TimeSeconds - IntroQuietSince > 0.5)
	{
		if (bIntroSeen)
		{
			JoinHostAfterIntro("the opening is over");
		}
		else
		{
			JoinHostAfterIntro("this level has no opening");
		}
	}
}

function JoinHostAfterIntro(string Why)
{
	local PlayerController PC;

	if (bIntroJoining)
	{
		return;
	}
	bIntroJoining = true;
	PC = HostController();
	T("opening: " $ Why $ ", joining the host " $ IntroOnlyHost);
	if (PC != None)
	{
		// the host plays this same level: through the menu book (a level loaded over another copy of itself crashed the engine, see Hop)
		PC.ConsoleCommand("open " $ HopURL("join", MapName(), IntroOnlyHost));
	}
}

// Loading a level over another copy of the same level (the host's swamp -> the guest's own swamp, and back) crashed the engine: it lets go of the old
// level's loader first and then draws the loading screen with that old level (ATerrainInfo::UpdateVertices). The guest goes through the menu book,
// a small level of its own, and from there to where he was going.
static function string HopURL(string Mode, string Map, string Host)
{
	return "Book_FrontEnd.unr?Game=Enhanced.EnhancedGame?EnhIntroOnly=?EnhIntroDone=?EnhHop=" $ Mode $ "?EnhHopMap=" $ Map $ "?EnhHopHost=" $ Host;
}

function HopTick()
{
	local PlayerController PC;

	if (bHopGone)
	{
		return;
	}
	PC = Level.GetLocalPlayerController();
	if (PC == None)
	{
		return;
	}
	bHopGone = true;
	if (HopMode ~= "intro")
	{
		T("hop: on to the opening of " $ HopMap $ " alone, then " $ HopHost);
		PC.ConsoleCommand("open " $ HopMap $ "?Game=Enhanced.EnhancedGame?EnhHop=?EnhHopMap=?EnhHopHost=?EnhIntroDone=?EnhIntroOnly=" $ HopHost);
	}
	else
	{
		T("hop: on to the host " $ HopHost $ " after the opening of " $ HopMap);
		PC.ConsoleCommand("open " $ HopHost $ "?EnhHop=?EnhHopMap=?EnhHopHost=?EnhIntroOnly=?EnhIntroDone=" $ HopMap);
	}
}

// ---- Every player sees the cutscene in his own game ----
// The stock cutscenes run where the game runs, on the host. When one starts there, every guest gets its script and its cast and plays it himself
// (EnhancedPlayerController.StartLocalCut): his own camera, sound, subtitles and pace, skippable. His Shrek stays hidden until he says he is back
// (ServerLocalCutDone); then it appears next to the host, in the host's world as it is by then. A guest who comes in while a cutscene plays gets it too,
// from its start. ?EnhOff=localcut: the old way (the guests watch the host's camera).
function WatchCutscenes()
{
	local KWCutScene CS;
	local int i;
	local EnhancedPlayerController PC;

	if (Off("localcut") || Level.NetMode != NM_ListenServer || IsMenuLevel())
	{
		return;
	}
	if (CutList.Length == 0 || Level.TimeSeconds - CutListAt > 10.0)
	{
		CutListAt = Level.TimeSeconds;
		CutList.Length = 0;
		foreach DynamicActors(Class'KWGame.KWCutScene', CS)
		{
			if (EnhancedLocalCut(CS) == None)
			{
				CutList[CutList.Length] = CS;
			}
		}
	}
	if (ActiveCut != None && (ActiveCut.bDeleteMe || !ActiveCut.bInCutScene))
	{
		T("cutscene " $ ActiveCut.ScriptFileName $ " is over on the host after " $ string(int(Level.TimeSeconds - ActiveCutStart)) $ " s");
		for (i = 0; i < GPC.Length; i++)
		{
			PC = EnhancedPlayerController(GPC[i]);
			if (PC != None && PC.LocalCutSent == CutSerial)
			{
				PC.ClientCutHostEnded(CutSerial, Level.TimeSeconds - ActiveCutStart);
			}
		}
		ActiveCut = None;
		bPullAfterCut = true;
	}
	if (bPullAfterCut && HostController() != None && HostController().Pawn != None)
	{
		bPullAfterCut = false;
		PullGuestsToHost(HostController());
	}
	if (ActiveCut == None)
	{
		for (i = 0; i < CutList.Length; i++)
		{
			if (CutList[i] != None && CutList[i].bInCutScene)
			{
				ActiveCut = CutList[i];
				ActiveCutStart = Level.TimeSeconds;
				CutSerial++;
				NoteCutStartPlace();
				T("cutscene " $ ActiveCut.ScriptFileName $ " starts on the host (number " $ string(CutSerial) $ ")");
				break;
			}
		}
	}
	for (i = 0; i < GPC.Length; i++)
	{
		PC = EnhancedPlayerController(GPC[i]);
		if (PC == None)
		{
			continue;
		}
		if (bLocalCutOpt && ActiveCut != None && PC.LocalCutSent != CutSerial && PC.Player != None && PC.PlayerReplicationInfo != None)
		{
			SendLocalCut(PC);
		}
		// a guest who never answers (his game is stuck, or he has an old build) is not waited for longer than ten minutes
		if (PC.bLocalCutBusy && Level.TimeSeconds - PC.LocalCutBusySince > 600.0)
		{
			T("cutscene: " $ PC.PlayerReplicationInfo.PlayerName $ " did not come back from his cutscene, his Shrek is shown anyway");
			PC.bLocalCutBusy = false;
			EnhDeaf(PC, 0);
			SendHostSong(PC);
		}
	}
}

// where the host's hero stands as the host's cutscene begins (see HostPlace): the level's start for an opening, else his place
function bool IntroEndFor(out Vector V)
{
	local int i, P;
	local string S, M;

	M = MapName();
	for (i = 0; i < IntroEnd.Length; i++)
	{
		P = InStr(IntroEnd[i], "=");
		if (P > 0 && Left(IntroEnd[i], P) ~= M)
		{
			S = Mid(IntroEnd[i], P + 1);
			V.X = float(NextComma(S));
			V.Y = float(NextComma(S));
			V.Z = float(S);
			return true;
		}
	}
	return false;
}

function string NextComma(out string S)
{
	local int P;
	local string R;

	P = InStr(S, ",");
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

function NoteCutStartPlace()
{
	local Vector Spot;
	local Rotator R;
	local Pawn H;

	bCutStartLoc = false;
	// the opening of a level: where the host will stand after it (the swamp's opening is played at the house, then the level throws the hero to the
	// obstacle course with an event of its own: the level's start spot is the house); a level not in the table: its start spot
	if (Level.TimeSeconds < 8.0 && IntroEndFor(Spot))
	{
		CutStartHeroLoc = Spot;
		bCutStartLoc = true;
	}
	else if (Level.TimeSeconds < 8.0 && FindStartSpot(Spot, R))
	{
		CutStartHeroLoc = Spot;
		bCutStartLoc = true;
	}
	else
	{
		H = HostHero(HostController());
		if (H != None)
		{
			CutStartHeroLoc = H.Location;
			bCutStartLoc = true;
		}
	}
	if (Level.TimeSeconds < 8.0)
	{
		bLevelHadOpening = true;
		OpeningSerial = CutSerial;
	}
	if (bCutStartLoc)
	{
		T("cutscene: the host's hero stands at " $ string(CutStartHeroLoc) $ " as it begins (a guest through his own one early comes in there)");
	}
}

// The host's cutscene is over and the host is in the world again: a guest who came in earlier (through his own cutscene first) and stands far from
// him is put next to him at once (the host's world is the one the guests take; the leash would bring him only after its countdown).
function PullGuestsToHost(PlayerController Host)
{
	local int i, k;
	local Vector Loc;
	local bool bPlaced;
	local float D;

	for (i = 0; i < GPC.Length; i++)
	{
		SelectGuest(i);
		if (P2Pawn != None && !bP2Hidden && VSize(P2Pawn.Location - Host.Pawn.Location) > 3000.0)
		{
			D = VSize(P2Pawn.Location - Host.Pawn.Location);
			ChooseJoinCenter(Host);
			bPlaced = false;
			for (k = 0; k < 40 && !bPlaced; k++)
			{
				if (GuestSpot(Host, k, Loc))
				{
					bPlaced = P2Pawn.SetLocation(Loc);
				}
			}
			if (bPlaced)
			{
				P2Pawn.Velocity = vect(0.0, 0.0, 0.0);
				P2Pawn.SetPhysics(PHYS_Falling);
				PendingPC.ClientSetLocation(P2Pawn.Location, PendingPC.Rotation);
				ChaseRotation(Host);
			}
			T("cutscene over: " $ PendingPC.PlayerReplicationInfo.PlayerName $ " stood " $ string(int(D)) $ " units away, put next to the host: " $ string(bPlaced));
		}
		StoreGuest(i);
	}
}

function SendLocalCut(EnhancedPlayerController PC)
{
	local int j, N;
	local KWCutController CC;
	local Pawn P;

	N = 0;
	for (j = 0; j < ActiveCut.CutControllers.Length; j++)
	{
		CC = ActiveCut.CutControllers[j];
		if (CC == None || CC.Pawn == None)
		{
			continue;
		}
		P = CC.Pawn;
		PC.ClientCutCast(N, CC.pawntag, P.GetPropertyText("Label"), P, string(P.Class), P.Location, P.Rotation);
		N++;
	}
	PC.ClientLocalCut(ActiveCut.ScriptFileName, string(ActiveCut.Tag), N, CutSerial, ActiveCut.bNoBypass);
	PC.LocalCutSent = CutSerial;
	PC.bLocalCutBusy = true;
	EnhDeaf(PC, 1);
	PC.LocalCutBusySince = Level.TimeSeconds;
	T("cutscene " $ ActiveCut.ScriptFileName $ " sent to " $ PC.PlayerReplicationInfo.PlayerName $ " with " $ string(N) $ " actors");
}

function IdleWatch()
{
	local int i;
	local KWPawn P;
	local name A;
	local Rotator R;

	for (i = 0; i < GPawn.Length; i++)
	{
		P = GPawn[i];
		if (P != None && P.Controller != None && !P.IsInState('stateHeroDying') && EnhancedPlayerController(P.Controller) != None && EnhancedPlayerController(P.Controller).bViewSrv)
		{
			// The guest's facing is his camera's yaw (sent by his machine). The stock pawn code turns the pawn towards DesiredRotation
			// (it switches bRotateToDesired on again every few frames), so this is done every tick.
			// The controller's own DesiredRotation (left by the last attack's turn to its target) is copied to the pawn by the engine
			// every frame, so both are set.
			R = P.Rotation;
			R.Yaw = EnhancedPlayerController(P.Controller).ViewYawSrv;
			P.bRotateToDesired = False;
			P.Controller.bRotateToDesired = False;
			P.DesiredRotation = R;
			P.Controller.DesiredRotation = R;
			if ((R.Yaw & 65535) != (P.Rotation.Yaw & 65535))
			{
				P.SetRotation(R);
			}
		}
		if (P != None && !P.bHidden && !P.IsInState('stateHeroDying') && !P.IsAnimating(0))
		{
			A = P.GetIdleAnimName();
			if (A == 'None')
			{
				A = 'idle';
			}
			P.LoopAnim(A, 1.0, 0.2);
			if (IdleFixes < 12)
			{
				IdleFixes++;
				T("animation: guest " $ string(i) $ " had none, the idle loop '" $ string(A) $ "' is started");
			}
		}
	}
}

// ---- Guests (up to three besides the host) ----
// The fields PendingPC, P2Pawn, bP2Hidden, P2DeadSince and CutCam are the state of the guest that is being worked on ("the current guest"); the
// arrays hold the state of all of them. PendingPC / P2Pawn outside a wrapper show the first guest, for the debug dump and the tests.


function int GuestIndex(Controller C)
{
	local int i;

	for (i = 0; i < GPC.Length; i++)
	{
		if (GPC[i] == C)
		{
			return i;
		}
	}
	return -1;
}

function bool IsGuestPC(Controller C)
{
	return GuestIndex(C) >= 0;
}

function AddGuest(PlayerController PC)
{
	GPC[GPC.Length] = PC;
	GPawn[GPawn.Length] = None;
	GHidden[GHidden.Length] = false;
	GDead[GDead.Length] = 0.0;
	GCam[GCam.Length] = None;
	PendingPC = GPC[0];
	P2Pawn = GPawn[0];
	T("guest " $ string(GPC.Length) $ " joined: " $ string(PC));
}

function RemoveGuest(int i)
{
	if (GCam[i] != None)
	{
		GCam[i].Destroy();
	}
	GPC.Remove(i, 1);
	GPawn.Remove(i, 1);
	GHidden.Remove(i, 1);
	GDead.Remove(i, 1);
	GCam.Remove(i, 1);
	MirrorFirst();
}

function MirrorFirst()
{
	PendingPC = None;
	P2Pawn = None;
	bP2Hidden = false;
	if (GPC.Length > 0)
	{
		PendingPC = GPC[0];
		P2Pawn = GPawn[0];
		bP2Hidden = GHidden[0];
	}
}

function SelectGuest(int i)
{
	PendingPC = GPC[i];
	P2Pawn = GPawn[i];
	bP2Hidden = GHidden[i];
	P2DeadSince = GDead[i];
	CutCam = GCam[i];
}

function StoreGuest(int i)
{
	GPawn[i] = P2Pawn;
	GHidden[i] = bP2Hidden;
	GDead[i] = P2DeadSince;
	GCam[i] = CutCam;
}

function ManageSecond()
{
	local int i;

	for (i = 0; i < GPC.Length; i++)
	{
		SelectGuest(i);
		ManageOne();
		StoreGuest(i);
	}
	MirrorFirst();
}

// Every frame: the host's cutscene subtitle goes to the guests' controllers (only when it changes).
function SyncSubs()
{
	local PlayerController Host;
	local EnhancedCutText CT;
	local string T, N, ET, EN;
	local int i;

	Host = HostController();
	if (Host == None || KWHud(Host.myHUD) == None)
	{
		return;
	}
	CT = EnhancedCutText(KWHud(Host.myHUD).CutTextController);
	if (CT == None)
	{
		return;
	}
	T = CT.strText;
	N = CT.SpeakerName;
	if (T == HostNoteText)
	{
		T = "";
		N = "";
	}
	// the codes are worked out only when the line changes (this runs every frame)
	if (T != SubRawT || N != SubRawN)
	{
		SubRawT = T;
		SubRawN = N;
		SubEncT = Class'Enhanced.EnhancedText'.static.Encode(T);
		SubEncN = Class'Enhanced.EnhancedText'.static.Encode(N);
	}
	ET = SubEncT;
	EN = SubEncN;
	for (i = 0; i < GPC.Length; i++)
	{
		if (EnhancedPlayerController(GPC[i]) != None && (EnhancedPlayerController(GPC[i]).SubText != ET || EnhancedPlayerController(GPC[i]).SubName != EN))
		{
			EnhancedPlayerController(GPC[i]).SubText = ET;
			EnhancedPlayerController(GPC[i]).SubName = EN;
			EnhancedPlayerController(GPC[i]).SubColor = CT.SpeakerColor;
		}
	}
}

function MirrorCamera()
{
	local int i;

	for (i = 0; i < GPC.Length; i++)
	{
		SelectGuest(i);
		MirrorOne();
		StoreGuest(i);
	}
}

function SyncFriendlyFire()
{
	local int i;

	if (GPC.Length == 0)
	{
		SyncOne();
		return;
	}
	for (i = 0; i < GPC.Length; i++)
	{
		SelectGuest(i);
		SyncOne();
		StoreGuest(i);
	}
}

event PlayerController Login(string Portal, string Options, out string Error)
{
	local PlayerController NewPlayer;
	local Class<Security> MySecurityClass;

	T("enter, hostLoggedIn=" $ string(bHostLoggedIn) $ " options=" $ Options);
	if (!bHostLoggedIn)
	{
		bHostLoggedIn = true;
		T("host path");
		NewPlayer = Super.Login(Portal, Options, Error);
		if (NewPlayer != None && ParseOption(Options, "Name") != "")
		{
			ChangeName(NewPlayer, ParseOption(Options, "Name"), false);
		}
		return NewPlayer;
	}

	// Player two gets the stock controller and HUD; the game's own ones need server-only actors.
	HUDType = "Enhanced.EnhancedGuestHud";
	T("step 6: spawn EnhancedPlayerController");
	NewPlayer = Spawn(Class'Enhanced.EnhancedPlayerController');
	T("step 7: controller=" $ string(NewPlayer));
	if (NewPlayer == None)
	{
		Error = "Enhanced: could not spawn controller for player two";
		T(Error);
		return None;
	}

	NewPlayer.GameReplicationInfo = GameReplicationInfo;
	NewPlayer.GotoState('Spectating');
	T("step 8: spectating, PRI=" $ string(NewPlayer.PlayerReplicationInfo));
	MySecurityClass = Class<Security>(DynamicLoadObject(SecurityClass, Class'Core.Class'));
	NewPlayer.PlayerSecurity = Spawn(MySecurityClass, self);
	T("step 9: security=" $ string(NewPlayer.PlayerSecurity));

	// the stock Login puts the player's name from the URL into his PlayerReplicationInfo; this one has to do it itself (the name is shown over his Shrek)
	if (ParseOption(Options, "Name") != "")
	{
		ChangeName(NewPlayer, ParseOption(Options, "Name"), false);
	}
	// he has played this level's opening on his own machine (see ClientIntroFirst) and joined after it
	if (EnhancedPlayerController(NewPlayer) != None && ParseOption(Options, "EnhIntroDone") ~= MapName())
	{
		EnhancedPlayerController(NewPlayer).bIntroDone = true;
		T("step 9b: he has played the opening of " $ MapName() $ " by himself");
		IntroBack(NewPlayer.PlayerReplicationInfo.PlayerName);
	}
	AddGuest(NewPlayer);
	T("step 10: login done, the pawn of player two is made after the cutscenes");
	return NewPlayer;
}

// ---- The lobby (front-end level) ----

function bool IsMenuLevel()
{
	return Left(MapName(), 5) ~= "Book_";
}

// Levels where only a cutscene plays (the Fairy Godmother's office, the credits): the guests watch it through the host's camera, no Shrek is made for
// them, nothing is checked (no places, no gates, no deaths).
function bool IsCutsceneLevel()
{
	return MapName() ~= "4_FGM_Office" || MapName() ~= "Credits";
}

// What a hosting game answers to the LAN question: port | name | map | players | max players | build | locked (1 = password).
function string HostLine()
{
	local PlayerController Host;
	local string N, Lock;

	N = Class'Enhanced.EnhancedLobbySettings'.default.LobbyName;
	if (N == "")
	{
		Host = HostController();
		N = "Shrek 2";
		if (Host != None && Host.PlayerReplicationInfo != None)
		{
			N = Host.PlayerReplicationInfo.PlayerName;
		}
	}
	Lock = "0";
	if (Class'Enhanced.EnhancedLobbySettings'.default.Password != "")
	{
		Lock = "1";
	}
	return string(GamePortDefault) $ "|" $ N $ "|" $ MapName() $ "|" $ string(PlayerCount()) $ "|" $ string(Clamp(Class'Enhanced.EnhancedLobbySettings'.default.MaxPlayers, LobbyMin, LobbyMax)) $ "|1|" $ Lock;
}

// The host's password is checked before a guest gets in (the guest sends it in the URL option Pass).
event PreLogin(string Options, string Address, out string Error, out string FailCode)
{
	local string Pw;

	Super.PreLogin(Options, Address, Error, FailCode);
	if (Error != "")
	{
		return;
	}
	if (bLaunching)
	{
		Error = "The game has started";
		FailCode = "STARTED";
		return;
	}
	// the front-end level of a host who has closed his lobby is still a listen server (the URL cannot lose "listen"): nobody may join the plain menu
	if (IsMenuLevel() && LobbyMode != "host" && Level.NetMode == NM_ListenServer)
	{
		Error = "The host has closed the lobby";
		FailCode = "CLOSED";
		return;
	}
	Pw = Class'Enhanced.EnhancedLobbySettings'.default.Password;
	if (LobbyMode == "host" && Pw != "" && ParseOption(Options, "Pass") != Pw)
	{
		Error = "Wrong password";
		FailCode = "WRONGPW";
		T("lobby: a guest from " $ Address $ " was refused: wrong password");
	}
}

// Every guest has pressed Ready (no guests: true, the host may start alone).
// The players that are connected (the engine's NumPlayers does not count the second player: his Login is the mod's own).
function int PlayerCount()
{
	local Controller C;
	local int n;

	for (C = Level.ControllerList; C != None; C = C.NextController)
	{
		if (PlayerController(C) != None)
		{
			n++;
		}
	}
	return n;
}

function bool CanStart()
{
	return PlayerCount() >= LobbyMin && AllReady();
}

function bool AllReady()
{
	local Controller C;
	local EnhancedPlayerController P;

	for (C = Level.ControllerList; C != None; C = C.NextController)
	{
		P = EnhancedPlayerController(C);
		if (P != None && !P.bLobbyReady)
		{
			return false;
		}
	}
	return true;
}

function StartLanSearch()
{
	if (Beacon == None)
	{
		Beacon = Spawn(Class'Enhanced.EnhancedLanBeacon');
		Beacon.StartSearch();
	}
}

function StopLanSearch()
{
	if (Beacon != None && Beacon.bSearching)
	{
		Beacon.Destroy();
		Beacon = None;
	}
}

// The host's lobby: the places, the name the guests see, friendly fire, the LAN answer and (UPnP) the port on the router. Run when the front-end
// level is loaded as a lobby (?Lobby=host) or turned into one in place (OpenLobby).
function StartHostLobby()
{
	MaxPlayers = Clamp(Class'Enhanced.EnhancedLobbySettings'.default.MaxPlayers, LobbyMin, LobbyMax);
	GameReplicationInfo.GoalScore = MaxPlayers;   // carries the number of places to the guests' room page
	GameReplicationInfo.ServerName = Class'Enhanced.EnhancedLobbySettings'.default.LobbyName;
	FriendlyFire = 0.0;
	if (Class'Enhanced.EnhancedLobbySettings'.default.bFriendlyFire)
	{
		FriendlyFire = 1.0;
	}
	if (Beacon == None)
	{
		Beacon = Spawn(Class'Enhanced.EnhancedLanBeacon');
	}
	Beacon.StartHost(HostLine());
	if (bLobbyUpnp && Upnp == None)
	{
		Upnp = Spawn(Class'Enhanced.EnhancedUpnp');
		Upnp.Start(GamePortDefault, UpnpTarget);
	}
}

// "Create a game". Owner's wish (2026-11-21): the game must not restart when he goes into the co-op lobby. The menu level becomes a listen server
// where it is (native 3543 EnhListen, the engine's own ULevel::Listen) and the room page opens at once: true. Only if that fails (or with
// ?EnhOff=listennow) the front-end level is loaded again as a listen server, as before: false.
function bool OpenLobby(PlayerController PC, bool bUpnp)
{
	local string Opt, E;

	StopLanSearch();
	Class'Enhanced.EnhancedLobbySettings'.static.Save();
	if (IsMenuLevel() && !Off("listennow") && (Level.NetMode == NM_Standalone || Level.NetMode == NM_ListenServer))
	{
		if (Level.NetMode == NM_Standalone)
		{
			E = EnhListen();
		}
		if (Level.NetMode == NM_ListenServer)
		{
			LobbyMode = "host";
			bLobbyUpnp = bUpnp;
			bLaunching = false;
			StartHostLobby();
			T("lobby: opened in place (the menu level listens now), no level load");
			return true;
		}
		T("lobby: the menu level could not listen (" $ E $ "), it is loaded again as a listen server");
	}
	Opt = "";
	if (bUpnp)
	{
		Opt = "?Upnp=1";
	}
	PC.ConsoleCommand("open Book_FrontEnd.unr?Game=Enhanced.EnhancedGame?listen?Lobby=host" $ Opt);
	return false;
}

// The host closes his lobby. In place: the guests go back to their own menus, the LAN answer and the router port are given up, and the level
// stays a listen server that refuses every join (PreLogin: "The host has closed the lobby"); true, the page turns back. Otherwise the plain menu
// is loaded: false.
function bool CloseLobby(PlayerController PC)
{
	local Controller C;
	local PlayerController G;

	Class'Enhanced.EnhancedLobbySettings'.default.Password = "";
	Class'Enhanced.EnhancedLobbySettings'.static.Save();
	if (Upnp != None)
	{
		Upnp.Release();
	}
	if (IsMenuLevel() && !Off("listennow") && Level.NetMode == NM_ListenServer)
	{
		LobbyMode = "";
		for (C = Level.ControllerList; C != None; C = C.NextController)
		{
			G = PlayerController(C);
			if (G != None && IsGuestPC(G))
			{
				G.ClientTravel(PlainMenuURL(), TRAVEL_Absolute, false);
			}
		}
		if (Beacon != None)
		{
			Beacon.Destroy();
			Beacon = None;
		}
		if (Upnp != None)
		{
			Upnp.Destroy();
			Upnp = None;
		}
		T("lobby: closed in place, the guests go back to their menus");
		return true;
	}
	PC.ConsoleCommand("open " $ PlainMenuURL());
	return false;
}

// The plain main menu. A relative "open" keeps the options of the URL that is open now, so the lobby's own options have to be cleared by name:
// without that the book came back as the host's lobby again (the room page opens whenever Lobby=host is in the URL; tester report of 1 Nov).
static function string PlainMenuURL()
{
	return "Book_FrontEnd.unr?Game=Enhanced.EnhancedGame?Lobby=?Upnp=?Pass=?EnhWait=?EnhPlayers=?EnhSession=?EnhMenu=?listen=";
}

// The host starts the game: everybody in the lobby travels to the first level, or to the level of the chosen co-op save
// (the save is loaded there, see EnhLoad).
function LaunchCoop(optional string LoadSlot)
{
	local string Opt, Map, Session;
	local EnhancedSaveData R;

	if (Upnp != None)
	{
		Upnp.Release();
	}
	bLaunching = true;
	Class'Enhanced.EnhancedLobbySettings'.default.Password = "";
	Class'Enhanced.EnhancedLobbySettings'.static.Save();
	Map = FirstMap;
	Session = NewSessionId();
	Opt = "";
	if (LoadSlot != "")
	{
		R = new(None, LoadSlot) Class'Enhanced.EnhancedSaveData';
		if (R.Map != "")
		{
			Map = R.Map;
			if (R.Session != "")
			{
				Session = R.Session;
			}
			Opt = "?EnhLoad=" $ LoadSlot;
		}
	}
	if (Class'Enhanced.EnhancedLobbySettings'.default.bFriendlyFire)
	{
		Opt = Opt $ "?FriendlyFire=1";
	}
	T("lobby: the host starts the game, " $ string(PlayerCount()) $ " player(s), map " $ Map $ ", session " $ Session $ ", save '" $ LoadSlot $ "'");
	Level.ServerTravel(Map $ "?Game=Enhanced.EnhancedGame?listen?EnhWait=1?EnhSession=" $ Session $ "?EnhPlayers=" $ string(PlayerCount()) $ Opt, false);
}

// ---- Checkpoint record (variant C of the save rework) ----

function string MapName()
{
	local string S;

	S = string(Level);
	return Left(S, InStr(S, "."));
}

function string Two(int N)
{
	if (N < 10)
	{
		return "0" $ string(N);
	}
	return string(N);
}

// Sets a key in the record (replaces an existing one).
function SetPair(EnhancedSaveData D, string K, string V)
{
	local int i;

	for (i = 0; i < D.Keys.Length; i++)
	{
		if (D.Keys[i] == K)
		{
			D.Values[i] = V;
			return;
		}
	}
	D.Keys[D.Keys.Length] = K;
	D.Values[D.Values.Length] = V;
}

function bool IsTrue(Actor A, string Prop)
{
	return A.GetPropertyText(Prop) ~= "True";
}

// What the game's own SavePersistentData() of the persistent classes writes into the store, written
// into the record directly. The compile tools cannot call that event (it exists only in the game's
// engine), and the record needs nothing else: the keys and the value format are the game's.
// One typed loop per class: the engine filters by class, much cheaper than testing 1800 actors.
function AddActorStates(EnhancedSaveData D, string LevelID)
{
	local KWTrigger Tr;
	local KWPickup Pk;
	local KWMover Mv;
	local KWDecoration De;
	local KWGenericSpawner Sp;
	local BreakableObject Bo;
	local Counter Co;
	local RoundRobin Rr;
	local PlayerStart Ps;

	foreach AllActors(Class'KWGame.KWTrigger', Tr)
	{
		if (IsTrue(Tr, "bPersistent"))
		{
			SetPair(D, LevelID $ string(Tr.Name) $ "_bTOO", Tr.GetPropertyText("bInitiallyActive"));
		}
	}
	foreach AllActors(Class'KWGame.KWPickup', Pk)
	{
		if (IsTrue(Pk, "bRememberLoc"))
		{
			SetPair(D, LevelID $ string(Pk.Name) $ "_x", string(Pk.Location.X));
			SetPair(D, LevelID $ string(Pk.Name) $ "_y", string(Pk.Location.Y));
			SetPair(D, LevelID $ string(Pk.Name) $ "_z", string(Pk.Location.Z));
		}
	}
	foreach AllActors(Class'KWGame.KWMover', Mv)
	{
		if (IsTrue(Mv, "bPersistent"))
		{
			SetPair(D, LevelID $ string(Mv.Name) $ "_KeyNum", Mv.GetPropertyText("KeyNum"));
		}
	}
	foreach AllActors(Class'KWGame.KWDecoration', De)
	{
		if (IsTrue(De, "bPersistent"))
		{
			SetPair(D, LevelID $ string(De.Name) $ "_iCAI", De.GetPropertyText("currentAnimIndex"));
			SetPair(D, LevelID $ string(De.Name) $ "_bAS", De.GetPropertyText("bAnimsStarted"));
		}
	}
	foreach AllActors(Class'KWGame.KWGenericSpawner', Sp)
	{
		if (IsTrue(Sp, "bLivesPersistent"))
		{
			SetPair(D, LevelID $ string(Sp.Name) $ "_lives", Sp.GetPropertyText("Lives"));
		}
	}
	foreach AllActors(Class'ShGame.BreakableObject', Bo)
	{
		SetPair(D, string(Bo.Name) $ "_WasDestroyed", Bo.GetPropertyText("WasDestroyed"));
	}
	foreach AllActors(Class'GamePlay.Counter', Co)
	{
		if (IsTrue(Co, "bCounterPersistent"))
		{
			SetPair(D, LevelID $ string(Co.Name) $ "_iNTC", Co.GetPropertyText("NumToCount"));
		}
	}
	foreach AllActors(Class'KWGame.RoundRobin', Rr)
	{
		if (IsTrue(Rr, "bPersistent"))
		{
			SetPair(D, LevelID $ string(Rr.Name) $ "_iOEI", Rr.GetPropertyText("outEventIndex"));
		}
	}
	foreach AllActors(Class'Engine.PlayerStart', Ps)
	{
		SetPair(D, LevelID $ string(Ps.Name) $ "_bSTBS", Ps.GetPropertyText("bSavedToBookMarkSlot"));
	}
}

// Takes a checkpoint: the live PersistentStore plus the state of the persistent actors, the shared
// coins and the players' positions go into a small record.
// The nicknames of everybody who is playing, joined with &.
function string PlayerNicks()
{
	local Controller C;
	local PlayerController PC;
	local string R;

	for (C = Level.ControllerList; C != None; C = C.NextController)
	{
		PC = PlayerController(C);
		if (PC != None && PC.PlayerReplicationInfo != None)
		{
			if (R != "")
			{
				R = R $ "&";
			}
			R = R $ PC.PlayerReplicationInfo.PlayerName;
		}
	}
	return R;
}

// Puts a co-op save slot first in the registry the lobby reads (User.ini), keeping the newest eight.
function RegisterCoopSave(string Slot)
{
	local int i;
	local array<string> L;

	L = Class'Enhanced.EnhancedLobbySettings'.default.CoopSaves;
	for (i = L.Length - 1; i >= 0; i--)
	{
		if (L[i] == Slot)
		{
			L.Remove(i, 1);
		}
	}
	L.Insert(0, 1);
	L[0] = Slot;
	while (L.Length > 8)
	{
		L.Remove(L.Length - 1, 1);
	}
	Class'Enhanced.EnhancedLobbySettings'.default.CoopSaves = L;
	Class'Enhanced.EnhancedLobbySettings'.static.Save();
}

function string NewSessionId()
{
	return "c" $ string(Level.Year) $ Two(Level.Month) $ Two(Level.Day) $ Two(Level.Hour) $ Two(Level.Minute) $ Two(Level.Second);
}

function bool CaptureCheckpoint(string Slot, string CheckpointName, optional bool bNoWrite)
{
	local PersistentStore PS;
	local EnhancedSaveData D;
	local Controller C;
	local PlayerController PC;
	local int i;
	local string HeroLine, LevelID;

	LevelID = Level.GetPropertyText("ID");
	D = new(None, Slot) Class'Enhanced.EnhancedSaveData';
	D.Format = 1;
	D.Map = MapName();
	D.GameState = GetPropertyText("CurrentGameState");
	D.Checkpoint = CheckpointName;
	D.Session = SessionId;
	D.Title = Class'Enhanced.EnhancedLobbySettings'.default.LobbyName;
	D.Players = PlayerNicks();
	D.Stamp = string(Level.Year) $ "-" $ Two(Level.Month) $ "-" $ Two(Level.Day) $ " " $ Two(Level.Hour) $ ":" $ Two(Level.Minute) $ ":" $ Two(Level.Second);
	D.Keys.Length = 0;
	D.Values.Length = 0;

	// 1. what the game already keeps in its store
	foreach AllActors(Class'KWGame.PersistentStore', PS)
	{
		for (i = 0; i < PS.Keys.Length; i++)
		{
			SetPair(D, PS.Keys[i], PS.Values[i]);
		}
	}
	if (!bQuiet) T("capture: store pairs " $ string(D.Keys.Length));

	// 2. what the persistent actors would write now
	AddActorStates(D, LevelID);
	if (!bQuiet) T("capture: pairs now " $ string(D.Keys.Length) $ ", level id '" $ LevelID $ "'");

	// 3. the players
	D.Heroes.Length = 0;
	for (C = Level.ControllerList; C != None; C = C.NextController)
	{
		PC = PlayerController(C);
		if (PC != None && PC.Pawn != None)
		{
			HeroLine = string(PC.Pawn.Location.X) $ "," $ string(PC.Pawn.Location.Y) $ "," $ string(PC.Pawn.Location.Z)
				$ "," $ string(PC.Pawn.Rotation.Yaw) $ "," $ PC.Pawn.GetPropertyText("Health");
			D.Heroes[D.Heroes.Length] = HeroLine;
			if (KWPawn(PC.Pawn) != None && D.Coins == 0)
			{
				D.Coins = InvOf(PC.Pawn).GetInventoryCount('Coin');
			}
		}
	}

	if (bNoWrite)
	{
		return true;
	}
	D.SaveConfig();
	T("capture: saved slot " $ Slot $ " map=" $ D.Map $ " state=" $ D.GameState $ " keys=" $ string(D.Keys.Length)
		$ " heroes=" $ string(D.Heroes.Length) $ " coins=" $ string(D.Coins));
	return true;
}

// Loading, part one: the saved key/value pairs go into the game's own PersistentStore, so that the
// RestorePersistentData of every actor (which the engine runs after the actors have started) finds them as
// if the level had been left and re-entered. The mutator calls this when the store actor starts: the store
// does not exist yet in the game's PostBeginPlay.
function ApplyStoreTo(PersistentStore PS)
{
	local int i, before;

	if (!bLoading || LoadRecord == None)
	{
		return;
	}
	if (LoadRecord.Map != MapName())
	{
		T("load: record is for map '" $ LoadRecord.Map $ "', this level is " $ MapName() $ ", nothing applied");
		return;
	}
	before = PS.Keys.Length;
	for (i = 0; i < LoadRecord.Keys.Length; i++)
	{
		PS.SaveValue(LoadRecord.Keys[i], LoadRecord.Values[i]);
	}
	T("load: store had " $ string(before) $ " pairs, now " $ string(PS.Keys.Length) $ " (record " $ string(LoadRecord.Keys.Length) $ ")");
}

// True when the opening cutscene must not play: after a load, or by the option ?EnhSkipIntro=1.
event Logout(Controller Exiting)
{
	local string Nick;
	local bool bGuest;

	bGuest = IsGuestPC(Exiting);
	if (PlayerController(Exiting) != None)
	{
		EnhDeaf(PlayerController(Exiting), 0);
		EnhHeroClear();     // his hero goes: the engine layer must not keep it until the next Poll
	}
	if (bGuest)
	{
		Nick = Exiting.PlayerReplicationInfo.PlayerName;
		T("a guest has left: " $ Nick);
		RemoveGuest(GuestIndex(Exiting));
	}
	Super.Logout(Exiting);
	// his Shrek falls (the stock controller takes the pawn down with it) and stays on the ground; the host decides about the session. A guest who left to
	// play the opening by himself comes back: no question then.
	if (bGuest && WentForIntro(Nick))
	{
		T("a guest left to play the opening by himself: " $ Nick);
		return;
	}
	if (bGuest && GPC.Length == 0 && !bRestarting && !bLaunching && !IsMenuLevel() && Level.NextURL == "")
	{
		AskCloseSession(Nick);
	}
}

// Two players were left, one went: the host is asked whether to close the session and keep the progress.
function AskCloseSession(string Nick)
{
	local PlayerController Host;

	Host = HostController();
	if (Host == None || Host.Player == None || Host.Player.InteractionMaster == None)
	{
		return;
	}
	if (LeavePrompt == None)
	{
		LeavePrompt = EnhancedLeavePrompt(Host.Player.InteractionMaster.AddInteraction("Enhanced.EnhancedLeavePrompt", Host.Player));
	}
	if (LeavePrompt != None)
	{
		LeavePrompt.Ask(Nick, LeaveTestMode);
		T("leave: the host is asked about closing the session (" $ Nick $ " left)");
	}
}

// The host's answer: yes = a co-op save of the checkpoint state and back to the main menu, no = goes on alone (the session stays open for new guests).
function LeaveAnswered(bool bYes)
{
	if (!bYes)
	{
		T("leave: the host goes on alone");
		return;
	}
	if (SessionId != "")
	{
		CaptureCheckpoint("coop_" $ SessionId, "session closed");
		RegisterCoopSave("coop_" $ SessionId);
	}
	else
	{
		CaptureCheckpoint("auto", "session closed");
	}
	T("leave: the session is closed with a save, back to the main menu");
	bRestarting = true;
	// the options of this level are merged into the new URL unless the new one names the same key: the ones that steer a session are emptied
	Level.ServerTravel("Book_FrontEnd.unr?Game=Enhanced.EnhancedGame?EnhSkipIntro=?EnhWait=?EnhPlayers=?EnhSession=?EnhLoad=?EnhLeaveTest=?EnhDeathTest=?EnhJitter=?EnhMenu=?EnhGateTest=", false);
}

// The opening cutscene starts from the PlayerStart's event. With EnhWait the event is taken off at the level start
// and sent when player two has joined (or when the host presses the fire key to start alone).
function HoldIntro()
{
	local PlayerStart Ps;

	if (!bWaitOpt || ShouldSkipIntro())
	{
		return;
	}
	// The players were gathered in the menu's room: the opening cutscene starts at once and nobody stands about on the start place. A player who comes
	// back to the level a few seconds later watches it through the host's camera (MirrorOne) and gets his Shrek when it is over (ManageOne).
	T("intro is not held: it starts with the level, the guests join its picture when they are back");
	return;
	foreach AllActors(Class'Engine.PlayerStart', Ps)
	{
		if (Ps.Event != 'None')
		{
			HoldEvent = Ps.Event;
			Ps.Event = 'None';
		}
	}
	bHold = HoldEvent != 'None';
	T("intro held, event " $ string(HoldEvent));
}

function ReleaseIntro(string Why)
{
	local PlayerController Host;

	if (!bHold)
	{
		return;
	}
	bHold = false;
	ReleaseAt = Level.TimeSeconds;
	Host = HostController();
	T("intro released: " $ Why);
	if (Host != None && Host.Pawn != None)
	{
		TriggerEvent(HoldEvent, Host.Pawn, Host.Pawn);
	}
	else
	{
		TriggerEvent(HoldEvent, Self, None);
	}
}

// The host pressed the fire key while the cutscene is held: start without waiting.
function OnHostFire()
{
	// a game of one (no room before it) starts at the host's key; the players of a room are waited for (Poll)
	if (bHold && ExpectedPlayers <= 1)
	{
		ReleaseIntro("the host started alone");
	}
}

function bool ShouldSkipIntro()
{
	return bLoading || bSkipIntroOpt;
}

// Reads the next comma separated field of a short string and returns the rest.
function string NextField(out string S)
{
	local int i;
	local string F;

	i = InStr(S, ",");
	if (i < 0)
	{
		F = S;
		S = "";
		return F;
	}
	F = Left(S, i);
	S = Mid(S, i + 1);
	return F;
}

// Loading, part two: the hero gets the saved position, health and the saved number of coins.
function ApplyHero(Controller C)
{
	local string Line, X, Y, Z, Yaw, Hp;
	local Vector Loc;
	local Rotator Rot;
	local int have;

	if (!bLoading || LoadRecord == None || C == None || C.Pawn == None)
	{
		return;
	}
	if (LoadRecord.Heroes.Length == 0)
	{
		T("load: the record has no hero position");
		return;
	}
	Line = LoadRecord.Heroes[0];
	X = NextField(Line);
	Y = NextField(Line);
	Z = NextField(Line);
	Yaw = NextField(Line);
	Hp = NextField(Line);
	Loc.X = float(X);
	Loc.Y = float(Y);
	Loc.Z = float(Z);
	Rot = C.Pawn.Rotation;
	Rot.Yaw = int(Yaw);
	C.Pawn.SetLocation(Loc);
	C.Pawn.SetRotation(Rot);
	C.Pawn.SetPropertyText("Health", Hp);
	T("load: hero " $ string(C.Pawn) $ " placed at " $ string(C.Pawn.Location) $ " yaw " $ Yaw $ " health " $ Hp);
	if (KWPawn(C.Pawn) != None)
	{
		have = InvOf(C.Pawn).GetInventoryCount('Coin');
		if (LoadRecord.Coins > have)
		{
			InvOf(C.Pawn).AddToInventoryCollection(Class'ShGame.CoinCollection', LoadRecord.Coins - have);
		}
		T("load: coins were " $ string(have) $ ", record " $ string(LoadRecord.Coins) $ ", now " $ string(InvOf(C.Pawn).GetInventoryCount('Coin')));
	}
}

function bool HasPassed(Controller C)
{
	local int i;
	local bool bFound;

	for (i = 0; i < CkptPassed.Length; i++)
	{
		if (CkptPassed[i] == C)
		{
			bFound = true;
		}
	}
	return bFound;
}

// A player counts as having passed the checkpoint once he has been within CheckpointRadius of its place;
// he does not have to be there at the same time as the others, and leaving again does not undo it.
function MarkPassed()
{
	local Controller C;
	local PlayerController PC;

	for (C = Level.ControllerList; C != None; C = C.NextController)
	{
		PC = PlayerController(C);
		if (PC != None && PC.Pawn != None && !HasPassed(PC))
		{
			if (VSize(PC.Pawn.Location - CkptLoc) <= CheckpointRadius)
			{
				CkptPassed[CkptPassed.Length] = PC;
				T("checkpoint passed by " $ string(PC));
			}
		}
	}
}

// True when every player that has a pawn has passed the checkpoint.
function bool AllPassed()
{
	local Controller C;
	local PlayerController PC;
	local bool bAll;

	bAll = true;
	for (C = Level.ControllerList; C != None; C = C.NextController)
	{
		PC = PlayerController(C);
		if (PC != None && PC.Pawn != None && !HasPassed(PC))
		{
			bAll = false;
		}
	}
	return bAll;
}

function int PlayersWithPawn()
{
	local Controller C;
	local PlayerController PC;
	local int n;

	for (C = Level.ControllerList; C != None; C = C.NextController)
	{
		PC = PlayerController(C);
		if (PC != None && PC.Pawn != None)
		{
			n++;
		}
	}
	return n;
}

// A small status record for the test harness: it can read the file, not the locked log.
function WriteStatus(string What)
{
	local EnhancedSaveData D;

	D = new(None, "status") Class'Enhanced.EnhancedSaveData';
	D.Checkpoint = What;
	D.Stamp = string(Level.Hour) $ ":" $ Two(Level.Minute) $ ":" $ Two(Level.Second);
	D.SaveConfig();
}




// ---- The guests' HUD ----

// Which stock potion item belongs to a selection of the potion menu (the same table as HudItemPotion.GetCount).
function int PotionNumber(int Sel)
{
	switch (Sel)
	{
		case 0:
			return 1;
		case 5:
			return 2;
		case 2:
			return 3;
		case 3:
			return 4;
		case 4:
			return 5;
		case 1:
			return 6;
		case 6:
			return 7;
		case 7:
			return 8;
		case 8:
			return 9;
	}
	return 0;
}

function name PotionName(int N)
{
	switch (N)
	{
		case 1:
			return 'Potion1sh';
		case 2:
			return 'Potion2sh';
		case 3:
			return 'Potion3sh';
		case 4:
			return 'Potion4sh';
		case 5:
			return 'Potion5sh';
		case 6:
			return 'Potion6sh';
		case 7:
			return 'Potion7sh';
		case 8:
			return 'Potion8sh';
	}
	return 'Potion9sh';
}

// Coins and potions are shared (they live in the inventory of the host's Shrek); the guests' HUDs get the numbers here.
function SyncGuestHud()
{
	local PlayerController Host;
	local Controller C;
	local EnhancedPlayerController G;
	local int Coins, Potions, Sel, N, Icons;

	Host = HostController();
	if (Host == None || KWPawn(Host.Pawn) == None)
	{
		return;
	}
	Coins = InvOf(Host.Pawn).GetInventoryCount('Coin');
	Icons = Min(6, InvOf(Host.Pawn).GetInventoryCount('Shamrock') + 1);
	Sel = int(Host.GetPropertyText("PotionSelected"));
	N = PotionNumber(Sel);
	Potions = 0;
	if (N > 0)
	{
		Potions = InvOf(Host.Pawn).GetInventoryCount(PotionName(N));
	}
	if (Level.TimeSeconds - HudExtraAt > 0.2)
	{
		HudExtraAt = Level.TimeSeconds;
		HudExtraNow = HostHudExtra(Host);
	}
	for (C = Level.ControllerList; C != None; C = C.NextController)
	{
		G = EnhancedPlayerController(C);
		if (G != None)
		{
			G.HudCoins = Coins;
			G.HudPotions = Potions;
			G.HudPotionSel = Sel;
			G.HudIcons = Icons;
			if (G.HudExtra != HudExtraNow)
			{
				G.HudExtra = HudExtraNow;
			}
		}
	}
}

// What the host's own HUD shows besides health, coins and potions, for the guests' HUDs (the stock HUD items draw only on the host's screen): the boss's
// health bar ("B:<fraction>:<boss>"), the game timer ("T:<fraction>") and the potion timer ("P:<fraction>"), each while the host's item is showing.
function string HostHudExtra(PlayerController Host)
{
	local KWHud H;
	local int i;
	local string S, Boss;
	local KWHudItem It;
	local Actor B;
	local float Cur, Len;

	H = KWHud(Host.myHUD);
	if (H == None)
	{
		return "";
	}
	for (i = 0; i < H.HudItems.Length; i++)
	{
		It = H.HudItems[i];
		if (It == None || It.IsInState('Idle'))
		{
			continue;
		}
		if (It.IsA('HudItemHealthBoss') && KWPawn(Host.Pawn) != None)
		{
			B = KWPawn(Host.Pawn).aBoss;
			if (B != None)
			{
				Boss = "pib";
				if (B.IsA('BossFGM'))
				{
					Boss = "fgm";
				}
				else if (B.IsA('FatKnight'))
				{
					Boss = "fat";
				}
				else if (B.IsA('BanditBoss'))
				{
					Boss = "bandit";
				}
				S = S $ "B:" $ string(FClamp(float(It.GetPropertyText("Damage")), 0.0, 1.0)) $ ":" $ Boss $ ";";
			}
		}
		else if (It.IsA('SHHudGameTimer') || It.IsA('SHHudPotionTimer'))
		{
			Cur = float(It.GetPropertyText("Current"));
			Len = float(It.GetPropertyText("Length"));
			if (Len > 0.0)
			{
				if (It.IsA('SHHudGameTimer'))
				{
					S = S $ "T:" $ string(FClamp(Cur / Len, 0.0, 1.0)) $ ";";
				}
				else
				{
					S = S $ "P:" $ string(FClamp(Cur / Len, 0.0, 1.0)) $ ";";
				}
			}
		}
	}
	return S;
}

// ---- Enemy scaling ----

// How many players the level is for: the connected ones, or the number the lobby had (the guests come back a few seconds after the host
// after a level change, and the enemies of the level are made before that).
// The shared inventory (coins, potions, shamrocks) lives on one pawn the level names, Level.InventoryCarrierPawn, not on the hero being played:
// with the Donkey or Puss in Boots the hero's own count is zero. The stock HUD and shop read the carrier.
function KWPawn InvOf(Pawn Hero)
{
	local string S;
	local KWPawn A;

	if (CarrierCache == None)
	{
		// the stripped editor scripts do not declare the level's property; it is read by name
		S = Level.GetPropertyText("InventoryCarrierPawn");
		if (S != "" && S != "None")
		{
			foreach AllActors(Class'KWGame.KWPawn', A)
			{
				if (InStr(S, "'" $ string(A) $ "'") >= 0)
				{
					CarrierCache = A;
					T("inventory carrier: " $ string(A) $ ", the played hero is " $ string(Hero) $ "; coins on the carrier " $ string(A.GetInventoryCount('Coin')) $ ", on the hero " $ string(KWPawn(Hero).GetInventoryCount('Coin')));
					break;
				}
			}
		}
	}
	if (CarrierCache != None)
	{
		return CarrierCache;
	}
	return KWPawn(Hero);
}

function int PlayersForScale()
{
	return Max(PlayerCount(), ExpectedPlayers);
}

// Every additional player makes an enemy tougher by EnemyHealthPerPlayer (its health) and EnemyDamagePerPlayer (the damage of its hits),
// as a fraction of the stock value. One player: nothing changes. Called by the mutator for every ShEnemy as it is made.
function ScaleEnemy(Actor E)
{
	local int n;
	local float H, D, HS, DS;

	n = PlayersForScale();
	if (n <= 1 || IsMenuLevel())
	{
		return;
	}
	HS = 1.0 + float(n - 1) * EnemyHealthPerPlayer;
	DS = 1.0 + float(n - 1) * EnemyDamagePerPlayer;
	H = float(E.GetPropertyText("Health"));
	D = float(E.GetPropertyText("DamageAmount"));
	if (H > 0.0)
	{
		E.SetPropertyText("Health", string(H * HS));
	}
	if (D > 0.0)
	{
		E.SetPropertyText("DamageAmount", string(D * DS));
	}
	if (EnemiesLogged < 6)
	{
		EnemiesLogged++;
		T("enemy " $ string(E) $ " for " $ string(n) $ " players: health " $ string(H) $ " > " $ string(H * HS) $ ", damage " $ string(D) $ " > " $ string(D * DS));
	}
}

// The video tab of the stock Settings page offers 640x480, 800x600, 1024x768 only: its table is fixed in the class. The three places are
// filled here with what this PC can really do (Direct3D is asked: `SupportedResolution`): the largest, 1920 x 1080 when it is smaller than the
// largest, and 1280 x 720. The resolution that is set in the ini stays in the box whatever it is, so nothing that was chosen is lost.
function PatchResolutionList()
{
	local PlayerController Host;
	local int W[6], H[6], i, Top;
	local string Q;

	Host = HostController();
	if (Host == None)
	{
		return;
	}
	W[0] = 3840; H[0] = 2160;
	W[1] = 3440; H[1] = 1440;
	W[2] = 2560; H[2] = 1440;
	W[3] = 1920; H[3] = 1080;
	W[4] = 1600; H[4] = 900;
	W[5] = 1280; H[5] = 720;
	Top = -1;
	for (i = 0; i < 6 && Top < 0; i++)
	{
		Q = Host.ConsoleCommand("SupportedResolution WIDTH=" $ string(W[i]) $ " HEIGHT=" $ string(H[i]) $ " BITDEPTH=32");
		if (Q == "1")
		{
			Top = i;
		}
	}
	bResListDone = true;
	if (Top < 0)
	{
		return;
	}
	Class'SHGame.Tab_OptionsVideo'.default.DisplayModes[3].Width = W[Top];
	Class'SHGame.Tab_OptionsVideo'.default.DisplayModes[3].Height = H[Top];
	if (Top < 3)
	{
		Class'SHGame.Tab_OptionsVideo'.default.DisplayModes[2].Width = 1920;
		Class'SHGame.Tab_OptionsVideo'.default.DisplayModes[2].Height = 1080;
	}
	else
	{
		Class'SHGame.Tab_OptionsVideo'.default.DisplayModes[2].Width = W[Min(Top + 1, 5)];
		Class'SHGame.Tab_OptionsVideo'.default.DisplayModes[2].Height = H[Min(Top + 1, 5)];
	}
	Class'SHGame.Tab_OptionsVideo'.default.DisplayModes[1].Width = 1280;
	Class'SHGame.Tab_OptionsVideo'.default.DisplayModes[1].Height = 720;
	T("resolutions: the settings page offers 1280x720, " $ string(Class'SHGame.Tab_OptionsVideo'.default.DisplayModes[2].Width) $ "x" $ string(Class'SHGame.Tab_OptionsVideo'.default.DisplayModes[2].Height) $ ", " $ string(W[Top]) $ "x" $ string(H[Top]));
}

// Tests only: what kinds of actors the level has, and which of them the engine does not send to a client (RemoteRole none) although they are not static.
function SurveyTick()
{
	local Actor A;
	local array<string> Names;
	local array<int> Counts;
	local int i, k;
	local string Cls;

	if (!bSurveyOpt || bSurveyDone || Level.TimeSeconds < 25.0)
	{
		return;
	}
	bSurveyDone = true;
	foreach AllActors(Class'Engine.Actor', A)
	{
		Cls = string(A.Class) $ " rr=" $ string(int(A.RemoteRole)) $ " st=" $ string(int(A.bStatic)) $ " nd=" $ string(int(A.bNoDelete)) $ " dt=" $ string(int(A.DrawType)) $ " ph=" $ string(int(A.Physics)) $ " am=" $ string(int(A.IsAnimating(0)));
		k = -1;
		for (i = 0; i < Names.Length; i++)
		{
			if (Names[i] == Cls)
			{
				k = i;
				break;
			}
		}
		if (k < 0)
		{
			k = Names.Length;
			Names[k] = Cls;
			Counts[k] = 0;
		}
		Counts[k]++;
	}
	for (i = 0; i < Names.Length; i++)
	{
		Log("[WS] " $ string(Counts[i]) $ " x " $ Names[i]);
	}
	T("survey: " $ string(Names.Length) $ " kinds of actors");
}

// Tests only: where a guest who comes in during the game could be put. One line for every checkpoint fairy, start place, cutscene trigger, level change and enemy.
function JoinSurveyTick()
{
	local Actor A;
	local Vector HitLoc, HitNorm, From, To;
	local PlayerController Host;
	local int Foes, i, Strict, Relaxed;
	local Vector Probe;
	local string RingList, Why;
	local array<Vector> Saves;
	local array<string> SaveNames;
	local Vector Center;
	local int CStrict, CRelaxed, k;

	if (!bJoinSurveyOpt || bJoinSurveyDone || Level.TimeSeconds < 1.0)
	{
		return;
	}
	Host = HostController();
	if (Host == None)
	{
		// a level where the hero is the Donkey (or another hero): his controller is not the mod's
		Host = Level.GetLocalPlayerController();
	}
	if (Host == None)
	{
		return;
	}
	// a level may start with a cutscene after which the hero stands somewhere else: the survey is taken when the hero has been free for 4 s after a
	// cutscene (or after 40 s without one), and both places are logged
	if (Host.Pawn == None)
	{
		bSurveyBusy = true;
		SurveyFreeSince = 0.0;
		return;
	}
	if (!bSurveyInit)
	{
		bSurveyInit = true;
		SurveyInitPos = Host.Pawn.Location;
	}
	if (SurveyFreeSince == 0.0)
	{
		SurveyFreeSince = Level.TimeSeconds;
	}
	if (Level.TimeSeconds - SurveyFreeSince < 4.0 || (!bSurveyBusy && Level.TimeSeconds < 40.0) || Level.TimeSeconds < 8.0)
	{
		return;
	}
	bJoinSurveyDone = true;
	Log("[JS] map " $ MapName() $ " host " $ string(Host.Pawn) $ " ctl " $ string(Host.Class) $ " at " $ string(Host.Pawn.Location));
	Log("[JS] cutscene=" $ string(bSurveyBusy) $ " first place " $ string(SurveyInitPos) $ " moved " $ string(int(VSize(Host.Pawn.Location - SurveyInitPos))) $ " units, at t=" $ string(int(Level.TimeSeconds)));
	foreach AllActors(Class'Engine.Actor', A)
	{
		if (A.IsA('SHSavePoint'))
		{
			From = A.Location;
			From.Z += 120.0;
			To = A.Location;
			To.Z -= 200.0;
			Trace(HitLoc, HitNorm, To, From, false);
			Log("[JS] save " $ string(A.Name) $ " " $ string(A.Location) $ " floorNormalZ=" $ string(HitNorm.Z) $ " floorDz=" $ string(HitLoc.Z - A.Location.Z));
			Saves[Saves.Length] = A.Location;
			SaveNames[SaveNames.Length] = string(A.Name);
		}
		else if (A.IsA('PlayerStart'))
		{
			Log("[JS] start " $ string(A.Name) $ " " $ string(A.Location));
		}
		else if (A.IsA('CutSceneTrigger'))
		{
			Log("[JS] cut " $ string(A.Name) $ " " $ string(A.Location) $ " radius=" $ string(int(A.CollisionRadius)) $ " event=" $ string(A.Event));
		}
		else if (A.IsA('ChangeLevelTrigger'))
		{
			Log("[JS] exit " $ string(A.Name) $ " " $ string(A.Location) $ " map=" $ A.GetPropertyText("NewMapName"));
		}
		else if (A.IsA('ShEnemy') && Pawn(A) != None)
		{
			Foes++;
			Log("[JS] foe " $ string(A.Class) $ " " $ string(A.Location));
		}
	}
	// the places a guest's Shrek could be put around the host's start (the same test as the real spawn): strict rules, then the relaxed ones
	if (Host.Pawn != None)
	{
		SetupSpawnScale(Host.Pawn);
		Strict = 0;
		Relaxed = 0;
		SpawnFails = 0;
		for (i = 0; i < 40; i++)
		{
			if (GroundSpot(Host.Pawn.Location, Host.Pawn.Rotation, i, Probe))
			{
				Strict++;
				RingList = RingList $ string(i) $ " ";
				Why = Why $ "+";
			}
			else if (Left(GroundWhy, 5) ~= "floor")
			{
				Why = Why $ "F";
			}
			else if (Left(GroundWhy, 7) ~= "no line")
			{
				Why = Why $ "L";
			}
			else if (Left(GroundWhy, 9) ~= "no ground")
			{
				Why = Why $ "S";
			}
			else
			{
				Why = Why $ "P";
			}
		}
		SpawnFails = 41;
		for (i = 0; i < 40; i++)
		{
			if (GroundSpot(Host.Pawn.Location, Host.Pawn.Rotation, i, Probe))
			{
				Relaxed++;
			}
		}
		SpawnFails = 0;
		Log("[JS] ring reasons (+ ok, F floor, L sight, S side ground, P way) " $ Why);
		Log("[JS] ring strict=" $ string(Strict) $ " relaxed=" $ string(Relaxed) $ " of 40, free places: " $ RingList);
	}
	// the same around every checkpoint, as ChooseJoinCenter would put a late guest there: the floor under it, then the ring
	for (k = 0; k < Saves.Length; k++)
	{
		From = Saves[k];
		From.Z += 60.0;
		To = Saves[k];
		To.Z -= 400.0;
		if (Trace(HitLoc, HitNorm, To, From, false) == None || HitNorm.Z < 0.7)
		{
			Log("[JS] ckring " $ SaveNames[k] $ " no usable floor under it: a late guest falls back to the host");
			continue;
		}
		Center = HitLoc;
		Center.Z += HostH;
		CStrict = 0;
		CRelaxed = 0;
		SpawnFails = 0;
		RingList = "";
		Why = "";
		for (i = 0; i < 40; i++)
		{
			if (GroundSpot(Center, Host.Pawn.Rotation, i, Probe))
			{
				CStrict++;
				RingList = RingList $ string(i) $ " ";
				Why = Why $ "+";
			}
			else if (Left(GroundWhy, 5) ~= "floor")
			{
				Why = Why $ "F";
			}
			else if (Left(GroundWhy, 7) ~= "no line")
			{
				Why = Why $ "L";
			}
			else if (Left(GroundWhy, 9) ~= "no ground")
			{
				Why = Why $ "S";
			}
			else
			{
				Why = Why $ "P";
			}
		}
		Log("[JS] ckwhy " $ SaveNames[k] $ " " $ Why $ " last: " $ GroundWhy);
		SpawnFails = 41;
		for (i = 0; i < 40; i++)
		{
			if (GroundSpot(Center, Host.Pawn.Rotation, i, Probe))
			{
				CRelaxed++;
			}
		}
		SpawnFails = 0;
		Log("[JS] ckring " $ SaveNames[k] $ " at " $ string(Center) $ " strict=" $ string(CStrict) $ " relaxed=" $ string(CRelaxed) $ " of 40, free: " $ RingList);
	}
	Log("[JS] done foes=" $ string(Foes));
	Host.ConsoleCommand("quit");
}

// What the game's hero controller (ShHeroController.PlayerTick) does for a hero every frame, and a guest's controller does not (the server does not tick a remote
// player's controller): the ground under the feet is looked at and the hero is slowed in water (HeroInWater: ground speed 550 -> 150) and in quicksand, and
// pulled to a ledge by the jump magnet. Called from the ticker every frame for every guest's pawn.
function GuestGround()
{
	local int i, Mt;
	local ShHeroPawn H;

	for (i = 0; i < GPawn.Length; i++)
	{
		H = ShHeroPawn(GPawn[i]);
		if (H == None || H.bHidden || H.IsInState('stateHeroDying') || H.Controller == None)
		{
			continue;
		}
		H.UseSHJumpMagnet();
		Mt = int(H.TraceMaterial(H.Location, 1.5 * H.CollisionHeight));
		if (Mt != 6 && H.GetPropertyText("bInWater") ~= "True")
		{
			H.HeroOutOfWater();
			T("terrain: " $ string(H) $ " is out of the water, ground speed " $ string(int(H.GroundSpeed)));
		}
		if (Mt != 14 && H.GetPropertyText("bInQuicksand") ~= "True")
		{
			H.HeroOutOfQuicksand();
		}
		if (Mt == 14)
		{
			if (!(H.GetPropertyText("bInQuicksand") ~= "True"))
			{
				H.HeroInQuicksand();
			}
		}
		else if (Mt == 6)
		{
			if (!(H.GetPropertyText("bInWater") ~= "True"))
			{
				H.HeroInWater();
				T("terrain: " $ string(H) $ " is in the water, ground speed " $ string(int(H.GroundSpeed)));
			}
		}
	}
}

// Tests only: the host looks the other way.
function HostTurnTick()
{
	local PlayerController Host;
	local Rotator R;

	if (HostTurnAt <= 0.0 || bHostTurned || Level.TimeSeconds < HostTurnAt)
	{
		return;
	}
	Host = HostController();
	if (Host == None || Host.Pawn == None)
	{
		return;
	}
	bHostTurned = true;
	R = Host.Rotation;
	R.Yaw += 32768;
	Host.SetRotation(R);
	Host.ClientSetRotation(R);
	Host.Pawn.SetRotation(R);
	T("host turned half a circle");
}

// Tests only: where each guest's pawn is on the server, ten times a second.
function string AnimInfo(Pawn P)
{
	local name N, N2;
	local float F, Rate, F2, R2;
	local string Ch;
	local int C;

	P.GetAnimParams(0, N, F, Rate);
	Ch = "";
	for (C = 4; C < 8; C++)
	{
		P.GetAnimParams(C, N2, F2, R2);
		Ch = Ch $ " c" $ string(C) $ "=" $ string(N2) $ "/" $ string(R2);
	}
	N2 = N;
	return Ch $ " acc=" $ string(int(VSize(P.Acceleration))) $ " bpau=" $ P.GetPropertyText("bPhysicsAnimUpdate") $ " gs=" $ string(int(P.GroundSpeed)) $ " dgs=" $ P.GetPropertyText("DestGroundSpeed") $ " twn=" $ P.GetPropertyText("bTweenGroundSpeed") $ " ar=" $ string(Rate) $ " an=" $ string(N) $ " td=" $ string(Level.TimeDilation);
}

// Tests only (EnhJitter): what the host sees of the first guest on every frame of the host.
// Test only (EnhPivotTest): which way PrePivot shifts the drawn mesh of a guest (0 until 34 s, then +300 forward, +300 right, +300 up).
function PivotTest()
{
	local Pawn P;
	local Vector V;
	local Coords B1, B2, B3;

	if (!bPivotTest || GPC.Length < 1 || GPC[0] == None || GPC[0].Pawn == None)
	{
		return;
	}
	P = GPC[0].Pawn;
	if (Level.TimeSeconds > 34.0 && Level.TimeSeconds < 38.0)
	{
		V = vect(300.0, 0.0, 0.0);
	}
	else if (Level.TimeSeconds >= 38.0 && Level.TimeSeconds < 42.0)
	{
		V = vect(0.0, 300.0, 0.0);
	}
	else if (Level.TimeSeconds >= 42.0)
	{
		V = vect(0.0, 0.0, 300.0);
	}
	P.PrePivot = V;
	if (int(Level.TimeSeconds * 2.0) != PivotLog)
	{
		PivotLog = int(Level.TimeSeconds * 2.0);
		B1 = P.GetBoneCoords('Bip01');
		B2 = P.GetBoneCoords('Bip01 Pelvis');
		B3 = P.GetBoneCoords('Bip01 Spine');
		Log("[PIV] t=" $ string(Level.TimeSeconds) $ " loc=" $ string(P.Location) $ " pre=" $ string(P.PrePivot) $ " yaw=" $ string(P.Rotation.Yaw & 65535)
			$ " b1=" $ string(B1.Origin) $ " b2=" $ string(B2.Origin) $ " b3=" $ string(B3.Origin));
	}
}

// The host draws a guest where the server has him, and the server moves him only when a packet of his moves arrives, so on the host he
// stepped (0 to 46 units a frame at a speed of 18) and stood still for a frame now and then while his legs went on. The drawn position runs
// along his velocity and is pulled to the real one; it is applied as PrePivot by the engine layer just before the host's picture is drawn
// (see enhnative.c: the value is replicated, so it must not be set while the replication runs).
function GuestSmooth(float DeltaTime)
{
	local int i;
	local KWPawn P;
	local Vector L, S, Base;

	for (i = 0; i < 4; i++)
	{
		P = None;
		if (i < GPawn.Length)
		{
			P = GPawn[i];
		}
		if (P == None || P.bHidden || bNoSmooth || DeltaTime <= 0.0)
		{
			EnhDrawOffset(i, None, 0.0, 0.0);
			GSInit[i] = 0;
		}
		else
		{
			if (!bPivotCal)
			{
				Base = P.PrePivot;
				P.PrePivot = vect(123.0, 456.0, 789.0);
				if (EnhPrePivotCalib(P) > 0)
				{
					bPivotCal = true;
				}
				else
				{
					bNoSmooth = true;
				}
				P.PrePivot = Base;
			}
			if (GSInit[i] == 0)
			{
				GBaseX[i] = P.PrePivot.X;
				GBaseY[i] = P.PrePivot.Y;
			}
			P.PrePivot.X = GBaseX[i];
			P.PrePivot.Y = GBaseY[i];
			L = P.Location;
			if (GSInit[i] == 0 || VSize(GSmooth[i] - L) > 200.0)
			{
				GSmooth[i] = L;
				GSInit[i] = 1;
			}
			else
			{
				S = GSmooth[i] + P.Velocity * DeltaTime;
				S += (L - S) * FMin(1.0, DeltaTime * 14.0);
				GSmooth[i] = S;
			}
			if (i == 0)
			{
				DispX = GSmooth[0].X;
				DispY = GSmooth[0].Y;
			}
			EnhDrawOffset(i, P, GSmooth[i].X - L.X, GSmooth[i].Y - L.Y);
		}
	}
}

function GuestTrace(float DeltaTime)
{
	local Pawn P;
	local name N0, N4;
	local float F0, R0, F4, R4;

	if (!bJitterOpt || GPC.Length < 1 || GPC[0] == None || GPC[0].Pawn == None)
	{
		return;
	}
	P = GPC[0].Pawn;
	P.GetAnimParams(0, N0, F0, R0);
	P.GetAnimParams(4, N4, F4, R4);
	Log("[GT] t=" $ string(Level.TimeSeconds) $ " dt=" $ string(DeltaTime) $ " x=" $ string(P.Location.X) $ " y=" $ string(P.Location.Y) $ " dx=" $ string(DispX) $ " dy=" $ string(DispY) $ " vel=" $ string(int(VSize(P.Velocity)))
		$ " acc=" $ string(int(VSize(P.Acceleration))) $ " c0=" $ string(N0) $ "/" $ string(F0) $ " c4=" $ string(F4) $ "/" $ string(R4));
}

// Tests only (EnhJumpTest): one jump of the host's Shrek, a double jump 0.4 s after it, whatever the frame rate; the log says how high he got and how
// long he was in the air, so that runs at different frame rates can be compared.
function JumpTestTick(float DeltaTime)
{
	local Controller C;
	local PlayerController PC;
	local ShHeroPawn H;

	if (!bJumpTestOpt || bJtGuestOnly || JtState >= 2 || Level.TimeSeconds < 14.0)
	{
		return;
	}
	for (C = Level.ControllerList; C != None; C = C.NextController)
	{
		if (PlayerController(C) != None && PlayerController(C).Pawn != None && !IsGuestPC(PlayerController(C)))
		{
			PC = PlayerController(C);
			break;
		}
	}
	if (PC == None)
	{
		return;
	}
	H = ShHeroPawn(PC.Pawn);
	if (H == None)
	{
		return;
	}
	if (JtHold > 0.0)
	{
		JtHold -= DeltaTime;
		PC.aUp = 1200.0;                  // the Jump key is "Jump | Axis aUp Speed=+1200"
	}
	if (JtState == 0)
	{
		if (H.Physics != PHYS_Walking)
		{
			return;
		}
		JtZ0 = H.Location.Z;
		JtMaxZ = JtZ0;
		JtT = 0.0;
		bJtDid2 = false;
		JtState = 1;
		if (bJtInput)
		{
			PC.bPressedJump = true;
			JtHold = 0.12;
			T("[JT] jump pressed (input path) at level time " $ string(Level.TimeSeconds) $ " from z=" $ string(JtZ0));
		}
		else
		{
			T("[JT] jump at level time " $ string(Level.TimeSeconds) $ " from z=" $ string(JtZ0) $ ", result " $ string(H.DoJump(false)));
		}
		return;
	}
	JtT += DeltaTime;
	JtMaxZ = FMax(JtMaxZ, H.Location.Z);
	T("[JT] t=" $ string(JtT) $ " dt=" $ string(DeltaTime) $ " z=" $ string(H.Location.Z - JtZ0) $ " vz=" $ string(H.Velocity.Z) $ " phys=" $ string(int(H.Physics)));
	if (!bJtDid2 && JtT >= 0.4 && H.Physics == PHYS_Falling)
	{
		bJtDid2 = true;
		if (bJtInput)
		{
			PC.bPressedJump = true;
			JtHold = 0.12;
		}
		else
		{
			H.DoDoubleJump(false);
		}
		T("[JT] double jump asked at t=" $ string(JtT) $ " z=" $ string(H.Location.Z - JtZ0) $ " vz=" $ string(H.Velocity.Z));
	}
	if (JtT > 0.3 && H.Physics == PHYS_Walking)
	{
		T("[JT] RESULT air time " $ string(JtT) $ " s, highest " $ string(JtMaxZ - JtZ0) $ " units, double jump asked " $ string(bJtDid2));
		JtState = 2;
	}
	else if (JtT > 6.0)
	{
		T("[JT] RESULT still not landed after 6 s, highest " $ string(JtMaxZ - JtZ0) $ ", double " $ string(bJtDid2));
		JtState = 2;
	}
}

// Tests only (EnhJumpTest): what the server sees of a guest's jumps (the guest's scripted input presses jump). Per jump: the air time, the highest
// point and whether a second upward impulse came while he was falling (the double jump).
function GuestJumpTick(float DeltaTime)
{
	local Controller C;
	local Pawn P;

	if (!bJumpTestOpt)
	{
		return;
	}
	for (C = Level.ControllerList; C != None && P == None; C = C.NextController)
	{
		if (PlayerController(C) != None && IsGuestPC(PlayerController(C)) && PlayerController(C).Pawn != None)
		{
			P = PlayerController(C).Pawn;
		}
	}
	if (P == None)
	{
		return;
	}
	if (GjState == 0)
	{
		if (P.Physics == PHYS_Falling && P.Velocity.Z > 100.0)
		{
			GjState = 1;
			GjZ0 = P.Location.Z;
			GjMax = GjZ0;
			GjAir = 0.0;
			GjPrevVz = P.Velocity.Z;
			bGjSecond = false;
			GjCount++;
			T("[GJ] jump " $ string(GjCount) $ " takes off, vz=" $ string(P.Velocity.Z));
		}
		return;
	}
	GjAir += DeltaTime;
	GjMax = FMax(GjMax, P.Location.Z);
	if (!bGjSecond && P.Physics == PHYS_Falling && P.Velocity.Z > GjPrevVz + 150.0)
	{
		bGjSecond = true;
		T("[GJ] second upward impulse at " $ string(GjAir) $ " s, vz " $ string(GjPrevVz) $ " -> " $ string(P.Velocity.Z));
	}
	GjPrevVz = P.Velocity.Z;
	if (P.Physics == PHYS_Walking && GjAir > 0.2)
	{
		T("[GJ] jump " $ string(GjCount) $ " RESULT air time " $ string(GjAir) $ " s, highest " $ string(GjMax - GjZ0) $ " units, second impulse " $ string(bGjSecond));
		GjState = 0;
	}
}

// Tests only (EnhCkptTest=<seconds>): a save of a cutscene's end in the middle of the level must leave the checkpoint place alone; a save next to a fairy
// must put it at the fairy.
function CkptTest()
{
	local Controller C, Host;
	local Actor A, Point, Fairy;
	local Vector V;

	if (CkptTestAt <= 0.0 || CkptTestStep >= 4 || Level.TimeSeconds < CkptTestAt + float(CkptTestStep) * 3.0)
	{
		return;
	}
	for (C = Level.ControllerList; C != None && Host == None; C = C.NextController)
	{
		if (PlayerController(C) != None && C.Pawn != None)
		{
			Host = C;
		}
	}
	if (Host == None)
	{
		return;
	}
	if (CkptTestStep == 0)
	{
		T("CKPTTEST 1: have=" $ string(bHaveCheckpointLoc) $ " loc=" $ string(LastCheckpointLoc) $ ", a cutscene's save in the middle of the level (t=" $ string(Level.TimeSeconds) $ ")");
		OnCheckpointRequest(Host, "SaveSlottedGame 1");
	}
	else if (CkptTestStep == 1)
	{
		T("CKPTTEST 2: after the cutscene's save have=" $ string(bHaveCheckpointLoc) $ " loc=" $ string(LastCheckpointLoc) $ " (it must be unchanged)");
		foreach AllActors(Class'Engine.Actor', A)
		{
			if (A.IsA('SHSavePoint'))
			{
				Point = A;
			}
			else if (A.IsA('SavePointFairy'))
			{
				Fairy = A;
			}
		}
		if (Point == None)
		{
			Point = Fairy;
		}
		CkptTestFairy = Point;
		if (Point == None)
		{
			T("CKPTTEST: no fairy in this level");
			CkptTestStep = 4;
			return;
		}
		V = Point.Location;
		V.X += 300.0;
		V.Z += 80.0;
		Host.Pawn.SetLocation(V);
		T("CKPTTEST: the host stands 300 units from the fairy " $ string(Point) $ " at " $ string(Point.Location));
	}
	else if (CkptTestStep == 2)
	{
		OnCheckpointRequest(Host, "SaveGame");
	}
	else if (CkptTestStep == 3)
	{
		T("CKPTTEST 3: after the fairy's save have=" $ string(bHaveCheckpointLoc) $ " loc=" $ string(LastCheckpointLoc) $ " distance to the fairy " $ string(int(VSize(LastCheckpointLoc - CkptTestFairy.Location))));
	}
	CkptTestStep++;
}

// Tests (EnhBagTest): see BagTestAt.
function BagTestTick()
{
	local KActor K;
	local EnhancedPlayerController PC;
	local Vector V, HL, HN;
	local Rotator R;
	local int i;
	local name Seq;
	local float Fr, Rt, Best;

	if (Level.TimeSeconds < BagTestAt || BagStep >= 8)
	{
		return;
	}
	if (Level.TimeSeconds - BagLogAt >= 0.5)
	{
		BagLogAt = Level.TimeSeconds;
		for (i = 0; i < GPC.Length && BagStep >= 2 && BagStep <= 6; i++)
		{
			if (GPC[i] != None && GPC[i].Pawn != None)
			{
				GPC[i].Pawn.GetAnimParams(0, Seq, Fr, Rt);
				Log("[BAG] guest's hero on the server at " $ string(GPC[i].Pawn.Location) $ " yaw " $ string(GPC[i].Pawn.Rotation.Yaw & 65535) $ " state "
					$ string(GPC[i].Pawn.GetStateName()) $ " anim " $ string(Seq) $ " frame " $ string(Fr));
				break;
			}
		}
		foreach DynamicActors(Class'Engine.KActor', K)
		{
			if (K.IsA('PunchingBag'))
			{
				Log("[BAG] host t=" $ string(int((Level.TimeSeconds - BagTestAt) * 10.0)) $ " " $ string(K.Name) $ " at " $ string(K.Location) $ " rot " $ string(K.Rotation)
					$ " state " $ string(K.GetStateName()) $ " hidden " $ string(K.bHidden) $ " hits left " $ string(KWKarmaActor(K).NumberToHit));
			}
		}
	}
	if (BagStep == 0)
	{
		BagStep = 1;
		foreach DynamicActors(Class'Engine.KActor', K)
		{
			if (K.IsA('PunchingBag'))
			{
				K.KAddImpulse(vect(5000, 0, 0), K.Location);
				T("test: the punching bag " $ string(K.Name) $ " is pushed on the host");
			}
		}
	}
	if (BagStep == 1 && Level.TimeSeconds > BagTestAt + 6.0)
	{
		BagStep = 2;
		// the bag nearest above its floor (some hang high over a ledge and are hit from above)
		Best = 100000.0;
		foreach DynamicActors(Class'Engine.KActor', K)
		{
			if (K.IsA('PunchingBag') && !K.bHidden && Trace(HL, HN, K.Location + vect(-75, 0, -800), K.Location + vect(-75, 0, 0), true) != None)
			{
				Log("[BAG] " $ string(K.Name) $ " hangs " $ string(int(K.Location.Z - HL.Z)) $ " above the floor next to it");
				if (K.Location.Z - HL.Z < Best)
				{
					Best = K.Location.Z - HL.Z;
					BagHit = K;
				}
			}
		}
		for (i = 0; i < GPC.Length && BagHit != None; i++)
		{
			PC = EnhancedPlayerController(GPC[i]);
			if (PC != None && PC.Pawn != None)
			{
				// on the ground under the bag's side (the bag hangs: its own height is in the air)
				V = BagHit.Location + vect(-75, 0, 0);
				if (Trace(HL, HN, V - vect(0, 0, 800), V, true) != None)
				{
					V = HL + vect(0, 0, 1) * (PC.Pawn.CollisionHeight + 4.0);
				}
				if (!PC.Pawn.SetLocation(V))
				{
					PC.Pawn.SetLocation(V + vect(0, 0, 30));
				}
				R = rotator(BagHit.Location - PC.Pawn.Location);
				R.Pitch = 0;
				R.Roll = 0;
				PC.Pawn.SetRotation(R);
				PC.SetRotation(R);
				PC.ClientSetRotation(R);
				T("test: " $ PC.PlayerReplicationInfo.PlayerName $ " put at " $ string(PC.Pawn.Location) $ " next to the punching bag " $ string(BagHit.Name) $ " at " $ string(BagHit.Location));
				break;
			}
		}
	}
	if (BagStep >= 2 && BagStep < 6 && Level.TimeSeconds > BagTestAt + 7.0 + float(BagStep - 2))
	{
		BagStep++;
		for (i = 0; i < GPC.Length; i++)
		{
			PC = EnhancedPlayerController(GPC[i]);
			if (PC != None && PC.Pawn != None)
			{
				if (BagHit != None)
				{
					R = rotator(BagHit.Location - PC.Pawn.Location);
					R.Pitch = 0;
					R.Roll = 0;
					PC.Pawn.SetRotation(R);
				}
				T("test: " $ PC.PlayerReplicationInfo.PlayerName $ "'s attack is pressed (as his attack key does)");
				PC.ServerAction();
				break;
			}
		}
	}
	if (BagStep == 6 && Level.TimeSeconds > BagTestAt + 14.0)
	{
		BagStep = 7;
		foreach DynamicActors(Class'Engine.KActor', K)
		{
			if (K.IsA('PunchingBag') && !K.IsInState('stateSpawning') && !K.bHidden)
			{
				T("test: the punching bag " $ string(K.Name) $ " is used up on the host");
				K.GotoState('stateSpawning');
			}
		}
	}
	if (BagStep == 7 && Level.TimeSeconds > BagTestAt + 18.0)
	{
		BagStep = 8;
	}
}

function GotoTick()
{
	local Controller C;
	local EnhancedLeaveBonus X;
	local EnhancedPlayerController PC;
	local int i;
	local bool bPlaced;

	CkptTest();

	// a guest's climb that never ends (see EnhancedPlayerController.EndClimb): the server's copy is put on the climb's top after four seconds, and the guest too
	for (i = 0; i < GPC.Length; i++)
	{
		PC = EnhancedPlayerController(GPC[i]);
		if (PC == None)
		{
			continue;
		}
		if (PC.Pawn != None && PC.Pawn.Physics == PHYS_Projectile && !Class'Enhanced.EnhancedPlayerController'.static.InClimb(PC.Pawn) && !PC.Pawn.IsInState('MountHanging'))
		{
			if (PC.ClimbPhysSince == 0.0)
			{
				PC.ClimbPhysSince = Level.TimeSeconds;
			}
			else if (Level.TimeSeconds - PC.ClimbPhysSince > 0.4)
			{
				T("climb: " $ PC.PlayerReplicationInfo.PlayerName $ "'s hero kept the climbing physics after the climb at " $ string(PC.Pawn.Location) $ ": it falls again");
				PC.Pawn.Velocity = vect(0, 0, 0);
				PC.Pawn.SetPhysics(PHYS_Falling);
				PC.ClimbPhysSince = 0.0;
			}
		}
		else if (PC != None)
		{
			PC.ClimbPhysSince = 0.0;
		}
		if (PC.Pawn == None || !Class'Enhanced.EnhancedPlayerController'.static.InClimb(PC.Pawn))
		{
			PC.ClimbStuckSince = 0.0;
			continue;
		}
		if (PC.ClimbStuckSince == 0.0)
		{
			PC.ClimbStuckSince = Level.TimeSeconds;
		}
		else if (Level.TimeSeconds - PC.ClimbStuckSince > 4.0)
		{
			T("climb: " $ PC.PlayerReplicationInfo.PlayerName $ "'s hero still in " $ string(PC.Pawn.GetStateName()) $ " after 4 s at " $ string(PC.Pawn.Location)
				$ ", put on the climb's top " $ string(KWPawn(PC.Pawn).MountDestination));
			Class'Enhanced.EnhancedPlayerController'.static.EndClimb(PC.Pawn);
			PC.ClientEndClimb(PC.Pawn.Location);
			PC.ClimbStuckSince = 0.0;
		}
	}

	// the stump of the swamp's climbing lesson (CutSceneTrigger15 "CS_climb" at -13580,-2020): both players' climbs there had the yaw 28772 (owner's logs)
	if (!bClimbTested && ClimbTestAt > 0.0 && Level.TimeSeconds > ClimbTestAt && ActiveCut == None && MapName() ~= "1_Shreks_Swamp")
	{
		for (i = 0; i < GPC.Length; i++)
		{
			PC = EnhancedPlayerController(GPC[i]);
			if (PC != None && PC.Pawn != None && !PC.bLocalCutBusy)
			{
				bClimbTested = true;
				bPlaced = PC.Pawn.SetLocation(vect(-13741.0, -1960.0, -60.0));
				PC.Pawn.SetRotation(rot(0, 28772, 0));
				PC.SetRotation(rot(0, 28772, 0));
				PC.ClientSetRotation(rot(0, 28772, 0));
				PC.ClientClimbTest();
				ClimbWatch = PC;
				ClimbWatchUntil = Level.TimeSeconds + 16.0;
				T("climb test: " $ PC.PlayerReplicationInfo.PlayerName $ " put in front of the stump (" $ string(bPlaced) $ ")");
				break;
			}
		}
	}
	if (ClimbWatch != None && ClimbWatch.Pawn != None && Level.TimeSeconds < ClimbWatchUntil && Level.TimeSeconds - ClimbLogAt >= 0.25)
	{
		ClimbLogAt = Level.TimeSeconds;
		Log("[CLIMB] server at " $ string(ClimbWatch.Pawn.Location) $ " state " $ string(ClimbWatch.Pawn.GetStateName()) $ " phys " $ string(int(ClimbWatch.Pawn.Physics))
			$ " base " $ string(ClimbWatch.Pawn.Base));
	}

	if (BagTestAt > 0.0)
	{
		BagTestTick();
	}

	if (!bBonusTested && BonusTestAt > 0.0 && Level.TimeSeconds > BonusTestAt)
	{
		bBonusTested = true;
		foreach AllActors(Class'Enhanced.EnhancedLeaveBonus', X)
		{
			T("test: the exit of the bonus level " $ string(X) $ " is activated");
			X.PerformLevelTravel();
			break;
		}
	}

	if (bGotoDone || GotoAt <= 0.0 || GotoMap == "" || Level.TimeSeconds < GotoAt || !IsMenuLevel())
	{
		return;
	}
	for (C = Level.ControllerList; C != None; C = C.NextController)
	{
		if (PlayerController(C) != None)
		{
			bGotoDone = true;
			T("test: the front-end level opens " $ GotoMap);
			PlayerController(C).ConsoleCommand("open " $ GotoMap $ ".unr?Game=Enhanced.EnhancedGame?EnhSkipIntro=1?EnhHostMenu=10?EnhGoto=?EnhGotoAt=?Lobby=?listen=");
			return;
		}
	}
}

function JitterTick(float DeltaTime)
{
	local int i;
	local Pawn P;

	if (!bJitterOpt)
	{
		return;
	}
	JitterClock += DeltaTime;
	if (JitterClock < 0.1)
	{
		return;
	}
	JitterClock = 0.0;
	for (i = 0; i < GPC.Length; i++)
	{
		P = GPC[i].Pawn;
		if (P != None)
		{
			Log("[JIT] g" $ string(i) $ " t=" $ string(Level.TimeSeconds) $ " loc=" $ string(P.Location.X) $ "," $ string(P.Location.Y) $ "," $ string(P.Location.Z)
				$ " vel=" $ string(int(VSize(P.Velocity))) $ " phys=" $ string(int(P.Physics)) $ " state=" $ string(P.GetStateName()) $ " base=" $ string(P.Base) $ " yaw=" $ string(P.Rotation.Yaw & 65535) $ " cyaw=" $ string(P.Controller.Rotation.Yaw & 65535) $ " vyaw=" $ string(EnhancedPlayerController(P.Controller).ViewYawSrv) $ " des=" $ string(P.DesiredRotation.Yaw & 65535) $ " rtd=" $ P.GetPropertyText("bRotateToDesired") $ " anim=" $ P.GetPropertyText("AnimSequence") $ " ing=" $ string(P.IsAnimating(0)) $ " sim=" $ P.GetPropertyText("SimAnim") $ " ctl=" $ string(P.Controller) $ AnimInfo(P));
		}
	}
	if (HostController() != None && HostController().Pawn != None)
	{
		Log("[JITH] t=" $ string(Level.TimeSeconds) $ " vel=" $ string(int(VSize(HostController().Pawn.Velocity))) $ " state=" $ string(HostController().Pawn.GetStateName()) $ AnimInfo(HostController().Pawn));
	}
}

// Tests only: the game's own screenshot command at the listed times (seconds of the level).
function TakeShots()
{
	local string S;
	local int i, P, ShotAt;
	local PlayerController Host;

	if (ShotTimes == "")
	{
		return;
	}
	S = ShotTimes;
	for (i = 0; i < ShotsTaken; i++)
	{
		P = InStr(S, ",");
		if (P < 0)
		{
			return;
		}
		S = Mid(S, P + 1);
	}
	P = InStr(S, ",");
	if (P >= 0)
	{
		S = Left(S, P);
	}
	ShotAt = int(S);
	if (Level.TimeSeconds >= float(ShotAt))
	{
		Host = HostController();
		if (Host != None)
		{
			ShotsTaken++;
			Host.ConsoleCommand("shot");
			T("shot " $ string(ShotsTaken) $ " taken at " $ string(int(Level.TimeSeconds)));
		}
	}
}

// ---- Death in co-op ----

// Every half second (Poll). The stock death state of a hero ends in "stop" unless the game is single-player, so in a network game a player who
// went down stays on the ground. He waits there: a friend who stands next to him for a moment helps him up (ReviveHero, 10% of the health).
// The level is loaded again from the last co-op checkpoint only when everybody is down for five seconds.
function Pawn PlayerPawn(int i)
{
	local PlayerController Host;

	if (i == 0)
	{
		Host = HostController();
		if (Host != None)
		{
			return Host.Pawn;
		}
		return None;
	}
	if (i - 1 < GPawn.Length)
	{
		return GPawn[i - 1];
	}
	return None;
}

// The text with its first %s replaced by a name.
function string FillName(string Text, string Name)
{
	local int k;

	k = InStr(Text, "%s");
	if (k < 0)
	{
		return Text;
	}
	return Left(Text, k) $ Name $ Mid(Text, k + 2);
}

function string PlayerLabel(int i)
{
	local Pawn P;

	P = PlayerPawn(i);
	if (P != None && P.PlayerReplicationInfo != None && P.PlayerReplicationInfo.PlayerName != "")
	{
		return P.PlayerReplicationInfo.PlayerName;
	}
	return "?";
}

function DeathWatch()
{
	local Pawn P, A;
	local int i, j, total, downs, n;
	local bool bNear;
	local string Near;

	if (IsMenuLevel() || IsCutsceneLevel() || bRestarting)
	{
		return;
	}
	n = Min(GPC.Length + 1, 4);
	for (i = 0; i < n; i++)
	{
		P = PlayerPawn(i);
		if (P == None || P.bHidden)
		{
			DownSince[i] = 0.0;
			ReviveSince[i] = 0.0;
			continue;
		}
		total++;
		if (!P.IsInState('stateHeroDying'))
		{
			DownSince[i] = 0.0;
			ReviveSince[i] = 0.0;
			continue;
		}
		downs++;
		if (DownSince[i] == 0.0)
		{
			DownSince[i] = Level.TimeSeconds;
			T("death: " $ PlayerLabel(i) $ " is down and waits for help");
		}
		bNear = false;
		for (j = 0; j < n; j++)
		{
			A = PlayerPawn(j);
			if (j != i && A != None && !A.bHidden && !A.IsInState('stateHeroDying') && VSize(A.Location - P.Location) < 170.0)
			{
				bNear = true;
				Near = PlayerLabel(j);
			}
		}
		if (bNear && Level.TimeSeconds - DownSince[i] > 2.0)
		{
			if (ReviveSince[i] == 0.0)
			{
				ReviveSince[i] = Level.TimeSeconds;
			}
			else if (Level.TimeSeconds - ReviveSince[i] >= 1.5)
			{
				ReviveHero(P, i, Near);
				DownSince[i] = 0.0;
				ReviveSince[i] = 0.0;
			}
		}
		else
		{
			ReviveSince[i] = 0.0;
		}
	}
	SetDownNotes(n);
	if (total > 0 && downs == total)
	{
		if (AllDownSince == 0.0)
		{
			AllDownSince = Level.TimeSeconds;
			T("death: everybody is down");
		}
		else if (Level.TimeSeconds - AllDownSince > 5.0)
		{
			RestartFromCheckpoint();
		}
	}
	else
	{
		AllDownSince = 0.0;
	}
}

// The hints: to the downed player "wait for help", to the others "go to <name>" (the host's through the subtitle line, the guests' through their controllers).
function SetDownNotes(int n)
{
	local int i, j;
	local string Mine, Other, Who;
	local Pawn P;
	local EnhancedPlayerController C;

	for (i = 0; i < n; i++)
	{
		Mine = "";
		Other = "";
		P = PlayerPawn(i);
		if (P != None && !P.bHidden && !P.IsInState('stateHeroDying'))
		{
			for (j = 0; j < n; j++)
			{
				if (j != i && DownSince[j] != 0.0)
				{
					Who = PlayerLabel(j);
					Other = FillName(Localize("Lobby", "DownOther", "Enhanced"), Who);
				}
			}
		}
		else if (P != None && DownSince[i] != 0.0)
		{
			Mine = Localize("Lobby", "DownSelf", "Enhanced");
		}
		if (i == 0)
		{
			DownNoteHost = Mine $ Other;
		}
		else if (i - 1 < GPC.Length)
		{
			C = EnhancedPlayerController(GPC[i - 1]);
			if (C != None)
			{
				C.DownNote = Class'Enhanced.EnhancedText'.static.Encode(Mine $ Other);
			}
		}
	}
}

// Helps a downed player up: back on his feet where he lay, with a tenth of the full health (100 per shamrock of the shared inventory, plus 100).
function ReviveHero(Pawn P, int Index, string By)
{
	local PlayerController Host;
	local int Mx, Hp;

	Mx = 100;
	Host = HostController();
	if (Host != None && KWPawn(Host.Pawn) != None)
	{
		Mx = 100 * (InvOf(Host.Pawn).GetInventoryCount('Shamrock') + 1);
	}
	Hp = Max(1, Mx / 10);
	P.SetPropertyText("Health", string(Hp));
	P.GotoState('StateIdle');
	P.SetPhysics(PHYS_Falling);
	P.PlayAnim('getupback', 1.0, 0.1);
	T("death: " $ PlayerLabel(Index) $ " was helped up by " $ By $ ", health " $ string(Hp) $ " of " $ string(Mx));
}

// Every frame: a downed Shrek does not walk away (the controller of a guest keeps sending his moves).
function DownFreeze()
{
	local int i, n;
	local Pawn P;

	n = Min(GPC.Length + 1, 4);
	for (i = 0; i < n; i++)
	{
		if (DownSince[i] != 0.0)
		{
			P = PlayerPawn(i);
			if (P != None && P.IsInState('stateHeroDying'))
			{
				P.Acceleration = vect(0.0, 0.0, 0.0);
				if (P.Physics == PHYS_Walking)
				{
					P.Velocity = vect(0.0, 0.0, 0.0);
				}
			}
		}
	}
}

function RestartFromCheckpoint()
{
	local EnhancedSaveData R;
	local string Opt, Map, Slot;

	bRestarting = true;
	Map = MapName();
	Slot = "";
	if (SessionId != "")
	{
		R = new(None, "coop_" $ SessionId) Class'Enhanced.EnhancedSaveData';
		if (R.Map != "")
		{
			Map = R.Map;
			Slot = "coop_" $ SessionId;
		}
	}
	Opt = "?Game=Enhanced.EnhancedGame?listen?EnhWait=1?EnhPlayers=" $ string(PlayerCount());
	if (SessionId != "")
	{
		Opt = Opt $ "?EnhSession=" $ SessionId;
	}
	if (Slot != "")
	{
		Opt = Opt $ "?EnhLoad=" $ Slot;
	}
	if (FriendlyFire > 0.0)
	{
		Opt = Opt $ "?FriendlyFire=1";
	}
	T("death: the host died, restarting at " $ Map $ " from '" $ Slot $ "'");
	Level.ServerTravel(Map $ Opt, false);
}

// Tests only (URL option EnhDeathTest=1): at 12 s player two is killed, at 40 s the host.
function DeathTestTick(float DeltaTime)
{
	local PlayerController Host;

	if (DeathTestMode == "" || PendingPC == None || PendingPC.Pawn == None)
	{
		return;
	}
	Host = HostController();
	if (Host == None || Host.Pawn == None)
	{
		return;
	}
	DeathTestClock += DeltaTime;
	if (DeathTestStep == 0 && DeathTestClock > 12.0)
	{
		DeathTestStep = 1;
		T("death test: killing player two");
		PendingPC.Pawn.TakeDamage(10000, None, PendingPC.Pawn.Location, vect(0.0, 0.0, 0.0), Class'Engine.DamageType');
	}
	else if (DeathTestStep == 1 && DeathTestClock > 40.0)
	{
		DeathTestStep = 2;
		T("death test: killing the host");
		Host.Pawn.TakeDamage(10000, None, Host.Pawn.Location, vect(0.0, 0.0, 0.0), Class'Engine.DamageType');
	}
}

// ---- Cutscene gates ----

function RegisterGate(Actor A)
{
	GateT[GateT.Length] = A;
	T("gate registered: " $ string(A) $ " at " $ string(A.Location) $ " event " $ string(A.Event) $ " radius " $ string(int(A.CollisionRadius)));
}

function bool HasEntry(array<Controller> Ctl, array<int> Idx, int g, Controller C)
{
	local int i;

	for (i = 0; i < Ctl.Length; i++)
	{
		if (Ctl[i] == C && Idx[i] == g)
		{
			return true;
		}
	}
	return false;
}

function DropEntry(out array<Controller> Ctl, out array<int> Idx, int g, Controller C)
{
	local int i;

	for (i = Ctl.Length - 1; i >= 0; i--)
	{
		if (Ctl[i] == C && Idx[i] == g)
		{
			Ctl.Remove(i, 1);
			Idx.Remove(i, 1);
		}
	}
}

// A waiting player is let go of a gate (the three lists of the waiting players stay in step).
function DropPass(int g, Controller C)
{
	local int i;

	for (i = PassCtl.Length - 1; i >= 0; i--)
	{
		if (PassCtl[i] == C && PassGate[i] == g)
		{
			PassCtl.Remove(i, 1);
			PassGate.Remove(i, 1);
			PassTime.Remove(i, 1);
		}
	}
}

// When the first of the waiting players reached this gate (0 if nobody waits).
function float WaitingSince(int g)
{
	local int i;
	local float R;

	for (i = 0; i < PassGate.Length; i++)
	{
		if (PassGate[i] == g && (R == 0.0 || PassTime[i] < R))
		{
			R = PassTime[i];
		}
	}
	return R;
}

// Is the pawn inside the volume of the trigger (its collision cylinder grown by the pawn's own).
function bool InGateZone(Actor Trig, Pawn P)
{
	local Vector D;

	D = P.Location - Trig.Location;
	if (Abs(D.Z) > Trig.CollisionHeight + P.CollisionHeight)
	{
		return false;
	}
	D.Z = 0.0;
	return VSize(D) <= Trig.CollisionRadius + P.CollisionRadius;
}

function bool GateLive(int g)
{
	local Actor A;

	A = GateT[g];
	return A != None && !A.bDeleteMe && Trigger(A).bInitiallyActive && !A.IsInState('StateNothing');
}

// Every frame (EnhancedTicker): who passes which gate, whether a gate is complete, and the leash of those who wait.
function GateTick(float DeltaTime)
{
	local int g, nWait, nAll;
	local Controller C;
	local PlayerController PC;
	local Pawn P;
	local Vector D, Edge;
	local bool bWaitGuests;

	if (IsMenuLevel() || IsCutsceneLevel() || GateT.Length == 0)
	{
		return;
	}
	// after a level change the guests come back a few seconds after the host: nothing is counted until all of them are here
	bWaitGuests = PlayerCount() < ExpectedPlayers && Level.TimeSeconds < 60.0;
	for (g = 0; g < GateT.Length; g++)
	{
		if (!GateLive(g))
		{
			continue;
		}
		if (GateT[g].bCollideActors)
		{
			GateT[g].SetCollision(false, false, false);   // it must not fire by itself (a level event may switch it on again)
		}
		if (bWaitGuests)
		{
			continue;
		}
		nWait = 0;
		nAll = 0;
		for (C = Level.ControllerList; C != None; C = C.NextController)
		{
			PC = PlayerController(C);
			if (PC == None)
			{
				continue;
			}
			nAll++;   // everybody who is connected counts, also a player who has no Shrek yet (he has not passed)
			if (PC.Pawn == None || PC.Pawn.bHidden)
			{
				continue;
			}
			P = PC.Pawn;
			if (InGateZone(GateT[g], P))
			{
				if (!HasEntry(LatchCtl, LatchGate, g, C) && !HasEntry(PassCtl, PassGate, g, C))
				{
					PassCtl[PassCtl.Length] = C;
					PassGate[PassGate.Length] = g;
					PassTime[PassTime.Length] = Level.TimeSeconds;
					T("gate " $ string(GateT[g]) $ ": " $ string(PC) $ " has passed");
				}
			}
			else
			{
				DropEntry(LatchCtl, LatchGate, g, C);
			}
			if (HasEntry(PassCtl, PassGate, g, C))
			{
				nWait++;
			}
		}
		if (nWait > 0 && nWait < nAll && GateTimeout > 0.0 && Level.TimeSeconds - WaitingSince(g) > GateTimeout)
		{
			T("gate " $ string(GateT[g]) $ ": the partner did not come in " $ string(int(GateTimeout)) $ " s, the scene starts anyway");
			nWait = nAll;
		}
		if (nAll > 0 && nWait >= nAll)
		{
			T("gate " $ string(GateT[g]) $ ": everybody has passed, the scene starts");
			P = None;
			for (C = Level.ControllerList; C != None; C = C.NextController)
			{
				if (HasEntry(PassCtl, PassGate, g, C))
				{
					DropPass(g, C);
					LatchCtl[LatchCtl.Length] = C;
					LatchGate[LatchGate.Length] = g;
					if (P == None && C.Pawn != None)
					{
						P = C.Pawn;
					}
				}
			}
			SetGateNote(None, "");
			GateT[g].Trigger(P, P);
		}
		else if (nWait > 0)
		{
			// the ones who came first wait, within reach of the trigger
			for (C = Level.ControllerList; C != None; C = C.NextController)
			{
				PC = PlayerController(C);
				if (PC != None && PC.Pawn != None && HasEntry(PassCtl, PassGate, g, C))
				{
					SetGateNote(PC, Localize("Lobby", "GateWait", "Enhanced"));
					D = PC.Pawn.Location - GateT[g].Location;
					D.Z = 0.0;
					if (VSize(D) > GateLeash)
					{
						Edge = GateT[g].Location + Normal(D) * (GateLeash - 20.0);
						Edge.Z = PC.Pawn.Location.Z;
						PC.Pawn.SetLocation(Edge);
						PC.Pawn.Velocity.X = 0.0;
						PC.Pawn.Velocity.Y = 0.0;
						if (EnhancedPlayerController(PC) != None)
						{
							PC.ClientSetLocation(Edge, PC.Rotation);
						}
					}
				}
			}
		}
	}
}

// The host's note goes out as a subtitle line, renewed every two seconds; the HUD actor itself gets no tick of its own to do it.
function ShowHostNote()
{
	local PlayerController Host;
	local string S;

	S = "";
	if (LeavePrompt != None && LeavePrompt.bAsking)
	{
		S = FillName(Localize("Lobby", "LeaveAsk1", "Enhanced"), LeavePrompt.Nick) $ " " $ Localize("Lobby", "LeaveAsk2", "Enhanced") $ "  " $ Localize("Lobby", "LeaveKeys", "Enhanced");
	}
	else if (bHold)
	{
		S = FillName(FillName(Localize("Lobby", "Waiting", "Enhanced"), string(GPC.Length + 1)), string(Max(ExpectedPlayers, GPC.Length + 1)));
	}
	else if (GateNoteHost != "")
	{
		S = GateNoteHost;
	}
	else if (DownNoteHost != "")
	{
		S = DownNoteHost;
	}
	else if (LeashNoteHost != "")
	{
		S = LeashNoteHost;
	}
	if (S == "" || Level.TimeSeconds - NoteTime < 2.0)
	{
		return;
	}
	Host = HostController();
	if (Host != None && KWHud(Host.myHUD) != None && KWHud(Host.myHUD).CutTextController != None)
	{
		// a cutscene's own subtitles use this line: our notes wait until it is over (they ran against each other)
		if (KWHud(Host.myHUD).CutTextController.bCutSceneInProgress)
		{
			return;
		}
		NoteTime = Level.TimeSeconds;
		HostNoteText = S;
		KWHud(Host.myHUD).CutTextController.SetText(S, 2.5);
	}
}

// The hint "wait for your partner": on the host's HUD through the game, on a guest's through his controller.
function SetGateNote(PlayerController PC, string S)
{
	local Controller C;

	if (PC == None)
	{
		GateNoteHost = "";
		for (C = Level.ControllerList; C != None; C = C.NextController)
		{
			if (EnhancedPlayerController(C) != None)
			{
				EnhancedPlayerController(C).GateNote = "";
			}
		}
		return;
	}
	if (EnhancedPlayerController(PC) != None)
	{
		EnhancedPlayerController(PC).GateNote = Class'Enhanced.EnhancedText'.static.Encode(S);
	}
	else
	{
		GateNoteHost = S;
	}
}

// Tests only (URL option EnhGateTest): at 15 s the host is put into the first gate, at 22 s he is thrown far away from it, at 27 s the
// second player is put into the gate. The log shows the wall holding the first one and the scene starting when the second arrives.
function GateTestTick(float DeltaTime)
{
	local PlayerController Host;
	local Vector V;
	local int i;

	if (GateTestMode == "" || GateT.Length == 0 || PendingPC == None || PendingPC.Pawn == None)
	{
		return;
	}
	Host = HostController();
	if (Host == None || Host.Pawn == None)
	{
		return;
	}
	GateTestClock += DeltaTime;
	if (GateTestStep == 0 && GateTestClock > 15.0)
	{
		GateTestStep = 1;
		GateTestIdx = -1;
		for (i = 0; i < GateT.Length; i++)
		{
			if (GateLive(i) && GateT[i].Event != 'None' && GateT[i].CollisionRadius >= 100.0 && VSize(GateT[i].Location - Host.Pawn.Location) > 1500.0
				&& (GateTestIdx < 0 || VSize(GateT[i].Location - Host.Pawn.Location) < VSize(GateT[GateTestIdx].Location - Host.Pawn.Location)))
			{
				GateTestIdx = i;
			}
		}
		if (GateTestIdx < 0)
		{
			T("gate test: no suitable gate");
			GateTestStep = 9;
			return;
		}
		T("gate test: the gate is " $ string(GateT[GateTestIdx]) $ " (" $ string(GateT[GateTestIdx].Event) $ ")");
		V = GateT[GateTestIdx].Location;
		V.Z += 60.0;
		Host.Pawn.SetLocation(V);
		T("gate test: host put into the gate");
	}
	else if (GateTestStep == 1 && GateTestClock > 22.0)
	{
		GateTestStep = 2;
		for (i = 0; i < 8; i++)
		{
			V = GateT[GateTestIdx].Location;
			V.X += 1300.0 * Cos(float(i) * 0.7853982);
			V.Y += 1300.0 * Sin(float(i) * 0.7853982);
			V.Z += 80.0;
			if (Host.Pawn.SetLocation(V))
			{
				break;
			}
		}
		T("gate test: host thrown 1300 units away (direction " $ string(i) $ "), at " $ string(Host.Pawn.Location));
	}
	else if (GateTestStep == 2 && GateTestClock > 27.0)
	{
		GateTestStep = 3;
		T("gate test: host now at " $ string(Host.Pawn.Location) $ ", distance from the gate " $ string(int(VSize(Host.Pawn.Location - GateT[GateTestIdx].Location))));
		V = GateT[GateTestIdx].Location;
		V.Z += 60.0;
		PendingPC.Pawn.SetLocation(V);
		T("gate test: player two put into the gate");
	}
}

// ---- The leash and the exits ----

function RegisterExit(Actor A)
{
	Exits[Exits.Length] = A;
	ExitOpen[ExitOpen.Length] = 1;
	T("exit registered: " $ string(A) $ " at " $ string(A.Location) $ ", leads to " $ A.GetPropertyText("NewMapName"));
}

// An exit (level-change trigger) works only while every player is within ExitRadius of it. Disabling its
// collision is enough: the game's own trigger and level-change code is not touched, it just never fires.
function UpdateExits()
{
	local int i, nOpen;
	local bool bOk;
	local Actor X;
	local Controller C;
	local PlayerController PC;

	for (i = 0; i < Exits.Length; i++)
	{
		X = Exits[i];
		if (X != None)
		{
			bOk = true;
			for (C = Level.ControllerList; C != None; C = C.NextController)
			{
				PC = PlayerController(C);
				if (PC != None && PC.Pawn != None && VSize(PC.Pawn.Location - X.Location) > ExitRadius)
				{
					bOk = false;
				}
			}
			nOpen = 0;
			if (bOk)
			{
				nOpen = 1;
			}
			if (nOpen != ExitOpen[i])
			{
				ExitOpen[i] = nOpen;
				X.SetCollision(bOk, X.bBlockActors, X.bBlockPlayers);
				T("exit " $ string(X) $ " is now " $ string(bOk) $ " (all players within " $ string(int(ExitRadius)) $ " units)");
			}
		}
	}
}

// Two players may not drift apart for good: when they are farther apart than LeashDistance for longer than
// LeashGrace, the one who ran ahead (farther from the last checkpoint, or from the level start) is brought
// back, to the last checkpoint if his partner is within reach of it, otherwise to his partner.
// He sees the seconds left on his screen first (the old warning was a client message, which a guest's controller swallows: guests were moved
// without a word). Nobody is moved during a cutscene (the cutscene hides and places the heroes itself), while somebody is down, or while the
// one ahead waits at a cutscene gate (the gate holds him there on purpose; moving him away broke the wait).
function CheckLeash()
{
	local Controller C;
	local PlayerController PC, Runaway, Other;
	local array<PlayerController> L;
	local Vector Ref, Target, Center;
	local Rotator SpotRot;
	local float d, dd;
	local int i;
	local bool bPlaced;

	if (Off("leash") || IsMenuLevel() || IsCutsceneLevel() || bHold || bRestarting)
	{
		StopLeash();
		return;
	}
	for (C = Level.ControllerList; C != None; C = C.NextController)
	{
		PC = PlayerController(C);
		if (PC != None && PC.Pawn != None)
		{
			if (PC.Pawn.bHidden || PC.Pawn.IsInState('stateHeroDying'))
			{
				StopLeash();
				return;
			}
			L[L.Length] = PC;
		}
	}
	if (L.Length < 2)
	{
		StopLeash();
		return;
	}
	if (bHaveCheckpointLoc)
	{
		Ref = LastCheckpointLoc;
	}
	else
	{
		// the start of the level is looked up once (it was looked up, and written to the log, on every frame)
		if (LeashStartState == 0)
		{
			LeashStartState = 2;
			if (FindStartSpot(LeashStart, SpotRot))
			{
				LeashStartState = 1;
			}
		}
		if (LeashStartState == 1)
		{
			Ref = LeashStart;
		}
		else
		{
			Ref = L[0].Pawn.Location;
		}
	}
	// the anchor is the player nearest to the checkpoint (or the start); the runaway is whoever is farthest from the anchor
	Other = L[0];
	for (i = 1; i < L.Length; i++)
	{
		if (VSize(L[i].Pawn.Location - Ref) < VSize(Other.Pawn.Location - Ref))
		{
			Other = L[i];
		}
	}
	Runaway = None;
	d = 0.0;
	for (i = 0; i < L.Length; i++)
	{
		dd = VSize(L[i].Pawn.Location - Other.Pawn.Location);
		if (dd > d)
		{
			d = dd;
			Runaway = L[i];
		}
	}
	if (Runaway == None || d <= LeashDistance || AtGate(Runaway))
	{
		StopLeash();
		return;
	}
	if (LeashSince == 0.0 || LeashWarned != Runaway)
	{
		StopLeash();
		LeashSince = Level.TimeSeconds;
		LeashWarned = Runaway;
		T("leash: " $ string(int(d)) $ " units apart, " $ string(Runaway) $ " is ahead, back in " $ string(int(LeashGrace)) $ " s");
	}
	if (Level.TimeSeconds - LeashSince < LeashGrace)
	{
		SetLeashNote(Runaway, FillName(Localize("Lobby", "LeashWarn", "Enhanced"), string(int(LeashGrace - (Level.TimeSeconds - LeashSince)) + 1)));
		return;
	}
	StopLeash();
	// a free place on the ground around the checkpoint or the partner (the old way put him right on top of his partner, where the move could fail)
	SetupSpawnScale(Runaway.Pawn);
	if (bHaveCheckpointLoc && VSize(Other.Pawn.Location - LastCheckpointLoc) <= LeashDistance)
	{
		Center = BodyAt(LastCheckpointLoc);
		T("leash: " $ string(Runaway) $ " is returned to the last checkpoint at " $ string(Center));
	}
	else
	{
		Center = Other.Pawn.Location;
		T("leash: " $ string(Runaway) $ " is brought to his partner at " $ string(Center));
	}
	bPlaced = PlaceNear(Runaway.Pawn, Center, Other.Pawn.Rotation);
	if (!bPlaced)
	{
		Target = Center;
		Target.Z += 60.0;
		bPlaced = Runaway.Pawn.SetLocation(Target);
	}
	T("leash: placed=" $ string(bPlaced) $ " at " $ string(Runaway.Pawn.Location));
	Runaway.Pawn.Velocity = vect(0.0, 0.0, 0.0);
	Runaway.Pawn.SetPhysics(PHYS_Falling);
	Runaway.ClientSetLocation(Runaway.Pawn.Location, Runaway.Pawn.Rotation);
}

// the leash is not counting: its note goes away
function StopLeash()
{
	LeashSince = 0.0;
	if (LeashWarned != None)
	{
		SetLeashNote(LeashWarned, "");
		LeashWarned = None;
	}
}

function SetLeashNote(PlayerController PC, string S)
{
	if (EnhancedPlayerController(PC) != None)
	{
		EnhancedPlayerController(PC).LeashNote = Class'Enhanced.EnhancedText'.static.Encode(S);
	}
	else
	{
		LeashNoteHost = S;
	}
}

// the player waits at a cutscene gate he reached first
function bool AtGate(Controller C)
{
	local int i;

	for (i = 0; i < PassCtl.Length; i++)
	{
		if (PassCtl[i] == C)
		{
			return true;
		}
	}
	return false;
}

// where the centre of a hero's body is when he stands on the floor under V (a checkpoint place is kept on the floor, a level start at the body)
function Vector BodyAt(Vector V)
{
	local Vector HitLoc, HitNorm, From, To;

	From = V;
	From.Z += 80.0;
	To = V;
	To.Z -= 600.0;
	if (Trace(HitLoc, HitNorm, To, From, false) != None)
	{
		HitLoc.Z += HostH;
		return HitLoc;
	}
	return V;
}

// Entry point for every save request of the game (see EnhancedHeroController). One request can arrive
// several times within a moment (a trigger plus the autosave); those are merged. The checkpoint counts, and the
// record is taken, only when every player has passed it: those who are there now count at once, the others
// when they arrive (see Poll).
// The bonus level (the Beanstalk coin rounds) is over: back to the level the player left from the wanted poster. The checkpoint the game took when he
// entered it is the record of his session (or the cell he started from); no checkpoint is taken in the bonus level itself (see OnCheckpointRequest).
function ReturnFromBonus()
{
	local string S, Opt, Best, BestStamp;
	local int i;
	local EnhancedSaveData R;

	if (bBonusLeaving)
	{
		return;
	}
	bBonusLeaving = true;
	if (SessionId != "")
	{
		S = "coop_" $ SessionId;
	}
	else
	{
		S = "slot" $ string(SaveCell());
	}
	R = new(None, S) Class'Enhanced.EnhancedSaveData';
	if (R.Map == "" || InStr(Caps(R.Map), "BEANSTALK") >= 0)
	{
		// the cell is unknown or empty: the newest record of the six cells
		Best = "";
		for (i = 0; i < 6; i++)
		{
			R = new(None, "slot" $ string(i)) Class'Enhanced.EnhancedSaveData';
			if (R.Map != "" && (Best == "" || R.Stamp > BestStamp))
			{
				Best = "slot" $ string(i);
				BestStamp = R.Stamp;
			}
		}
		if (Best != "")
		{
			S = Best;
		}
		else
		{
			S = "auto";
		}
		R = new(None, S) Class'Enhanced.EnhancedSaveData';
	}
	T("bonus level left: record '" $ S $ "' map='" $ R.Map $ "' cell=" $ string(SaveCell()));
	if (R.Map == "" || InStr(Caps(R.Map), "BEANSTALK") >= 0)
	{
		T("bonus level left: no record of the level he came from, back to the menu");
		Level.ServerTravel(PlainMenuURL(), false);
		return;
	}
	Opt = "?Game=Enhanced.EnhancedGame?EnhLoad=" $ S;
	if (SessionId != "")
	{
		Opt = Opt $ "?listen?EnhWait=1?EnhSession=" $ SessionId $ "?EnhPlayers=" $ string(PlayerCount());
	}
	if (FriendlyFire > 0.0)
	{
		Opt = Opt $ "?FriendlyFire=1";
	}
	T("bonus level left: back to " $ R.Map $ " from '" $ S $ "'");
	Level.ServerTravel(R.Map $ Opt, false);
}

// Whether a save request of the engine is a "checkpoint" in the sense of the mod: the place the leash brings a runaway back to and a late guest is
// put at. That is the save of a save fairy, or a save of a level's start. The end of a cutscene also asks for a save (the exit command "SaveGame N" of
// KWCutScene, it arrives as SaveSlottedGame in the middle of a level): its record is taken as before, but the place where the players happened to
// stand is no place to come back to. For a fairy the place is the fairy's own, on the ground, not where the player stood when her wand finished.
function bool CheckpointAnchor(string Why, out Vector Origin)
{
	local Actor A, Point, Fairy;
	local float D, DPoint, DFairy;
	local Vector HitLoc, HitNorm, From, To;

	if (Left(Why, 15) ~= "SaveSlottedGame" && Level.TimeSeconds > CkptStartWindow)
	{
		return false;
	}
	DPoint = FairyReach;
	DFairy = FairyReach;
	foreach AllActors(Class'Engine.Actor', A)
	{
		if (A.IsA('SHSavePoint'))
		{
			D = VSize(A.Location - Origin);
			if (D < DPoint)
			{
				DPoint = D;
				Point = A;
			}
		}
		else if (A.IsA('SavePointFairy'))
		{
			D = VSize(A.Location - Origin);
			if (D < DFairy)
			{
				DFairy = D;
				Fairy = A;
			}
		}
	}
	if (Point == None)
	{
		Point = Fairy;
	}
	if (Point != None)
	{
		From = Point.Location;
		From.Z += 80.0;
		To = Point.Location;
		To.Z -= 600.0;
		if (Trace(HitLoc, HitNorm, To, From, false) != None)
		{
			Origin = HitLoc;
		}
		else
		{
			Origin = Point.Location;
		}
		T("checkpoint place: the fairy " $ string(Point) $ " at " $ string(Origin));
	}
	return true;
}

function OnCheckpointRequest(Controller Who, string Why)
{
	local Vector Origin;
	local bool bAnchor;

	// a guest who plays the opening by himself before he joins saves nothing (the opening ends with "SaveGame 1": it would write his own saves)
	if (IntroOnlyHost != "")
	{
		return;
	}

	if (InStr(Caps(MapName()), "BEANSTALK") >= 0)
	{
		T("checkpoint request in the bonus level ignored (" $ Why $ ")");
		return;
	}

	T("checkpoint requested by " $ string(Who) $ " (" $ Why $ ") at t=" $ string(Level.TimeSeconds));
	if (Who != None && Who.Pawn != None)
	{
		Origin = Who.Pawn.Location;
	}
	bAnchor = CheckpointAnchor(Why, Origin);
	if (!bAnchor)
	{
		T("this save is not a fairy's or a level start's (the end of a cutscene or a script): the record is taken, but it is not a place to come back to");
	}
	if (bCkptPending)
	{
		if (VSize(Origin - CkptLoc) <= CheckpointRadius && (bCkptAnchor || !bAnchor))
		{
			T("checkpoint request merged with the one that is waiting");
			return;
		}
		T("checkpoint request at a new place replaces the waiting one");
	}
	else if (Level.TimeSeconds - LastCheckpointTime < 1.0 && LastCheckpointTime > 0.0)
	{
		if (bAnchor)
		{
			LastCheckpointLoc = Origin;
			bHaveCheckpointLoc = true;
		}
		T("checkpoint merged with the previous request");
		return;
	}
	bCkptAnchor = bAnchor;
	CkptLoc = Origin;
	CkptWhy = Why;
	CkptPassed.Length = 0;
	bCkptPending = true;
	MarkPassed();
	if (AllPassed())
	{
		FinishCheckpoint("everybody was there");
		return;
	}
	T("checkpoint waits for the other player(s): " $ string(CkptPassed.Length) $ " of " $ string(PlayersWithPawn()) $ " have passed");
}

function FinishCheckpoint(string How)
{
	bCkptPending = false;
	if (bCkptAnchor)
	{
		LastCheckpointLoc = CkptLoc;
		bHaveCheckpointLoc = true;
	}
	LastCheckpointTime = Level.TimeSeconds;
	T("checkpoint counts (" $ How $ "): " $ string(PlayersWithPawn()) $ " player(s), recording");
	if (SessionId != "")
	{
		CaptureCheckpoint("coop_" $ SessionId, CkptWhy);
		RegisterCoopSave("coop_" $ SessionId);
	}
	else
	{
		CaptureCheckpoint("auto", CkptWhy);
		// the cell of the save window the player picked (a record per cell: the window lists them, see EnhancedSavesPage)
		CaptureCheckpoint("slot" $ string(SaveCell()), CkptWhy);
	}
}

// The cell (0..5) of the save window the host chose when he started or continued this game.
function int SaveCell()
{
	local Controller C;
	local int N;

	for (C = Level.ControllerList; C != None; C = C.NextController)
	{
		if (PlayerController(C) != None && NetConnection(PlayerController(C).Player) == None)
		{
			N = int(C.GetPropertyText("iSaveSlotID"));
			if (N >= 0 && N < 6)
			{
				return N;
			}
		}
	}
	return 0;
}

// Twice a second (from EnhancedTicker): a waiting checkpoint is completed as soon as the last player has passed it.
function Poll()
{
	if (HopMode != "")
	{
		HopTick();
		return;
	}
	if (bIntroPaused)
	{
		return;
	}
	// The players were gathered in the menu's room; after the level change they come back one by one. The opening cutscene starts 3 s after the last of
	// them is back, and without waiting for ever for one who did not come (a minute and a half after the level began).
	if (bHold)
	{
		if (GPC.Length >= Max(1, ExpectedPlayers - 1))
		{
			if (HoldSince == 0.0)
			{
				HoldSince = Level.TimeSeconds;
			}
			else if (Level.TimeSeconds > HoldSince + 3.0)
			{
				ReleaseIntro("everybody is back");
			}
		}
		else if (Level.TimeSeconds > 90.0)
		{
			ReleaseIntro("the players who did not come back are not waited for any longer");
		}
	}
	if (Beacon != None && Level.TimeSeconds - NetLogTime > 4.0)
	{
		NetLogTime = Level.TimeSeconds;
		Beacon.Prune();
		Log("[SDBG] lan: " $ NetTestMode $ " mode, games known: " $ string(Beacon.Addrs.Length));
	}
	if (Upnp != None && Level.TimeSeconds - NetLogTime > 3.0)
	{
		NetLogTime = Level.TimeSeconds;
		Log("[SDBG] upnp status: stage " $ string(Upnp.Stage) $ " - " $ Upnp.Status);
	}
	if (LobbyMode == "host" && Beacon != None && Level.TimeSeconds - LobbyTimer > 2.0)
	{
		LobbyTimer = Level.TimeSeconds;
		Beacon.SetHostLine(HostLine());
	}
	if (!bResListDone && HostController() != None)
	{
		PatchResolutionList();
	}
	if (IntroOnlyHost != "")
	{
		IntroOnlyTick();
	}
	TakeShots();
	HeroTweaks();
	SaveTestTick();
	SyncGuestHud();
	EnsureAnimSync();
	IdleWatch();
	WatchCutscenes();
	HeroTick();
	MusicTick();
	DeathWatch();
	ManageSecond();
	SyncFriendlyFire();
	CheckLeash();
	UpdateExits();
	if (bCkptPending)
	{
		MarkPassed();
		if (AllPassed())
		{
			FinishCheckpoint("the last player arrived");
		}
	}
}

// Measurement: n captures in one frame without writing, then the frame time shows the cost.
function BenchCapture(int n)
{
	local int i;

	bQuiet = true;
	for (i = 0; i < n; i++)
	{
		CaptureCheckpoint("bench", "bench", true);
	}
	bQuiet = false;
	T("bench: " $ string(n) $ " captures done");
}

// Reads the record back from the file and reports what is in it.
function VerifyCheckpoint(string Slot)
{
	local EnhancedSaveData D;

	D = new(None, Slot) Class'Enhanced.EnhancedSaveData';
	T("verify: slot " $ Slot $ " map=" $ D.Map $ " state=" $ D.GameState $ " stamp=" $ D.Stamp
		$ " keys=" $ string(D.Keys.Length) $ " values=" $ string(D.Values.Length)
		$ " heroes=" $ string(D.Heroes.Length) $ " coins=" $ string(D.Coins));
}

function PlayerController HostController()
{
	local Controller C;
	local PlayerController Host;

	for (C = Level.ControllerList; C != None; C = C.NextController)
	{
		if ((C.IsA('EnhancedHeroController') || C.IsA('EnhancedDonkeyController')) && Host == None)
		{
			Host = PlayerController(C);
		}
	}
	return Host;
}

// The measures of the hero the guests are made like: a Shrek's body is about 45 units from his centre to the floor and under 48 wide; a bigger hero (Mongo) spreads the places.
function SetupSpawnScale(Pawn H)
{
	HostH = 45.0;
	RingS = 1.0;
	if (H != None)
	{
		HostH = H.CollisionHeight;
		if (HostH < 20.0)
		{
			HostH = 45.0;
		}
		RingS = FMax(1.0, (H.CollisionRadius + 48.0) / 96.0);
	}
}

// Candidate places around a center: eight directions at two distances, the first to the right of the facing.
// 125 units: right next to the host, but more than two collision radii (a Shrek's is under 50), so they never touch.
function Vector RingSpot(Vector Center, Rotator Rot, int i)
{
	local float r, a;
	local Vector V;

	// five rings of eight places: 125 units from the host, then 190, then a close one (90: a Shrek's collision radius is under 50) for a narrow place such as the
	// mouth of a cave, then 260 and 330 for a place where the near ground is no good
	switch (i / 8)
	{
		case 0:
			r = 125.0;
			break;
		case 1:
			r = 190.0;
			break;
		case 2:
			r = 90.0;
			break;
		case 3:
			r = 260.0;
			break;
		default:
			r = 330.0;
			break;
	}
	a = float(Rot.Yaw) * 0.0000958738 + (i % 8) * 0.7853982 - 1.5707963;
	r *= RingS;
	V = Center;
	V.X += r * Cos(a);
	V.Y += r * Sin(a);
	V.Z += HostH - 5.0;
	return V;
}

// A ring place that is a walkable floor at about the height of the center, in sight of it. A place over a
// ledge or water would drop the new pawn (the first test killed player two by a fall of 119 units).
// A walkable floor under the place V, at about the height of the center and in sight of it (a place over a ledge or water would drop the new pawn).
function bool GroundAt(Vector V, Vector Center, out Vector Spot)
{
	local Vector HitLoc, HitNorm, From, To, P, Q, N2, Probe, SideHit;
	local Actor Hit;
	local float MinNormal, FloorZ;
	local int i;

	// the host stands on a floor 45 units under the centre of his body; the place must be a floor of the same level, flat, with ground all around it and
	// all the way to it (a ledge, a slope or the edge of a rock is refused), in sight of the host
	MinNormal = 0.9;
	if (SpawnFails > 40 || RingS > 1.5)
	{
		MinNormal = 0.7;
	}
	FloorZ = Center.Z - HostH;
	From = V;
	From.Z = Center.Z + HostH + 75.0;
	To = V;
	To.Z = Center.Z - HostH - 155.0;
	Hit = Trace(HitLoc, HitNorm, To, From, false);
	if (Hit == None || HitNorm.Z < MinNormal || Abs(HitLoc.Z - FloorZ) > 30.0 * RingS)
	{
		GroundWhy = "floor: hit=" $ string(Hit) $ " normalZ=" $ string(HitNorm.Z) $ " dz=" $ string(HitLoc.Z - FloorZ);
		return false;
	}
	if (!FastTrace(V, Center))
	{
		GroundWhy = "no line of sight to the host";
		return false;
	}
	if (SpawnFails <= 40 && RingS <= 1.5)
	{
		// ground on the four sides of the place, at about the same height (no edge of a ledge)
		for (i = 0; i < 4; i++)
		{
			Probe = HitLoc;
			if (i == 0)
			{
				Probe.X += 50.0 * RingS;
			}
			else if (i == 1)
			{
				Probe.X -= 50.0 * RingS;
			}
			else if (i == 2)
			{
				Probe.Y += 50.0 * RingS;
			}
			else
			{
				Probe.Y -= 50.0 * RingS;
			}
			P = Probe;
			P.Z = HitLoc.Z + 80.0;
			Q = Probe;
			Q.Z = HitLoc.Z - 80.0;
			if (Trace(SideHit, N2, Q, P, false) == None || Abs(SideHit.Z - HitLoc.Z) > 40.0)
			{
				GroundWhy = "no ground at the side of the place";
				return false;
			}
		}
		// the same ground half way from the host
		Probe = (V + Center) * 0.5;
		P = Probe;
		P.Z = Center.Z + 100.0;
		Q = Probe;
		Q.Z = Center.Z - 120.0;
		if (Trace(SideHit, N2, Q, P, false) == None || Abs(SideHit.Z - FloorZ) > 40.0 || N2.Z < 0.7)
		{
			GroundWhy = "the way to the place is not level ground";
			return false;
		}
	}
	From = V;
	From.Z = Center.Z + 120.0;
	To = V;
	To.Z = Center.Z - 200.0;
	Spot = HitLoc;
	Spot.Z += HostH;
	return true;
}

function bool GroundSpot(Vector Center, Rotator Rot, int i, out Vector Spot)
{
	return GroundAt(RingSpot(Center, Rot, i), Center, Spot);
}

// The places of the guests relative to the host, as a team that walks together: guest 1 beside him on the right and a little behind, guest 2 on his
// left, guest 3 in the middle behind them (distances in units; a Shrek's collision radius is under 50, so they never touch).
function bool FormationSpot(Vector Center, Rotator Rot, int k, out Vector Spot)
{
	local float Fwd, Side, Yaw;
	local Vector V;

	switch (k)
	{
		case 0:
			Fwd = -80.0;
			Side = 130.0;
			break;
		case 1:
			Fwd = -80.0;
			Side = -130.0;
			break;
		default:
			Fwd = -190.0;
			Side = 0.0;
			break;
	}
	Yaw = float(Rot.Yaw) * 0.0000958738;
	V = Center;
	// the right of the heading is (sin yaw, -cos yaw): the same direction the ring places use for their first place
	V.X += Fwd * Cos(Yaw) + Side * Sin(Yaw);
	V.Y += Fwd * Sin(Yaw) - Side * Cos(Yaw);
	V.Z += 40.0;
	if (!GroundAt(V, Center, Spot))
	{
		T("formation place " $ string(k) $ " refused: " $ GroundWhy);
		return false;
	}
	return true;
}

// The i-th try for the current guest. The start of the swamp is a ridge: places straight behind the host are a slope or a drop, so the formation is
// made of the ring around him in a fixed order that looks intended: guest 1 on his right, guest 2 on his left, guest 3 behind him (the ring places
// are 45 degrees apart, place 0 is on the right, 2 ahead, 4 on the left, 6 behind). If a place is not walkable the nearest one of the same ring is taken,
// then the same places on the wider ring.
// The host's hero, also while a cutscene drives him (the host's controller has no pawn then: the cutscene's controller has it, with the host's
// controller as its PendingController).
function Pawn HostHero(PlayerController Host)
{
	local KWPawn P;

	if (Host == None)
	{
		return None;
	}
	if (Host.Pawn != None)
	{
		LastHostHero = Host.Pawn;
		return Host.Pawn;
	}
	if (LastHostHero != None && !LastHostHero.bDeleteMe)
	{
		return LastHostHero;
	}
	foreach DynamicActors(Class'KWGame.KWPawn', P)
	{
		if (KWCutController(P.Controller) != None && KWCutController(P.Controller).PendingController == Host)
		{
			LastHostHero = P;
			return P;
		}
	}
	return None;
}

function bool GuestSpot(PlayerController Host, int i, out Vector Spot)
{
	local int Pref, Step, Ring, Block, Off;

	switch (Max(GuestIndex(PendingPC), 0))
	{
		case 0:
			Pref = 0;
			break;
		case 1:
			Pref = 4;
			break;
		default:
			Pref = 6;
			break;
	}
	Block = i / 8;
	Step = i % 8;
	switch (Step)
	{
		case 0:
			Off = 0;
			break;
		case 1:
			Off = 1;
			break;
		case 2:
			Off = 7;
			break;
		case 3:
			Off = 2;
			break;
		case 4:
			Off = 6;
			break;
		case 5:
			Off = 3;
			break;
		case 6:
			Off = 5;
			break;
		default:
			Off = 4;
			break;
	}
	Ring = Block * 8 + ((Pref + Off) % 8);
	if (bNoRingOpt)
	{
		return false;
	}
	return GroundSpot(JoinCenter, HostHero(Host).Rotation, Ring, Spot);
}

// Puts a pawn on the first free ring place around a center (SetLocation fails where there is no room, so
// a pawn is never pushed into a wall or under the map).
function bool PlaceNear(Pawn P, Vector Center, Rotator Rot)
{
	local int i;
	local Vector V;
	local bool bPlaced;

	for (i = 0; i < 40 && !bPlaced; i++)
	{
		if (GroundSpot(Center, Rot, i, V))
		{
			bPlaced = P.SetLocation(V);
		}
	}
	return bPlaced;
}

// Player two's own Shrek, on a free place of his own next to the host. Called when the host has a pawn,
// i.e. when no cutscene owns him.
// Where a guest who comes in is put: next to the host, unless the host is in a fight (a living enemy within 1800 units) and a checkpoint has been passed:
// then at that checkpoint, a quiet place the level itself offers (the guest walks to the host from there; the leash brings him if he is far). Before any
// checkpoint, and in a level without enemies, next to the host.
// Where the host's hero is in the world. While a cutscene drives him he may stand on its stage (the swamp's opening plays at the house, and the host
// starts at the obstacle course after it): a guest who is through his own cutscene earlier is put where the host's hero stood when it began, and for
// the opening of a level at the level's start.
function Vector HostPlace(PlayerController Host)
{
	if (Host != None && Host.Pawn != None)
	{
		return Host.Pawn.Location;
	}
	if (bCutStartLoc)
	{
		return CutStartHeroLoc;
	}
	return HostHero(Host).Location;
}

function bool ChooseJoinCenter(PlayerController Host)
{
	local Pawn A;
	local Vector HitLoc, HitNorm, From, To, V;
	local int Foes, i, Passed, Saved;

	SetupSpawnScale(HostHero(Host));
	JoinCenter = HostPlace(Host);
	if (!bHaveCheckpointLoc)
	{
		return false;
	}
	foreach DynamicActors(Class'Engine.Pawn', A)
	{
		if (A.IsA('ShEnemy') && float(A.GetPropertyText("Health")) > 0.0 && VSize(A.Location - HostPlace(Host)) < 1800.0)
		{
			Foes++;
		}
	}
	if (Foes == 0)
	{
		return false;
	}
	From = LastCheckpointLoc;
	From.Z += 60.0;
	To = LastCheckpointLoc;
	To.Z -= 400.0;
	if (Trace(HitLoc, HitNorm, To, From, false) == None || HitNorm.Z < 0.7)
	{
		return false;
	}
	JoinCenter = HitLoc;
	JoinCenter.Z += HostH;
	// a checkpoint may stand in a cell, under a low ceiling or in a corner with no room around it (survey of 31 Oct: five checkpoints of the prison and
	// Hamlet levels had no free place at all, and a guest sent there would try for ever): at least four places, with the relaxed rules, or the host's side
	Saved = SpawnFails;
	SpawnFails = 41;
	for (i = 0; i < 40; i++)
	{
		if (GroundSpot(JoinCenter, HostHero(Host).Rotation, i, V))
		{
			Passed++;
		}
	}
	SpawnFails = Saved;
	if (Passed < 4)
	{
		T("join: only " $ string(Passed) $ " free places around the checkpoint " $ string(JoinCenter) $ ", the guest is put next to the host");
		JoinCenter = HostPlace(Host);
		return false;
	}
	T("join: " $ string(Foes) $ " enemies near the host, the guest is put at the last checkpoint " $ string(JoinCenter));
	return true;
}

// The last resort when the ring around the center has no walkable place: the places in front of the host first (he looks at them, the guest comes into
// view at once), then to his sides, then behind, each at a few distances, first in his sight and then, if that gives nothing, through walls too. There is
// no floor rule here except "some floor within 600 units under it" (a void is never chosen); Spawn itself refuses a place that is inside a wall or another actor.
function bool ForcedSpot(Vector Center, Rotator Rot, int k, out Vector Spot)
{
	local float Yaw, Ang, Dist;
	local Vector V, HitLoc, HitNorm, To;
	local int Dir, Far;
	local bool bSight;

	bSight = (k < 28);
	Far = k % 28;
	Dir = Far % 7;
	Far = Far / 7;
	switch (Dir)
	{
		case 0:
			Ang = 0.0;
			break;
		case 1:
			Ang = 0.5236;
			break;
		case 2:
			Ang = -0.5236;
			break;
		case 3:
			Ang = 1.5708;
			break;
		case 4:
			Ang = -1.5708;
			break;
		case 5:
			Ang = 2.6180;
			break;
		default:
			Ang = -2.6180;
			break;
	}
	Dist = (130.0 + 90.0 * Far) * RingS;
	Yaw = float(Rot.Yaw) * 0.0000958738 + Ang;
	V = Center;
	V.X += Dist * Cos(Yaw);
	V.Y += Dist * Sin(Yaw);
	if (bSight && !FastTrace(V, Center))
	{
		return false;
	}
	To = V;
	To.Z -= 600.0;
	if (Trace(HitLoc, HitNorm, To, V, false) == None)
	{
		return false;
	}
	Spot = V;
	return true;
}

function Pawn SpawnGuestPawn(PlayerController Host, Vector Loc)
{
	local Pawn P;

	// the guest is the same hero as the host's (the Donkey in the Hunt and the Donkey levels, Puss in Boots in his levels)
	if (HostHero(Host).IsA('Donkey'))
	{
		P = Spawn(Class'Enhanced.EnhancedDonkey', , 'SecondShrek', Loc, HostHero(Host).Rotation);
	}
	else if (HostHero(Host).IsA('PIB'))
	{
		P = Spawn(Class'Enhanced.EnhancedPib', , 'SecondShrek', Loc, HostHero(Host).Rotation);
	}
	else if (string(HostHero(Host).Class) ~= "ShGame.Shrek")
	{
		P = Spawn(Class'Enhanced.EnhancedShrek', , 'SecondShrek', Loc, HostHero(Host).Rotation);
	}
	else
	{
		// any other hero (Mongo, the human Shrek, the Steed): the same class as the host's
		P = Spawn(HostHero(Host).Class, , 'SecondShrek', Loc, HostHero(Host).Rotation);
	}
	if (P != None)
	{
		CopyHeroValues(HostHero(Host), P);
	}
	return P;
}

// A level sets its own values on the hero it places (the map's actor), a spawned guest had the class defaults: the Steed of 7_Prison_Donkey double
// jumps 128 (96 for a guest), Puss in the factory 4_FGM_PIB dies from falls over 1000 (768), Castle Siege and Hamlet set other run and walk speeds,
// the swamp takes the jump attack away. The guest is the same class as the host's hero: he gets the host's values.
function CopyHeroValues(Pawn From, Pawn To)
{
	local string Names, N, V, Log1;
	local int k;
	local KWPawn KP;

	if (From == None || To == None || Off("herovalues"))
	{
		return;
	}
	Names = "fJumpHeight,fDoubleJumpHeight,DeathIfFallDistance,GroundRunSpeed,GroundWalkSpeed,bCanUseJumpAttack,JumpAttackMoveAhead,";
	while (Names != "")
	{
		k = InStr(Names, ",");
		N = Left(Names, k);
		Names = Mid(Names, k + 1);
		V = From.GetPropertyText(N);
		if (V != "" && To.GetPropertyText(N) != V)
		{
			To.SetPropertyText(N, V);
			Log1 = Log1 $ " " $ N $ "=" $ V;
		}
	}
	KP = KWPawn(To);
	if (KP != None)
	{
		KP.SetJumpVars();
		KP.GroundSpeed = KP.GroundRunSpeed;
		if (KP.GroundRunSpeed > 0.0)
		{
			KP.WalkingPct = KP.GroundWalkSpeed / KP.GroundRunSpeed;
		}
	}
	if (Log1 != "")
	{
		T("spawn: the level's values of the host's hero for " $ string(To) $ ":" $ Log1);
	}
}

// ---- The host's camera stays on his hero ----
// Every frame (EnhancedTicker). Moving a guest's pawn with the stock KWPawn.MovePawn (a telepit, a level's move command) turns the camera of "the
// player" to that pawn: KWGetCamera() is always the host's camera. Outside the host's cutscenes his camera goes back to his own hero at once.
// (The review's telepit fade for a guest is not needed: no retail map places a TelePit, checked with UELib on all 20 maps.)
function HostCameraWatch()
{
	local PlayerController Host;
	local KWHeroController KH;
	local Actor Tgt;

	if (GPC.Length == 0 || Off("camwatch"))
	{
		return;
	}
	Host = HostController();
	KH = KWHeroController(Host);
	if (KH != None && KH.Camera != None && Host.Pawn != None && ActiveCut == None)
	{
		Tgt = KH.Camera.GetCurrentTargetActor();
		if (Pawn(Tgt) != None && Tgt != Host.Pawn && EnhancedPlayerController(Pawn(Tgt).Controller) != None)
		{
			KH.Camera.InitTarget(Host.Pawn, 0.0, false, true);
			T("camera: the host's camera was turned to the guest's " $ string(Tgt) $ ", back on the host's hero");
		}
	}
}

// ---- Fixes taken from MPatcher (Master_64's MPak, Shrek 2.2), the owner's choice of 2026-11-20; ?EnhOff=mpatcher turns them off ----
// Every two seconds (Poll): the Steed double jumps 128 everywhere (the stock has it only in his own level 7_Prison_Donkey, 96 where the others can
// switch to him); Puss in Boots dies from a fall over 1000 everywhere (his factory level's value; 768 elsewhere); the swinging stones and spiked balls
// hit with a cylinder of 100 x 100 instead of a box of 150 x 200 (they hit a hero they visibly missed). The guests' controllers get their hero's jump
// heights: a guest's machine predicts his jumps with them.
function HeroTweaks()
{
	local KWPawn P;
	local Controller C;
	local EnhancedPlayerController G;

	if (Level.TimeSeconds < TweakAt)
	{
		return;
	}
	TweakAt = Level.TimeSeconds + 2.0;
	if (!Off("mpatcher"))
	{
		foreach DynamicActors(Class'KWGame.KWPawn', P)
		{
			if (P.IsA('Steed') && P.fDoubleJumpHeight < 128.0)
			{
				P.fDoubleJumpHeight = 128.0;
				P.SetJumpVars();
				T("mpatcher: " $ string(P) $ " double jumps 128");
			}
			else if (P.IsA('PIB') && int(P.GetPropertyText("DeathIfFallDistance")) < 1000)
			{
				P.SetPropertyText("DeathIfFallDistance", "1000");
				T("mpatcher: " $ string(P) $ " dies from falls over 1000");
			}
		}
		FixSwings(self);
	}
	for (C = Level.ControllerList; C != None; C = C.NextController)
	{
		G = EnhancedPlayerController(C);
		if (G != None && KWPawn(G.Pawn) != None)
		{
			G.HeroJump = KWPawn(G.Pawn).fJumpHeight;
			G.HeroDoubleJump = KWPawn(G.Pawn).fDoubleJumpHeight;
		}
	}
}

// the server's swinging attachments and a guest's copies of them (his movement is predicted against them)
static function FixSwings(Actor Ctx)
{
	local Pawn A;

	foreach Ctx.DynamicActors(Class'Engine.Pawn', A)
	{
		if ((A.IsA('SwingStoneAttachment') || A.IsA('BallSpikedAttachment')) && (A.CollisionRadius != 100.0 || A.CollisionHeight != 100.0))
		{
			A.SetCollisionSize(100.0, 100.0);
			A.SetPropertyText("CollideType", "CT_Cylinder");
			Log("[SDBG] mpatcher: " $ string(A) $ " hits with a cylinder of 100 x 100");
		}
	}
}

// Tests: a stock save (slot 9 of the test profile) with the hero's health at 37 and a picture, three seconds later the load of it; after the load
// PostLoadGame logs the health and the projectors, and one more picture is taken.
function SaveTestTick()
{
	local PlayerController Host;
	local Projector Pj;

	Host = HostController();
	if (Host == None || Host.Pawn == None)
	{
		return;
	}
	if (SaveTestAt > 0.0 && !bSaveTestDone && Level.TimeSeconds >= SaveTestAt)
	{
		bSaveTestDone = true;
		Host.Pawn.SetPropertyText("Health", "37");
		foreach AllActors(Class'Engine.Projector', Pj)
		{
			if (!Pj.IsA('ShadowProjector'))
			{
				Log("[SDBG] save test: projector " $ string(Pj) $ " render info before the save '" $ Pj.GetPropertyText("RenderInfo") $ "'");
			}
		}
		Log("[SDBG] save test: health of " $ string(Host.Pawn) $ " set to " $ Host.Pawn.GetPropertyText("Health") $ ", saving to slot 9");
		Host.ConsoleCommand("shot");
		Host.ConsoleCommand("SaveGame 9");
		SaveTestLoadAt = Level.TimeSeconds + 3.0;
		return;
	}
	if (SaveTestLoadAt > 0.0 && Level.TimeSeconds >= SaveTestLoadAt)
	{
		SaveTestLoadAt = 0.0;
		Log("[SDBG] save test: loading slot 9");
		Host.ConsoleCommand("open ?load=9");
		return;
	}
	if (SaveTestShotAt > 0.0 && Level.TimeSeconds >= SaveTestShotAt)
	{
		SaveTestShotAt = 0.0;
		Log("[SDBG] save test: after the load, health of " $ string(Host.Pawn) $ " " $ Host.Pawn.GetPropertyText("Health"));
		Host.ConsoleCommand("shot");
	}
}

// A stock save game (a save fairy, the single-player game): the heroes' health is kept here and put back after the load (MPatcher saw it lost).
event PreSaveGame()
{
	local KWPawn P;

	// no Super: the Level Editor's engine classes the mod compiles against lack these two events (the stock game classes add nothing to them)
	SavedHeroes.Length = 0;
	SavedHealth.Length = 0;
	foreach DynamicActors(Class'KWGame.KWPawn', P)
	{
		if (P.IsA('ShHeroPawn'))
		{
			SavedHeroes[SavedHeroes.Length] = P;
			SavedHealth[SavedHealth.Length] = P.GetPropertyText("Health");
		}
	}
	Log("[SDBG] save game: the health of " $ string(SavedHeroes.Length) $ " heroes is kept");
}

// After a stock load: the projectors placed in the level (light spots, marks; not the shadows) lost their link to the renderer (transient RenderInfo)
// and are attached again; the heroes' health is put back. Both are logged, so a run shows whether the stock really lost them.
event PostLoadGame(bool bLoadFromSaveGame)
{
	local Projector Pj;
	local int i, nP, nA;
	local string H, R;

	if (!bLoadFromSaveGame || Off("mpatcher"))
	{
		return;
	}
	for (i = 0; i < SavedHeroes.Length; i++)
	{
		if (SavedHeroes[i] == None)
		{
			continue;
		}
		H = SavedHeroes[i].GetPropertyText("Health");
		Log("[SDBG] load game: " $ string(SavedHeroes[i]) $ " health after the load " $ H $ ", at the save " $ SavedHealth[i]);
		if (H != SavedHealth[i] && SavedHealth[i] != "")
		{
			SavedHeroes[i].SetPropertyText("Health", SavedHealth[i]);
		}
	}
	foreach AllActors(Class'Engine.Projector', Pj)
	{
		if (Pj.IsA('ShadowProjector'))
		{
			continue;
		}
		nP++;
		R = Pj.GetPropertyText("RenderInfo");
		Log("[SDBG] load game: projector " $ string(Pj) $ " render info '" $ R $ "'");
		if (R == "" || R == "0" || InStr(R, "=0)") >= 0)
		{
			Pj.AttachProjector();
			nA++;
		}
	}
	Log("[SDBG] load game: " $ string(nP) $ " projectors, " $ string(nA) $ " attached again");
	if (bSaveTestDone)
	{
		SaveTestShotAt = Level.TimeSeconds + 3.0;
	}
}

function SpawnSecond(PlayerController Host)
{
	local Vector Loc;
	local Controller Old;
	local string HeroBefore;
	local int i;

	HeroBefore = Level.GetPropertyText("PlayerHeroActor");
	ChooseJoinCenter(Host);
	for (i = 0; i < 40 && P2Pawn == None; i++)
	{
		if (GuestSpot(Host, i, Loc))
		{
			P2Pawn = KWPawn(SpawnGuestPawn(Host, Loc));
		}
	}
	if (P2Pawn == None)
	{
		// no walkable place: in front of the host, then beside and behind him, whatever the floor looks like
		for (i = 0; i < 56 && P2Pawn == None; i++)
		{
			if (ForcedSpot(JoinCenter, HostHero(Host).Rotation, i, Loc))
			{
				P2Pawn = KWPawn(SpawnGuestPawn(Host, Loc));
				if (P2Pawn != None)
				{
					T("spawn: no walkable place, the guest is put by force at try " $ string(i) $ " (" $ string(Loc) $ ")");
				}
			}
		}
	}
	if (P2Pawn == None)
	{
		SpawnFails++;
		T("spawn: no free place around the host for player two, will retry");
		return;
	}
	SpawnFails = 0;
	T("spawn: attempt " $ string(i) $ " (1 = his place in the formation)" $ ", " $ string(int(VSize(P2Pawn.Location - HostHero(Host).Location))) $ " units from the host");
	T("spawn: Shrek for player two " $ string(P2Pawn) $ " at " $ string(P2Pawn.Location) $ ", controller " $ string(P2Pawn.Controller));
	T("spawn: PlayerHeroActor before " $ HeroBefore $ ", after " $ Level.GetPropertyText("PlayerHeroActor"));
	Old = P2Pawn.Controller;
	if (Old != None)
	{
		Old.UnPossess();
		Old.Destroy();
	}
	PendingPC.Possess(P2Pawn);
	PendingPC.SetViewTarget(P2Pawn);
	ChaseRotation(Host);
	PendingPC.ClientSetLocation(P2Pawn.Location, PendingPC.Rotation);
	P2Pawn.SetPropertyText("bIsMainPlayer", "True");
	PendingPC.SetViewTarget(P2Pawn);
	bP2Hidden = false;
	T("spawn: possessed, pawn=" $ string(PendingPC.Pawn));
	T("spawn: name of the controller '" $ PendingPC.PlayerReplicationInfo.PlayerName $ "', pawn PRI " $ string(P2Pawn.PlayerReplicationInfo) $ " '" $ P2Pawn.PlayerReplicationInfo.PlayerName $ "'");
	if (Dbg != None)
	{
		Dbg.Dump("after the Shrek of player two appeared");
	}
}

// During a cutscene player two's Shrek is hidden and held still (the cutscene scripts know only one Shrek).
function HideSecond(PlayerController Host)
{
	P2Pawn.bHidden = true;
	P2Pawn.SetCollision(false, false, false);
	P2Pawn.SetPhysics(PHYS_None);
	bP2Hidden = true;
	PendingPC.SetViewTarget(Host.ViewTarget);
	T("cutscene: the Shrek of player two is hidden");
}

// After the cutscene he is back, next to the host.
function ShowSecond(PlayerController Host)
{
	local Vector Loc;
	local int i;
	local bool bPlaced;

	// the host is free: a place next to him now (the centre chosen when the guest came in can be far behind by then). The host still watches his
	// cutscene: the guest comes back where he stood before it.
	if (Host.Pawn != None)
	{
		ChooseJoinCenter(Host);
		for (i = 0; i < 40 && !bPlaced; i++)
		{
			if (GuestSpot(Host, i, Loc))
			{
				bPlaced = P2Pawn.SetLocation(Loc);
			}
		}
	}
	P2Pawn.SetCollision(P2Pawn.default.bCollideActors, P2Pawn.default.bBlockActors, P2Pawn.default.bBlockPlayers);
	P2Pawn.bHidden = false;
	P2Pawn.SetPhysics(PHYS_Falling);
	PendingPC.SetViewTarget(P2Pawn);
	if (Host.Pawn != None)
	{
		ChaseRotation(Host);
	}
	PendingPC.ClientSetLocation(P2Pawn.Location, PendingPC.Rotation);
	bP2Hidden = false;
	if (Host.Pawn == None)
	{
		T("own cutscene over: the Shrek of player two is back at " $ string(P2Pawn.Location) $ " (the host still watches his)");
	}
	else
	{
		T("cutscene over: the Shrek of player two is back at " $ string(P2Pawn.Location));
	}
}

// From the heartbeat: makes, hides and shows player two's Shrek depending on whether the host is free.
// With friendly fire on, a hero is nobody's "friend" for the other hero's attack search (the stock attacks
// skip bIsAFriend pawns); off by default.
function SyncOne()
{
	local PlayerController Host;
	local string V;

	V = "True";
	if (FriendlyFire > 0.0)
	{
		V = "False";
	}
	Host = HostController();
	if (Host != None && Host.Pawn != None)
	{
		Host.Pawn.SetPropertyText("bIsAFriend", V);
	}
	if (P2Pawn != None)
	{
		P2Pawn.SetPropertyText("bIsAFriend", V);
	}
}

// The chase camera of player two looks the way the host's does, a little from above (a camera at the height of
// the ground sits in the foliage, which has no collision for the camera to see).
function ChaseRotation(PlayerController Host)
{
	local Rotator R;

	R = HostHero(Host).Rotation;   // the host's controller keeps an arbitrary yaw after a cutscene; his Shrek's facing is what the camera should follow
	R.Pitch = -3000;
	R.Roll = 0;
	PendingPC.SetRotation(R);
	PendingPC.ClientSetRotation(R);
	T("chase camera: yaw " $ string(R.Yaw) $ " pitch " $ string(R.Pitch) $ ", host pawn " $ string(HostHero(Host).Location) $ ", player two " $ string(P2Pawn.Location) $ " radius " $ string(P2Pawn.default.CollisionRadius));
}

// While the host has no Shrek of his own (a cutscene) or player two has none yet (or he is hidden), player two
// looks through a camera stand that sits where the host's camera is.
function MirrorOne()
{
	local PlayerController Host;
	local EnhancedPlayerController Guest;
	local Actor VA;
	local Vector Loc;
	local Rotator Rot;
	local bool bFree;

	if (PendingPC == None)
	{
		return;
	}
	Host = HostController();
	if (Host == None)
	{
		return;
	}
	Guest = EnhancedPlayerController(PendingPC);
	bFree = Host.Pawn != None;
	// a guest whose Shrek is in the world plays (also while the host still watches his cutscene): no mirrored camera
	if (P2Pawn != None && !bP2Hidden)
	{
		if (Guest != None && (!Guest.bCutViewSentInit || Guest.bCutViewSent))
		{
			Guest.bCutViewSentInit = true;
			Guest.bCutViewSent = false;
			Guest.ClientCutView(false);
		}
		return;
	}
	if (CutCam == None)
	{
		CutCam = Spawn(Class'Enhanced.EnhancedCam');
	}
	if (CutCam == None)
	{
		return;
	}
	Host.PlayerCalcView(VA, Loc, Rot);
	CutCam.SetLocation(Loc);
	CutCam.SetRotation(Rot);
	if (Guest != None)
	{
		if (!Guest.bCutViewSentInit || !Guest.bCutViewSent)
		{
			Guest.bCutViewSentInit = true;
			Guest.bCutViewSent = true;
			Guest.ClientCutView(true);
		}
		Guest.CutLoc = Loc;
		Guest.CutYaw = Rot.Yaw;
		Guest.CutPitch = Rot.Pitch;
		Guest.CutRoll = Rot.Roll;
		if (EnhancedHeroController(Host) != None && EnhancedHeroController(Host).bFovScaled)
		{
			Guest.CutFov = EnhancedHeroController(Host).LogicalFov;
		}
		else
		{
			Guest.CutFov = Host.FovAngle;
		}
	}
	if (bJitterOpt)
	{
		Log("[CAMH] w=" $ string(Level.Second * 1000 + Level.Millisecond) $ " loc=" $ string(Loc.X) $ "," $ string(Loc.Y) $ "," $ string(Loc.Z) $ " yaw=" $ string(Rot.Yaw & 65535));
	}
	if (bJitterOpt && Level.TimeSeconds - MirrorLog > 2.0)
	{
		MirrorLog = Level.TimeSeconds;
		Log("[MIR] t=" $ string(Level.TimeSeconds) $ " hostPawn=" $ string(Host.Pawn) $ " hostVT=" $ string(Host.ViewTarget) $ " va=" $ string(VA) $ " loc=" $ string(Loc) $ " rot=" $ string(Rot.Yaw) $ " cam=" $ string(CutCam.Location) $ " guestVT=" $ string(PendingPC.ViewTarget));
	}
	if (PendingPC.ViewTarget != CutCam)
	{
		PendingPC.SetViewTarget(CutCam);
	}
}

// the current guest is still watching a cutscene of his own (his Shrek appears when he is back)
function bool GuestInOwnCut()
{
	return EnhancedPlayerController(PendingPC) != None && EnhancedPlayerController(PendingPC).bLocalCutBusy;
}

// the current guest has played the host's cutscene now running and is back from it: he plays on while the host still watches
function bool GuestDoneOwnCut()
{
	local EnhancedPlayerController G;

	G = EnhancedPlayerController(PendingPC);
	if (G == None || ActiveCut == None)
	{
		return false;
	}
	// he played the level's opening on his own machine before he joined
	if (G.bIntroDone && bLevelHadOpening && CutSerial == OpeningSerial)
	{
		return true;
	}
	return bLocalCutOpt && G.LocalCutSent == CutSerial && !G.bLocalCutBusy;
}

function ManageOne()
{
	local PlayerController Host;
	local bool bFree;

	if (PendingPC == None)
	{
		return;
	}
	if (IsMenuLevel() || IsCutsceneLevel())
	{
		return;
	}
	Host = HostController();
	bFree = Host != None && Host.Pawn != None;
	if (P2Pawn == None)
	{
		// The guests see the opening cutscene in their own game (or the host's camera, ?EnhOff=localcut); their Shrek appears when they are done with
		// it, next to the host's hero, even if the host still watches (owner's rule: whoever is through his cutscene comes into the world)
		if (Host != None && HostHero(Host) != None && !bHold && (ReleaseAt == 0.0 || Level.TimeSeconds - ReleaseAt > 4.0) && !GuestInOwnCut() && (bFree || GuestDoneOwnCut()))
		{
			SpawnSecond(Host);
		}
		return;
	}
	if (!bFree && !bP2Hidden && Host != None && !GuestDoneOwnCut())
	{
		HideSecond(Host);
	}
	else if (bP2Hidden && !GuestInOwnCut() && (bFree || GuestDoneOwnCut()))
	{
		ShowSecond(Host);
	}
}
event PostLogin(PlayerController NewPlayer)
{
	local Class<HUD> HudClass;

	T("postlogin: " $ string(NewPlayer) $ " player=" $ string(NewPlayer.Player));
	if (IsGuestPC(NewPlayer))
	{
		WriteStatus("joined");
		// What KWGame.PostLogin does for a player, minus the start location taken from a pawn that player two does not have yet.
		if (HUDType != "")
		{
			HudClass = Class<HUD>(DynamicLoadObject(HUDType, Class'Core.Class'));
		}
		NewPlayer.ClientSetHUD(HudClass, None);
	}
	else
	{
		Super.PostLogin(NewPlayer);
	}
	if (LobbyMode == "host" && !IsGuestPC(NewPlayer) && Class'Enhanced.EnhancedLobbySettings'.default.PlayerNick != "")
	{
		ChangeName(NewPlayer, Class'Enhanced.EnhancedLobbySettings'.default.PlayerNick, false);
	}
	SendHostSong(EnhancedPlayerController(NewPlayer));
	// a guest who comes into a level that began with an opening, and has not played it: he plays it by himself first and joins again after it
	if (IsGuestPC(NewPlayer) && EnhancedPlayerController(NewPlayer) != None && !EnhancedPlayerController(NewPlayer).bIntroDone && bLevelHadOpening && !Off("introfirst"))
	{
		T("postlogin: " $ NewPlayer.PlayerReplicationInfo.PlayerName $ " has not seen the opening of " $ MapName() $ ": he plays it by himself first");
		EnhancedPlayerController(NewPlayer).ClientIntroFirst(MapName());
		AwayForIntro[AwayForIntro.Length] = NewPlayer.PlayerReplicationInfo.PlayerName;
		IntroAway(NewPlayer.PlayerReplicationInfo.PlayerName);
	}
	T("postlogin: done");
}

defaultproperties
{
	OpeningMaps(0)="1_Shreks_Swamp"
	OpeningMaps(1)="2_Carriage_Hijack"
	OpeningMaps(2)="3_The_Hunt_Part1"
	OpeningMaps(3)="4_FGM_Office"
	OpeningMaps(4)="4_FGM_PIB"
	OpeningMaps(5)="6_Hamlet"
	OpeningMaps(6)="7_Prison_Donkey"
	OpeningMaps(7)="8_Prison_PIB"
	OpeningMaps(8)="9_Prison_Shrek"
	OpeningMaps(9)="10_Castle_Siege"
	OpeningMaps(10)="11_FGM_Battle"
	OpeningMaps(11)="Beanstalk_bonus"
	OpeningMaps(12)="Beanstalk_bonus_dawn"
	OpeningMaps(13)="Beanstalk_bonus_knight"
	IntroEnd(0)="10_Castle_Siege=-7.44,6218.19,303.62"
	IntroEnd(1)="11_FGM_Battle=2176.14,5039.42,-981.20"
	IntroEnd(2)="1_Shreks_Swamp=-12857.52,1089.40,-164.50"
	IntroEnd(3)="2_Carriage_Hijack=-88.42,-1501.73,-5.50"
	IntroEnd(4)="3_The_Hunt_Part1=4323.03,12646.69,45.39"
	IntroEnd(5)="3_The_Hunt_Part2=-5116.98,12065.05,32.27"
	IntroEnd(6)="3_The_Hunt_Part3=959.71,7469.90,147.19"
	IntroEnd(7)="3_The_Hunt_Part4=866.52,-490.08,-596.17"
	IntroEnd(8)="4_FGM_PIB=-744.96,-314.25,-1000.20"
	IntroEnd(9)="5_FGM_Donkey=105.18,-2171.18,-997.25"
	IntroEnd(10)="6_Hamlet=-2122.79,9870.43,-122.43"
	IntroEnd(11)="6_Hamlet_End=-11165.84,60.54,351.15"
	IntroEnd(12)="6_Hamlet_Mine=5059.34,2955.14,-1597.00"
	IntroEnd(13)="7_Prison_Donkey=-1786.75,-2693.66,-104.25"
	IntroEnd(14)="8_Prison_PIB=-839.92,-4304.51,279.80"
	IntroEnd(15)="9_Prison_Shrek=-1621.21,-3564.85,298.84"
	GamePortDefault=7777
	LobbyMin=2
	LobbyMax=4
	HUDType="Enhanced.EnhancedHud"
	GateLeash=900.0
	EnemyHealthPerPlayer=0.6
	EnemyDamagePerPlayer=0.25
	GateTimeout=90.0
	CheckpointRadius=1500.0
	LeashDistance=5000.0
	LeashGrace=6.0
	ExitRadius=1500.0
}

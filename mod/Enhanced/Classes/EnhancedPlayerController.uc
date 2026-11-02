class EnhancedPlayerController extends PlayerController
	config(User);

var string TravelHost;    // the host's address while the level is being changed
var int TravelTries;
var string LastView;
var float BotJumpHold;
var config bool bTestBot;   // tests only: the client plays a fixed script of inputs (set in the test profile's User.ini)
var float BotTime;
var Rotator MyView;
var bool bViewInit;
var int DbgSet, DbgRot;
var float SilenceTime;
var string DownNote;     // set by the game: "you are down, wait for help" / "go to <name>"; the guest HUD draws it
var string GateNote;     // set by the game while this player waits at a cutscene gate; the guest HUD draws it
var config bool bTestReady;   // tests only (the test profile's User.ini): a guest presses Ready by himself
var float ReadyClock;
var config bool bHorPlus;     // widen the horizontal field of view with the aspect ratio (see EnhancedFov)
var float FovK;                // the aspect ratio relative to 4:3, asked from the viewport once a second
var float FovCheck;
var float LogicalFov;
var float LogicalDesired;          // the angle the game wants; FovAngle holds the widened one between two ticks
var bool bFovScaled;
var config bool bJitterLog;    // tests only: log this guest's own view of his pawn every 0.1 s
var float JitterClock;
var Vector EyeSm;              // the filtered point the chase camera looks at
var bool bEyeInit;
var float CamDist;             // the distance of the chase camera (see PlayerCalcView)
var float LastCamTime;
// What the guest's HUD shows of the shared inventory; the game sets them every half second (the inventory lives on the host's Shrek).
var int HudCoins;
var int HudPotions;
var int HudIcons;             // 1 + the shamrocks: the length of the health bar
var int HudPotionSel;          // index of the selected potion, 9 = the timer
var bool bMenuCleaned;   // the menu pages of the level this guest came from were closed
var bool bRoomOpened;   // a guest: the room page of the lobby has been opened
var bool bLobbyReady;   // in the lobby: this guest pressed Ready (set on the server through ServerSetReady)
var float LastAT, LastAL, LastAF;   // what the input class produced last, for the test log
var bool bBotHit1, bBotHit2, bBotHit3;
var int ViewYawSrv;           // on the server: the yaw of this guest's camera, sent every frame by his machine (ServerSetView)
var bool bViewSrv;
var int LastSentYaw;
var int LastAnimLog;
var Vector LastCamLoc;
var Rotator LastCamRot;
var string SubText, SubName;
var Color SubColor;            // the speaker's colour   // the host's subtitle during a cutscene (set by the server)
var bool bCutView;            // the host is in a cutscene: this guest's picture is the host's camera (a reliable RPC carries mode changes)
var bool bCutViewSent;        // server: the last mode sent by ClientCutView; the pose below remains unreliable
var bool bCutViewSentInit;
var Vector CutLoc;
var Rotator CutRot;
var int CutYaw, CutPitch, CutRoll;   // the angles again as whole numbers: a replicated Rotator is sent in steps of 256 units (1.4 degrees), a slow pan came out in jerks
var float CutFov;
var Vector SmLoc;             // what the guest's camera shows of the host's camera: it follows the replicated pose smoothly (the pose arrives in bursts)
var Rotator SmRot;
var bool bCutInit;
var float LastCutTime;
var config string TestMenu;    // tests only: the guest's menu opens by itself ("main", "settings", "leave")
var config bool bTestShots;    // tests only: this guest takes three pictures of his own screen with the game's own shot command
var float ShotClock;
var Vector MenuCamLoc;         // the camera as it was when the game's own pause menu was opened (the book is put in front of it; see EnhancedGuestBook)
var Rotator MenuCamRot;
var Rotator MenuLiveRot;      // the camera of the open menu: the stock page's fixed angle plus what the player has turned since
var Rotator MenuOpenView;     // the player's own view angle when the menu was opened
var Actor MenuBookActor;      // the book of the open menu (EnhancedGuestBook), kept in front of the camera
var bool bMenuHold;            // the pause menu is open: the camera stays where it was
var float MenuTestClock;
var bool bMenuTested;
var float MenuTestClock2;
var int ShotsDone;
var float LastSubShot;
var float PawnSince;
var bool bOverlayAdded;      // the overlay (subtitle and notes) was put on this client's viewport
var bool bNickSent;            // the nickname of the lobby settings was sent to the server (a guest who joined straight into a level)
var float NickClock;
var input float aArrowRight;   // the game binds the arrow keys to these two axes (see EnhancedInput)
var input float aArrowUp;

// Player two's controller. The game's own hero controllers (KWHeroController and below) rely on
// actors that exist only on the server (the BaseCam camera, the HUD item pointers), so on a joined
// client they spam "Accessed None" every frame and have no camera. This controller is the stock
// Unreal one: its third-person chase camera and walking state work on a client, and it can drive
// any KWPawn. Game-specific abilities are added back on top of it step by step.
//
// The hero's attack, pick up, throw and switch are all one call on the server: ShHeroPawn.DoSomeAction
// (the stock ShHeroController.Fire makes it). On a client the key is seen here, so it goes to the server.

// The chase camera is worked out here instead of by the stock CalcBehindView, with the stock hero camera's measures (Shrek: the look-at point is 75 units
// above his feet, 170 units behind) and its rule for the scenery: the trace from the look-at point back to the camera is stopped by the world, the
// terrain and every actor that says it blocks the camera (trunks, foliage, camera volumes), and the camera sits 15 units in front of what it hit.
// The distance goes in at once and comes out slowly, so the picture does not jump when the trace flickers between two things.
function bool CameraBlocks(Actor A)
{
	if (A.IsA('LevelInfo') || A.IsA('TerrainInfo'))
	{
		return true;
	}
	if (A.GetPropertyText("bWorldGeometry") ~= "True")
	{
		return true;
	}
	// The stock camera fades the foliage between itself and the hero (bChangeOpacityForCamera); this one has no way to fade it, so it stays in front of it.
	return A.GetPropertyText("bBlocksCamera") ~= "True" || A.GetPropertyText("bChangeOpacityForCamera") ~= "True";
}

event PlayerCalcView(out Actor ViewActor, out Vector CameraLocation, out Rotator CameraRotation)
{
	local Vector Eye, Dir, HitLoc, HitNorm;
	local float Want, D, Dt, K;
	local int DY, DP, DR;
	local Actor A;

	if (bMenuHold)
	{
		if (bViewInit)
		{
			DR = MyView.Yaw - MenuOpenView.Yaw;
			DP = MyView.Pitch - MenuOpenView.Pitch;
		}
		MenuLiveRot = MenuCamRot;
		MenuLiveRot.Yaw += DR;
		MenuLiveRot.Pitch += DP;
		UpdateMenuBook();
		ViewActor = Self;
		CameraLocation = MenuCamLoc;
		CameraRotation = MenuLiveRot;
		return;
	}
	// the host's cutscene camera (a stand the server moves to where the host's camera is): the picture is exactly that place and angle, the third-person
	// shift the controller adds for a Shrek (bBehindView is forced on) must not be applied to it
	if (bCutView)
	{
		Dt = Level.TimeSeconds - LastCutTime;
		LastCutTime = Level.TimeSeconds;
		if (Dt < 0.0 || Dt > 0.2)
		{
			Dt = 0.016;
		}
		CutRot.Yaw = CutYaw;
		CutRot.Pitch = CutPitch;
		CutRot.Roll = CutRoll;
		DY = (CutRot.Yaw - SmRot.Yaw) & 65535;
		if (DY > 32768)
		{
			DY -= 65536;
		}
		DP = (CutRot.Pitch - SmRot.Pitch) & 65535;
		if (DP > 32768)
		{
			DP -= 65536;
		}
		DR = (CutRot.Roll - SmRot.Roll) & 65535;
		if (DR > 32768)
		{
			DR -= 65536;
		}
		// a cut (a new shot) shows at once, a move is followed smoothly
		if (!bCutInit || VSize(CutLoc - SmLoc) > 300.0 || Abs(DY) > 9000 || Abs(DP) > 9000)
		{
			SmLoc = CutLoc;
			SmRot = CutRot;
			bCutInit = true;
		}
		else
		{
			K = FMin(1.0, 14.0 * Dt);
			SmLoc += (CutLoc - SmLoc) * K;
			SmRot.Yaw += int(float(DY) * K);
			SmRot.Pitch += int(float(DP) * K);
			SmRot.Roll += int(float(DR) * K);
		}
		if (bTestShots)
		{
			Log("[CAMC] w=" $ string(Level.Second * 1000 + Level.Millisecond) $ " loc=" $ string(SmLoc.X) $ "," $ string(SmLoc.Y) $ "," $ string(SmLoc.Z) $ " yaw=" $ string(SmRot.Yaw & 65535) $ " raw=" $ string(CutLoc.X) $ "," $ string(CutLoc.Y) $ "," $ string(CutLoc.Z));
		}
		ViewActor = Self;
		CameraLocation = SmLoc;
		CameraRotation = SmRot;
		return;
	}
	bCutInit = false;
	if (EnhancedCam(ViewTarget) != None)
	{
		ViewActor = ViewTarget;
		CameraLocation = ViewTarget.Location;
		CameraRotation = ViewTarget.Rotation;
		return;
	}
	if (Pawn != None && ViewTarget == Pawn && !Pawn.bHidden)
	{
		ViewActor = Pawn;
		if (bViewInit)
		{
			CameraRotation = MyView;
		}
		else
		{
			CameraRotation = Rotation;
		}
		// The point looked at follows the pawn through a short low-pass filter: the guest's pawn is corrected by the server in small steps, and an unfiltered
		// camera shows every correction as a shake.
		Dt = Level.TimeSeconds - LastCamTime;
		LastCamTime = Level.TimeSeconds;
		if (Dt < 0.0 || Dt > 0.1)
		{
			Dt = 0.016;
		}
		Eye = Pawn.Location + vect(0.0, 0.0, 75.0);
		if (!bEyeInit || VSize(Eye - EyeSm) > 250.0)
		{
			EyeSm = Eye;
			bEyeInit = true;
		}
		else
		{
			EyeSm += (Eye - EyeSm) * FMin(1.0, 18.0 * Dt);
		}
		Eye = EyeSm;
		Dir = vect(0.0, 0.0, 0.0) - Vector(CameraRotation);
		Want = 170.0;
		foreach TraceActors(Class'Engine.Actor', A, HitLoc, HitNorm, Eye + Dir * (Want + 20.0), Eye, vect(0.0, 0.0, 0.0))
		{
			if (A == Pawn || A.IsA('Pawn') || A.IsA('Projectile'))
			{
				continue;
			}
			if (CameraBlocks(A))
			{
				D = VSize(HitLoc - Eye) - 15.0;
				if (D < Want)
				{
					Want = D;
				}
				break;
			}
		}
		if (Want < 40.0)
		{
			Want = 40.0;
		}
		// the distance moves toward the wanted one at a steady speed in both directions (faster in), and small changes are ignored
		if (CamDist == 0.0)
		{
			CamDist = Want;
		}
		else if (Abs(Want - CamDist) > 6.0)
		{
			if (Want < CamDist)
			{
				CamDist += (Want - CamDist) * FMin(1.0, 14.0 * Dt);
			}
			else
			{
				CamDist += (Want - CamDist) * FMin(1.0, 3.0 * Dt);
			}
		}
		CameraLocation = Eye + Dir * CamDist;
		LastCamLoc = CameraLocation;
		LastCamRot = CameraRotation;
		return;
	}
	Super.PlayerCalcView(ViewActor, CameraLocation, CameraRotation);
}

// A level change: the host loads the new level and closes this connection. The patched engine (tools/patch_engine.py)
// no longer throws the client out to the default map for that, so this level stays on the screen, and here the client
// keeps asking the host to let it in until the new level is ready (one request is lost while the host is loading).
event PostNetBeginPlay()
{
	Super.PostNetBeginPlay();
	if (Level.NetMode == NM_Client && Player != None && Player.InteractionMaster != None && TravelWatch() == None)
	{
		Player.InteractionMaster.AddInteraction("Enhanced.EnhancedTravelWatch", Player);
	}
}

function EnhancedTravelWatch TravelWatch()
{
	local int i;

	if (Player == None)
	{
		return None;
	}
	for (i = 0; i < Player.LocalInteractions.Length; i++)
	{
		if (EnhancedTravelWatch(Player.LocalInteractions[i]) != None)
		{
			return EnhancedTravelWatch(Player.LocalInteractions[i]);
		}
	}
	return None;
}

event PreClientTravel()
{
	local EnhancedTravelWatch W;

	Class'Enhanced.EnhancedGame'.static.PatchWorldDefaults(self);
	Super.PreClientTravel();
	W = TravelWatch();
	if (Level.NetMode == NM_Client && W == None && Player != None && Player.InteractionMaster != None)
	{
		W = EnhancedTravelWatch(Player.InteractionMaster.AddInteraction("Enhanced.EnhancedTravelWatch", Player));
	}
	Log("[SDBG] client: PreClientTravel, netmode " $ string(Level.NetMode) $ ", player " $ string(Player) $ ", watch " $ string(W));
	if (Level.NetMode == NM_Client && W != None)
	{
		TravelHost = Level.GetAddressURL();
		W.Arm(TravelHost, Self);
		Log("[SDBG] client: level change, will keep asking " $ TravelHost $ " to let this client in");
	}
}

replication
{
	reliable if (Role == ROLE_Authority)
		ClientCutView, GateNote, DownNote, SubText, SubName, SubColor, HudCoins, HudPotions, HudPotionSel, HudIcons;
	reliable if (Role < ROLE_Authority)
		ServerAction, ServerSetReady;
	unreliable if (Role == ROLE_Authority && bNetOwner)
		CutLoc, CutYaw, CutPitch, CutRoll, CutFov;
	unreliable if (Role < ROLE_Authority)
		ServerSetView;
}

simulated function ClientCutView(bool bOn)
{
	if (bCutView == bOn)
	{
		return;
	}
	bCutView = bOn;
	bCutInit = false;
	LastCutTime = Level.TimeSeconds;
	if (bTestShots)
	{
		Log("[CUTSYNC] mode=" $ string(bOn));
	}
}

function ServerSetReady(bool bOn)
{
	bLobbyReady = bOn;
}

// The controller's own rotation cannot carry the camera to the server: the game's native pawn code puts it back to the pawn's facing every frame,
// so the pawn turned after its own previous facing and never followed the camera. The camera's yaw goes in a call of its own.
function ServerSetView(int Yaw)
{
	ViewYawSrv = Yaw;
	bViewSrv = true;
}

function ServerAction()
{
	local ShHeroPawn H;

	H = ShHeroPawn(Pawn);
	if (H != None)
	{
		H.DoSomeAction();
	}
}


// Hor+: the stock code interpolates and sets FovAngle as the angle it wants; the widened value is put over it after the tick (the scene is
// drawn after the tick) and taken off again before the next one, so the game never sees its own value changed.
function UndoHorPlus()
{
	if (bFovScaled)
	{
		FovAngle = LogicalFov;
		DesiredFOV = LogicalDesired;
		bFovScaled = false;
	}
}

function DoHorPlus(float DeltaTime)
{
	FovCheck -= DeltaTime;
	if (FovCheck <= 0.0 || FovK == 0.0)
	{
		FovCheck = 1.0;
		FovK = Class'Enhanced.EnhancedFov'.static.AspectK(ConsoleCommand("GetCurrentRes"));
	}
	if (bHorPlus && FovK > 1.01)
	{
		LogicalFov = FovAngle;
		LogicalDesired = DesiredFOV;
		FovAngle = Class'Enhanced.EnhancedFov'.static.HorPlus(LogicalFov, FovK);
		DesiredFOV = Class'Enhanced.EnhancedFov'.static.HorPlus(LogicalDesired, FovK);   // the stock AdjustView pulls FovAngle back to DesiredFOV every frame: both are widened
		bFovScaled = true;
	}
}

// Tests only: a scripted player. The inputs go through the same EnhancedInput code a keyboard and a mouse reach.
function BotInput(float DeltaTime)
{
	if (!bTestBot || Pawn == None)
	{
		return;
	}
	if (BotTime == 0.0)
	{
		Log("[SDBG] bot: scripted input starts");
	}
	BotTime += DeltaTime;
	if (BotTime > 10.0 && BotTime < 13.0)
	{
		aBaseY = 1200.0;                    // walk forward
	}
	if (BotTime > 15.0 && BotTime < 15.0 + DeltaTime * 2.0)
	{
		BotAttack("attack A");              // three attacks, standing still
	}
	if (BotTime > 17.0 && BotTime < 17.0 + DeltaTime * 2.0)
	{
		BotAttack("attack B");
	}
	if (BotTime > 19.0 && BotTime < 19.0 + DeltaTime * 2.0)
	{
		BotAttack("attack C");
	}
	if (BotTime > 22.0 && BotTime < 23.2)
	{
		aArrowRight = 1000.0;               // arrow key: turn right
	}
	if (BotTime > 25.0 && BotTime < 26.0)
	{
		aMouseY = -300.0;                   // mouse up: look up
	}
	if (BotTime > 28.0 && BotTime < 29.0)
	{
		aMouseY = 300.0;                    // mouse down: look down
	}
	if (BotTime > 31.0 && BotTime < 32.0)
	{
		aMouseX = 300.0;                    // mouse right: turn
	}
	if (BotTime > 34.0 && BotTime < 37.0)
	{
		aBaseY = 1200.0;                    // walk again, now in the new direction
	}
	// jumps through the real input path (the flag the Jump key sets): one jump, then a jump with a second press 0.4 s into it
	if (BotJumpHold > 0.0)
	{
		BotJumpHold -= DeltaTime;
		aUp = 1200.0;                       // the Jump key is "Jump | Axis aUp Speed=+1200"
	}
	if (BotTime > 40.0 && BotTime < 40.0 + DeltaTime * 1.5)
	{
		bPressedJump = true;
		BotJumpHold = 0.12;
		Log("[SDBG] bot: jump t=" $ string(Level.TimeSeconds));
	}
	if (BotTime > 46.0 && BotTime < 46.0 + DeltaTime * 1.5)
	{
		bPressedJump = true;
		BotJumpHold = 0.12;
		Log("[SDBG] bot: jump (with a second press) t=" $ string(Level.TimeSeconds));
	}
	if (BotTime > 46.4 && BotTime < 46.4 + DeltaTime * 1.5)
	{
		bPressedJump = true;
		BotJumpHold = 0.12;
		Log("[SDBG] bot: second press t=" $ string(Level.TimeSeconds));
	}
}

function BotAttack(string What)
{
	Log("[SDBG] bot: " $ What $ " t=" $ string(Level.TimeSeconds));
	ServerAction();
}

// The commentary managers (the heroes' spoken comments and the Donkey's lines) exist on every machine and each decides by itself
// when to talk, so a client said the host's lines a second time, out of step. The client keeps them quiet.
function SilenceLocalCommentary()
{
	local CommentaryManager C;

	foreach AllActors(Class'KWGame.CommentaryManager', C)
	{
		C.bAmPaused = true;
	}
}

// Test log: channel 0 and the movement channels of a pawn as this machine plays them (name/rate/frame).
function string AnimLine(Pawn P)
{
	local name N;
	local float F, R;
	local int C;
	local string S;

	if (P == None)
	{
		return "none";
	}
	for (C = 0; C < 8; C++)
	{
		if (C == 1 || C == 2 || C == 3)
		{
			continue;
		}
		P.GetAnimParams(C, N, F, R);
		S = S $ " c" $ string(C) $ "=" $ string(N) $ "/" $ string(R) $ "/" $ string(F);
	}
	return S;
}

function Pawn OtherHero()
{
	local Pawn Q;

	foreach DynamicActors(Class'Pawn', Q)
	{
		if (Q != Pawn && Q.IsA('ShHeroPawn'))
		{
			return Q;
		}
	}
	return None;
}

// The view angles are kept here. Something outside the script (the engine's native pawn code for the game's hero pawns) puts the
// controller's rotation back to the pawn's facing on every frame, so the stock UpdateRotation turned the camera by a few units and lost
// it again. The turn is added to our own copy, the pawn is turned with it (he walks the way the camera looks), and the controller and
// the camera take the copy.
// The server puts the camera somewhere (spawn, after a cutscene): take it over.
function ClientSetRotation(Rotator NewRotation)
{
	Super.ClientSetRotation(NewRotation);
	if (bTestBot && DbgSet < 40)
	{
		DbgSet++;
		Log("[SDBG] ClientSetRotation yaw " $ string(NewRotation.Yaw & 65535) $ " pitch " $ string(NewRotation.Pitch & 65535) $ " (view was " $ string(MyView.Yaw & 65535) $ ")");
	}
	MyView = NewRotation;
	bViewInit = true;
}

function UpdateRotation(float DeltaTime, float maxPitch)
{
	local Rotator R;

	if (bInterpolating || (Pawn != None && Pawn.bInterpolating))
	{
		ViewShake(DeltaTime);
		return;
	}
	if (!bViewInit)
	{
		MyView = Rotation;
		bViewInit = true;
	}
	MyView.Yaw += int(32.0 * DeltaTime * aTurn);
	MyView.Pitch += int(32.0 * DeltaTime * aLookUp);
	MyView.Pitch = MyView.Pitch & 65535;
	// Looking up swings the chase camera down under the ground (it hangs 150 units behind and below the look-at point): the Shrek
	// slid up out of the picture and the camera sat in the terrain. Up to about 25 degrees; down is the stock hero camera's limit (14000).
	if (MyView.Pitch > 4500 && MyView.Pitch < 51536)
	{
		if (aLookUp > 0.0)
		{
			MyView.Pitch = 4500;
		}
		else
		{
			MyView.Pitch = 51536;
		}
	}
	MyView.Roll = 0;
	if (bTestBot)
	{
		// tests only: fixed pitches at fixed times to see where the Shrek sits in the picture
		if (Level.TimeSeconds > 24.0 && Level.TimeSeconds < 29.0)
		{
			MyView.Pitch = 51536;
		}
		else if (Level.TimeSeconds > 30.0 && Level.TimeSeconds < 35.0)
		{
			MyView.Pitch = 58000;
		}
		else if (Level.TimeSeconds > 36.0 && Level.TimeSeconds < 41.0)
		{
			MyView.Pitch = 0;
		}
		else if (Level.TimeSeconds > 42.0 && Level.TimeSeconds < 47.0)
		{
			MyView.Pitch = 4500;
		}
	}
	if (bTestBot && DbgRot < 60 && (Rotation.Yaw & 65535) != (MyView.Yaw & 65535))
	{
		DbgRot++;
		Log("[SDBG] urot: controller yaw " $ string(Rotation.Yaw & 65535) $ " differs from own view " $ string(MyView.Yaw & 65535) $ " aTurn=" $ string(aTurn));
	}
	SetRotation(MyView);
	if (Pawn != None)
	{
		R = MyView;
		R.Pitch = 0;
		// the stock pawn code keeps turning the pawn towards a DesiredRotation left over from an attack or a cutscene: he trailed the camera
		Pawn.bRotateToDesired = False;
		bRotateToDesired = False;
		Pawn.DesiredRotation = R;
		DesiredRotation = R;
		Pawn.SetRotation(R);
	}
	ViewShake(DeltaTime);
	ViewFlash(DeltaTime);
}

// The guest's own machine moves his Shrek (client-side prediction): it has to know about the water too, or it runs at full speed and the server pulls it back.
// The same calls the game's hero controller makes every frame (ShHeroController.PlayerTick): the ground under the feet, then HeroInWater (ground speed 550 -> 150)
// or HeroInQuicksand, and the jump magnet. The server does the same for every guest (EnhancedGame.GuestGround).
function HeroGround()
{
	local int Mt;
	local ShHeroPawn H;

	H = ShHeroPawn(Pawn);
	if (H == None || Level.NetMode != NM_Client || H.bHidden || H.IsInState('stateHeroDying'))
	{
		return;
	}
	H.UseSHJumpMagnet();
	Mt = int(H.TraceMaterial(H.Location, 1.5 * H.CollisionHeight));
	if (Mt != 6 && H.GetPropertyText("bInWater") ~= "True")
	{
		H.HeroOutOfWater();
		Log("[HG] client: out of the water, ground speed " $ string(int(H.GroundSpeed)));
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
			Log("[HG] client: in the water, ground speed " $ string(int(H.GroundSpeed)));
		}
	}
}

// Test log of the client's own view: camera angles and the animation its own pawn plays (see GAME-STUDY.md / NOTES.md).
// ---- The game's own pause menu for a joined player ----
// The host opens it with Escape (EscHandler of his hero controller, ShowInGameMenu, ShowMenu: the game is paused and the page opens). The book that is its
// first page turns itself to the next pages by calling these functions on the controller (ShowInGameMenuControls and the like), so a joined player's
// controller has them too; the pages themselves are the game's own pages with a few steps changed (EnhancedGuestBook, -Controls, -Quit, -Return).
function SetMenuHud(bool bHide)
{
	if (myHUD != None)
	{
		if (bHide)
		{
			myHUD.SetPropertyText("bHideHUD", "True");
		}
		else
		{
			myHUD.SetPropertyText("bHideHUD", "False");
		}
	}
}

// The book of the pause menu is tied to the camera: it is put in front of the camera again every frame and turns with it, as in the stock game.
function UpdateMenuBook()
{
	local Vector X, Y, Z, Off;
	local Rotator R;
	local string Map;

	if (MenuBookActor == None)
	{
		return;
	}
	GetAxes(MenuLiveRot, X, Y, Z);
	Map = Level.GetLocalURL();
	if (InStr(Map, "1_Shreks_Swamp") >= 0 || InStr(Map, "3_The_Hunt_Part1") >= 0)
	{
		Off = Class'Enhanced.EnhancedGuestBook'.default.MenuBook2Offset;
	}
	else
	{
		Off = Class'Enhanced.EnhancedGuestBook'.default.MenuBookOffset;
	}
	MenuBookActor.SetLocation(MenuCamLoc + Off.X * X + Off.Y * Y + Off.Z * Z);
	R = Class'Enhanced.EnhancedGuestBook'.default.MenuBookRotation;
	R.Yaw += MenuLiveRot.Yaw - MenuCamRot.Yaw;
	R.Pitch += MenuLiveRot.Pitch - MenuCamRot.Pitch;
	MenuBookActor.SetRotation(R);
}

function bool MenuIsOpen()
{
	return Player != None && GUIController(Player.GUIController) != None && GUIController(Player.GUIController).ActivePage != None;
}

exec function EscHandler()
{
	ShowInGameMenu();
}

exec function ShowInGameMenu()
{
	if (Level.NetMode != NM_Client || Player == None || MenuIsOpen() || bCutView || Pawn == None)
	{
		return;
	}
	MenuCamLoc = LastCamLoc;
	// the stock page turns the camera to one fixed angle (Camera.SetRotation(0, 18656, 0)) and the book's own angle is measured from it
	MenuCamRot.Pitch = 0;
	MenuCamRot.Yaw = 18656;
	MenuCamRot.Roll = 0;
	MenuLiveRot = MenuCamRot;
	if (bViewInit)
	{
		MenuOpenView = MyView;
	}
	else
	{
		MenuOpenView = Rotation;
	}
	bMenuHold = true;
	SetMenuHud(true);
	ClientOpenMenu("Enhanced.EnhancedGuestBook");
}

function MenuClosed()
{
	MenuBookActor = None;
	bMenuHold = false;
	SetMenuHud(false);
}

function ShowInGameMenuControls()
{
	ClientOpenMenu("Enhanced.EnhancedGuestControls");
}

function ShowInGameMenuOptions()
{
	ClientOpenMenu("SHGame.Tab_InGameOptions");
}

function ShowInGameMenuPosters()
{
	ClientOpenMenu("Enhanced.EnhancedGuestControls");
}

function ShowInGameMenuYesNo()
{
	ClientOpenMenu("Enhanced.EnhancedGuestQuit");
}

function ShowReturnToFEYesNo()
{
	ClientOpenMenu("Enhanced.EnhancedGuestReturn");
}

event PlayerTick(float DeltaTime)
{
	local string S;

	// A guest always plays in the third person. The engine puts bBehindView back from Pawn.PointOfView() whenever it restarts the controller
	// (ClientReStart / Restart), and with it off the pawn is not drawn for its owner (bOwnerNoSee): the Shrek of the guest vanished from his own screen.
	bBehindView = true;
	UndoHorPlus();
	Super.PlayerTick(DeltaTime);
	HeroGround();
	bBehindView = true;
	if (bCutView && CutFov > 10.0)
	{
		FovAngle = CutFov;
		DesiredFOV = CutFov;
	}
	DoHorPlus(DeltaTime);
	if (Level.NetMode == NM_Client && bViewInit && (MyView.Yaw & 65535) != LastSentYaw)
	{
		LastSentYaw = MyView.Yaw & 65535;
		ServerSetView(LastSentYaw);
	}
	if (bJitterLog && Pawn != None)
	{
		Log("[JITC] t=" $ string(Level.TimeSeconds) $ " dt=" $ string(DeltaTime) $ " loc=" $ string(Pawn.Location.X) $ "," $ string(Pawn.Location.Y) $ "," $ string(Pawn.Location.Z)
			$ " vel=" $ string(int(VSize(Pawn.Velocity))) $ " phys=" $ string(int(Pawn.Physics)) $ " acc=" $ string(int(VSize(Pawn.Acceleration)))
			$ " pyaw=" $ string(Pawn.Rotation.Yaw & 65535) $ " vyaw=" $ string(MyView.Yaw & 65535) $ " base=" $ string(Pawn.Base) $ " gs=" $ string(int(Pawn.GroundSpeed)) $ " dgs=" $ Pawn.GetPropertyText("DestGroundSpeed") $ " an=" $ Pawn.GetPropertyText("AnimSequence") $ " bb=" $ string(bBehindView) $ " vt=" $ string(ViewTarget) $ " hid=" $ string(Pawn.bHidden) $ " ons=" $ string(Pawn.bOwnerNoSee) $ " cs=" $ string(GetStateName()) $ " cd=" $ string(int(VSize(LastCamLoc - Pawn.Location))) $ " vp=" $ string(ViewTarget.bHidden) $ " ct=" $ string(CamDist));
		if (Level.NetMode == NM_Client && int(Level.TimeSeconds * 10.0) != LastAnimLog)
		{
			LastAnimLog = int(Level.TimeSeconds * 10.0);
			Log("[JITA] t=" $ string(Level.TimeSeconds) $ " own:" $ AnimLine(Pawn) $ " | host:" $ AnimLine(OtherHero()));
		}
	}
	if (!bMenuCleaned && Level.NetMode == NM_Client && Player != None && GUIController(Player.GUIController) != None)
	{
		bMenuCleaned = true;
		GUIController(Player.GUIController).CloseAll(false);
	}
	// a guest in somebody's lobby (a front-end level): the pages of the menu he came from are closed, the room opens, the nickname is set
	if (Level.NetMode == NM_Client && !bRoomOpened && Player != None && Player.GUIController != None && Left(string(Level), 5) ~= "Book_")
	{
		bRoomOpened = true;
		GUIController(Player.GUIController).CloseAll(false);
		Player.GUIController.OpenMenu("Enhanced.EnhancedRoomPage");
		if (Class'Enhanced.EnhancedLobbySettings'.default.PlayerNick != "")
		{
			ConsoleCommand("SetName " $ Class'Enhanced.EnhancedLobbySettings'.default.PlayerNick);
		}
	}
	if (bTestShots && Level.NetMode == NM_Client && Level.TimeSeconds - ShotClock > 2.0)
	{
		ShotClock = Level.TimeSeconds;
		Log("[VT] t=" $ string(Level.TimeSeconds) $ " vt=" $ string(ViewTarget) $ " vtloc=" $ string(Rotation.Yaw) $ " pawn=" $ string(Pawn) $ " bb=" $ string(bBehindView));
	}
	if (bTestShots && Level.NetMode == NM_Client && Player != None && PlayerReplicationInfo != None && ShotsDone < 4)
	{
		// at the same level times as the host's EnhShot (40, 46, 52, 58), so a picture of each machine shows the same moment
		if (Pawn != None && PawnSince == 0.0)
		{
			PawnSince = Level.TimeSeconds;
		}
		if ((SubText != "" || (PawnSince != 0.0 && Level.TimeSeconds - PawnSince > 25.0)) && Level.TimeSeconds - LastSubShot > 6.0)
		{
			ShotsDone++;
			LastSubShot = Level.TimeSeconds;
			ConsoleCommand("shot");
			Log("[SDBG] guest shot " $ string(ShotsDone) $ " as " $ PlayerReplicationInfo.PlayerName);
		}
	}
	if (TestMenu != "" && !bMenuTested && Level.NetMode == NM_Client && Pawn != None)
	{
		// tests only: the pause menu opens by itself 25 s after the pawn appeared
		MenuTestClock += DeltaTime;
		if (MenuTestClock > 25.0)
		{
			bMenuTested = true;
			ShowInGameMenu();
		}
	}
	if (bMenuTested && TestMenu != "" && !(TestMenu ~= "main"))
	{
		MenuTestClock2 += DeltaTime;
		if (MenuTestClock2 > 8.0)
		{
			MenuTestClock2 = -1000.0;
			if (TestMenu ~= "options")
			{
				ShowInGameMenuOptions();
			}
			else if (TestMenu ~= "leave")
			{
				ShowReturnToFEYesNo();
			}
			else if (TestMenu ~= "quit")
			{
				ShowInGameMenuYesNo();
			}
		}
	}
	if (Level.NetMode == NM_Client && Player != None && Player.InteractionMaster != None && !bOverlayAdded)
	{
		bOverlayAdded = true;
		Player.InteractionMaster.AddInteraction("Enhanced.EnhancedGuestOverlay", Player);
	}
	if (Level.NetMode == NM_Client && !bNickSent && Player != None && PlayerReplicationInfo != None)
	{
		NickClock += DeltaTime;
		if (NickClock > 3.0)
		{
			bNickSent = true;
			if (Class'Enhanced.EnhancedLobbySettings'.default.PlayerNick != "")
			{
				ConsoleCommand("SetName " $ Class'Enhanced.EnhancedLobbySettings'.default.PlayerNick);
			}
		}
	}
	if (bRoomOpened && bTestReady && !bLobbyReady)
	{
		ReadyClock += DeltaTime;
		if (ReadyClock > 4.0)
		{
			bLobbyReady = true;
			ServerSetReady(true);
			Log("[SDBG] lobby: test guest pressed Ready");
		}
	}
	if (Level.NetMode == NM_Client)
	{
		SilenceTime -= DeltaTime;
		if (SilenceTime <= 0.0)
		{
			SilenceTime = 2.0;
			SilenceLocalCommentary();
		}
	}
	if (bTestBot && Level.NetMode == NM_Client && Pawn != None)
	{
		S = "yaw=" $ string(MyView.Yaw & 65535) $ " pitch=" $ string(MyView.Pitch & 65535) $ " anim=" $ Pawn.GetPropertyText("AnimSequence")
			$ " sim=" $ Pawn.GetPropertyText("SimAnim") $ " role=" $ string(int(Pawn.Role)) $ " state=" $ string(Pawn.GetStateName())
			$ " cs=" $ string(GetStateName()) $ " interp=" $ string(bInterpolating) $ "/" $ Pawn.GetPropertyText("bInterpolating") $ " phys=" $ string(int(Pawn.Physics)) $ " acc=" $ string(int(VSize(Pawn.Acceleration))) $ " loc=" $ string(int(Pawn.Location.X)) $ "," $ string(int(Pawn.Location.Y)) $ " aT=" $ string(int(LastAT)) $ " aL=" $ string(int(LastAL)) $ " aF=" $ string(int(LastAF));
		if (S != LastView)
		{
			LastView = S;
			Log("[SDBG] c-view " $ S);
		}
	}
}

// He walks the way the camera looks (the game's own heroes do the same through their camera).
state PlayerWalking
{
	function Rotator GetRotationForPawnMove()
	{
		local Rotator R;

		R = MyView;
		R.Pitch = 0;
		R.Roll = 0;
		return R;
	}
}

// The stock game prints its debug lines (CM(...)) as client messages; they must not appear on player two's screen.
event ClientMessage(coerce string S, optional Name Type)
{
}

exec function Fire(optional float F)
{
	ServerAction();
}

defaultproperties
{
	bHorPlus=True
	bBehindView=True
	CameraDist=6.0
	InputClass=Class'Enhanced.EnhancedInput'
}

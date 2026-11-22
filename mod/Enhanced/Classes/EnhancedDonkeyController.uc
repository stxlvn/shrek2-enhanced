class EnhancedDonkeyController extends ShGame.DonkeyController;

// The hero controller of the mod for the levels where the Donkey is the hero (made from EnhancedHeroController by tools/gen_controllers.py): the game's own ShrekController with the stock save removed.
// Every save trigger of the game (the fairy, the autosave at level start, the timer, the poster) ends in
// ShHeroPawn.OnSaveGame(), whose last step is SaveGame() on this controller. The stock SaveGame set
// bQueuedToSaveGame, which the engine turns into a synchronous write of the whole level with a saving tile.
// Here the request becomes a checkpoint record instead, and the engine's save is never entered.

var config bool bHorPlus;     // widen the horizontal field of view with the aspect ratio (see EnhancedFov)
var float FovK;                // the aspect ratio relative to 4:3, asked from the viewport once a second
var float FovCheck;
var int HostMenuFrames;       // tests only: frames since the host's pause menu was opened (a picture is taken after 240, whatever the game clock does)
var bool bHostMenuDone;       // tests only: see EnhHostMenu
var bool bCursorFixed;      // the menu cursor's hot spot has been moved to the tip of the arrow
var float LogicalFov;
var float LogicalDesired;          // the angle the game wants; FovAngle holds the widened one between two ticks
var bool bFovScaled;
var bool bMenuCleaned;   // the menu pages of the previous level were closed
var float MenuClock;   // tests only: see RunMenuScript
var float MenuNextAt;  // tests only: when the next menu step is due
var EnhancedPlayBot PlayBot;   // the play test (EnhancedPlayBot): this controller's hero is driven by the bot
var bool bPlayBotChecked;
var int PosterFrames;          // frames the wanted poster's picture is up (the bot clicks it away)
var int MenuStep;
var Tab_Options FixedPage;     // the stock Settings page whose video tab has been rearranged (see FixSettingsPage)
var bool bAASet, bAFSet;
var float DropWatch;           // tests only: until this time the visibility of the resolution list is logged
var float DropLog;
var GUIComboBox DropCombo;
var bool bDropRelease;         // tests only: the mouse button pressed by the step 'clickres' is released on the next tick
var bool bFilling;             // the two repurposed lists are being filled: their change events are not ours
var float HudHiddenSince;      // since when the HUD has been hidden with nothing to explain it (see HostMenuWatch)
var bool bHudTested;           // tests only: see EnhHudTest
var bool bMenuHoldHost;        // the camera is held where the pause menu's page put it (see ShowInGameMenu)
var Vector HostHoldLoc;
var Rotator HostHoldRot;
var string SettingsTab;        // set by EnhancedSettingsPage: which group the stock Settings page shows (game, sound, video; empty = the stock page)       // the two repurposed lists have been given their items

native(3511) final function int EnhGetSetting(int Id);
native(3512) final function EnhSetSetting(int Id, int Value);

function SaveGame()
{
	local EnhancedGame G;

	G = EnhancedGame(Level.Game);
	if (G != None)
	{
		G.OnCheckpointRequest(Self, "SaveGame");
		return;
	}
	Super.SaveGame();
}

exec function SaveSlottedGame(int Slot, optional bool bCopyToSlotZero)
{
	local EnhancedGame G;

	G = EnhancedGame(Level.Game);
	if (G != None)
	{
		G.OnCheckpointRequest(Self, "SaveSlottedGame " $ string(Slot));
		return;
	}
	Super.SaveSlottedGame(Slot, bCopyToSlotZero);
}

exec function Fire(optional float F)
{
	local EnhancedGame G;

	G = EnhancedGame(Level.Game);
	if (G != None)
	{
		G.OnHostFire();
	}
	Super.Fire(F);
}

// The engine calls this once, before the first tick of a level. After a load the opening cutscene must not
// play (the game's own load path avoids it through bLoadFromSaveGame, and its "smart start" clears the
// PlayerStart events), and the saved hero state is put back.
event OnEnginePreFirstTick(bool bLoadFromSaveGame)
{
	local EnhancedGame G;
	local PlayerStart Ps;

	G = EnhancedGame(Level.Game);
	if (G != None && G.ShouldSkipIntro())
	{
		foreach AllActors(Class'Engine.PlayerStart', Ps)
		{
			Ps.Event = 'None';
		}
		if (G.bLoading)
		{
			bLoadFromSaveGame = true;
		}
	}
	if (G != None)
	{
		G.HoldIntro();
	}
	Super.OnEnginePreFirstTick(bLoadFromSaveGame);
	if (G != None && G.bLoading)
	{
		G.ApplyHero(Self);
	}
}

// ---- The menu of the mod ----
// The book of the front-end level asks the controller for its page by the stock name; the page of the mod takes its place.
// Other pages of the game go back to the stock page directly (Settings > Back, Exit > No, a confirmed delete), so a stock page
// that shows up is changed for the page of the mod in the next tick.
event ClientOpenMenu(string Menu, optional bool bDisconnect, optional string Msg1, optional string Msg2)
{
	if (Menu ~= "SHGame.ShFEGUIPage" || Left(Menu, 9) ~= "Enhanced.")
	{
		// pages of the level that was left stay open across a level change; start from a clean stack
		if (Player != None && GUIController(Player.GUIController) != None)
		{
			GUIController(Player.GUIController).CloseAll(false);
		}
	}
	if (Menu ~= "SHGame.ShFEGUIPage")
	{
		Menu = "Enhanced.EnhancedFEPage";
		if (EnhancedGame(Level.Game) != None && EnhancedGame(Level.Game).LobbyMode == "host")
		{
			Menu = "Enhanced.EnhancedRoomPage";
		}
		Log("[SDBG] menu: the front-end book opens " $ Menu);
	}
	Super.ClientOpenMenu(Menu, bDisconnect, Msg1, Msg2);
}


// ---- The stock Settings page, video tab ----
// The tab is two columns of labels and lists that overlap (a long label runs over its list, the rows are uneven), "colour depth" (32 or 16 bit)
// means nothing on a machine of today, and the row for the renderer is hidden. The controls are put on one grid (EnhancedMenuFit.LayoutOptions);
// "colour depth" becomes the anti-aliasing and the hidden renderer row the anisotropic filtering (EnhancedMenuFit.VideoLists).
function Place(GUIComponent C, float L, float T, float W, float H)
{
	C.WinLeft = L;
	C.WinTop = T;
	C.WinWidth = W;
	C.WinHeight = H;
}

function FixSettingsPage(GUIController GC)
{
	local Tab_OptionsVideo V;

	if (bDropRelease && Tab_Options(GC.ActivePage) != None)
	{
		bDropRelease = false;
		DropCombo.ShowListBox(None);
		Log("[SDBG] drop test: list shown by the click, focus " $ string(GC.FocusedControl));
	}
	if (DropWatch > Level.TimeSeconds && Level.TimeSeconds > DropLog && Tab_Options(GC.ActivePage) != None)
	{
		DropLog = Level.TimeSeconds + 0.25;
		Log("[SDBG] drop test: t=" $ string(Level.TimeSeconds) $ " visible=" $ string(Tab_Options(GC.ActivePage).VideoTab.cbResolution.MyListBox.bVisible) $ " focus=" $ string(GC.FocusedControl) $ " list h=" $ string(Tab_Options(GC.ActivePage).VideoTab.cbResolution.MyListBox.WinHeight) $ " top=" $ string(Tab_Options(GC.ActivePage).VideoTab.cbResolution.MyListBox.WinTop));
	}

	if (GC.ActivePage == None || Tab_Options(GC.ActivePage) == None)
	{
		if (GC.ActivePage != FixedPage)
		{
			FixedPage = None;
			bAASet = false;
			bAFSet = false;
		}
		return;
	}
	V = Tab_Options(GC.ActivePage).VideoTab;
	if (V == None)
	{
		return;
	}
	if (FixedPage != Tab_Options(GC.ActivePage))
	{
		FixedPage = Tab_Options(GC.ActivePage);
		bAASet = false;
		bAFSet = false;
		if (SettingsTab != "")
		{
			// opened from the Settings page of the mod: one group on the page, no tabs
			FixedPage.GameTab.MyButton.bVisible = false;
			FixedPage.SoundTab.MyButton.bVisible = false;
			FixedPage.VideoTab.MyButton.bVisible = false;
			if (SettingsTab == "game")
			{
				FixedPage.tabOptions.ActiveTab = FixedPage.GameTab.MyButton;
			}
			else if (SettingsTab == "sound")
			{
				FixedPage.tabOptions.ActiveTab = FixedPage.SoundTab.MyButton;
			}
			else
			{
				FixedPage.tabOptions.ActiveTab = FixedPage.VideoTab.MyButton;
			}
			FixedPage.tabOptions.ActiveTab.ChangeActiveState(true, true);
		}
		// the places of every control of the three tabs (also for the guests' settings page): EnhancedMenuFit.LayoutOptions
		Class'Enhanced.EnhancedMenuFit'.static.LayoutOptions(FixedPage);
		V.lblTextureDetail.Caption = Localize("Menu", "Textures", "Enhanced");
		V.lblObjectDetail.Caption = Localize("Menu", "Objects", "Enhanced");
		V.lblColorDepth.Caption = Localize("Menu", "AA", "Enhanced");
		V.lblRenderer.Caption = Localize("Menu", "AF", "Enhanced");
		V.lblBrightness.TextAlign = TXTA_Left;
		V.lblTextureDetail.TextAlign = TXTA_Left;
		V.lblObjectDetail.TextAlign = TXTA_Left;
		V.lblResolution.TextAlign = TXTA_Left;
		V.lblColorDepth.TextAlign = TXTA_Left;
		V.lblRenderer.TextAlign = TXTA_Left;
		V.cbRenderer.bVisible = true;
		V.cbRenderer.Edit.bVisible = true;
		V.lblRenderer.bVisible = true;
	}
	Class'Enhanced.EnhancedMenuFit'.static.ShortKeyNames(FixedPage.GameTab);
	// the two repurposed lists of the video tab (anti-aliasing, anisotropy): EnhancedMenuFit.VideoLists, for the guests' page as well
}

// Tests only: the steps of EnhMenu are pressed on the open page, one every five seconds, after twelve.
function RunMenuScript(GUIController GC)
{
	local EnhancedGame G;
	local string S, Step;
	local int i;

	G = EnhancedGame(Level.Game);
	if (G == None || G.MenuScript == "" || GC.ActivePage == None)
	{
		return;
	}
	// one step every five seconds after the first twelve; "untilguest" waits for a guest in the lobby; a step ending in "+" is pressed again every five
	// seconds while the page it is for is open (Start until everybody is ready)
	if (MenuClock < FMax(12.0, MenuNextAt) || !G.IsMenuLevel())
	{
		return;
	}
	MenuNextAt = MenuClock + 5.0;
	S = G.MenuScript;
	for (i = 0; i < MenuStep; i++)
	{
		if (InStr(S, ";") < 0)
		{
			return;
		}
		S = Mid(S, InStr(S, ";") + 1);
	}
	if (InStr(S, ";") >= 0)
	{
		Step = Left(S, InStr(S, ";"));
	}
	else
	{
		Step = S;
	}
	MenuStep++;
	if (Step ~= "untilguest")
	{
		// a guest in the lobby logs in as a spectator: NumPlayers does not count him (play run p11); the mod's list of guests does
		if (G.GPC.Length < 1)
		{
			MenuStep--;
		}
		else
		{
			Log("[SDBG] menu test: a guest is in the lobby");
		}
		return;
	}
	if (Right(Step, 1) == "+")
	{
		Step = Left(Step, Len(Step) - 1);
		MenuStep--;
	}
	Log("[SDBG] menu test: step " $ string(MenuStep + 1) $ " '" $ Step $ "' on " $ string(GC.ActivePage.Class));
	G.EnhLog("[PLAY] menu step " $ string(MenuStep + 1) $ " '" $ Step $ "' on " $ string(GC.ActivePage.Class));
	if (Tab_Options(GC.ActivePage) != None)
	{
		// the stock Settings page: Step is the tab to show (game, video, sound), or "drop<list>" opens a drop-down list (res, aa, af, tex, obj)
		if (Step ~= "dropres")
		{
			Tab_Options(GC.ActivePage).VideoTab.cbResolution.ShowListBox(None);
			DropWatch = Level.TimeSeconds + 4.0;
			Log("[SDBG] drop test: list shown now, visible=" $ string(Tab_Options(GC.ActivePage).VideoTab.cbResolution.MyListBox.bVisible));
		}
		else if (Left(Step, 5) ~= "click")
		{
			// what a click on the arrow does: the button's FocusInstead (the list) gets the focus when the button is pressed, the list is shown on release
			// (click + res, aa, af, tex, obj)
			DropCombo = Tab_Options(GC.ActivePage).VideoTab.cbResolution;
			if (Mid(Step, 5) ~= "aa")
			{
				DropCombo = Tab_Options(GC.ActivePage).VideoTab.cbColorDepth;
			}
			else if (Mid(Step, 5) ~= "af")
			{
				DropCombo = Tab_Options(GC.ActivePage).VideoTab.cbRenderer;
			}
			else if (Mid(Step, 5) ~= "tex")
			{
				DropCombo = Tab_Options(GC.ActivePage).VideoTab.cbTextureDetail;
			}
			else if (Mid(Step, 5) ~= "obj")
			{
				DropCombo = Tab_Options(GC.ActivePage).VideoTab.cbObjectDetail;
			}
			Log("[SDBG] hitbox: combo bounds " $ string(DropCombo.Bounds[0]) $ "," $ string(DropCombo.Bounds[1]) $ "," $ string(DropCombo.Bounds[2]) $ "," $ string(DropCombo.Bounds[3])
				$ " actual " $ string(DropCombo.ActualLeft()) $ "," $ string(DropCombo.ActualTop()) $ "," $ string(DropCombo.ActualWidth()) $ "," $ string(DropCombo.ActualHeight()));
			Log("[SDBG] hitbox: arrow bounds " $ string(DropCombo.MyShowListBtn.Bounds[0]) $ "," $ string(DropCombo.MyShowListBtn.Bounds[1]) $ "," $ string(DropCombo.MyShowListBtn.Bounds[2]) $ "," $ string(DropCombo.MyShowListBtn.Bounds[3])
				$ " actual " $ string(DropCombo.MyShowListBtn.ActualLeft()) $ "," $ string(DropCombo.MyShowListBtn.ActualTop()) $ "," $ string(DropCombo.MyShowListBtn.ActualWidth()) $ "," $ string(DropCombo.MyShowListBtn.ActualHeight()));
			Log("[SDBG] hitbox: edit bounds " $ string(DropCombo.Edit.Bounds[0]) $ "," $ string(DropCombo.Edit.Bounds[1]) $ "," $ string(DropCombo.Edit.Bounds[2]) $ "," $ string(DropCombo.Edit.Bounds[3])
				$ " mouse " $ string(GC.MouseX) $ "," $ string(GC.MouseY));
			DropCombo.MyShowListBtn.FocusInstead.SetFocus(None);
			DropWatch = Level.TimeSeconds + 4.0;
			Log("[SDBG] drop test: focus on the list before the click: " $ string(GC.FocusedControl));
			bDropRelease = true;
		}
		else if (Step ~= "dropaa")
		{
			Tab_Options(GC.ActivePage).VideoTab.cbColorDepth.ShowListBox(None);
		}
		else if (Step ~= "dropaf")
		{
			Tab_Options(GC.ActivePage).VideoTab.cbRenderer.ShowListBox(None);
		}
		else if (Step ~= "droptex")
		{
			Tab_Options(GC.ActivePage).VideoTab.cbTextureDetail.ShowListBox(None);
		}
		else if (Step ~= "video")
		{
			Tab_Options(GC.ActivePage).tabOptions.ActiveTab = Tab_Options(GC.ActivePage).VideoTab.MyButton;
		}
		else if (Step ~= "sound")
		{
			Tab_Options(GC.ActivePage).tabOptions.ActiveTab = Tab_Options(GC.ActivePage).SoundTab.MyButton;
		}
		else
		{
			Tab_Options(GC.ActivePage).tabOptions.ActiveTab = Tab_Options(GC.ActivePage).GameTab.MyButton;
		}
		Tab_Options(GC.ActivePage).tabOptions.ActiveTab.ChangeActiveState(true, true);
	}
	else if (EnhancedSettingsPage(GC.ActivePage) != None)
	{
		EnhancedSettingsPage(GC.ActivePage).TestClick(Step);
	}
	else if (EnhancedFEPage(GC.ActivePage) != None)
	{
		EnhancedFEPage(GC.ActivePage).TestClick(Step);
	}
	else if (EnhancedSavesPage(GC.ActivePage) != None)
	{
		EnhancedSavesPage(GC.ActivePage).TestClick(Step);
	}
	else if (EnhancedLobbyPage(GC.ActivePage) != None)
	{
		EnhancedLobbyPage(GC.ActivePage).TestClick(Step);
	}
	else if (EnhancedLanPage(GC.ActivePage) != None)
	{
		EnhancedLanPage(GC.ActivePage).TestClick(Step);
	}
	else if (EnhancedHostPage(GC.ActivePage) != None)
	{
		EnhancedHostPage(GC.ActivePage).TestClick(Step);
	}
	else if (EnhancedRoomPage(GC.ActivePage) != None)
	{
		EnhancedRoomPage(GC.ActivePage).TestClick(Step);
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
	if (bHorPlus && FovK > 1.01 && !EnhancedGame(Level.Game).Off("nohorplus"))
	{
		LogicalFov = FovAngle;
		LogicalDesired = DesiredFOV;
		FovAngle = Class'Enhanced.EnhancedFov'.static.HorPlus(LogicalFov, FovK);
		DesiredFOV = Class'Enhanced.EnhancedFov'.static.HorPlus(LogicalDesired, FovK);   // the stock AdjustView pulls FovAngle back to DesiredFOV every frame: both are widened
		bFovScaled = true;
	}
}

// In the front-end level the hero is held by a cutscene while the controller still walks: the stock move code then reads a pawn that is not there,
// twice per frame, for as long as the menu is open (ten thousand warnings in a minute).
state PlayerWalking
{
	function PlayerMove(float DeltaTime)
	{
		if (Pawn == None)
		{
			return;
		}
		Super.PlayerMove(DeltaTime);
	}
}

// ---- The game's own pause menu of the hero ----
// The page of the pause menu turns the camera to one fixed angle (Camera.SetRotation(0, 18656, 0)) and puts the book in front of it; the stock game
// is paused while it is open, so the camera stands still. With other players in the world the game is not paused (see EnhancedGame.SetPause), the
// camera went on following the hero, the book was left behind it and the menu showed only the wooden board while the world went on. Here the camera is
// held where the page put it for as long as the menu is open, with or without a pause. When the menu is closed the HUD it hid comes back.
exec function ShowInGameMenu()
{
	Super.ShowInGameMenu();
	if (!bMenuHoldHost && Player != None && GUIController(Player.GUIController) != None && GUIController(Player.GUIController).ActivePage != None)
	{
		bMenuHoldHost = true;
		HostHoldLoc = vCameraStart();
		HostHoldRot = rCameraRot();
	}
}

event PlayerCalcView(out Actor ViewActor, out Vector CameraLocation, out Rotator CameraRotation)
{
	Super.PlayerCalcView(ViewActor, CameraLocation, CameraRotation);
	if (bMenuHoldHost)
	{
		CameraLocation = HostHoldLoc;
		CameraRotation = HostHoldRot;
	}
}

// The menu hides the HUD and shows it again when its page closes; if the page goes away some other way (the window was minimized and brought back,
// a cutscene was skipped in the same moment), the HUD stayed hidden for good. A HUD that has been hidden for 2.5 s while the hero walks, no page is open
// and no cutscene plays, is shown again.
function HostMenuWatch()
{
	local bool bPage, bCutText;

	bPage = Player != None && GUIController(Player.GUIController) != None && GUIController(Player.GUIController).ActivePage != None;
	if (bMenuHoldHost && !bPage)
	{
		bMenuHoldHost = false;
	}
	if (EnhancedGame(Level.Game) != None && EnhancedGame(Level.Game).HudTestAt > 0.0 && !bHudTested && Level.TimeSeconds > EnhancedGame(Level.Game).HudTestAt && myHUD != None)
	{
		bHudTested = true;
		myHUD.SetPropertyText("bHideHUD", "True");
		Log("[SDBG] test: the HUD is hidden by hand at t=" $ string(Level.TimeSeconds));
	}
	if (KWHud(myHUD) != None && KWHud(myHUD).CutTextController != None)
	{
		bCutText = KWHud(myHUD).CutTextController.bCutSceneInProgress;
	}
	if (myHUD == None || bPage || Pawn == None || bCutText || !(myHUD.GetPropertyText("bHideHUD") ~= "True") || bInCutScene() || string(GetStateName()) != "PlayerWalking")
	{
		HudHiddenSince = 0.0;
		return;
	}
	if (HudHiddenSince == 0.0)
	{
		HudHiddenSince = Level.TimeSeconds;
		return;
	}
	if (Level.TimeSeconds - HudHiddenSince > 2.5)
	{
		HudHiddenSince = 0.0;
		myHUD.SetPropertyText("bHideHUD", "False");
		Log("[SDBG] the HUD was hidden with no menu and no cutscene: shown again at t=" $ string(Level.TimeSeconds));
	}
}

// Tests only (EnhHostMenu): where the camera looks and where the pause menu's book is while the menu is open.
function LogMenuGeometry()
{
	local MenuBook Mb;
	local Vector Cp, Ax, Ay, Az, D;
	local Rotator Cr;
	local string Cam;

	Cp = vCameraStart();
	Cr = rCameraRot();
	GetAxes(Cr, Ax, Ay, Az);
	Cam = GetPropertyText("Camera") $ " pri=" $ string(PlayerReplicationInfo) $ " netmode=" $ string(int(Level.NetMode)) $ " pauseable=" $ Level.Game.GetPropertyText("bPauseable") $ " adminPause=" $ Level.Game.GetPropertyText("bAdminCanPause") $ " game=" $ string(Level.Game.Class);
	Log("[BKG] frame " $ string(HostMenuFrames) $ " paused=" $ string(Level.Pauser) $ " camStart=" $ string(Cp) $ " camRot=" $ string(Cr) $ " camera=" $ Cam $ " fov=" $ string(FovAngle) $ " desired=" $ string(DesiredFOV) $ " behind=" $ string(bBehindView) $ " hideHud=" $ myHUD.GetPropertyText("bHideHUD") $ " ctlState=" $ string(GetStateName()));
	foreach AllActors(Class'GUI.MenuBook', Mb)
	{
		D = Mb.Location - Cp;
		Log("[BKG]   book " $ string(Mb) $ " loc=" $ string(Mb.Location) $ " rot=" $ string(Mb.Rotation) $ " hidden=" $ string(int(Mb.bHidden)) $ " drawtype=" $ string(int(Mb.DrawType)) $ " mesh=" $ string(Mb.Mesh) $ " state=" $ string(Mb.GetStateName())
			$ " | fwd=" $ string(int(D Dot Ax)) $ " right=" $ string(int(D Dot Ay)) $ " up=" $ string(int(D Dot Az)) $ " dist=" $ string(int(VSize(D))));
	}
}

// Tests: a button of the pause menu's page pressed by name.
function PressPauseMenu(string What)
{
	local ShInGameMenuControls M;
	local GUIButton B;

	if (Player == None || GUIController(Player.GUIController) == None)
	{
		return;
	}
	M = ShInGameMenuControls(GUIController(Player.GUIController).ActivePage);
	if (M == None)
	{
		Log("[SDBG] test: the pause menu is not the open page");
		return;
	}
	if (What ~= "options")
	{
		B = M.btnOptions;
	}
	else if (What ~= "posters")
	{
		B = M.btnWanterPoster;
	}
	else if (What ~= "main")
	{
		B = M.btnMainMenu;
	}
	else if (What ~= "quit")
	{
		B = M.btnQuit;
	}
	if (B != None)
	{
		Log("[SDBG] test: the pause menu's " $ What $ " button is pressed");
		M.InternalOnClick(B);
	}
}

// The play test (EnhancedPlayBot): why the controls are not the player's now ("" = they are).
function string BotBusy()
{
	// Health is a float in the game's Pawn and an int in the classes the mod compiles against: reading Pawn.Health from the mod's script crashed
	// the script engine (tests b1-b3); the value is read by name
	if (Pawn == None || float(Pawn.GetPropertyText("Health")) <= 0.0)
	{
		return "no hero";
	}
	if (Player != None && GUIController(Player.GUIController) != None && GUIController(Player.GUIController).ActivePage != None)
	{
		// the wanted poster's full-screen picture (the game is paused under it): a player clicks it away, the bot does after a moment (frames are
		// counted: the level's clock stands still while it is paused)
		if (PlayBot != None && GUIController(Player.GUIController).ActivePage.IsA('SHInGameWantedPoster'))
		{
			PosterFrames++;
			if (PosterFrames == 150)
			{
				Log("[PLAY] host: the wanted poster's picture is clicked away");
				EnhancedGame(Level.Game).EnhLog("[PLAY] " $ string(Level) $ " host: the wanted poster's picture is clicked away");
				SHInGameWantedPoster(GUIController(Player.GUIController).ActivePage).InternalOnClick(SHInGameWantedPoster(GUIController(Player.GUIController).ActivePage).PosterBtn);
			}
			return "the wanted poster is shown";
		}
		return "a menu is open";
	}
	PosterFrames = 0;
	if (Level.Pauser != None)
	{
		return "paused";
	}
	// (the mod's gate hold, GateNoteHost, is handled by the bot itself: it stands on the gate's trigger, EnhancedPlayBot.AtGate)
	if (IsInState('PlayerWalking') || IsInState('PlayerSwimming') || IsInState('PlayerClimbing'))
	{
		return "";
	}
	return "controller state " $ string(GetStateName());
}

// The bot's choices for this frame, given as the keyboard gives them: the view's direction, forward, jump, attack.
function PlayBotTick(float DeltaTime)
{
	local Rotator R;
	local int BasisYaw;
	local float A;

	if (!bPlayBotChecked)
	{
		bPlayBotChecked = true;
		if (Player != None && Viewport(Player) != None && InStr(EnhancedGame(Level.Game).EnhBotEnv(0), "play=1") >= 0)
		{
			PlayBot = new Class'Enhanced.EnhancedPlayBot';
			PlayBot.Init(true);
			Log("[PLAY] host: the play bot drives this hero on " $ string(Level));
		}
	}
	// only on a level that is played, with a real hero (not the menu, not the logos' map SH2_Preamble with its stand-in DummyPlayer: the bot started there
	// and the game ended in this controller's PlayerTick, test p10)
	// nor in a guest's own opening (a single-player game of his until he joins the host: the bot took it for the host's game, play run p12)
	if (PlayBot == None || EnhancedGame(Level.Game) == None || EnhancedGame(Level.Game).IsMenuLevel() || Left(string(Level), 12) ~= "SH2_Preamble"
		|| EnhancedGame(Level.Game).IntroOnlyHost != ""
		|| Pawn == None || !Pawn.IsA('ShHeroPawn') || Pawn.IsA('DummyPlayer'))
	{
		return;
	}
	PlayBot.Drive(self, DeltaTime, BotBusy());
	if (PlayBot.bOutTurn)
	{
		R = Rotation;
		R.Yaw = PlayBot.OutYaw;
		SetRotation(R);
	}
	// the hero walks along the camera's axes (KWHeroController.GetRotationForPawnMove, bUseCameraAxesForPawnMove): the bot presses the forward and
	// sideways keys for the way it wants relative to the camera, as a player does (turning the controller moved nothing: the hero kept walking the
	// camera's way and ran into a rock, nav4)
	if (Pawn.IsInState('MountHanging'))
	{
		// hanging: sideways moves along a vine, forward climbs up, back lets go (ShPlayerInput)
		aStrafe = 1200.0 * PlayBot.OutHangX;
		aBaseY = 1200.0 * PlayBot.OutHangY;
	}
	else if (PlayBot.OutForward > 0.0)
	{
		if (bUseCameraAxesForPawnMove)
		{
			BasisYaw = rCameraRot().Yaw;
		}
		else
		{
			BasisYaw = Pawn.Rotation.Yaw;
		}
		A = float((PlayBot.OutYaw - BasisYaw) & 65535) * 0.0000958738;
		aBaseY = 1200.0 * PlayBot.OutForward * Cos(A);
		aStrafe = 1200.0 * PlayBot.OutForward * Sin(A);
	}
	if (PlayBot.bOutJump)
	{
		bPressedJump = true;
	}
	if (PlayBot.bOutFire)
	{
		Fire(0);
	}
}

event PlayerTick(float DeltaTime)
{
	local GUIController GC;

	Class'Enhanced.EnhancedMenuFit'.static.Ensure(self);
	if (EnhancedGame(Level.Game) != None)
	{
		PlayBotTick(DeltaTime);
	}

	if (!bHostMenuDone && EnhancedGame(Level.Game) != None && EnhancedGame(Level.Game).HostMenuAt > 0.0 && Level.TimeSeconds > EnhancedGame(Level.Game).HostMenuAt && Pawn != None)
	{
		bHostMenuDone = true;
		Log("[SDBG] test: the host's own pause menu is opened (ShowInGameMenu)");
		ConsoleCommand("ShowInGameMenu");
	}
	if (bHostMenuDone)
	{
		HostMenuFrames++;
		if (HostMenuFrames == 5 || HostMenuFrames == 60 || HostMenuFrames == 238)
		{
			LogMenuGeometry();
		}
		if (HostMenuFrames == 240)
		{
			ConsoleCommand("shot");
			Log("[SDBG] test: picture of the host's pause menu");
		}
		// EnhHostMenuPage=options|posters|main|quit: then that button of the pause menu is pressed (the page turns as for a player) and the next
		// page is taken too
		if (HostMenuFrames == 260 && EnhancedGame(Level.Game) != None && EnhancedGame(Level.Game).HostMenuPage != "")
		{
			PressPauseMenu(EnhancedGame(Level.Game).HostMenuPage);
		}
		if (HostMenuFrames == 560 && EnhancedGame(Level.Game) != None && EnhancedGame(Level.Game).HostMenuPage != "")
		{
			ConsoleCommand("shot");
			Log("[SDBG] test: picture of the pause menu's settings page");
		}
	}
	HostMenuWatch();
	UndoHorPlus();
	Super.PlayerTick(DeltaTime);
	DoHorPlus(DeltaTime);
	if (Player != None)
	{
		GC = GUIController(Player.GUIController);
		if (!bMenuCleaned && GC != None)
		{
			bMenuCleaned = true;
			GC.CloseAll(false);
		}
		MenuClock += DeltaTime;
		if (GC != None)
		{
			if (EnhancedGame(Level.Game) != None && EnhancedGame(Level.Game).CursorTestX > 0.0)
			{
				GC.MouseX = EnhancedGame(Level.Game).CursorTestX;
				GC.MouseY = EnhancedGame(Level.Game).CursorTestY;
			}
			if (!bCursorFixed)
			{
				// the stock book cursor is an arrow of 64 x 64 whose tip is at the top centre (32, 1), but its hot spot is set to (0.25, 0.25) of the picture: a click
				// landed about 22 px (more at a larger resolution, where the arrow is drawn larger) below and left of the tip. The hot spot goes to the tip.
				bCursorFixed = true;
				GC.MouseCursorOffset[0].X = 0.5;
				GC.MouseCursorOffset[0].Y = 0.02;
			}
			FixSettingsPage(GC);
			RunMenuScript(GC);
		}
		if (GC != None && GC.ActivePage != None && GC.ActivePage.Class == Class'SHGame.ShFEGUIPage')
		{
			GC.ReplaceMenu("Enhanced.EnhancedFEPage");
		}
	}
}

defaultproperties
{
	bHorPlus=True
}

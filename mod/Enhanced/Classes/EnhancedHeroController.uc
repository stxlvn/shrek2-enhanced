class EnhancedHeroController extends ShrekController;

// The hero controller of the mod: the game's own ShrekController with the stock save removed.
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
var int MenuStep;
var Tab_Options FixedPage;     // the stock Settings page whose video tab has been rearranged (see FixSettingsPage)
var bool bAASet, bAFSet;
var float DropWatch;           // tests only: until this time the visibility of the resolution list is logged
var float DropLog;
var GUIComboBox DropCombo;
var bool bDropRelease;         // tests only: the mouse button pressed by the step 'clickres' is released on the next tick
var bool bFilling;             // the two repurposed lists are being filled: their change events are not ours
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
// means nothing on a machine of today, and the row for the renderer is hidden. The controls are put on one grid (a label above its list, the
// same pitch everywhere, short labels); "colour depth" becomes the anti-aliasing and the hidden renderer row the anisotropic filtering, both
// applied at once through a change of the resolution to the current one (the Direct3D hook of the engine layer asks for them when the device
// is made again).
function string AAText(int Samples)
{
	if (Samples < 2)
	{
		return Localize("Menu", "Off", "Enhanced");
	}
	return string(Samples) $ "x";
}

function string AFText(int Level)
{
	if (Level < 2)
	{
		return Localize("Menu", "Off", "Enhanced");
	}
	return string(Level) $ "x";
}

function int AAIndex(int Samples)
{
	if (Samples >= 8)
	{
		return 3;
	}
	if (Samples >= 4)
	{
		return 2;
	}
	if (Samples >= 2)
	{
		return 1;
	}
	return 0;
}

function int AFIndex(int Level)
{
	if (Level >= 16)
	{
		return 3;
	}
	if (Level >= 8)
	{
		return 2;
	}
	if (Level >= 4)
	{
		return 1;
	}
	return 0;
}

function ApplyVideoNow()
{
	ConsoleCommand("SETRES " $ ConsoleCommand("GetCurrentRes"));
}

function EnhAAChanged(GUIComponent Sender)
{
	local string T;
	local int V;

	if (bFilling)
	{
		return;
	}
	T = FixedPage.VideoTab.cbColorDepth.GetText();
	if (T != AAText(0) && T != "2x" && T != "4x" && T != "8x")
	{
		return;
	}
	V = 0;
	if (T == "2x")
	{
		V = 2;
	}
	else if (T == "4x")
	{
		V = 4;
	}
	else if (T == "8x")
	{
		V = 8;
	}
	EnhSetSetting(1, V);
	ApplyVideoNow();
}

function EnhAFChanged(GUIComponent Sender)
{
	local string T;
	local int V;

	if (bFilling)
	{
		return;
	}
	T = FixedPage.VideoTab.cbRenderer.GetText();
	if (T != AFText(1) && T != "4x" && T != "8x" && T != "16x")
	{
		return;
	}
	V = 1;
	if (T == "4x")
	{
		V = 4;
	}
	else if (T == "8x")
	{
		V = 8;
	}
	else if (T == "16x")
	{
		V = 16;
	}
	EnhSetSetting(2, V);
	ApplyVideoNow();
}

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
	local float XL, XR, W, T0, P, LH, CH;

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
		XL = 0.2608;
		XR = 0.5107;
		W = 0.2207;
		T0 = 0.06;
		P = 0.165;
		LH = 0.05;
		CH = 0.05;
		// left column: brightness, texture detail, object detail; right column: resolution, anti-aliasing, anisotropy
		Place(V.lblBrightness, XL, T0, W, LH);
		Place(V.sldBrightness, XL, T0 + LH, W, CH);
		Place(V.lblTextureDetail, XL, T0 + P, W, LH);
		Place(V.cbTextureDetail, XL, T0 + P + LH, W, CH);
		Place(V.lblObjectDetail, XL, T0 + P * 2.0, W, LH);
		Place(V.cbObjectDetail, XL, T0 + P * 2.0 + LH, W, CH);
		Place(V.lblResolution, XR, T0, W, LH);
		Place(V.cbResolution, XR, T0 + LH, W, CH);
		Place(V.lblColorDepth, XR, T0 + P, W, LH);
		Place(V.cbColorDepth, XR, T0 + P + LH, W, CH);
		Place(V.lblRenderer, XR, T0 + P * 2.0, W, LH);
		Place(V.cbRenderer, XR, T0 + P * 2.0 + LH, W, CH);
		Place(V.btnApplyVideoChanges, XR, T0 + P * 3.0 + 0.02, W, CH);
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
	// the stock page fills these two lists with the bit depth and the renderer again whenever it refreshes: filled again until they are ours
	if (!bAASet)
	{
		bFilling = true;
		V.cbColorDepth.OnChange = EnhAAChanged;
		Log("[SDBG] settings: AA=" $ string(EnhGetSetting(1)) $ " AF=" $ string(EnhGetSetting(2)) $ " dxvk=" $ string(EnhGetSetting(3)) $ " texts '" $ V.cbColorDepth.GetText() $ "' '" $ V.cbRenderer.GetText() $ "'");
		V.cbColorDepth.List.Clear();
		V.cbColorDepth.AddItem(AAText(0));
		V.cbColorDepth.AddItem("2x");
		V.cbColorDepth.AddItem("4x");
		V.cbColorDepth.AddItem("8x");
		V.cbColorDepth.SetIndex(AAIndex(EnhGetSetting(1)));
		bAASet = true;
		bFilling = false;
	}
	if (!bAFSet)
	{
		bFilling = true;
		V.cbRenderer.OnChange = EnhAFChanged;
		V.cbRenderer.List.Clear();
		V.cbRenderer.AddItem(AFText(1));
		V.cbRenderer.AddItem("4x");
		V.cbRenderer.AddItem("8x");
		V.cbRenderer.AddItem("16x");
		V.cbRenderer.SetIndex(AFIndex(EnhGetSetting(2)));
		bAFSet = true;
		bFilling = false;
	}
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
	if (MenuClock < 12.0 + 5.0 * float(MenuStep))
	{
		return;
	}
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
	Log("[SDBG] menu test: step " $ string(MenuStep) $ " '" $ Step $ "' on " $ string(GC.ActivePage.Class));
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

event PlayerTick(float DeltaTime)
{
	local GUIController GC;

	if (!bHostMenuDone && EnhancedGame(Level.Game) != None && EnhancedGame(Level.Game).HostMenuAt > 0.0 && Level.TimeSeconds > EnhancedGame(Level.Game).HostMenuAt && Pawn != None)
	{
		bHostMenuDone = true;
		Log("[SDBG] test: the host's own pause menu is opened (ShowInGameMenu)");
		ConsoleCommand("ShowInGameMenu");
	}
	if (bHostMenuDone)
	{
		HostMenuFrames++;
		if (HostMenuFrames == 240)
		{
			ConsoleCommand("shot");
			Log("[SDBG] test: picture of the host's pause menu");
		}
	}
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

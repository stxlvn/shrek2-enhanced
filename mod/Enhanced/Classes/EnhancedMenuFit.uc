class EnhancedMenuFit extends Interaction;

// Every page of the menu book (the mod's pages and the stock ones, front end and pause menu): a caption wider than its own box is drawn with the
// next smaller face of its style, until it fits (owner, 2026-11-21: "all the content of every book menu must fit on one page"). A caption that
// changes (a player's name, the address, a key binding) is fitted again from its original style. The measuring needs the canvas, so it runs
// after the menu has been drawn; a change shows from the next frame.
// Tests (URL option EnhMenuDump): one second after a page opens, every component's place on the screen in pixels goes to the log ([MENUBOX]).

var array<GUIComponent> FitComp;
var array<string> FitCaption;
var array<string> FitBase;
var array<int> FitClip;
var array<int> FitWidth;
var GUIPage LastPage;
var float PageSince;
var bool bDumped;
var int FitLogs;
var GUIController ColoredFor;     // the menu controller whose stock styles got the readable inactive colour

// Put on a player's viewport once (the interactions stay across level changes; a controller is made again in every level).
static function Ensure(PlayerController P)
{
	local int i;

	if (P == None || P.Player == None || P.Player.InteractionMaster == None)
	{
		return;
	}
	for (i = 0; i < P.Player.LocalInteractions.Length; i++)
	{
		if (EnhancedMenuFit(P.Player.LocalInteractions[i]) != None)
		{
			return;
		}
	}
	P.Player.InteractionMaster.AddInteraction("Enhanced.EnhancedMenuFit", P.Player);
}

// how wide a style draws a text at this canvas, in pixels (enhnative.c: the style's own UGUIStyles::TextSize)
native(3544) final function int EnhTextWidth(Canvas C, GUIStyles Style, string Text);

function Initialize()
{
	bVisible = true;
	bActive = false;
	bRequiresTick = false;
}

function PostRender(Canvas C)
{
	local GUIController GC;
	local PlayerController P;

	if (ViewportOwner == None || C == None)
	{
		return;
	}
	P = ViewportOwner.Actor;
	GC = GUIController(ViewportOwner.GUIController);
	if (P == None || GC == None || GC.ActivePage == None || !GC.ActivePage.bVisible)
	{
		LastPage = None;
		return;
	}
	if (GC.ActivePage != LastPage)
	{
		LastPage = GC.ActivePage;
		if (Tab_Options(LastPage) != None)
		{
			LayoutOptions(Tab_Options(LastPage));
		}
		if (SHPageYesNo(LastPage) != None)
		{
			LayoutYesNo(SHPageYesNo(LastPage));
		}
		PageSince = P.Level.TimeSeconds;
		bDumped = false;
		FitComp.Length = 0;
		FitCaption.Length = 0;
		FitBase.Length = 0;
		FitClip.Length = 0;
		FitWidth.Length = 0;
	}
	if (ColoredFor != GC)
	{
		ColoredFor = GC;
		InactiveColours(GC);
	}
	if (Tab_Options(GC.ActivePage) != None)
	{
		ShortKeyNames(Tab_Options(GC.ActivePage).GameTab);
	}
	FitAll(C, GC, GC.ActivePage.Controls, 0);
	if (!bDumped && P.Level.TimeSeconds - PageSince > 1.0 && P.Level.Game != None && EnhancedGame(P.Level.Game) != None && EnhancedGame(P.Level.Game).bMenuDump)
	{
		bDumped = true;
		Log("[MENUBOX] page " $ string(GC.ActivePage.Class) $ " screen " $ string(int(C.ClipX)) $ "x" $ string(int(C.ClipY)));
		MeasureTest(C, GC);
		DumpAll(C, GC.ActivePage.Controls, 0);
	}
}

// An inactive button (the save page's Delete with no save chosen, the pause menu's Load) or settings box was drawn in a light sand colour at half
// alpha, or a light grey, and vanished on the parchment (owner, 2026-11-21: "fix the colours of the text"): those styles get a muted ink, fully
// opaque. Styles whose stock inactive colour is already the dark ink keep it (the anisotropy list of the video tab is drawn inactive).
function InactiveColours(GUIController GC)
{
	local array<string> Names;
	local int i;
	local GUIStyles S;

	Names[0] = "SHSolidBox";
	Names[1] = "SHBTNDeleteStyle";
	Names[2] = "SHBTNOptionsStyle";
	Names[3] = "SHBTNQuitStyle";
	Names[4] = "SHBTNBackStyle";
	Names[5] = "IGBTNLoadStyle";
	Names[6] = "IGBTNMainMenuStyle";
	Names[7] = "IGBTNOptionsStyle";
	Names[8] = "IGBTNPlayStyle";
	Names[9] = "IGBTNQuitStyle";
	Names[10] = "IGBTNWanterPosterStyle";
	for (i = 0; i < Names.Length; i++)
	{
		S = GC.GetStyle(Names[i]);
		if (S != None)
		{
			S.FontColors[4].R = 102;
			S.FontColors[4].G = 88;
			S.FontColors[4].B = 62;
			S.FontColors[4].A = 255;
		}
	}
}

// ---- The stock settings page (main menu and pause menu, the host's and the guests'): everything on the right-hand page ----
static function Put(GUIComponent C, float L, float T, float W, float H)
{
	if (C == None)
	{
		return;
	}
	C.WinLeft = L;
	C.WinTop = T;
	C.WinWidth = W;
	C.WinHeight = H;
}

static function LayoutOptions(Tab_Options Page)
{
	local Tab_OptionsVideo V;
	local Tab_OptionsGame G;
	local Tab_OptionsSound S;
	local float XL, XR, W, T0, P, LH, CH;
	local int i;

	if (Page == None)
	{
		return;
	}
	V = Page.VideoTab;
	// Everything on the right-hand page of the book (owner, 2026-11-21: all the content of a menu on one page; the stock tabs spread over both
	// pages). Horizontal places are parts of the screen's width (the right page is about 0.31 to 0.70 at 16:9). The tab headers (Game, Video,
	// Sound; shown in the pause menu's settings, hidden on the main menu's) go to the top of the right page; the panels below them start where
	// the headers end, and vertical places are parts of the panel: at 720p y = 183 + 532 * T pixels. A caption still too wide gets a smaller face.
	Page.tabOptions.WinLeft = 0.315;
	Page.tabOptions.WinTop = 0.195;
	XL = 0.3125;
	XR = 0.512;
	W = 0.1875;
	T0 = 0.0;
	P = 0.2;
	LH = 0.05;
	CH = 0.05;
	// video, two columns: brightness, texture detail, object detail | resolution, anti-aliasing, anisotropy
	if (V != None)
	{
		Put(V.lblBrightness, XL, T0, W, LH);
		Put(V.sldBrightness, XL, T0 + LH, W, CH);
		Put(V.lblTextureDetail, XL, T0 + P, W, LH);
		Put(V.cbTextureDetail, XL, T0 + P + LH, W, CH);
		Put(V.lblObjectDetail, XL, T0 + P * 2.0, W, LH);
		Put(V.cbObjectDetail, XL, T0 + P * 2.0 + LH, W, CH);
		Put(V.lblResolution, XR, T0, W, LH);
		Put(V.cbResolution, XR, T0 + LH, W, CH);
		Put(V.lblColorDepth, XR, T0 + P, W, LH);
		Put(V.cbColorDepth, XR, T0 + P + LH, W, CH);
		Put(V.lblRenderer, XR, T0 + P * 2.0, W, LH);
		Put(V.cbRenderer, XR, T0 + P * 2.0 + LH, W, CH);
		Put(V.btnApplyVideoChanges, XR, T0 + P * 3.0, W, CH);
	}
	// game: the six keys (a label and its key box per row), the mouse speed and the camera's auto-level side by side, the reset
	G = Page.GameTab;
	if (G != None)
	{
		Put(G.lblKeyForward, XL, 0.0, 0.135, LH);
		Put(G.lblKeyBackward, XL, 0.055, 0.135, LH);
		Put(G.lblKeyTurnLeft, XL, 0.11, 0.135, LH);
		Put(G.lblKeyTurnRight, XL, 0.165, 0.135, LH);
		Put(G.lblKeyJump, XL, 0.22, 0.135, LH);
		Put(G.lblKeyAttack, XL, 0.275, 0.135, LH);
		for (i = 0; i < 6; i++)
		{
			if (G.InGame_KeyButtons[i] != None)
			{
				Put(G.InGame_KeyButtons[i], 0.45, 0.055 * float(i), 0.245, LH);
			}
		}
		Put(G.lblMouseSpeedGame, XL, 0.33, W, LH);
		Put(G.sldMouseSpeedGame, XL, 0.38, W, LH);
		Put(G.lblAutoLevel, XR, 0.33, W, LH);
		if (Localize("Menu", "AutoLevel", "Enhanced") != "" && InStr(Localize("Menu", "AutoLevel", "Enhanced"), "<?") < 0)
		{
			G.lblAutoLevel.Caption = Localize("Menu", "AutoLevel", "Enhanced");
		}
		Put(G.btnAutolevel, XR + W / 2.0 - 0.05, 0.38, 0.1, 0.075);
		Put(G.btnReset, 0.405, 0.5, 0.19, LH);
	}
	// sound: the two volumes one below the other
	S = Page.SoundTab;
	if (S != None)
	{
		Put(S.lblMusicVolume, XL, 0.0, 0.385, LH);
		Put(S.sldMusicVolume, XL, LH, 0.385, CH);
		Put(S.lblEffectsVolume, XL, 0.17, 0.385, LH);
		Put(S.sldEffectsVolume, XL, 0.17 + LH, 0.385, CH);
	}
	// the stock Back button stood on the left page: to the right one, below the controls, in the middle of the page (the page's own frame:
	// at 720p x = -384.5 + 1857.6 * L pixels, measured from two places of the button: 0.2608 at 100, 0.664 at 849)
	if (Page.BackButton != None)
	{
		Page.BackButton.WinLeft = 0.5176;
	}
}

// The key boxes of the stock game tab name the mouse buttons in full ("Left Mouse Button or Enter" did not fit its box on the page): the long names
// are written short ([Menu] KeyLongN / KeyShortN in Enhanced.int / .Rus). The stock page writes the captions again when a key is changed: every frame.
static function ShortKeyNames(Tab_OptionsGame G)
{
	local int i, n, k;
	local string C, Long, Short;

	if (G == None)
	{
		return;
	}
	for (i = 0; i < 6; i++)
	{
		if (G.InGame_KeyButtons[i] == None)
		{
			continue;
		}
		C = G.InGame_KeyButtons[i].Caption;
		for (n = 1; n <= 3; n++)
		{
			Long = Localize("Menu", "KeyLong" $ string(n), "Enhanced");
			Short = Localize("Menu", "KeyShort" $ string(n), "Enhanced");
			k = InStr(C, Long);
			if (Long != "" && Short != "" && InStr(Long, "<?") < 0 && k >= 0)
			{
				C = Left(C, k) $ Short $ Mid(C, k + Len(Long));
			}
		}
		if (C != G.InGame_KeyButtons[i].Caption)
		{
			G.InGame_KeyButtons[i].Caption = C;
		}
	}
}

// ---- The stock yes/no pages (quit, back to the main menu, load; the guests' too): their lines ran over both pages ----
// The lines go to the right page's width; a line longer than 30 letters is split at the space nearest its middle (no more than four lines in
// all: the page has four rows), and the lines are laid out again from the top. Yes and No stand side by side inside the page.
static function LayoutYesNo(SHPageYesNo Page)
{
	local array<string> Lines;
	local string S;
	local int i, k, best, n;

	if (Page == None)
	{
		return;
	}
	for (i = 0; i < 4; i++)
	{
		S = YesNoLine(Page, i).Caption;
		if (S == "")
		{
			continue;
		}
		if (Len(S) > 30)
		{
			best = -1;
			for (k = 0; k < Len(S); k++)
			{
				if (Mid(S, k, 1) == " " && (best < 0 || Abs(k - Len(S) / 2) < Abs(best - Len(S) / 2)))
				{
					best = k;
				}
			}
			if (best > 0)
			{
				Lines[Lines.Length] = Left(S, best);
				Lines[Lines.Length] = Mid(S, best + 1);
				continue;
			}
		}
		Lines[Lines.Length] = S;
	}
	if (Lines.Length > 4)
	{
		return;
	}
	n = Lines.Length;
	for (i = 0; i < 4; i++)
	{
		if (i < n)
		{
			YesNoLine(Page, i).Caption = Lines[i];
		}
		else
		{
			YesNoLine(Page, i).Caption = "";
		}
		YesNoLine(Page, i).WinLeft = 0.31;
		YesNoLine(Page, i).WinWidth = 0.39;
	}
	Put(Page.btnYes, 0.33, Page.btnYes.WinTop, 0.16, Page.btnYes.WinHeight);
	Put(Page.btnNo, 0.515, Page.btnNo.WinTop, 0.16, Page.btnNo.WinHeight);
}

static function GUIButton YesNoLine(SHPageYesNo Page, int i)
{
	if (i == 0)
	{
		return Page.lblMsg;
	}
	if (i == 1)
	{
		return Page.lblMsg2;
	}
	if (i == 2)
	{
		return Page.lblMsg3;
	}
	return Page.lblMsg4;
}

// the controls of a page, of the active tab's panel, of a panel inside it
function FitAll(Canvas C, GUIController GC, array<GUIComponent> Cs, int Depth)
{
	local int i;
	local GUITabControl Tab;

	if (Depth > 4)
	{
		return;
	}
	for (i = 0; i < Cs.Length; i++)
	{
		if (Cs[i] == None || !Cs[i].bVisible)
		{
			continue;
		}
		if (GUILabel(Cs[i]) != None)
		{
			FitOne(C, GC, Cs[i], GUILabel(Cs[i]).Caption);
		}
		else if (GUIButton(Cs[i]) != None && EnhancedEntry(Cs[i]) == None)
		{
			FitOne(C, GC, Cs[i], GUIButton(Cs[i]).Caption);
		}
		else if (GUITabControl(Cs[i]) != None)
		{
			Tab = GUITabControl(Cs[i]);
			if (Tab.ActiveTab != None && Tab.ActiveTab.MyPanel != None)
			{
				FitAll(C, GC, Tab.ActiveTab.MyPanel.Controls, Depth + 1);
			}
		}
		else if (GUIMultiComponent(Cs[i]) != None)
		{
			FitAll(C, GC, GUIMultiComponent(Cs[i]).Controls, Depth + 1);
		}
	}
}

function FitOne(Canvas C, GUIController GC, GUIComponent X, string Caption)
{
	local int i;
	local float XL, W;
	local string Next;
	local GUIStyles S;

	if (Caption == "" || X.Style == None)
	{
		return;
	}
	for (i = 0; i < FitComp.Length; i++)
	{
		if (FitComp[i] == X)
		{
			break;
		}
	}
	if (i == FitComp.Length)
	{
		FitComp[i] = X;
		FitBase[i] = X.StyleName;
		FitCaption[i] = "";
		FitClip[i] = 0;
		FitWidth[i] = 0;
	}
	// fitted again when the caption, the resolution or the box changes (a page may place its controls after they were first drawn)
	if (FitCaption[i] == Caption && FitClip[i] == int(C.ClipX) && FitWidth[i] == int(X.ActualWidth()))
	{
		return;
	}
	FitCaption[i] = Caption;
	FitClip[i] = int(C.ClipX);
	FitWidth[i] = int(X.ActualWidth());
	if (X.StyleName != FitBase[i])
	{
		X.StyleName = FitBase[i];
		X.Style = GC.GetStyle(FitBase[i]);
	}
	// a box's text keeps a few pixels from its frame
	W = X.ActualWidth() - 6.0;
	if (W <= 10.0)
	{
		return;
	}
	while (true)
	{
		if (X.Style == None)
		{
			return;
		}
		XL = float(EnhTextWidth(C, X.Style, Caption));
		if (XL <= 0.0 || XL <= W)
		{
			return;
		}
		Next = Smaller(X.StyleName);
		if (Next == "")
		{
			if (FitLogs++ < 30)
			{
				Log("[FIT] still too wide at the smallest face: '" $ Caption $ "' " $ string(int(XL)) $ " > " $ string(int(W)) $ " (" $ X.StyleName $ ")");
			}
			return;
		}
		S = Register(GC, Next);
		if (S == None)
		{
			return;
		}
		if (FitLogs++ < 30)
		{
			Log("[FIT] '" $ Caption $ "' " $ string(int(XL)) $ " > " $ string(int(W)) $ ": " $ X.StyleName $ " -> " $ Next);
		}
		X.StyleName = Next;
		X.Style = S;
	}
}

// the next smaller face of a style (the same colours and frame), or "" when there is none
function string Smaller(string StyleName)
{
	if (StyleName ~= "SHSolidBox")
	{
		return "EnhSolidBox12";
	}
	if (StyleName ~= "EnhSolidBox12")
	{
		return "EnhSolidBox10";
	}
	// at 720p every ink face of the menus is the same smallest font: then only a plain face is narrower
	if (StyleName ~= "EnhSolidBox10")
	{
		return "EnhSolidBoxPlain";
	}
	if (StyleName ~= "EnhSolidBoxPlain")
	{
		return "EnhSolidBoxPlainSmall";
	}
	if (StyleName ~= "SH12AuptimaghBlack" || StyleName ~= "SH12Auptimagh")
	{
		return "EnhLabel10";
	}
	if (StyleName ~= "EnhLabel10")
	{
		return "EnhLabelPlain";
	}
	if (StyleName ~= "EnhLabelPlain")
	{
		return "EnhLabelPlainSmall";
	}
	if (StyleName ~= "SHOptions12BoxStyle")
	{
		return "EnhOptions10Box";
	}
	if (StyleName ~= "EnhOptions10Box")
	{
		return "EnhOptionsBoxPlain";
	}
	if (StyleName ~= "EnhTitleStyle")
	{
		return "EnhTitleSmallStyle";
	}
	if (StyleName ~= "EnhTitleSmallStyle")
	{
		return "EnhTitleTinyStyle";
	}
	return "";
}

// the mod's styles and faces are put on the menu controller when first needed (the stock ones come from its lists)
function GUIStyles Register(GUIController GC, string StyleName)
{
	local ShGUIController SC;

	SC = ShGUIController(GC);
	if (GC.GetStyle(StyleName) != None || SC == None)
	{
		return GC.GetStyle(StyleName);
	}
	if (GC.GetMenuFont("FontEnhShrekSmall") == None)
	{
		SC.RegisterFont(Class'Enhanced.FONT_Enh_ShrekSmall');
	}
	if (GC.GetMenuFont("FontEnhShrekTiny") == None)
	{
		SC.RegisterFont(Class'Enhanced.FONT_Enh_ShrekTiny');
	}
	if (GC.GetMenuFont("FontEnhPlainMid") == None)
	{
		SC.RegisterFont(Class'Enhanced.FONT_Enh_PlainMid');
	}
	if (GC.GetMenuFont("FontEnhPlainSmall") == None)
	{
		SC.RegisterFont(Class'Enhanced.FONT_Enh_PlainSmall');
	}
	if (StyleName == "EnhSolidBox12")
	{
		SC.RegisterStyle(Class'Enhanced.STY_Enh_SolidBoxMid');
	}
	else if (StyleName == "EnhSolidBox10")
	{
		SC.RegisterStyle(Class'Enhanced.STY_Enh_SolidBoxSmall');
	}
	else if (StyleName == "EnhLabel10")
	{
		SC.RegisterStyle(Class'Enhanced.STY_Enh_LabelSmall');
	}
	else if (StyleName == "EnhOptions10Box")
	{
		SC.RegisterStyle(Class'Enhanced.STY_Enh_Options10Box');
	}
	else if (StyleName == "EnhSolidBoxPlain")
	{
		SC.RegisterStyle(Class'Enhanced.STY_Enh_SolidBoxPlain');
	}
	else if (StyleName == "EnhSolidBoxPlainSmall")
	{
		SC.RegisterStyle(Class'Enhanced.STY_Enh_SolidBoxPlainSmall');
	}
	else if (StyleName == "EnhLabelPlain")
	{
		SC.RegisterStyle(Class'Enhanced.STY_Enh_LabelPlain');
	}
	else if (StyleName == "EnhLabelPlainSmall")
	{
		SC.RegisterStyle(Class'Enhanced.STY_Enh_LabelPlainSmall');
	}
	else if (StyleName == "EnhOptionsBoxPlain")
	{
		SC.RegisterStyle(Class'Enhanced.STY_Enh_OptionsBoxPlain');
	}
	else if (StyleName == "EnhTitleSmallStyle")
	{
		SC.RegisterStyle(Class'Enhanced.STY_Enh_TitleSmall');
	}
	else if (StyleName == "EnhTitleTinyStyle")
	{
		SC.RegisterStyle(Class'Enhanced.STY_Enh_TitleTiny');
	}
	return GC.GetStyle(StyleName);
}

// tests: the width of one text in every style the fitter uses, and the face each style has at this resolution
function MeasureTest(Canvas C, GUIController GC)
{
	local array<string> Names;
	local int i;
	local GUIStyles S;

	Names[0] = "SHSolidBox";
	Names[1] = "EnhSolidBox12";
	Names[2] = "EnhSolidBox10";
	Names[3] = "SH12AuptimaghBlack";
	Names[4] = "EnhLabel10";
	Names[5] = "SHOptions12BoxStyle";
	Names[6] = "EnhOptions10Box";
	Names[7] = "EnhTitleStyle";
	Names[8] = "EnhTitleSmallStyle";
	Names[9] = "EnhTitleTinyStyle";
	Names[10] = "EnhLabelPlain";
	Names[11] = "EnhLabelPlainSmall";
	Names[12] = "EnhSolidBoxPlain";
	for (i = 0; i < Names.Length; i++)
	{
		S = Register(GC, Names[i]);
		if (S == None)
		{
			Log("[MENUBOX] measure " $ Names[i] $ ": no style");
			continue;
		}
		Log("[MENUBOX] measure " $ Names[i] $ ": width " $ string(EnhTextWidth(C, S, "MMMMMMMMMM")) $ " font0 " $ string(S.Fonts[0]) $ " name0 " $ S.FontNames[0]);
		if (S.Fonts[0] != None)
		{
			FontList(S.Fonts[0]);
		}
	}
}

function FontList(GUIFont F)
{
	local int j;
	local string L;

	for (j = 0; j < F.FontArrayNames.Length; j++)
	{
		L = L $ " [" $ string(j) $ "] " $ F.FontArrayNames[j];
	}
	Log("[MENUBOX]   faces of " $ string(F.Class.Name) $ ":" $ L);
}

function DumpAll(Canvas C, array<GUIComponent> Cs, int Depth)
{
	local int i;
	local string Cap;
	local GUITabControl Tab;

	if (Depth > 4)
	{
		return;
	}
	for (i = 0; i < Cs.Length; i++)
	{
		if (Cs[i] == None)
		{
			continue;
		}
		Cap = "";
		if (GUILabel(Cs[i]) != None)
		{
			Cap = GUILabel(Cs[i]).Caption;
		}
		else if (GUIButton(Cs[i]) != None)
		{
			Cap = GUIButton(Cs[i]).Caption;
		}
		Log("[MENUBOX] " $ Left("        ", Depth * 2) $ string(Cs[i].Name) $ " (" $ string(Cs[i].Class.Name) $ ") vis=" $ string(Cs[i].bVisible)
			$ " px " $ string(int(Cs[i].ActualLeft())) $ "," $ string(int(Cs[i].ActualTop())) $ " " $ string(int(Cs[i].ActualWidth())) $ "x" $ string(int(Cs[i].ActualHeight()))
			$ " win " $ string(Cs[i].WinLeft) $ "," $ string(Cs[i].WinTop) $ " " $ string(Cs[i].WinWidth) $ "x" $ string(Cs[i].WinHeight)
			$ " style " $ Cs[i].StyleName $ " '" $ Cap $ "' len " $ string(Len(Cap)) $ " tw " $ string(EnhTextWidth(C, Cs[i].Style, Cap)));
		if (GUITabControl(Cs[i]) != None)
		{
			Tab = GUITabControl(Cs[i]);
			if (Tab.ActiveTab != None && Tab.ActiveTab.MyPanel != None)
			{
				Log("[MENUBOX] " $ Left("        ", Depth * 2) $ "panel " $ string(Tab.ActiveTab.MyPanel.Name) $ " px " $ string(int(Tab.ActiveTab.MyPanel.ActualLeft())) $ ","
					$ string(int(Tab.ActiveTab.MyPanel.ActualTop())) $ " " $ string(int(Tab.ActiveTab.MyPanel.ActualWidth())) $ "x" $ string(int(Tab.ActiveTab.MyPanel.ActualHeight())));
				DumpAll(C, Tab.ActiveTab.MyPanel.Controls, Depth + 1);
			}
		}
		else if (GUIMultiComponent(Cs[i]) != None)
		{
			DumpAll(C, GUIMultiComponent(Cs[i]).Controls, Depth + 1);
		}
	}
}

defaultproperties
{
	bVisible=true
}

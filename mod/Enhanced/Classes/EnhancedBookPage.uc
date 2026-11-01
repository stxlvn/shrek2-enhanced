class EnhancedBookPage extends ShGame.SHGUIPage;

// Common ground of the co-op pages (lobby, network search, create a game, room): each is a page of the front-end book, opened with the
// book's page turn, built from the book's own button and label styles. Helpers to make, place and navigate.

var SHMenuBook Book;
var int KeyLogs;

function string Loc(string Key)
{
	return Localize("Menu", Key, "Enhanced");
}

function GUIButton MakeButton(string Caption)
{
	local GUIButton B;

	B = GUIButton(AddComponent("GUI.GUIButton"));
	B.StyleName = "SHBTNOptionsStyle";
	B.Style = Controller.GetStyle("SHBTNOptionsStyle");
	B.Caption = Caption;
	B.bNeverFocus = true;
	B.OnClick = InternalOnClick;
	return B;
}

// The heading face and its style are put on the menu controller once (the stock ones come from its lists).
function RegisterTitleStyle()
{
	if (Controller.GetMenuFont("FontEnhShrek") == None)
	{
		ShGUIController(Controller).RegisterFont(Class'Enhanced.FONT_Enh_Shrek');
	}
	if (Controller.GetStyle("EnhTitleStyle") == None)
	{
		ShGUIController(Controller).RegisterStyle(Class'Enhanced.STY_Enh_Title');
	}
}

function GUILabel MakeLabel(bool bBig)
{
	local GUILabel L;

	L = GUILabel(AddComponent("GUI.GUILabel"));
	if (bBig)
	{
		RegisterTitleStyle();
		L.StyleName = "EnhTitleStyle";
	}
	else
	{
		L.StyleName = "SH12AuptimaghBlack";
	}
	L.Style = Controller.GetStyle(L.StyleName);
	L.TextAlign = TXTA_Center;
	L.bNeverFocus = true;
	return L;
}

function EnhancedEntry MakeEdit(bool bPassword)
{
	local EnhancedEntry E;

	E = EnhancedEntry(AddComponent("Enhanced.EnhancedEntry"));
	E.StyleName = "SHOptions12BoxStyle";
	E.Style = Controller.GetStyle("SHOptions12BoxStyle");
	E.bMaskText = bPassword;
	return E;
}

function Place(GUIComponent C, float T, optional float H)
{
	// buttons take the book's own button size and place; labels and entry boxes are narrower and centred on the text of the buttons
	if (GUIButton(C) != None && EnhancedEntry(C) == None && C.WinLeft == 0.0)
	{
		// (left at 0.2925: the icon at the button's left end must not touch the edge of the page; the width keeps the icon's proportions)
		C.WinLeft = 0.2925;
		C.WinWidth = 0.4488;
	}
	else
	{
		// the frame of an entry box is drawn about a fifth wider than its rectangle, so the rectangle is narrower than the text above it
		C.WinLeft = 0.355;
		C.WinWidth = 0.325;
	}
	C.WinTop = T;
	if (H == 0.0)
	{
		// a button is as high as the book's own buttons (0.075): the picture at its left end is stretched to the height of the button
		if (GUIButton(C) != None && EnhancedEntry(C) == None)
		{
			H = 0.075;
		}
		else
		{
			H = 0.055;
		}
	}
	C.WinHeight = H;
}

function EnhancedGame Game()
{
	return EnhancedGame(PlayerOwner().Level.Game);
}

function bool IsGuest()
{
	return PlayerOwner().Level.NetMode == NM_Client;
}

function bool IsHost()
{
	return Game() != None && Game().LobbyMode == "host";
}

// Typing goes to the entry box that has the focus. The page also gets the keys (when the box itself did not take them): the box that is active takes them from here,
// so typing does not depend on how the controller hands the keys on.
function EnhancedEntry ActiveEntry()
{
	local int i;
	local EnhancedEntry E;

	for (i = 0; i < Controls.Length; i++)
	{
		E = EnhancedEntry(Controls[i]);
		if (E != None && E.bActive)
		{
			return E;
		}
	}
	return None;
}

// The viewport interaction that types into the active entry box (see EnhancedKeyTap), put there once.
function AddKeyTap()
{
	local int i;
	local Player P;

	P = PlayerOwner().Player;
	if (P == None || P.InteractionMaster == None)
	{
		return;
	}
	for (i = 0; i < P.LocalInteractions.Length; i++)
	{
		if (EnhancedKeyTap(P.LocalInteractions[i]) != None)
		{
			return;
		}
	}
	P.InteractionMaster.AddInteraction("Enhanced.EnhancedKeyTap", P);
}

function bool PageKeyType(out byte Key, optional string Unicode)
{
	local EnhancedEntry E;

	E = ActiveEntry();
	if (KeyLogs < 12)
	{
		KeyLogs++;
		Log("[KEY] page type key=" $ string(Key) $ " unicode='" $ Unicode $ "' entry=" $ string(E));
	}
	if (E != None)
	{
		return E.EntryKeyType(Key, Unicode);
	}
	return false;
}

function bool PageKeyEvent(out byte Key, out byte State, float Delta)
{
	local EnhancedEntry E;

	E = ActiveEntry();
	if (KeyLogs < 12)
	{
		KeyLogs++;
		Log("[KEY] page event key=" $ string(Key) $ " state=" $ string(State) $ " entry=" $ string(E));
	}
	if (E != None)
	{
		return E.EntryKeyEvent(Key, State, Delta);
	}
	return false;
}

function InitComponent(GUIController MyController, GUIComponent MyOwner)
{
	Super.InitComponent(MyController, MyOwner);
	OnKeyType = PageKeyType;
	OnKeyEvent = PageKeyEvent;
	AddKeyTap();
	TabFooter.WinLeft = (0.5 - (TabFooter.WinWidth / 2.0)) - 0.01;
	// the book's buttons fade in; where no stock page has primed the style yet (a guest's first page) they would stay dim
	STY_SH_BTNOptions(Controller.GetStyle("SHBTNOptionsStyle")).InitFadeIn();
	foreach PlayerOwner().AllActors(Class'SHGame.SHMenuBook', Book)
	{
		break;
	}
}

// Opens another page with a turn of the book's page (forward or back). Where the book cannot do it (a guest in somebody else's lobby has
// no hero controller to drive it) the page is simply replaced.
function TurnTo(string Page, bool bForward)
{
	PlayerOwner().PlaySound(sfxClick);
	if (Book != None && ShrekController(PlayerOwner()) != None)
	{
		Book.pc = PlayerOwner();
		Book.NextMenuPage = Page;
		if (bForward)
		{
			Book.GotoState('TurnPageForward');
		}
		else
		{
			Book.GotoState('TurnPageBackward');
		}
		Controller.CloseMenu(true);
		return;
	}
	Controller.ReplaceMenu(Page);
}

function string Field(out string S)
{
	local int i;
	local string F;

	i = InStr(S, "|");
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

function JoinAddress(string Addr, string Pass)
{
	while (Left(Addr, 1) == " ")
	{
		Addr = Mid(Addr, 1);
	}
	if (Addr == "")
	{
		return;
	}
	if (InStr(Addr, ":") < 0)
	{
		Addr = Addr $ ":7777";
	}
	if (Game() != None)
	{
		Game().StopLanSearch();
	}
	Class'Enhanced.EnhancedLobbySettings'.default.JoinNote = Loc("JoinFailed");
	Class'Enhanced.EnhancedLobbySettings'.static.Save();
	if (Pass != "")
	{
		Addr = Addr $ "?Pass=" $ Pass;
	}
	Log("[SDBG] lobby: joining " $ Addr);
	PlayerOwner().ConsoleCommand("open " $ Addr);
}

defaultproperties
{
	WinHeight=1.0
}

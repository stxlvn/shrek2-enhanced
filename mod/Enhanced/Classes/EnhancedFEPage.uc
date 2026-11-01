class EnhancedFEPage extends ShGame.ShFEGUIPage;

// The main menu of the mod. The stock page of the book shows the six save slots, Settings, Delete and Exit all at once.
// Here the main page keeps only the big buttons: Single player (the slots, on a page of their own), Co-op mode (the lobby),
// Settings and Exit. The slot buttons stay in this object, hidden, because the stock code of the page works with them.

var GUIButton btnSingle;
var GUIButton btnCoop;

function HideSlots()
{
	ButtonSaveGame0.bVisible = false;
	ButtonSaveGame1.bVisible = false;
	ButtonSaveGame2.bVisible = false;
	ButtonSaveGame3.bVisible = false;
	ButtonSaveGame4.bVisible = false;
	ButtonSaveGame5.bVisible = false;
	lblStartGame.bVisible = false;
	lblDeleteMsg.bVisible = false;
	btnDelete.bVisible = false;
}

// Opens another page with the turn of the book's page, the way the stock Settings and Exit pages do.
function TurnTo(string Page, bool bForward)
{
	PlayerOwner().PlaySound(sfxClick);
	Mb.NextMenuPage = Page;
	if (bForward)
	{
		Mb.GotoState('TurnPageForward');
	}
	else
	{
		Mb.GotoState('TurnPageBackward');
	}
	Controller.CloseMenu(true);
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

function InitComponent(GUIController MyController, GUIComponent MyOwner)
{
	local float Top, Step;

	Super.InitComponent(MyController, MyOwner);
	HideSlots();
	btnSingle = MakeButton(Localize("Menu", "Single", "Enhanced"));
	btnCoop = MakeButton(Localize("Menu", "Coop", "Enhanced"));
	RemapComponents();

	// four buttons one below the other, on the right-hand page of the book
	Top = 0.24;
	Step = Mb.controlBut_H + 0.045;
	btnSingle.WinLeft = btnOptions.WinLeft;
	btnSingle.WinWidth = Mb.controlBut_W;
	btnSingle.WinHeight = Mb.controlBut_H;
	btnSingle.WinTop = Top;
	btnCoop.WinLeft = btnOptions.WinLeft;
	btnCoop.WinWidth = Mb.controlBut_W;
	btnCoop.WinHeight = Mb.controlBut_H;
	btnCoop.WinTop = Top + Step;
	btnOptions.WinTop = Top + Step * 2.0;
	btnQuit.WinTop = Top + Step * 3.0;
	btnSingle.Hint = Localize("Menu", "SavesTitle", "Enhanced");
	btnCoop.Hint = Localize("Menu", "LanHint", "Enhanced");
}

function bool InternalOnClick(GUIComponent Sender)
{
	if (Sender == btnSingle)
	{
		TurnTo("Enhanced.EnhancedSavesPage", true);
		return true;
	}
	if (Sender == btnCoop)
	{
		TurnTo("Enhanced.EnhancedLobbyPage", true);
		return true;
	}
	if (Sender == btnOptions)
	{
		TurnTo("Enhanced.EnhancedSettingsPage", true);
		return true;
	}
	if (Sender == btnQuit)
	{
		return Super.InternalOnClick(Sender);
	}
	return true;
}

// Tests only: presses a button by name.
function bool TestClick(string What)
{
	if (What ~= "single")
	{
		return InternalOnClick(btnSingle);
	}
	if (What ~= "coop")
	{
		return InternalOnClick(btnCoop);
	}
	if (What ~= "options")
	{
		return InternalOnClick(btnOptions);
	}
	return false;
}

defaultproperties
{
}

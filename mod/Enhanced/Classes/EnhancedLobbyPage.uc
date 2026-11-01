class EnhancedLobbyPage extends EnhancedBookPage;

// The co-op page of the book: find a game on the local network (that includes Radmin VPN and the like, which are local networks too),
// type the address of a host over the Internet (with the password, if the game has one), or create a game.

var GUIButton btnFind, btnConnect, btnHost, btnBack;
var GUILabel lblTitle, lblAddr, lblPass, lblNote, lblNick;
var EnhancedEntry edAddress, edPass, edNick;

function InitComponent(GUIController MyController, GUIComponent MyOwner)
{
	Super.InitComponent(MyController, MyOwner);
	lblTitle = MakeLabel(true);
	lblTitle.Caption = Loc("CoopTitle");
	lblNote = MakeLabel(false);
	lblNick = MakeLabel(false);
	lblNick.Caption = Loc("NickHint");
	edNick = MakeEdit(false);
	edNick.SetValue(Class'Enhanced.EnhancedLobbySettings'.default.PlayerNick);
	btnFind = MakeButton(Loc("Find"));
	lblAddr = MakeLabel(false);
	lblAddr.Caption = Loc("AddrHint");
	edAddress = MakeEdit(false);
	lblPass = MakeLabel(false);
	lblPass.Caption = Loc("PassHint");
	edPass = MakeEdit(true);
	btnConnect = MakeButton(Loc("Connect"));
	btnHost = MakeButton(Loc("Host"));
	btnBack = MakeButton(Loc("Back"));
	RemapComponents();
	Place(lblTitle, 0.195, 0.04);
	Place(lblNote, 0.235, 0.03);
	Place(lblNick, 0.238, 0.03);
	Place(edNick, 0.277, 0.04);
	Place(btnFind, 0.327);
	Place(lblAddr, 0.408, 0.03);
	Place(edAddress, 0.447, 0.04);
	Place(lblPass, 0.495, 0.03);
	Place(edPass, 0.534, 0.04);
	Place(btnConnect, 0.575);
	Place(btnHost, 0.65);
	Place(btnBack, 0.725);
	// why the last attempt to join did not work (the host refused, or was not there)
	lblNote.Caption = Class'Enhanced.EnhancedLobbySettings'.default.JoinNote;
	Class'Enhanced.EnhancedLobbySettings'.default.JoinNote = "";
	Class'Enhanced.EnhancedLobbySettings'.static.Save();
}

// The nickname is what tells the players apart in the lobby and in the saves; nothing starts without one.
function bool NickOk()
{
	local string N;

	N = Class'Enhanced.EnhancedLobbySettings'.static.CleanNick(edNick.TextStr);
	if (N == "")
	{
		lblNote.Caption = Loc("NickNeeded");
		return false;
	}
	Class'Enhanced.EnhancedLobbySettings'.default.PlayerNick = N;
	Class'Enhanced.EnhancedLobbySettings'.static.Save();
	return true;
}

function bool InternalOnClick(GUIComponent Sender)
{
	if ((Sender == btnFind || Sender == btnConnect || Sender == btnHost) && !NickOk())
	{
		return true;
	}
	if (Sender == btnFind)
	{
		TurnTo("Enhanced.EnhancedLanPage", true);
	}
	else if (Sender == btnConnect)
	{
		PlayerOwner().PlaySound(sfxClick);
		JoinAddress(edAddress.TextStr, edPass.TextStr);
	}
	else if (Sender == btnHost)
	{
		TurnTo("Enhanced.EnhancedHostPage", true);
	}
	else if (Sender == btnBack)
	{
		TurnTo("Enhanced.EnhancedFEPage", false);
	}
	return true;
}

// Tests only: presses a button by name, or types into a box.
function bool TestClick(string What)
{
	if (What ~= "focus")
	{
		return edNick.EntryClick(None);
	}
	if (What ~= "dump")
	{
		Log("[KEY] nick text now '" $ edNick.TextStr $ "' active=" $ string(edNick.bActive));
		return true;
	}
	if (What ~= "find")
	{
		return InternalOnClick(btnFind);
	}
	if (What ~= "host")
	{
		return InternalOnClick(btnHost);
	}
	if (What ~= "back")
	{
		return InternalOnClick(btnBack);
	}
	if (Left(What, 5) ~= "nick=")
	{
		edNick.SetValue(Mid(What, 5));
		return true;
	}
	if (What ~= "connect")
	{
		return InternalOnClick(btnConnect);
	}
	if (Left(What, 5) ~= "text=")
	{
		edAddress.SetValue(Mid(What, 5));
		return true;
	}
	if (Left(What, 5) ~= "pass=")
	{
		edPass.SetValue(Mid(What, 5));
		return true;
	}
	return false;
}

defaultproperties
{
}

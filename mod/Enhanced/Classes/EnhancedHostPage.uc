class EnhancedHostPage extends EnhancedBookPage;

// Create a game: the name the guests will see, an optional password, friendly fire (UPnP is always on, see EnhancedLobbySettings.bUpnp). "Create" saves the choices and loads the
// front-end level again as a listen server; the room page opens in it.

var GUILabel lblTitle, lblName, lblPass;
var EnhancedEntry edName, edPass;
var GUIButton btnFF, btnCreate, btnBack, btnPlaces;
var int Places;
var bool bFF;

function InitComponent(GUIController MyController, GUIComponent MyOwner)
{
	local string N;

	Super.InitComponent(MyController, MyOwner);
	lblTitle = MakeLabel(true);
	lblTitle.Caption = Loc("Host");
	lblName = MakeLabel(false);
	lblName.Caption = Loc("NameHint");
	edName = MakeEdit(false);
	lblPass = MakeLabel(false);
	lblPass.Caption = Loc("SetPassHint");
	edPass = MakeEdit(true);
	btnFF = MakeButton("");
	btnPlaces = MakeButton("");
	btnCreate = MakeButton(Loc("Create"));
	btnBack = MakeButton(Loc("Back"));
	RemapComponents();
	Place(lblTitle, 0.195, 0.04);
	Place(lblName, 0.243, 0.03);
	Place(edName, 0.282, 0.04);
	Place(lblPass, 0.335, 0.03);
	Place(edPass, 0.374, 0.04);
	Place(btnPlaces, 0.425);
	Place(btnFF, 0.50);
	Place(btnCreate, 0.575);
	Place(btnBack, 0.65);
	N = Class'Enhanced.EnhancedLobbySettings'.default.LobbyName;
	if (N == "")
	{
		N = PlayerOwner().PlayerReplicationInfo.PlayerName;
		if (N == "")
		{
			N = "Shrek 2";
		}
	}
	edName.SetValue(N);
	bFF = Class'Enhanced.EnhancedLobbySettings'.default.bFriendlyFire;
	Places = Clamp(Class'Enhanced.EnhancedLobbySettings'.default.MaxPlayers, 2, 4);
	Refresh();
}

function Refresh()
{
	btnPlaces.Caption = Loc("Places") $ " " $ string(Places);
	if (bFF)
	{
		btnFF.Caption = Loc("FFOn");
	}
	else
	{
		btnFF.Caption = Loc("FFOff");
	}
}

function bool InternalOnClick(GUIComponent Sender)
{
	if (Sender == btnFF)
	{
		PlayerOwner().PlaySound(sfxClick);
		bFF = !bFF;
		Refresh();
	}
	else if (Sender == btnPlaces)
	{
		PlayerOwner().PlaySound(sfxClick);
		Places++;
		if (Places > 4)
		{
			Places = 2;
		}
		Refresh();
	}
	else if (Sender == btnCreate && Game() != None)
	{
		PlayerOwner().PlaySound(sfxClick);
		Class'Enhanced.EnhancedLobbySettings'.default.LobbyName = edName.TextStr;
		Class'Enhanced.EnhancedLobbySettings'.default.Password = edPass.TextStr;
		Class'Enhanced.EnhancedLobbySettings'.default.bFriendlyFire = bFF;
		Class'Enhanced.EnhancedLobbySettings'.default.MaxPlayers = Places;
		Game().OpenLobby(PlayerOwner(), Class'Enhanced.EnhancedLobbySettings'.default.bUpnp);
	}
	else if (Sender == btnBack)
	{
		TurnTo("Enhanced.EnhancedLobbyPage", false);
	}
	return true;
}

// Tests only.
function bool TestClick(string What)
{
	if (What ~= "places")
	{
		return InternalOnClick(btnPlaces);
	}
	if (What ~= "ff")
	{
		return InternalOnClick(btnFF);
	}
	if (What ~= "create")
	{
		return InternalOnClick(btnCreate);
	}
	if (What ~= "back")
	{
		return InternalOnClick(btnBack);
	}
	if (Left(What, 5) ~= "name=")
	{
		edName.SetValue(Mid(What, 5));
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

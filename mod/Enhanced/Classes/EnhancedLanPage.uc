class EnhancedLanPage extends EnhancedBookPage;

// The games found on the network: the list fills by itself (the question goes to the local network and to Radmin VPN and the
// like every two seconds), a click joins. A game with a lock needs its password typed in the box below first.

var GUILabel lblTitle, lblNote, lblPass;
var GUIButton btnRow[5];
var GUIButton btnBack;
var EnhancedEntry edPass;
var string RowAddr[5];

function InitComponent(GUIController MyController, GUIComponent MyOwner)
{
	local int i;

	Super.InitComponent(MyController, MyOwner);
	lblTitle = MakeLabel(true);
	lblTitle.Caption = Loc("LanTitle");
	lblNote = MakeLabel(false);
	for (i = 0; i < 5; i++)
	{
		btnRow[i] = MakeButton("");
	}
	lblPass = MakeLabel(false);
	lblPass.Caption = Loc("PassHint");
	edPass = MakeEdit(true);
	btnBack = MakeButton(Loc("Back"));
	RemapComponents();
	Place(lblTitle, 0.20, 0.045);
	Place(lblNote, 0.255, 0.03);
	for (i = 0; i < 5; i++)
	{
		Place(btnRow[i], 0.30 + 0.066 * i, 0.058);
	}
	Place(lblPass, 0.645, 0.03);
	Place(edPass, 0.678, 0.04);
	Place(btnBack, 0.72);
	if (Game() != None)
	{
		Game().StartLanSearch();
	}
	Refresh();
	SetTimer(0.5, true);
}

event Timer()
{
	Refresh();
}

function Refresh()
{
	local EnhancedLanBeacon B;
	local int i;
	local string Rest, Name, Players, Max, Lock, Port;

	if (Game() != None)
	{
		B = Game().Beacon;
	}
	lblNote.Caption = Loc("Searching");
	for (i = 0; i < 5; i++)
	{
		btnRow[i].Caption = "";
		btnRow[i].bVisible = false;
		RowAddr[i] = "";
		if (B != None && i < B.Addrs.Length)
		{
			Rest = B.Infos[i];
			Port = Field(Rest);
			Name = Field(Rest);
			Field(Rest);
			Players = Field(Rest);
			Max = Field(Rest);
			Field(Rest);
			Lock = Field(Rest);
			RowAddr[i] = B.Addrs[i] $ ":" $ Port;
			btnRow[i].Caption = Name $ "  " $ Players $ "/" $ Max;
			if (Lock == "1")
			{
				btnRow[i].Caption = btnRow[i].Caption $ "  [" $ Loc("Locked") $ "]";
			}
			btnRow[i].bVisible = true;
		}
	}
	if (B != None)
	{
		B.Prune();
		if (B.Addrs.Length > 0)
		{
			lblNote.Caption = "";
		}
	}
}

function bool InternalOnClick(GUIComponent Sender)
{
	local int i;

	for (i = 0; i < 5; i++)
	{
		if (Sender == btnRow[i] && RowAddr[i] != "")
		{
			PlayerOwner().PlaySound(sfxClick);
			JoinAddress(RowAddr[i], edPass.TextStr);
			return true;
		}
	}
	if (Sender == btnBack)
	{
		if (Game() != None)
		{
			Game().StopLanSearch();
		}
		TurnTo("Enhanced.EnhancedLobbyPage", false);
	}
	return true;
}

// Tests only.
function bool TestClick(string What)
{
	if (What ~= "row0")
	{
		return InternalOnClick(btnRow[0]);
	}
	if (What ~= "back")
	{
		return InternalOnClick(btnBack);
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

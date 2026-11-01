class EnhancedRoomPage extends EnhancedBookPage;

// The room of a lobby: who is in (the replicated player infos exist on the host and on every guest), the host's address and UPnP
// state; a guest presses Ready, the host starts the game when every guest is ready (or alone).

var GUILabel lblTitle, lblNote, lblLine[8];
var GUIButton btnMain, btnClose, btnSave;
var bool bReady;
var int SaveIndex;   // host: 0 = a new game, i > 0 = the i-th co-op save of the registry

function InitComponent(GUIController MyController, GUIComponent MyOwner)
{
	local int i;

	Super.InitComponent(MyController, MyOwner);
	// a guest sees no book of his own (the level of the host is loaded without its animation): a sheet of the book's parchment behind
	if (IsGuest())
	{
		Background = Material(DynamicLoadObject("Storybook_TX.stacked_pages", Class'Engine.Material'));
		BackgroundColor.R = 255;
		BackgroundColor.G = 255;
		BackgroundColor.B = 255;
		BackgroundColor.A = 255;
	}
	lblTitle = MakeLabel(true);
	lblNote = MakeLabel(false);
	for (i = 0; i < 8; i++)
	{
		lblLine[i] = MakeLabel(false);
	}
	btnMain = MakeButton("");
	btnClose = MakeButton("");
	btnSave = MakeButton("");
	RemapComponents();
	Place(lblTitle, 0.20, 0.045);
	Place(lblNote, 0.255, 0.03);
	// the players (as many lines as the lobby holds), then the address and UPnP lines, the save line, and the buttons
	for (i = 0; i < 8; i++)
	{
		Place(lblLine[i], 0.30 + 0.0345 * i, 0.03);
	}
	Place(btnSave, 0.56);
	Place(btnMain, 0.64);
	Place(btnClose, 0.72);
	if (IsHost())
	{
		btnClose.Caption = Loc("StopHost");
	}
	else
	{
		btnClose.Caption = Loc("Leave");
		Class'Enhanced.EnhancedLobbySettings'.default.JoinNote = "";
		Class'Enhanced.EnhancedLobbySettings'.static.Save();
	}
	Refresh();
	SetTimer(0.5, true);
}

event Timer()
{
	Refresh();
}

function int PlayerNames(out string Names[4])
{
	local GameReplicationInfo GRI;
	local int i, j, n, Ids[4], T;
	local string S;

	GRI = PlayerOwner().GameReplicationInfo;
	if (GRI == None)
	{
		return 0;
	}
	for (i = 0; i < GRI.PRIArray.Length; i++)
	{
		if (GRI.PRIArray[i] != None && !GRI.PRIArray[i].bBot && n < 4)
		{
			Names[n] = GRI.PRIArray[i].PlayerName;
			Ids[n] = GRI.PRIArray[i].PlayerID;
			n++;
		}
	}
	// the host joined first: the lowest id comes first, on every machine alike
	for (i = 0; i < n; i++)
	{
		for (j = i + 1; j < n; j++)
		{
			if (Ids[j] < Ids[i])
			{
				T = Ids[i];
				Ids[i] = Ids[j];
				Ids[j] = T;
				S = Names[i];
				Names[i] = Names[j];
				Names[j] = S;
			}
		}
	}
	return n;
}

// What the save button shows: a new game, or title, level, time and players of a co-op save.
function string CoopSlot(int i)
{
	if (i <= 0 || i > Class'Enhanced.EnhancedLobbySettings'.default.CoopSaves.Length)
	{
		return "";
	}
	return Class'Enhanced.EnhancedLobbySettings'.default.CoopSaves[i - 1];
}

function string SaveCaption()
{
	local EnhancedSaveData R;
	local string Slot;

	Slot = CoopSlot(SaveIndex);
	if (Slot == "")
	{
		return Loc("NewGame");
	}
	R = new(None, Slot) Class'Enhanced.EnhancedSaveData';
	return R.Title $ "  " $ R.Map $ "  " $ Left(R.Stamp, 16) $ "  " $ R.Players;
}

function Refresh()
{
	local EnhancedGame G;
	local string Names[4], Title;
	local int Count, i, Places;

	Count = PlayerNames(Names);
	G = Game();
	Title = Class'Enhanced.EnhancedLobbySettings'.default.LobbyName;
	if (IsGuest() && PlayerOwner().GameReplicationInfo != None)
	{
		Title = PlayerOwner().GameReplicationInfo.ServerName;
	}
	if (Title == "")
	{
		Title = Loc("RoomTitle");
	}
	lblTitle.Caption = Title;
	for (i = 0; i < 8; i++)
	{
		lblLine[i].Caption = "";
	}
	Places = Class'Enhanced.EnhancedLobbySettings'.default.MaxPlayers;
	if (IsGuest() && PlayerOwner().GameReplicationInfo != None)
	{
		Places = PlayerOwner().GameReplicationInfo.GoalScore;
	}
	Places = Clamp(Places, 2, 4);
	for (i = 0; i < Places; i++)
	{
		if (i < Count)
		{
			lblLine[i].Caption = string(i + 1) $ ". " $ Names[i];
			if (i == 0)
			{
				lblLine[i].Caption = lblLine[i].Caption $ "  (" $ Loc("HostMark") $ ")";
			}
		}
		else
		{
			lblLine[i].Caption = string(i + 1) $ ". " $ Loc("Empty");
		}
	}
	if (IsHost() && G != None)
	{
		lblNote.Caption = Loc("Hosting");
		if (G.Beacon != None)
		{
			lblLine[5].Caption = Loc("YourAddress") $ " " $ G.Beacon.LocalAddress() $ ":" $ string(Class'Enhanced.EnhancedGame'.default.GamePortDefault);
		}
		if (G.Upnp != None)
		{
			lblLine[6].Caption = G.Upnp.Status;
		}
		btnSave.bVisible = true;
		btnSave.Caption = Loc("ChangeSave");
		lblLine[7].Caption = Loc("SaveLabel") $ " " $ SaveCaption();
		btnMain.Caption = Loc("StartGame");
		btnMain.bVisible = G.CanStart();
		if (!btnMain.bVisible)
		{
			lblLine[4].Caption = Loc("WaitReady");
		}
	}
	else
	{
		btnSave.bVisible = false;
		lblNote.Caption = Loc("Joined");
		if (bReady)
		{
			btnMain.Caption = Loc("NotReady");
		}
		else
		{
			btnMain.Caption = Loc("Ready");
		}
	}
}

function bool InternalOnClick(GUIComponent Sender)
{
	if (Sender == btnMain)
	{
		PlayerOwner().PlaySound(sfxClick);
		if (IsHost())
		{
			if (!Game().CanStart())
			{
				return true;
			}
			Game().LaunchCoop(CoopSlot(SaveIndex));   // before the page is closed: a closed page has no controller to find the game by
			Controller.CloseAll(false);
			return true;
		}
		bReady = !bReady;
		if (EnhancedPlayerController(PlayerOwner()) != None)
		{
			EnhancedPlayerController(PlayerOwner()).bLobbyReady = bReady;
			EnhancedPlayerController(PlayerOwner()).ServerSetReady(bReady);
		}
		Refresh();
	}
	else if (Sender == btnSave && IsHost())
	{
		PlayerOwner().PlaySound(sfxClick);
		SaveIndex++;
		if (SaveIndex > Class'Enhanced.EnhancedLobbySettings'.default.CoopSaves.Length)
		{
			SaveIndex = 0;
		}
		Refresh();
	}
	else if (Sender == btnClose)
	{
		PlayerOwner().PlaySound(sfxClick);
		if (IsHost())
		{
			Game().CloseLobby(PlayerOwner());
		}
		else
		{
			PlayerOwner().ConsoleCommand("open " $ Class'Enhanced.EnhancedGame'.static.PlainMenuURL());
		}
	}
	return true;
}

// Tests only.
function bool TestClick(string What)
{
	if (What ~= "main")
	{
		return InternalOnClick(btnMain);
	}
	if (What ~= "save")
	{
		return InternalOnClick(btnSave);
	}
	if (What ~= "close")
	{
		return InternalOnClick(btnClose);
	}
	return false;
}

defaultproperties
{
}

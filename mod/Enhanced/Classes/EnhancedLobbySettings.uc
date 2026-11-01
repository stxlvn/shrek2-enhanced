class EnhancedLobbySettings extends Object
	config(User);

// What the host chose for the lobby, kept in User.ini: the name guests see, the password (empty = open), friendly fire, whether the
// router port is opened with UPnP. The lobby is a level of its own (the front-end level loaded again as a listen server), so these
// must survive the reload; the page writes them, the game reads them. The password is wiped when the lobby is closed or the game starts.
// JoinNote: why the last attempt to join failed (a guest comes back to the menu when the host refuses), shown once in the lobby.

var config string LobbyName;
var config string Password;
var config bool bFriendlyFire;
var config int MaxPlayers;           // places in the lobby, 2 to 4
var config bool bUpnp;
var config string JoinNote;
var config string PlayerNick;        // the player's name in lobbies: who is who
var config array<string> CoopSaves;  // the slots of the co-op saves (newest first), see EnhancedGame.RegisterCoopSave

// A name that is safe inside a URL option.
static function string CleanNick(string S)
{
	local string R, C;
	local int i;

	for (i = 0; i < Len(S); i++)
	{
		C = Mid(S, i, 1);
		if (C == " ")
		{
			C = "_";
		}
		if (C != "?" && C != "=" && C != "#" && C != "|" && C != "," && C != "&")
		{
			R = R $ C;
		}
	}
	return Left(R, 20);
}

static function Save()
{
	StaticSaveConfig();
}

defaultproperties
{
	MaxPlayers=2
	bUpnp=True
}

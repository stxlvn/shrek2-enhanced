//=============================================================================
// InternetLink: the base of the network sockets. The game ships IpDrv.dll with the native code for it and no script
// package, so Shrek 2 Enhanced carries these declarations itself (Enhanced uses UdpLink for the LAN search and
// UPnP, TcpLink for talking to the router). The natives are bound by name.
//=============================================================================
class InternetLink extends InternetInfo
	native
	transient;

// An IP address.
struct IpAddr
{
	var int Addr;
	var int Port;
};

// How received data is delivered. Cannot be set in default properties.
var enum ELinkMode
{
	MODE_Text,
	MODE_Line,
	MODE_Binary
} LinkMode;

// Internal
var	const int Socket;
var const int Port;
var	const int RemoteSocket;
var private native const int PrivateResolveInfo;
var const int DataPending;

// If the receive mode is RMODE_Manual the received events are not called; the script must read the data itself.
var enum EReceiveMode
{
	RMODE_Manual,
	RMODE_Event
} ReceiveMode;

// Natives.
native function bool IsDataPending();
native function bool ParseURL
(
	coerce string URL,
	out string Addr,
	out int Port,
	out string LevelName,
	out string EntryName
);
native function Resolve( coerce string Domain );
native function int GetLastError();
native function string IpAddrToString( IpAddr Arg );
native function bool StringToIpAddr( string Str, out IpAddr Addr );
native function string GameSpyValidate( string ValidationString );
native function string GameSpyGameName();
native function GetLocalIP(out IpAddr Arg );

// Events.
event Resolved( IpAddr Addr );
event ResolveFailed();

defaultproperties
{
}

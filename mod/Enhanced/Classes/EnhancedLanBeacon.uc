class EnhancedLanBeacon extends IpDrv.UdpLink
	config(User);

// Finding games on the local network. The stock game has no server browser (its IpDrv package is not even shipped),
// so this is a small one of our own: a hosting game answers a broadcast question with one line about itself, a
// searching game sends the question to the whole network every two seconds and keeps what answers.
//
//   question:  ENH2?
//   answer:    ENH2!<game port>|<host name>|<map>|<players>|<max players>|<mod build>
const QueryPort = 7790;
const Question = "ENH2?";
const Answer = "ENH2!";

// Broadcast addresses to ask besides the built-in ones, one per line in User.ini ([Enhanced.EnhancedLanBeacon] ExtraTargets=10.147.17.255).
// The installer fills them from the network adapters of the PC (ZeroTier and every other virtual network included).
var config array<string> ExtraTargets;
var bool bHosting;
var bool bSearching;
var string HostLine;          // what a hosting game answers
var float SearchTimer;
var float LastHeard;
var array<string> Addrs;      // found games: "ip", the game port is in Info
var array<string> Infos;      // "port|name|map|players|max|build"
var array<float> Seen;        // Level.TimeSeconds of the last answer

function bool StartHost(string Line)
{
	local int P;

	bHosting = true;
	HostLine = Line;
	LinkMode = MODE_Text;
	ReceiveMode = RMODE_Event;
	P = BindPort(QueryPort, false);
	Log("[SDBG] lan: host beacon bound to port " $ string(P));
	return P == QueryPort;
}

function bool StartSearch()
{
	local int P;

	bSearching = true;
	LinkMode = MODE_Text;
	ReceiveMode = RMODE_Event;
	P = BindPort(0, true);
	Log("[SDBG] lan: search socket bound to port " $ string(P));
	SearchTimer = 0.0;
	return P != 0;
}

function string LocalAddress()
{
	local IpAddr Me;

	GetLocalIP(Me);
	return AddrOnly(Me);
}

function SetHostLine(string Line)
{
	HostLine = Line;
}

// The question goes to the limited broadcast address and to the broadcast address of this computer's own network
// (the first reaches only the default adapter; Radmin and other virtual networks have their own).
function Ask()
{
	local IpAddr A, Me;
	local string S;
	local int i, Dot, Last;

	A.Port = QueryPort;
	A.Addr = BroadcastAddr;
	SendText(A, Question);
	GetLocalIP(Me);
	S = IpAddrToString(Me);
	i = InStr(S, ":");
	if (i >= 0)
	{
		S = Left(S, i);
	}
	Dot = -1;
	Last = -1;
	for (i = 0; i < Len(S); i++)
	{
		if (Mid(S, i, 1) == ".")
		{
			Last = i;
		}
	}
	if (Last > 0)
	{
		S = Left(S, Last + 1) $ "255";
		if (StringToIpAddr(S, A))
		{
			A.Port = QueryPort;
			SendText(A, Question);
		}
	}
	// Virtual local networks have an adapter of their own, and the broadcast of the default adapter does not reach them. The ranges
	// that are fixed: Radmin VPN 26.x, Hamachi 25.x, Tunngle 7.x; the question goes to all of them (a packet for a network this PC is
	// not in simply goes nowhere), and to every address of ExtraTargets.
	Tell("26.255.255.255");
	Tell("25.255.255.255");
	Tell("7.255.255.255");
	for (i = 0; i < ExtraTargets.Length; i++)
	{
		Tell(ExtraTargets[i]);
	}
}

function Tell(string Ip)
{
	local IpAddr A;

	if (StringToIpAddr(Ip, A))
	{
		A.Port = QueryPort;
		SendText(A, Question);
	}
}

event Tick(float DeltaTime)
{
	Super.Tick(DeltaTime);
	if (bSearching)
	{
		SearchTimer -= DeltaTime;
		if (SearchTimer <= 0.0)
		{
			SearchTimer = 2.0;
			Ask();
		}
	}
}

function string AddrOnly(IpAddr A)
{
	local string S;
	local int i;

	S = IpAddrToString(A);
	i = InStr(S, ":");
	if (i >= 0)
	{
		S = Left(S, i);
	}
	return S;
}

event ReceivedText(IpAddr Addr, string Text)
{
	local string IP, Rest;
	local int i;

	if (bHosting && Left(Text, Len(Question)) == Question)
	{
		SendText(Addr, Answer $ HostLine);
		return;
	}
	if (bSearching && Left(Text, Len(Answer)) == Answer)
	{
		IP = AddrOnly(Addr);
		Rest = Mid(Text, Len(Answer));
		for (i = 0; i < Addrs.Length; i++)
		{
			if (Addrs[i] == IP)
			{
				Infos[i] = Rest;
				Seen[i] = Level.TimeSeconds;
				return;
			}
		}
		Addrs[Addrs.Length] = IP;
		Infos[Infos.Length] = Rest;
		Seen[Seen.Length] = Level.TimeSeconds;
		Log("[SDBG] lan: found a game at " $ IP $ " : " $ Rest);
	}
}

// Games that have not answered for ten seconds are gone.
function Prune()
{
	local int i;

	for (i = Addrs.Length - 1; i >= 0; i--)
	{
		if (Level.TimeSeconds - Seen[i] > 10.0)
		{
			Addrs.Remove(i, 1);
			Infos.Remove(i, 1);
			Seen.Remove(i, 1);
		}
	}
}

defaultproperties
{
}

class EnhancedUpnpSsdp extends IpDrv.UdpLink;

// The first step of UPnP: ask the network "who is an Internet gateway?" (SSDP, UDP multicast to 239.255.255.250:1900).
// The router answers with the address of its description file.

var EnhancedUpnp Manager;
var string Target;     // where the search goes; the multicast group unless a test points it elsewhere

function bool Start()
{
	LinkMode = MODE_Text;
	ReceiveMode = RMODE_Event;
	return BindPort(0, true) != 0;
}

// Where this computer is on the network, for the mapping's target.
function string LocalAddress()
{
	local IpAddr Me;
	local string S;
	local int i;

	GetLocalIP(Me);
	S = IpAddrToString(Me);
	i = InStr(S, ":");
	if (i >= 0)
	{
		S = Left(S, i);
	}
	return S;
}

function Search()
{
	local IpAddr A;
	local string CRLF, Msg, Host, Mine, Base;
	local int P, Port, i;

	CRLF = Chr(13) $ Chr(10);
	Msg = "M-SEARCH * HTTP/1.1" $ CRLF
		$ "HOST: 239.255.255.250:1900" $ CRLF
		$ "MAN: \"ssdp:discover\"" $ CRLF
		$ "MX: 2" $ CRLF
		$ "ST: urn:schemas-upnp-org:device:InternetGatewayDevice:1" $ CRLF $ CRLF;
	if (Target == "")
	{
		Target = "239.255.255.250";
	}
	P = InStr(Target, ":");
	Port = 1900;
	Host = Target;
	if (P >= 0)
	{
		Host = Left(Target, P);
		Port = int(Mid(Target, P + 1));
	}
	if (StringToIpAddr(Host, A))
	{
		A.Port = Port;
		SendText(A, Msg);
	}
	if (Target == "239.255.255.250")
	{
		// Routers answer a search sent straight to them as well, and this PC has several adapters (the multicast may leave
		// by the wrong one): the router is usually the first or the last address of this network.
		Mine = LocalAddress();
		P = -1;
		for (i = 0; i < Len(Mine); i++)
		{
			if (Mid(Mine, i, 1) == ".")
			{
				P = i;
			}
		}
		if (P > 0)
		{
			Base = Left(Mine, P + 1);
			if (StringToIpAddr(Base $ "1", A))
			{
				A.Port = 1900;
				SendText(A, Msg);
			}
			if (StringToIpAddr(Base $ "254", A))
			{
				A.Port = 1900;
				SendText(A, Msg);
			}
		}
	}
}

event ReceivedText(IpAddr Addr, string Text)
{
	local string U;
	local int P, Q;

	P = InStr(Caps(Text), "LOCATION:");
	if (P < 0 || Manager == None)
	{
		return;
	}
	U = Mid(Text, P + 9);
	Q = InStr(U, Chr(13));
	if (Q < 0)
	{
		Q = InStr(U, Chr(10));
	}
	if (Q >= 0)
	{
		U = Left(U, Q);
	}
	while (Left(U, 1) == " ")
	{
		U = Mid(U, 1);
	}
	Manager.Located(U);
}

defaultproperties
{
}

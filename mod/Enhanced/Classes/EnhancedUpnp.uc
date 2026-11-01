class EnhancedUpnp extends Actor;

// UPnP: asks the router to forward the game's UDP port to this computer, so a friend over the Internet can join
// without anybody touching the router's settings. Steps: find the router (SSDP) > read its description > find the
// WAN connection service > ask for the external address > add the port mapping. The result is in Status / bMapped.
//
// Status is the text the lobby shows; Stage is the step. Everything runs in the background of the menu.

var int Stage;               // 0 idle, 1 searching, 2 reading description, 3 external address, 4 mapping, 5 done, 6 failed
var string Status;
var bool bMapped;
var string ExternalIP;
var string LocalIP;
var int GamePort;
var float StageAge;
var float SearchTimer;
var int SearchCount;
var EnhancedUpnpSsdp Ssdp;

var string RouterIp;
var int RouterPort;
var string BaseHost;         // address the control URL belongs to
var int BasePort;
var string ControlPath;
var string ServiceType;
var int Lease;
var bool bLeaseRetried;

function string CRLF()
{
	return Chr(13) $ Chr(10);
}

function string Between(string S, string Open, string Close)
{
	local int P, Q;

	P = InStr(S, Open);
	if (P < 0)
	{
		return "";
	}
	S = Mid(S, P + Len(Open));
	Q = InStr(S, Close);
	if (Q < 0)
	{
		return "";
	}
	return Left(S, Q);
}

function Fail(string Why)
{
	Stage = 6;
	bMapped = false;
	Status = Why;
	Log("[SDBG] upnp: failed - " $ Why);
}

function Start(int Port, optional string SearchTarget)
{
	GamePort = Port;
	Lease = 7200;
	bMapped = false;
	ExternalIP = "";
	Ssdp = Spawn(Class'Enhanced.EnhancedUpnpSsdp');
	Ssdp.Manager = self;
	Ssdp.Target = SearchTarget;
	if (!Ssdp.Start())
	{
		Fail("UPnP: cannot open a network socket");
		return;
	}
	LocalIP = Ssdp.LocalAddress();
	Stage = 1;
	StageAge = 0.0;
	SearchCount = 0;
	SearchTimer = 0.0;
	Status = "UPnP: looking for the router...";
	Log("[SDBG] upnp: start, port " $ string(Port) $ ", this computer " $ LocalIP);
}

event Tick(float DeltaTime)
{
	StageAge += DeltaTime;
	if (Stage == 1)
	{
		SearchTimer -= DeltaTime;
		if (SearchTimer <= 0.0 && SearchCount < 5)
		{
			SearchTimer = 1.5;
			SearchCount++;
			Ssdp.Search();
		}
		if (StageAge > 10.0)
		{
			Fail("UPnP: no router answered (UPnP may be off in the router)");
		}
	}
	else if (Stage >= 2 && Stage <= 4 && StageAge > 15.0)
	{
		Fail("UPnP: the router did not answer in time");
	}
}

// The router answered the search with the address of its description, for example http://192.168.1.1:5000/rootDesc.xml
function Located(string URL)
{
	local string Rest, HostPort, Path;
	local int P;

	if (Stage != 1)
	{
		return;
	}
	Log("[SDBG] upnp: router description at " $ URL);
	if (Left(Caps(URL), 7) != "HTTP://")
	{
		return;
	}
	Rest = Mid(URL, 7);
	P = InStr(Rest, "/");
	if (P < 0)
	{
		HostPort = Rest;
		Path = "/";
	}
	else
	{
		HostPort = Left(Rest, P);
		Path = Mid(Rest, P);
	}
	P = InStr(HostPort, ":");
	if (P >= 0)
	{
		RouterIp = Left(HostPort, P);
		RouterPort = int(Mid(HostPort, P + 1));
	}
	else
	{
		RouterIp = HostPort;
		RouterPort = 80;
	}
	BaseHost = RouterIp;
	BasePort = RouterPort;
	Stage = 2;
	StageAge = 0.0;
	Status = "UPnP: reading the router description...";
	Get(RouterIp, RouterPort, "GET " $ Path $ " HTTP/1.1" $ CRLF() $ "Host: " $ HostPort $ CRLF() $ "Connection: close" $ CRLF() $ CRLF(), "desc");
}

function Get(string HostIp, int HostPort, string Req, string Tag)
{
	local EnhancedUpnpHttp H;

	H = Spawn(Class'Enhanced.EnhancedUpnpHttp');
	H.Manager = self;
	H.Fetch(HostIp, HostPort, Req, Tag);
}

function Soap(string Action, string Args)
{
	local string Body, Req;

	Body = "<?xml version=\"1.0\"?>" $ CRLF()
		$ "<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\" s:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\">"
		$ "<s:Body><u:" $ Action $ " xmlns:u=\"" $ ServiceType $ "\">" $ Args $ "</u:" $ Action $ "></s:Body></s:Envelope>";
	Req = "POST " $ ControlPath $ " HTTP/1.1" $ CRLF()
		$ "Host: " $ BaseHost $ ":" $ string(BasePort) $ CRLF()
		$ "Content-Type: text/xml; charset=\"utf-8\"" $ CRLF()
		$ "SOAPACTION: \"" $ ServiceType $ "#" $ Action $ "\"" $ CRLF()
		$ "Content-Length: " $ string(Len(Body)) $ CRLF()
		$ "Connection: close" $ CRLF() $ CRLF() $ Body;
	Get(BaseHost, BasePort, Req, Action);
}

function bool Ok200(string Answer)
{
	return InStr(Left(Answer, 20), " 200") >= 0;
}

// The first service of the description that is a WAN connection (IP or PPP) gives the service type and the control URL.
function bool ReadDescription(string Xml)
{
	local string Svc, Type, Ctl, Base, Rest;
	local int P, Q;

	Base = Between(Xml, "<URLBase>", "</URLBase>");
	if (Left(Caps(Base), 7) == "HTTP://")
	{
		Rest = Mid(Base, 7);
		P = InStr(Rest, "/");
		if (P >= 0)
		{
			Rest = Left(Rest, P);
		}
		P = InStr(Rest, ":");
		if (P >= 0)
		{
			BaseHost = Left(Rest, P);
			BasePort = int(Mid(Rest, P + 1));
		}
		else
		{
			BaseHost = Rest;
			BasePort = 80;
		}
	}
	Rest = Xml;
	while (true)
	{
		P = InStr(Rest, "<service>");
		if (P < 0)
		{
			break;
		}
		Rest = Mid(Rest, P + 9);
		Q = InStr(Rest, "</service>");
		if (Q < 0)
		{
			break;
		}
		Svc = Left(Rest, Q);
		Type = Between(Svc, "<serviceType>", "</serviceType>");
		if (InStr(Type, ":WANIPConnection:") >= 0 || InStr(Type, ":WANPPPConnection:") >= 0)
		{
			Ctl = Between(Svc, "<controlURL>", "</controlURL>");
			if (Ctl != "")
			{
				ServiceType = Type;
				ControlPath = Ctl;
				if (Left(Caps(ControlPath), 7) == "HTTP://")
				{
					ControlPath = Mid(ControlPath, 7);
					P = InStr(ControlPath, "/");
					if (P >= 0)
					{
						ControlPath = Mid(ControlPath, P);
					}
				}
				if (Left(ControlPath, 1) != "/")
				{
					ControlPath = "/" $ ControlPath;
				}
				return true;
			}
		}
		Rest = Mid(Rest, Q + 10);
	}
	return false;
}

function MapPort()
{
	Stage = 4;
	StageAge = 0.0;
	Status = "UPnP: opening port " $ string(GamePort) $ "...";
	Soap("AddPortMapping", "<NewRemoteHost></NewRemoteHost><NewExternalPort>" $ string(GamePort) $ "</NewExternalPort>"
		$ "<NewProtocol>UDP</NewProtocol><NewInternalPort>" $ string(GamePort) $ "</NewInternalPort>"
		$ "<NewInternalClient>" $ LocalIP $ "</NewInternalClient><NewEnabled>1</NewEnabled>"
		$ "<NewPortMappingDescription>Shrek 2 Enhanced</NewPortMappingDescription><NewLeaseDuration>" $ string(Lease) $ "</NewLeaseDuration>");
}

function HttpDone(string Tag, string Answer)
{
	local string Code;

	if (Stage >= 5)
	{
		return;
	}
	if (Tag == "desc")
	{
		if (!Ok200(Answer) || !ReadDescription(Answer))
		{
			Fail("UPnP: the router has no Internet connection service");
			return;
		}
		Log("[SDBG] upnp: service " $ ServiceType $ " control " $ BaseHost $ ":" $ string(BasePort) $ ControlPath);
		Stage = 3;
		StageAge = 0.0;
		Status = "UPnP: asking for the external address...";
		Soap("GetExternalIPAddress", "");
	}
	else if (Tag == "GetExternalIPAddress")
	{
		ExternalIP = Between(Answer, "<NewExternalIPAddress>", "</NewExternalIPAddress>");
		Log("[SDBG] upnp: external address '" $ ExternalIP $ "'");
		if (GamePort == 0)
		{
			Stage = 5;
			Status = "UPnP: external address " $ ExternalIP;
			return;
		}
		MapPort();
	}
	else if (Tag == "AddPortMapping")
	{
		if (Ok200(Answer))
		{
			Stage = 5;
			bMapped = true;
			Status = "UPnP: port " $ string(GamePort) $ " is open. Your address: " $ ExternalIP $ ":" $ string(GamePort);
			Log("[SDBG] upnp: port mapped, " $ Status);
			return;
		}
		Code = Between(Answer, "<errorCode>", "</errorCode>");
		Log("[SDBG] upnp: AddPortMapping refused, code " $ Code);
		if (Code == "725" && !bLeaseRetried)
		{
			bLeaseRetried = true;
			Lease = 0;
			MapPort();
			return;
		}
		Fail("UPnP: the router refused to open the port (code " $ Code $ ")");
	}
}

// Takes the mapping away again when the game session ends. Best effort: the lease expires on its own.
function Release()
{
	if (bMapped && ControlPath != "")
	{
		Soap("DeletePortMapping", "<NewRemoteHost></NewRemoteHost><NewExternalPort>" $ string(GamePort) $ "</NewExternalPort><NewProtocol>UDP</NewProtocol>");
		bMapped = false;
		Log("[SDBG] upnp: mapping removed");
	}
}

defaultproperties
{
	bHidden=True
	RemoteRole=ROLE_None
}

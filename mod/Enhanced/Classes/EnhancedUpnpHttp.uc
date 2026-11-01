class EnhancedUpnpHttp extends IpDrv.TcpLink;

// One HTTP request to the router (UPnP speaks SOAP over plain HTTP). Opens the connection, sends the request,
// collects the answer until the router closes the connection ("Connection: close"), then hands it to the manager.

var EnhancedUpnp Manager;
var string Request;
var string Answer;
var string Tag;
var bool bFinished;
var float Age;

function Fetch(string HostIp, int HostPort, string Req, string NewTag)
{
	local IpAddr A;

	Request = Req;
	Tag = NewTag;
	LinkMode = MODE_Text;
	ReceiveMode = RMODE_Event;
	BindPort();
	if (!StringToIpAddr(HostIp, A))
	{
		Finish("");
		return;
	}
	A.Port = HostPort;
	if (!Open(A))
	{
		Finish("");
	}
}

event Opened()
{
	SendText(Request);
}

event ReceivedText(string Text)
{
	Answer = Answer $ Text;
}

event Closed()
{
	Finish(Answer);
}

event Tick(float DeltaTime)
{
	Super.Tick(DeltaTime);
	Age += DeltaTime;
	if (!bFinished && Age > 8.0)
	{
		Finish(Answer);
	}
}

function Finish(string What)
{
	if (bFinished)
	{
		return;
	}
	bFinished = true;
	if (Manager != None)
	{
		Manager.HttpDone(Tag, What);
	}
	Destroy();
}

defaultproperties
{
	bAlwaysTick=True
}

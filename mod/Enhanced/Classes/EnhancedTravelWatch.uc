class EnhancedTravelWatch extends Interaction;

// A level change on a client. The host loads the new level and its answer to the first request is lost; the engine
// neither repeats the request nor ticks the old level while it waits (so no timer of that level runs). An interaction
// belongs to the viewport and is ticked in every state, so this is where the client keeps asking the host to let it in.

var bool bArmed;
var string Host;
var Actor ArmedFor;       // the controller of the level the client is leaving
var float Next;
var int Tries;
var float AliveLog;

const MaxTries = 40;
const FirstDelay = 3.0;    // the first request is lost while the host loads the level; the engine does not repeat it

function Initialize()
{
	bRequiresTick = true;
}

function Arm(string NewHost, Actor Leaving)
{
	Host = NewHost;
	ArmedFor = Leaving;
	Tries = 0;
	Next = FirstDelay;
	bArmed = true;
}

function Tick(float DeltaTime)
{
	if (!bArmed)
	{
		return;
	}
	AliveLog += DeltaTime;
	if (AliveLog > 3.0)
	{
		AliveLog = 0.0;
		Log("[SDBG] client: waiting, tries " $ string(Tries) $ ", viewport actor " $ string(ViewportOwner.Actor));
	}
	if (ViewportOwner.Actor != None && ViewportOwner.Actor != ArmedFor)
	{
		// the client is in the new level
		bArmed = false;
		Log("[SDBG] client: viewport actor is now " $ string(ViewportOwner.Actor) $ " after " $ string(Tries) $ " tries");
		return;
	}
	Next -= DeltaTime;
	if (Next > 0.0)
	{
		return;
	}
	Next = 3.0;
	Tries++;
	if (Tries > MaxTries)
	{
		bArmed = false;
		return;
	}
	Log("[SDBG] client: try " $ string(Tries) $ " to join " $ Host);
	ConsoleCommand("open " $ Host);
}

defaultproperties
{
	bActive=True
}

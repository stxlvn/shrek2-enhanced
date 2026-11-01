class EnhancedLeavePrompt extends Interaction;

// The host's question when the last guest has left the session: "close the session and keep the progress?". It is a viewport interaction (the host is in
// a level, not in the book menu), so it takes the keys while it is up: Enter or Y closes the session with a co-op save, Escape or N goes on alone.

var bool bAsking;
var string Nick;
var float Shown;
var string AutoAnswer;      // tests only: "yes" or "no" is given after a few seconds

function Initialize()
{
	bRequiresTick = true;
	bVisible = true;
	bActive = true;
}

function Ask(string LeaverNick, string Auto)
{
	Nick = LeaverNick;
	AutoAnswer = Auto;
	Shown = 0.0;
	bAsking = true;
	bVisible = true;
}

function Answer(bool bYes)
{
	local EnhancedGame G;

	bAsking = false;
	if (ViewportOwner != None && ViewportOwner.Actor != None)
	{
		G = EnhancedGame(ViewportOwner.Actor.Level.Game);
	}
	if (G != None)
	{
		G.LeaveAnswered(bYes);
	}
}

function Tick(float DeltaTime)
{
	if (!bAsking)
	{
		return;
	}
	Shown += DeltaTime;
	if (AutoAnswer != "" && Shown > 6.0)
	{
		Answer(AutoAnswer ~= "yes");
	}
}

function bool KeyEvent(out Interactions.EInputKey Key, out Interactions.EInputAction Action, float Delta)
{
	if (!bAsking)
	{
		return false;
	}
	if (Action == IST_Press)
	{
		if (Key == IK_Enter || Key == IK_Y)
		{
			Answer(true);
		}
		else if (Key == IK_Escape || Key == IK_N)
		{
			Answer(false);
		}
	}
	return true;
}

defaultproperties
{
	bVisible=true
	bActive=true
	bRequiresTick=true
}

class EnhancedLocalCut extends KWCutScene;

// A cutscene played on a guest's own machine. The stock cutscenes (KWCutScene, made by the level's CutFactory) exist and run only where the game runs,
// on the host; a guest used to watch the host's camera. Now each guest plays the same script himself, with local copies of the actors in it (see
// EnhancedPlayerController.StartLocalCut), and takes the host's world back when it is over.
// What differs from the stock cutscene: the controllers are local ones (EnhancedLocalCutCtl, they leave out what would change the game), and nothing here
// reaches the game's state: no level change, no save, no event to the level, no change of the player's controls, no HUD of the host.

var EnhancedPlayerController Viewer;
var bool bEnded;
var float Age;
var float StuckAge[32];

// The stock one spawns KWCutControllerII; a guest needs the local kind (a replicated class cannot be spawned on a client).
function SetupControllers()
{
	local int i;
	local string TS, SpawnTag, F;
	local EnhancedLocalCutCtl cc;

	F = "Cutscenes\\" $ ScriptFileName;
	for (i = 0; i < 64; i++)
	{
		TS = Caps(Localize("Sequence_" $ string(i), "line_0", F));
		if (InStr(TS, "<?") >= 0)
		{
			break;
		}
		SpawnTag = Caps(Localize("Sequence_" $ string(i), "PawnTag", F));
		if (InStr(SpawnTag, "ONEXIT") >= 0)
		{
			LoadOnExitScript("Sequence_" $ string(i));
			continue;
		}
		cc = Spawn(Class'Enhanced.EnhancedLocalCutCtl',,, Location, Rotation);
		if (cc == None)
		{
			Log("[LCUT] no controller for " $ ScriptFileName $ " Sequence_" $ string(i));
			continue;
		}
		cc.ScriptFileName = ScriptFileName;
		cc.ScriptSequenceName = "Sequence_" $ string(i);
		cc.refMyCutScene = self;
		cc.myControllerID = i;
		CutControllers[CutControllers.Length] = cc;
	}
	Log("[LCUT] " $ ScriptFileName $ ": " $ string(CutControllers.Length) $ " sequences");
}

// Only the commands for the local copies of the actors; a level change, a save, a switch of the player's control belong to the host.
function DoExitCommands()
{
	local int i;
	local string PawnTag, Command, Err;
	local KWPawn P, Found;

	for (i = 0; i < ExitCommands.Length; i++)
	{
		PawnTag = Class'KWGame.KWHelper'.static.ParseDelimitedString(ExitCommands[i], " ", 1, false);
		Command = Class'KWGame.KWHelper'.static.ParseDelimitedString(ExitCommands[i], " ", 2, true);
		if (PawnTag == "" || PawnTag ~= "ChangeLevel" || PawnTag ~= "SaveGame" || InStr(Caps(Command), "SWITCHCONTROL") >= 0)
		{
			continue;
		}
		Found = None;
		foreach DynamicActors(Class'KWGame.KWPawn', P)
		{
			if (string(P.Tag) ~= PawnTag && Viewer != None && Viewer.IsCutClone(P))
			{
				Found = P;
				break;
			}
		}
		if (Found != None)
		{
			Found.OnCutExitCommand(Command, Err);
		}
	}
}

function EndScene()
{
	local int i;

	if (bEnded)
	{
		return;
	}
	bEnded = true;
	bInCutScene = false;
	DoExitCommands();
	for (i = 0; i < CutControllers.Length; i++)
	{
		if (CutControllers[i] != None)
		{
			CutControllers[i].PreDestroy();
			CutControllers[i].Destroy();
		}
	}
	CutControllers.Length = 0;
	DeliveredCues.Length = 0;
	ExitCommands.Length = 0;
	Log("[LCUT] " $ ScriptFileName $ " is over after " $ string(int(Age)) $ " s");
	if (Viewer != None)
	{
		Viewer.LocalCutOver(self);
	}
}

// the guest skips it (Space, like the stock game)
function ForceFinish()
{
	local int i;

	if (bNoBypass || !bInCutScene || bEnded)
	{
		return;
	}
	ConsoleCommand("stopsounds");
	for (i = 0; i < CutControllers.Length; i++)
	{
		if (CutControllers[i] != None)
		{
			CutControllers[i].ForceFinish();
		}
	}
}

// A sequence that waits for an event of the level (a door that opened, a fight that ended) waits for ever on a guest: the level's events happen on the
// host. Such a wait is given up after six seconds. A cutscene that is still running long after the host's ended is stopped (a cue that never came).
event Tick(float DeltaTime)
{
	local int i;
	local string A;
	local KWCutControllerII C;

	Age += DeltaTime;
	if (bEnded || !bInCutScene)
	{
		return;
	}
	for (i = 0; i < CutControllers.Length && i < 32; i++)
	{
		C = KWCutControllerII(CutControllers[i]);
		A = "";
		if (C != None && C.CurrentAction != None)
		{
			A = Caps(string(C.CurrentAction.Class.Name));
		}
		if (InStr(A, "WAITFOREVENT") >= 0 || InStr(A, "ONEVENT") >= 0)
		{
			StuckAge[i] += DeltaTime;
			if (StuckAge[i] > 6.0)
			{
				StuckAge[i] = 0.0;
				Log("[LCUT] " $ ScriptFileName $ " Sequence_" $ string(C.myControllerID) $ ": the wait for a level event (" $ A $ ") is given up");
				C.CompleteAction();
			}
		}
		else
		{
			StuckAge[i] = 0.0;
		}
	}
}

defaultproperties
{
	RemoteRole=ROLE_None
}

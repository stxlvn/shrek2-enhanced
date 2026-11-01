class EnhancedMutator extends Mutator;

// The mod's hook into the game: the engine asks the base mutator about every actor when it starts
// (Actor.PreBeginPlay -> CheckRelevance -> CheckReplacement). This is where the stock checkpoint,
// the hero controller and the enemies are replaced or changed.
//
// Stage 1: only observe. Which classes pass through here, how many of each, and in which order.

var array<string> Names;
var array<int> Counts;
var int Total;
var string Order;
var int OrderN;

event PostBeginPlay()
{
	Super.PostBeginPlay();
	SetTimer(8.0, false);
	Log("[SDBG] MUT up, t=" $ string(Level.TimeSeconds));
}

function Note(string C)
{
	local int i;

	Total++;
	for (i = 0; i < Names.Length; i++)
	{
		if (Names[i] == C)
		{
			Counts[i] = Counts[i] + 1;
			return;
		}
	}
	Names[Names.Length] = C;
	Counts[Counts.Length] = 1;
	if (OrderN < 60)
	{
		OrderN++;
		Order = Order @ C;
		if (Len(Order) > 150)
		{
			Log("[SDBG] MUT order:" $ Order);
			Order = "";
		}
	}
}

function ReplaceBonusExit(Actor Old)
{
	local Actor N;
	local int i;
	local string Names[10];

	N = Spawn(Class'Enhanced.EnhancedLeaveBonus', Old.Owner, Old.Tag, Old.Location, Old.Rotation);
	if (N == None)
	{
		Log("[SDBG] MUT bonus exit could not be replaced");
		return;
	}
	N.Event = Old.Event;
	N.SetCollisionSize(Old.CollisionRadius, Old.CollisionHeight);
	Names[0] = "TriggerType";
	Names[1] = "bInitiallyActive";
	Names[2] = "ReTriggerDelay";
	Names[3] = "DamageThreshold";
	Names[4] = "bTriggerOnceOnly";
	Names[5] = "bDoActionWhenTriggered";
	Names[6] = "bSetGameState";
	Names[7] = "NewGameState";
	Names[8] = "TriggerActor";
	Names[9] = "ClassProximityType";
	for (i = 0; i < 10; i++)
	{
		N.SetPropertyText(Names[i], Old.GetPropertyText(Names[i]));
	}
	Log("[SDBG] MUT the exit of the bonus level " $ string(Old) $ " is replaced by " $ string(N) $ " at " $ string(N.Location));
}

function bool CheckReplacement(Actor Other, out byte bSuperRelevant)
{
	Note(string(Other.Class));

	// The game is single-player: a pawn plays its animations only where it is driven, so on the other machine
	// it stands in the T pose. The engine sends the animation state of a pawn when this flag is set.
	if (Pawn(Other) != None)
	{
		if (!EnhancedGame(Level.Game).Off("norepanim"))
		{
			Other.SetPropertyText("bReplicateAnimations", "True");
		}
		// A pawn with no equipment lists makes the stock AddDefaultInventory read element 0 of an empty array (three warnings per pawn).
		// One empty entry does what the empty list meant.
		if (Other.GetPropertyText("RequiredEquipment") == "()")
		{
			Other.SetPropertyText("RequiredEquipment", "(\"\")");
		}
		if (Other.GetPropertyText("SelectedEquipment") == "()" && Other.GetPropertyText("OptionalEquipment") == "()")
		{
			Other.SetPropertyText("SelectedEquipment", "(0)");
			Other.SetPropertyText("OptionalEquipment", "(\"\")");
		}
	}

	// A hint cutscene (the Donkey's "walk on the water" talk and the like) fires again every time any hero steps on its trigger.
	// With two heroes wading in and out it repeated ten times; one repeat per 40 seconds at most.
	if (Other.IsA('CutSceneTrigger') && float(Other.GetPropertyText("ReTriggerDelay")) < 40.0)
	{
		Other.SetPropertyText("ReTriggerDelay", "40.0");
	}
	if (Other.IsA('ShEnemy'))
	{
		EnhancedGame(Level.Game).ScaleEnemy(Other);
	}
	if (Other.IsA('CutSceneTrigger'))
	{
		EnhancedGame(Level.Game).RegisterGate(Other);
	}
	// The stock exit of a bonus level loads a stock save, which the mod does not write: the mod's own exit takes the player back to his level.
	if (string(Other.Class) ~= "ShGame.LeaveBonusLevelTrigger")
	{
		ReplaceBonusExit(Other);
		return false;
	}
	if (Other.IsA('ChangeLevelTrigger'))
	{
		EnhancedGame(Level.Game).RegisterExit(Other);
	}
	if (string(Other.Class) ~= "KWGame.PersistentStore")
	{
		EnhancedGame(Level.Game).ApplyStoreTo(PersistentStore(Other));
	}

	// The hero controller placed in the level is removed; the game's Login then makes one from the
	// pawn's DefaultPlayerControllerClass, which is set to the mod's controller just below.
	if (EnhancedGame(Level.Game).Off("noctl"))
	{
		return true;      // test: the game's own hero controller is left alone
	}
	if (string(Other.Class) ~= "ShGame.ShrekController" || string(Other.Class) ~= "ShGame.DonkeyController")
	{
		Log("[SDBG] MUT removing the placed " $ string(Other));
		return false;
	}
	// The hero of the level (Shrek, or Puss in Boots, or the Donkey, whatever the level is made for) gets the mod's controller. The placed controller is
	// removed above, so the pawn has to name the replacement, or the game's Login fails ("Login failed" at the start of a level whose hero is not Shrek).
	if (string(Other.Class) ~= "ShGame.Shrek" || (ShHeroPawn(Other) != None && !Other.IsA('Donkey') && Other.GetPropertyText("bIsMainPlayer") ~= "True"))
	{
		if (EnhancedGame(Level.Game).Off("mina"))
		{
			KWPawn(Other).DefaultPlayerControllerClass = Class'Enhanced.EnhancedMinA';
		}
		else if (EnhancedGame(Level.Game).Off("minb"))
		{
			KWPawn(Other).DefaultPlayerControllerClass = Class'Enhanced.EnhancedMinB';
		}
		else if (EnhancedGame(Level.Game).Off("minctl"))
		{
			KWPawn(Other).DefaultPlayerControllerClass = Class'Enhanced.EnhancedMinController';
		}
		else
		{
			KWPawn(Other).DefaultPlayerControllerClass = Class'Enhanced.EnhancedHeroController';
		}
		Log("[SDBG] MUT " $ string(Other) $ " now uses EnhancedHeroController");
	}
	else if (Other.IsA('Donkey') && Other.GetPropertyText("bIsMainPlayer") ~= "True")
	{
		KWPawn(Other).DefaultPlayerControllerClass = Class'Enhanced.EnhancedDonkeyController';
		Log("[SDBG] MUT " $ string(Other) $ " now uses EnhancedDonkeyController");
	}
	return true;
}

event Timer()
{
	local int i;
	local string Line;

	if (Order != "")
	{
		Log("[SDBG] MUT order:" $ Order);
		Order = "";
	}
	Log("[SDBG] MUT summary: total=" $ string(Total) $ " classes=" $ string(Names.Length));
	for (i = 0; i < Names.Length; i++)
	{
		Line = Line @ Names[i] $ "=" $ string(Counts[i]);
		if (Len(Line) > 150)
		{
			Log("[SDBG] MUT count:" $ Line);
			Line = "";
		}
	}
	if (Line != "")
	{
		Log("[SDBG] MUT count:" $ Line);
	}
}

defaultproperties
{
}

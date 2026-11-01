class EnhancedLeaveBonus extends ShGame.LeaveBonusLevelTrigger;

// The trigger that ends a bonus level. The stock one loads the saved game of the slot the player started from (StartSavedRunningGame), and the mod keeps
// no stock save, so the player stayed in the bonus level for ever. This one asks the game to go back to the level he came from, from the mod's record.

function PerformLevelTravel()
{
	if (bSetGameState)
	{
		KWGame(Level.Game).SetGameState(NewGameState);
	}
	if (EnhancedGame(Level.Game) != None)
	{
		EnhancedGame(Level.Game).ReturnFromBonus();
	}
}

defaultproperties
{
}

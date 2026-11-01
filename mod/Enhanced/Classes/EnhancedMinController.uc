class EnhancedMinController extends ShrekController;

// Tests only (URL option EnhOff=minctl): the game's own ShrekController under a name of the mod, with nothing changed, to see whether a subclass alone
// changes the game's behaviour (the water slowdown of the hero did not work with the mod's own controller).

event OnEnginePreFirstTick(bool bLoadFromSaveGame)
{
	local EnhancedGame G;
	local PlayerStart Ps;

	G = EnhancedGame(Level.Game);
	if (G != None && G.ShouldSkipIntro())
	{
		foreach AllActors(Class'Engine.PlayerStart', Ps)
		{
			Ps.Event = 'None';
		}
	}
	if (G != None)
	{
		G.HoldIntro();
	}
	Super.OnEnginePreFirstTick(bLoadFromSaveGame);
}

defaultproperties
{
}

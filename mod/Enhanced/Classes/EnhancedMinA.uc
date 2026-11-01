class EnhancedMinA extends ShrekController;

// Tests only (EnhOff=mina): the stock ShrekController with only the mod's override of state PlayerWalking.

state PlayerWalking
{
	function PlayerMove(float DeltaTime)
	{
		if (Pawn == None)
		{
			return;
		}
		Super.PlayerMove(DeltaTime);
	}
}

defaultproperties
{
}

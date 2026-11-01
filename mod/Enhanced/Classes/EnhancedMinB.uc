class EnhancedMinB extends ShrekController;

// Tests only (EnhOff=minb): the stock ShrekController with only an override of PlayerTick that calls Super.

event PlayerTick(float DeltaTime)
{
	Super.PlayerTick(DeltaTime);
}

defaultproperties
{
}

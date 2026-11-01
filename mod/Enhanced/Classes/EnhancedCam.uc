class EnhancedCam extends Actor;

// An invisible camera stand. During the host's cutscenes the camera of player two is put on this actor and the
// server moves it every frame to where the host's own camera is, so both players watch the same shots.

defaultproperties
{
	bHidden=True
	bStatic=False
	bNoDelete=False
	Physics=PHYS_None
	RemoteRole=ROLE_SimulatedProxy
	bAlwaysRelevant=True
	bReplicateMovement=True
	NetUpdateFrequency=60.0
	DrawType=DT_None
}

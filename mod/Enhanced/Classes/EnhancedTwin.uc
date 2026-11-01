class EnhancedTwin extends Actor;

// The picture of a creature on a client (see EnhancedWorldSync): a client may only spawn actors that are not replicated, and the creatures' own classes are, so
// this class only wears the creature's mesh and plays what the host tells it.

defaultproperties
{
	RemoteRole=ROLE_None
	DrawType=DT_Mesh
	bHidden=False
	bStatic=False
	bCollideActors=False
	bBlockActors=False
	bBlockPlayers=False
	bCollideWorld=False
}

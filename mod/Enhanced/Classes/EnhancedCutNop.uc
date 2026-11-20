class EnhancedCutNop extends KWScriptedAction;

// Stands in a guest's own cutscene for a command that belongs to the host's game (an event sent to the level, a level change, ...): it does nothing and
// the sequence goes on at once (see EnhancedLocalCutCtl.LoadScript). The stock "Comment" cannot be used for that: it writes to the host's HUD.

function bool InitActionFor(KWCutController C)
{
	return false;
}

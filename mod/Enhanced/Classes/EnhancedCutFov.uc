class EnhancedCutFov extends KWScriptedAction;

// The script's "FOV" command in a guest's own cutscene. The stock one spawns a FOVController that changes the field of view of the host's hero controller
// (on a guest it has none and only fills the log); this one hands the same change to the guest's own view (EnhancedPlayerController.CutFovChange).

var float NewFov;
var float ChangeTime;
var bool bReset;

function bool InitActionFor(KWCutController C)
{
	local EnhancedPlayerController PC;

	PC = EnhancedPlayerController(C.Level.GetLocalPlayerController());
	if (PC != None)
	{
		PC.CutFovChange(NewFov, ChangeTime, bReset);
	}
	return false;
}

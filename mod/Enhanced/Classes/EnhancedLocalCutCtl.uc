class EnhancedLocalCutCtl extends KWCutControllerII;

// One sequence of a cutscene played on a guest's machine (see EnhancedLocalCut). It drives the local copies of the actors exactly like the stock controller,
// with two differences: the commands that would change the game (an event sent to the level, a level change, the game state, a menu, an objective,
// slow motion, a switch of the player's hero) are left out, and the spoken lines go to the guest's own sound and subtitles (the stock one hands them to the
// host's hero controller, which a guest does not have).

function LoadScript()
{
	local int i;
	local string C;
	local EnhancedCutFov F;

	Super.LoadScript();
	for (i = 0; i < Actions.Length; i++)
	{
		if (Actions[i] == None)
		{
			continue;
		}
		C = Caps(string(Actions[i].Class.Name));
		if (C == "KWACTION_TRIGGER" || C == "KWACTION_CHANGELEVEL" || C == "KWACTION_SETGAMESTATE" || C == "KWACTION_GOTOMENU" || C == "KWACTION_SETOBJECTIVE"
			|| C == "KWACTION_SLOMO" || C == "KWACTION_TAKEOVER" || C == "ACTION_TAKEOVER" || C == "KWACTION_SENDACTORCOMMAND" || C == "KWACTION_COMMENT")
		{
			Actions[i] = new(Level) Class'Enhanced.EnhancedCutNop';
		}
		else if (C == "KWACTION_FOV")
		{
			F = new(Level) Class'Enhanced.EnhancedCutFov';
			F.NewFov = float(Actions[i].GetPropertyText("NewFOV"));
			F.ChangeTime = float(Actions[i].GetPropertyText("ChangeTime"));
			F.bReset = Actions[i].GetPropertyText("bResetFOV") ~= "True";
			Actions[i] = F;
		}
	}
}

function float DeliverLocalizedDialog(string DlgID, bool bPlaySound, float fDisplayDuration, optional string IntFileName, optional bool No3D, optional Actor soundSource)
{
	local Sound S;
	local string Txt;
	local float L;
	local EnhancedPlayerController PC;

	PC = EnhancedPlayerController(Level.GetLocalPlayerController());
	if (IntFileName == "")
	{
		Txt = Localize("all", DlgID, "HPdialog");
	}
	else
	{
		Txt = Localize("all", DlgID, IntFileName);
	}
	if (bPlaySound)
	{
		S = Sound(DynamicLoadObject("AllDialog." $ DlgID, Class'Engine.Sound'));
	}
	if (S != None)
	{
		L = GetSoundDuration(S);
		if (soundSource == None && PC != None)
		{
			soundSource = PC.CutSoundSource();
		}
		if (soundSource != None)
		{
			soundSource.PlaySound(S, SLOT_Talk, 1.4, , 10000.0, , false);
		}
	}
	else
	{
		L = float(Len(Txt)) * 0.01 + 3.0;
	}
	if (fDisplayDuration > 0.0)
	{
		L = fDisplayDuration;
	}
	if (KWPawn(soundSource) != None)
	{
		Txt = KWPawn(soundSource).HandleFacialExpression(Txt, int(L));
	}
	else if (InStr(Txt, "]") >= 0)
	{
		Txt = Mid(Txt, InStr(Txt, "]") + 1);
	}
	if (PC != None)
	{
		PC.LocalSubtitle(DlgID, Txt, L);
	}
	return L;
}

defaultproperties
{
	RemoteRole=ROLE_None
}

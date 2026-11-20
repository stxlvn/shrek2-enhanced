class EnhancedGuestOverlay extends Interaction;

// What a joined player's screen gets on top of the picture and does not depend on the HUD: the host's subtitle during a cutscene and the notes ("wait for
// your partner", "you are down"). The HUD of a guest is not drawn in every state (a cutscene has none), a viewport interaction is.

var EnhancedHudKit Kit;

function Initialize()
{
	bVisible = true;
	bActive = false;
	bRequiresTick = false;
}

function PostRender(Canvas C)
{
	local EnhancedPlayerController P;
	local string S;

	if (ViewportOwner == None || C == None)
	{
		return;
	}
	P = EnhancedPlayerController(ViewportOwner.Actor);
	if (P == None)
	{
		return;
	}
	if (Kit == None)
	{
		Kit = new(None) Class'Enhanced.EnhancedHudKit';
	}
	// the guest's own cutscene speaks its own lines; the host's subtitle (sent by the server) belongs to the host's cutscene and is not shown meanwhile
	if (P.bLocalCut)
	{
		if (P.LocalSubText != "" && P.Level.TimeSeconds < P.LocalSubUntil)
		{
			Kit.DrawSubtitle(C, P.LocalSubName, P.LocalSubText, P.LocalSubColor);
		}
		return;
	}
	if (P.SubText != "")
	{
		Kit.DrawSubtitle(C, Class'Enhanced.EnhancedText'.static.Decode(P.SubName), Class'Enhanced.EnhancedText'.static.Decode(P.SubText), P.SubColor);
		return;
	}
	if (P.WaitNote != "")
	{
		Kit.DrawNoteAt(C, Class'Enhanced.EnhancedText'.static.Decode(P.WaitNote), 0.24);
		return;
	}
	S = P.GateNote;
	if (S == "")
	{
		S = P.DownNote;
	}
	if (S == "")
	{
		S = P.LeashNote;
	}
	S = Class'Enhanced.EnhancedText'.static.Decode(S);
	if (S != "" && !P.bCutView)
	{
		Kit.DrawNote(C, S);
	}
}

defaultproperties
{
	bVisible=true
}

class EnhancedGuestHud extends Engine.HUD;

// The HUD of a joined player: the stock Unreal one, with the text "wait for your partner" the host's game puts on the screen while
// this player waits at a cutscene trigger for the others to come.

var EnhancedHudKit Kit;

simulated function PostBeginPlay()
{
	Super.PostBeginPlay();
	Kit = new(None) Class'Enhanced.EnhancedHudKit';
	Kit.Load();
}

function DrawHUD(Canvas Canvas)
{
	local EnhancedPlayerController P;
	Super.DrawHUD(Canvas);
	P = EnhancedPlayerController(PlayerOwner);
	if (P != None && Kit != None && PlayerOwner.Pawn != None)
	{
		Kit.DrawHealth(Canvas, float(PlayerOwner.Pawn.GetPropertyText("Health")), P.HudIcons);
		Kit.DrawCounts(Canvas, Canvas.MedFont, P.HudCoins, P.HudPotions, P.HudPotionSel);
		if (P.ViewTarget == PlayerOwner.Pawn && P.LastCamTime > 0.0)
		{
			Kit.DrawNames(Canvas, P, PlayerOwner, PlayerOwner.Pawn, P.LastCamLoc, P.LastCamRot, P.FovAngle, Kit.TextFont(Canvas));
		}
	}
}

defaultproperties
{
}

class EnhancedHud extends ShGame.ShHud;

// The game's HUD with the mod's subtitle renderer. KWHud.PreBeginPlay spawns its own controller only
// when none is set, so the mod's one is created first.

var EnhancedHudKit Kit;       // draws the health bar, the coins and the potion (see EnhancedHudKit)
var float NoteLog;
var float HudLog;

simulated function PreBeginPlay()
{
	local int i;

	if (CutTextController == None)
	{
		CutTextController = Spawn(Class'Enhanced.EnhancedCutText');
		CutTextController.SetParentHud(Self);
		CutTextController.SetFont(KWBigFont, KWMedFont, KWSmallFont, KWTinyFont);
	}
	Super.PreBeginPlay();
	// The stock SHHud makes the HUD items (hearts, coins, potions, timers) and its load / save pictures in its own PreBeginPlay, together with
	// its subtitle controller. With the mod's subtitle controller in place that setup is skipped, and the screen had no HUD at all.
	if (HudItems.Length == 0)
	{
		InitHudItems();
	}
	// The health bar, the coin counter and the potion box are drawn by the mod (EnhancedHudKit); the stock items for them are taken out of the list.
	// Everything else (the timers, the boss bar) stays stock.
	for (i = HudItems.Length - 1; i >= 0; i--)
	{
		if (HudItems[i] != None && (HudItems[i].IsA('HudItemHealthBar') || HudItems[i].IsA('HudItemCoins') || HudItems[i].IsA('HudItemPotion')))
		{
			HudItems.Remove(i, 1);
		}
	}
	Kit = new(None) Class'Enhanced.EnhancedHudKit';
	Kit.Load();
	if (Loadimage == None)
	{
		Loadimage = Texture(DynamicLoadObject("SH_Hud.Loading_Elements.loading", Class'Engine.Texture'));
		saveimage = Texture(DynamicLoadObject("SH_Hud.Loading_Elements.saving", Class'Engine.Texture'));
		loadimagesolid = Texture(DynamicLoadObject("SH_Hud.Loading_Elements.loading_solid", Class'Engine.Texture'));
		blackimage = Texture(DynamicLoadObject("storybookanimTX.black_box", Class'Engine.Texture'));
	}
}

// One scale for both axes, from the height of the screen. The stock HUD is laid out for a 4:3 picture and scaled by width and by height separately,
// which on a wide screen (16:9, 21:9) stretches the icons and the numbers sideways. Left and right edges keep their place (the items are placed
// by fractions of the width), only the sizes follow the height.
function float CalculateScaleX(Canvas C)
{
	return float(C.SizeY) / fBaseResY;
}

// The three items, from the shared inventory (the pawn the level names as its carrier; see EnhancedGame.InvOf).
function DrawHUD(Canvas Canvas)
{
	local Pawn P;
	local EnhancedGame G;
	local int Sel, N, Coins, Potions;
	local KWPawn Inv;

	Super.DrawHUD(Canvas);
	P = PlayerOwner.Pawn;
	if (Kit == None || P == None || KWPawn(P) == None || bHideHUD || CutTextController.bCutSceneInProgress)
	{
		return;
	}
	G = EnhancedGame(Level.Game);
	Inv = KWPawn(P);
	if (G != None)
	{
		Inv = G.InvOf(P);
	}
	Kit.DrawHealth(Canvas, float(P.GetPropertyText("Health")), Inv.GetInventoryCount('Shamrock') + 1);
	Sel = int(PlayerOwner.GetPropertyText("PotionSelected"));
	Coins = Inv.GetInventoryCount('Coin');
	if (G != None)
	{
		N = G.PotionNumber(Sel);
		if (N > 0)
		{
			Potions = Inv.GetInventoryCount(G.PotionName(N));
		}
	}
	Kit.DrawCounts(Canvas, GetSmallHudTextFont(Canvas), Coins, Potions, Sel);
	if (KWPawn(P).KWGetCamera() != None)
	{
		Kit.DrawNames(Canvas, P, PlayerOwner, P, KWPawn(P).KWGetCamera().Location, KWPawn(P).KWGetCamera().Rotation, PlayerOwner.FovAngle, GetSmallHudTextFont(Canvas));
	}
}

defaultproperties
{
}

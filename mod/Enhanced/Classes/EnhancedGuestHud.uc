class EnhancedGuestHud extends Engine.HUD;

// The HUD of a joined player: the stock Unreal one, with the text "wait for your partner" the host's game puts on the screen while
// this player waits at a cutscene trigger for the others to come.

var EnhancedHudKit Kit;
var array<string> TexNames;
var array<Texture> TexObjs;

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
		DrawExtra(Canvas, P.HudExtra);
		if (P.ViewTarget == PlayerOwner.Pawn && P.LastCamTime > 0.0)
		{
			Kit.DrawNames(Canvas, P, PlayerOwner, PlayerOwner.Pawn, P.LastCamLoc, P.LastCamRot, P.FovAngle, Kit.TextFont(Canvas));
		}
	}
}

// The host's boss bar and timers, drawn here with the stock items' own textures and places (SHGame.HudItemHealthBossPib, SHHudGameTimer, SHHudPotionTimer).
function DrawExtra(Canvas C, string S)
{
	local string Part, Kind, V, Boss;
	local float F;
	local Texture Tx;

	while (S != "")
	{
		Part = Cut(S, ";");
		Kind = Cut(Part, ":");
		V = Cut(Part, ":");
		Boss = Part;
		F = FClamp(float(V), 0.0, 1.0);
		C.Style = ERenderStyle.STY_Alpha;
		C.SetDrawColor(255, 255, 255, 255);
		if (Kind == "B")
		{
			Tx = Tex("SH_Hud.boss_transbar");
			if (Tx != None)
			{
				C.SetPos(0.1 * C.SizeX, 0.1 * C.SizeY);
				C.DrawTile(Tx, 0.64 * C.SizeX, 0.16 * C.SizeY, 0.0, 0.0, 512.0, 128.0);
			}
			Tx = Tex("SH_Hud.BossHealth");
			if (Tx != None && F > 0.0)
			{
				C.SetPos(0.175 * C.SizeX, 0.105 * C.SizeY);
				C.DrawTile(Tx, 0.35375 * C.SizeX * F, 0.04 * C.SizeY, 0.0, 0.0, 512.0 * F, 64.0);
			}
			if (Boss == "fgm")
			{
				Tx = Tex("SH_Hud.Bosshealth_FGM");
			}
			else if (Boss == "fat")
			{
				Tx = Tex("SH_Hud.Bosshealth_FatKnt");
			}
			else if (Boss == "bandit")
			{
				Tx = Tex("SH_Hud.Bosshealth_Bandit");
			}
			else
			{
				Tx = Tex("SH_Hud.Bosshealth_PIB");
			}
			if (Tx != None)
			{
				C.SetPos(0.1 * C.SizeX, 0.1 * C.SizeY);
				C.DrawTile(Tx, 0.64 * C.SizeX, 0.16 * C.SizeY, 0.0, 0.0, 512.0, 128.0);
			}
		}
		else if (Kind == "T" || Kind == "P")
		{
			if (Kind == "T")
			{
				Tx = Tex("SH_Hud.Timer.Timerbar");
			}
			else
			{
				Tx = Tex("SH_Hud.Potions.potionbar");
				F = 1.0 - F;
			}
			if (Tx != None && F > 0.0)
			{
				C.SetPos(0.525 * C.SizeX, 0.0583333 * C.SizeY);
				C.DrawTile(Tx, 0.18125 * F * C.SizeX, 0.0233333 * C.SizeY, 0.0, 0.0, float(Tx.USize) * F, float(Tx.VSize));
			}
		}
	}
}

function string Cut(out string S, string Sep)
{
	local int P;
	local string R;

	P = InStr(S, Sep);
	if (P < 0)
	{
		R = S;
		S = "";
		return R;
	}
	R = Left(S, P);
	S = Mid(S, P + 1);
	return R;
}

function Texture Tex(string N)
{
	local int i;

	for (i = 0; i < TexNames.Length; i++)
	{
		if (TexNames[i] == N)
		{
			return TexObjs[i];
		}
	}
	i = TexNames.Length;
	TexNames[i] = N;
	TexObjs[i] = Texture(DynamicLoadObject(N, Class'Engine.Texture'));
	return TexObjs[i];
}

defaultproperties
{
}

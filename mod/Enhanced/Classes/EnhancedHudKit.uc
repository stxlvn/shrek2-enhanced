class EnhancedHudKit extends Object;

// The drawing of the health bar, the coin counter and the potion box, shared by the host's HUD and the guests'. The stock items place themselves
// by fractions of the screen WIDTH and size themselves by fractions of both axes, so on a wide screen the health plank is stretched sideways and the
// right-hand items stay where a 4:3 screen would have them. Here everything is measured from the screen HEIGHT (the HUD was drawn for 800 x 600 and
// 1024 x 768, one aspect ratio), the health group is fixed to the left edge, the coins and the potion to the right edge. At 4:3 the picture is the same as the
// stock one.

var Texture TexBack, TexHealth, TexLow, TexCoins;
var Texture TexIcon[6];
var Texture TexPotion[10];
var bool bLoaded;
var Font UiFont;            // a Windows font (Tahoma) for a guest's HUD text: the canvas fonts have no Cyrillic
var int UiFontH;

function Load()
{
	local int i;

	if (bLoaded)
	{
		return;
	}
	bLoaded = true;
	TexBack = Texture(DynamicLoadObject("SH_Hud.lifemeter_bar.Transbar", Class'Engine.Texture'));
	TexHealth = Texture(DynamicLoadObject("SH_Hud.lifemeter_bar.health", Class'Engine.Texture'));
	TexLow = Texture(DynamicLoadObject("SH_Hud.lifemeter_bar.healthlow", Class'Engine.Texture'));
	TexCoins = Texture(DynamicLoadObject("SH_Hud.Coins.coinbag", Class'Engine.Texture'));
	for (i = 0; i < 6; i++)
	{
		TexIcon[i] = Texture(DynamicLoadObject("SH_Hud.lifemeter_bar.lifebar_container" $ string(150 + 30 * i), Class'Engine.Texture'));
	}
	for (i = 0; i < 9; i++)
	{
		TexPotion[i] = Texture(DynamicLoadObject("SH_Hud.potions.potion" $ string(i + 1) $ "_Hud", Class'Engine.Texture'));
	}
	TexPotion[9] = Texture(DynamicLoadObject("SH_Hud.Timer.Timer", Class'Engine.Texture'));
}

// Health in points, Icons = 1 + the shamrocks (each adds 100 points and a longer bar).
function DrawHealth(Canvas C, float Health, int Icons)
{
	local float S, Frac, BarW;

	Load();
	if (TexBack == None || TexHealth == None)
	{
		return;
	}
	Icons = Clamp(Icons, 1, 6);
	S = float(C.SizeY) / 600.0;
	BarW = float(120 + 30 * Icons) * S;
	Frac = Health / (100.0 * float(Icons));
	if (Frac < 0.0)
	{
		Frac = 0.0;
	}
	if (Frac > 1.0)
	{
		Frac = 1.0;
	}
	C.SetDrawColor(255, 255, 255, 255);
	C.SetPos(89.0 * S, 34.0 * S);
	C.DrawTile(TexBack, BarW, 14.0 * S, 0.0, 0.0, 64.0, 64.0);
	C.SetPos(89.0 * S, 34.0 * S);
	if (Health < 50.0 && TexLow != None)
	{
		C.DrawTile(TexLow, BarW * Frac, 14.0 * S, 0.0, 0.0, 64.0 * Frac, 64.0);
	}
	else
	{
		C.DrawTile(TexHealth, BarW * Frac, 14.0 * S, 0.0, 0.0, 64.0 * Frac, 64.0);
	}
	if (TexIcon[Icons - 1] != None)
	{
		C.SetPos(20.0 * S, 15.0 * S);
		C.DrawTile(TexIcon[Icons - 1], 512.0 * S, 96.0 * S, 0.0, 0.0, 512.0, 128.0);
	}
}

function DrawNumber(Canvas C, Font F, string T, float CenterX, float CenterY)
{
	local float W, H;

	if (F != None)
	{
		C.Font = F;
	}
	C.TextSize(T, W, H);
	C.SetPos(CenterX - W * 0.5, CenterY - H * 0.5);
	C.DrawText(T, false);
}

// Coins and the selected potion, from the right edge (the stock positions are 738 and 517 on a 1024 wide screen).
function DrawCounts(Canvas C, Font F, int Coins, int Potions, int Sel)
{
	local float S, X, Y;

	Load();
	S = float(C.SizeY) / 768.0;
	C.SetDrawColor(255, 255, 255, 255);
	if (TexCoins != None)
	{
		X = float(C.SizeX) - (1024.0 - 738.0) * S;
		Y = 16.0 * S;
		C.SetPos(X, Y);
		C.DrawTile(TexCoins, float(TexCoins.USize) * S, float(TexCoins.VSize) * S, 0.0, 0.0, float(TexCoins.USize), float(TexCoins.VSize));
		DrawNumber(C, F, string(Coins), X + 105.0 * S, Y + 40.0 * S);
	}
	if (Sel >= 0 && Sel < 10 && TexPotion[Sel] != None)
	{
		X = float(C.SizeX) - (1024.0 - 517.0) * S;
		Y = 19.0 * S;
		C.SetPos(X, Y);
		C.DrawTile(TexPotion[Sel], float(TexPotion[Sel].USize) * S, float(TexPotion[Sel].VSize) * S, 0.0, 0.0, float(TexPotion[Sel].USize), float(TexPotion[Sel].VSize));
		if (Sel != 9)
		{
			DrawNumber(C, F, string(Potions), X + 182.0 * S, Y + 95.0 * S);
		}
	}
}

// The nickname over the head of every other player's Shrek. The projection is the stock one (KWPawn.KWWorldToScreen): the angle is the horizontal field of view
// of the picture, so with the Hor+ widening the name stays on the head. A name is not drawn for a hidden or dead Shrek, behind the camera, further than 3000 units,
// or when something solid is between the camera and his head; it fades with the distance.
function DrawNames(Canvas C, Actor Ctx, Controller Me, Pawn Own, Vector CamLoc, Rotator CamRot, float Fov, Font F)
{
	local KWPawn P;
	local Actor A;
	local Vector HL, HN;
	local bool bHidden;
	local Vector AX, AY, AZ, V, Head;
	local float D, K, SX, SY, W, H, Fade;
	local string N;
	local int Slot;

	if (Ctx == None || C == None || Fov < 10.0)
	{
		return;
	}
	if (F != None)
	{
		C.Font = F;
	}
	GetAxes(CamRot, AX, AY, AZ);
	K = (float(C.SizeX) * 0.5) / Tan(Fov * 0.0087266);
	foreach Ctx.AllActors(Class'KWGame.KWPawn', P)
	{
		if (P == Own || P.bHidden || P.PlayerReplicationInfo == None || (Me != None && (P.Controller == Me || P.PlayerReplicationInfo == Me.PlayerReplicationInfo)))
		{
			continue;
		}
		N = P.PlayerReplicationInfo.PlayerName;
		if (N == "" || float(P.GetPropertyText("Health")) <= 0.0)
		{
			continue;
		}
		Head = P.Location + vect(0.0, 0.0, 1.0) * (P.CollisionHeight + 22.0);
		V = Head - CamLoc;
		D = V Dot AX;
		if (D < 60.0 || VSize(V) > 3000.0)
		{
			continue;
		}
		// the same things that stop the chase camera (the world, the terrain, trunks, foliage) hide the name
		bHidden = false;
		foreach Ctx.TraceActors(Class'Engine.Actor', A, HL, HN, Head, CamLoc, vect(0.0, 0.0, 0.0))
		{
			if (A == P || A.IsA('Pawn') || A.IsA('Projectile'))
			{
				continue;
			}
			if (A.IsA('LevelInfo') || A.IsA('TerrainInfo') || A.GetPropertyText("bWorldGeometry") ~= "True" || A.GetPropertyText("bBlocksCamera") ~= "True"
				|| A.GetPropertyText("bChangeOpacityForCamera") ~= "True")
			{
				bHidden = true;
				break;
			}
		}
		if (bHidden)
		{
			continue;
		}
		SX = float(C.SizeX) * 0.5 + (V Dot AY) / D * K;
		SY = float(C.SizeY) * 0.5 - (V Dot AZ) / D * K;
		Fade = 255.0;
		if (VSize(V) > 1200.0)
		{
			Fade = 255.0 - (VSize(V) - 1200.0) / 1800.0 * 140.0;
		}
		C.TextSize(N, W, H);
		C.SetDrawColor(0, 0, 0, byte(Fade));
		C.SetPos(SX - W * 0.5 + 2.0, SY - H + 2.0);
		C.DrawText(N, false);
		Slot = P.PlayerReplicationInfo.PlayerID % 4;
		switch (Slot)
		{
			case 0:
				C.SetDrawColor(150, 255, 130, byte(Fade));
				break;
			case 1:
				C.SetDrawColor(255, 225, 110, byte(Fade));
				break;
			case 2:
				C.SetDrawColor(130, 215, 255, byte(Fade));
				break;
			default:
				C.SetDrawColor(255, 160, 120, byte(Fade));
				break;
		}
		C.SetPos(SX - W * 0.5, SY - H);
		C.DrawText(N, false);
	}
}

// The guest's text font: a Windows font (Tahoma) made by the engine through the proxy library, sized by the screen height (the canvas fonts have no Cyrillic).
function Font TextFont(Canvas C)
{
	local int H;

	H = Max(13, C.SizeY / 36);
	if (UiFont == None || UiFontH != H)
	{
		UiFont = Class'Enhanced.EnhancedText'.static.NativeFont(C, "Tahoma", H);
		UiFontH = H;
	}
	if (UiFont == None)
	{
		return C.MedFont;
	}
	return UiFont;
}

// One centred line with a shadow.
function CentreLine(Canvas C, string S, float Y, byte R, byte G, byte B)
{
	local float W, H;

	C.TextSize(S, W, H);
	C.SetDrawColor(0, 0, 0, 255);
	C.SetPos((float(C.SizeX) - W) * 0.5 + 2.0, Y + 2.0);
	C.DrawText(S, false);
	C.SetDrawColor(R, G, B, 255);
	C.SetPos((float(C.SizeX) - W) * 0.5, Y);
	C.DrawText(S, false);
}

// The host's subtitle on a guest's screen during a cutscene, made like the host's own (EnhancedCutText.DrawLines): the speaker's name in his colour and the
// line in white, centred in the lower band of the screen on lines no wider than 70% of the width, a light shadow and a translucent dark band behind.
function DrawSubtitle(Canvas C, string Name, string Text, Color NameColor)
{
	local string Line, Word, Rest, S;
	local array<string> Lines;
	local float W, H, MaxW, Y, Top, Height, Sh, Pad, X, PrefW, WideW;
	local int k, i, N, PrefixLen;
	local byte StyleSave;

	if (Text == "" || C == None)
	{
		return;
	}
	StyleSave = C.Style;
	C.Font = TextFont(C);
	if (Name != "")
	{
		S = Name $ ": " $ Text;
		PrefixLen = Len(Name) + 2;
	}
	else
	{
		S = Text;
	}
	MaxW = float(C.SizeX) * 0.7;
	Rest = S;
	Line = "";
	while (Rest != "")
	{
		k = InStr(Rest, " ");
		if (k < 0)
		{
			Word = Rest;
			Rest = "";
		}
		else
		{
			Word = Left(Rest, k);
			Rest = Mid(Rest, k + 1);
		}
		if (Line == "")
		{
			C.TextSize(Word, W, H);
			Line = Word;
		}
		else
		{
			C.TextSize(Line $ " " $ Word, W, H);
			if (W > MaxW)
			{
				Lines[Lines.Length] = Line;
				Line = Word;
			}
			else
			{
				Line = Line $ " " $ Word;
			}
		}
	}
	if (Line != "")
	{
		Lines[Lines.Length] = Line;
	}
	N = Lines.Length;
	C.TextSize("Ag", W, H);
	for (i = 0; i < N; i++)
	{
		C.TextSize(Lines[i], W, PrefW);
		WideW = FMax(WideW, W);
	}
	Top = 0.78 * float(C.SizeY);
	Height = 0.14 * float(C.SizeY);
	Y = Top + (Height - float(N) * H) * 0.5;
	Sh = FMax(1.0, 0.8 * float(C.SizeY) / 540.0);
	Pad = H * 0.3;
	C.Style = 5;
	C.SetDrawColor(0, 0, 0, 110);
	C.SetPos((float(C.SizeX) - WideW) * 0.5 - Pad * 2.0, Y - Pad);
	C.DrawTile(Texture'Engine.WhiteSquareTexture', WideW + Pad * 4.0, float(N) * H + Pad * 2.0, 0.0, 0.0, 2.0, 2.0);
	C.Style = 2;
	for (i = 0; i < N; i++)
	{
		C.TextSize(Lines[i], W, PrefW);
		X = (float(C.SizeX) - W) * 0.5;
		C.Style = 5;
		C.SetDrawColor(0, 0, 0, 90);
		C.SetPos(X + Sh, Y + Sh);
		C.DrawText(Lines[i], false);
		C.Style = 2;
		if (i == 0 && PrefixLen > 0 && Len(Lines[0]) > PrefixLen)
		{
			C.TextSize(Left(Lines[0], PrefixLen), PrefW, H);
			C.SetDrawColor(NameColor.R, NameColor.G, NameColor.B, 255);
			C.SetPos(X, Y);
			C.DrawText(Left(Lines[0], PrefixLen), false);
			C.SetDrawColor(255, 255, 255, 255);
			C.SetPos(X + PrefW, Y);
			C.DrawText(Mid(Lines[0], PrefixLen), false);
			C.TextSize("Ag", W, H);
		}
		else
		{
			C.SetDrawColor(255, 255, 255, 255);
			C.SetPos(X, Y);
			C.DrawText(Lines[i], false);
		}
		Y += H;
	}
	C.Style = StyleSave;
}

// A note at the top of the screen.
function DrawNote(Canvas C, string S)
{
	if (S == "" || C == None)
	{
		return;
	}
	C.Font = TextFont(C);
	CentreLine(C, S, float(C.SizeY) * 0.12, 255, 255, 255);
}

defaultproperties
{
}

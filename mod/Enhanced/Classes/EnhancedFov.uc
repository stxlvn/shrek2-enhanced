class EnhancedFov extends Object;

// Hor+ for Unreal Engine 2. The engine's field of view is the horizontal angle (90 degrees by default, made for 4:3). On a wide screen the same
// horizontal angle shows less above and below (16:9: a vertical angle of 59 degrees instead of 74), the picture looks zoomed in. Keeping the vertical
// angle of 4:3 means a wider horizontal one: tan(h'/2) = tan(h/2) * (aspect / (4/3)). It is applied to whatever angle the game wants at the moment
// (gameplay, a potion, a cutscene's zoom), so every camera of the game keeps its character.

// "1920x1080" > the aspect ratio relative to 4:3 (1.0 for a 4:3 screen), 0 when the text is not a resolution.
static function float AspectK(string Res)
{
	local int P;
	local float W, H;

	P = InStr(Caps(Res), "X");
	if (P < 0)
	{
		return 0.0;
	}
	W = float(Left(Res, P));
	H = float(Mid(Res, P + 1));
	if (W < 100.0 || H < 100.0)
	{
		return 0.0;
	}
	return (W / H) / (4.0 / 3.0);
}

// The horizontal angle in degrees for a screen K times wider than 4:3, never more than 160.
static function float HorPlus(float Fov, float K)
{
	local float R;

	R = 2.0 * Atan(Tan(Fov * 0.5 * 0.0174533) * K, 1.0) * 57.29578;
	if (R > 160.0)
	{
		R = 160.0;
	}
	return R;
}

defaultproperties
{
}

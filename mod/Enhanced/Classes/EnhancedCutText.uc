class EnhancedCutText extends KWGame.KWCutTextController;

// Subtitles in the style of Modern Warfare: the speaker's name in colour, then the line in white, straight on
// the picture. The stock controller draws a black bar over the bottom eighth of the screen (and a top bar in
// cutscenes) and blue text inside it. Here: no bar, a light shadow, and a translucent dark band behind the
// lines (BackAlpha) so white text stays readable on white spots. The bar is still drawn for the "skip"
// hourglass, which is a fade, not a subtitle.
//
// The game hands the HUD only the text of a line, not its dialog key (pc_<speaker>_...), so the speaker is
// looked up by the text: Enhanced.Rus / Enhanced.int hold "hash of the text = speaker code" and
// "speaker code = name" (made by tools/mkspeakers.py from the game's own dialog files).

var Color SubtitleColor;
var Color OutlineColor;
var int OutlineSize;
var Color ShadowColor;
var int BackAlpha;        // translucent dark band behind the lines, 0 = none
var float ShadowOffset;   // in pixels at 540 lines of screen height, scales with the resolution
var float TextTop;        // top of the text area as a fraction of the screen height
var float TextHeight;     // height of the text area as a fraction of the screen height
var float TextWidth;      // widest line as a fraction of the screen width
var string SpeakerName;
var Color SpeakerColor;
var float TextAge;        // how long the line has been on the screen

var string CacheKey;
var array<string> CLines;
var array<float> CWid;
var float CLineH, CMaxW, CPrefixW;
var bool bCacheSmall;
var int CacheFrames;       // frames drawn with this layout (the font is not loaded for the first frames, so the sizes it gives then are too small)

function DrawBorder(Canvas Canvas)
{
	if (IsInState('Hourglass'))
	{
		Super.DrawBorder(Canvas);
	}
}

// What the game shows with the facial-expression tags like [_Calm] taken out, without the spaces around it.
function string Norm(string S)
{
	local int P, Q;

	while (true)
	{
		P = InStr(S, "[");
		Q = InStr(S, "]");
		if (P < 0 || Q < P)
		{
			break;
		}
		S = Left(S, P) $ Mid(S, Q + 1);
	}
	while (Left(S, 1) == " ")
	{
		S = Mid(S, 1);
	}
	while (Right(S, 1) == " ")
	{
		S = Left(S, Len(S) - 1);
	}
	return S;
}

// The same two hashes as tools/mkspeakers.py; the modulus keeps every product inside 32 bits.
function string KeyOf(string S)
{
	local int i, C, H1, H2;

	for (i = 1; i <= Len(S); i++)
	{
		C = Asc(Mid(S, i - 1, 1));
		H1 = H1 * 31 + C;
		H1 = H1 - (H1 / 16777213) * 16777213;
		H2 = H2 * 37 + C;
		H2 = H2 - (H2 / 16777207) * 16777207;
	}
	return "k" $ string(Len(S)) $ "_" $ string(H1) $ "_" $ string(H2);
}

function Color NameColor(string Code)
{
	local Color C;

	C.A = 255;
	switch (Code)
	{
		case "shk":
			C.R = 195; C.G = 225; C.B = 155;
			break;
		case "dnk":
			C.R = 235; C.G = 208; C.B = 165;
			break;
		case "pib":
			C.R = 245; C.G = 195; C.B = 130;
			break;
		case "fin":
			C.R = 245; C.G = 190; C.B = 212;
			break;
		case "fgm":
			C.R = 215; C.G = 192; C.B = 245;
			break;
		case "nar":
			C.R = 195; C.G = 210; C.B = 245;
			break;
		default:
			C.R = 245; C.G = 232; C.B = 175;
	}
	return C;
}

function ResolveSpeaker(string T)
{
	local string N, Code, Name;

	SpeakerName = "";
	N = Norm(T);
	if (N == "")
	{
		return;
	}
	Code = Localize("Speaker", KeyOf(N), "Enhanced");
	if (Code == "" || Left(Code, 2) == "<?")
	{
		return;
	}
	Name = Localize("Name", Code, "Enhanced");
	if (Name == "" || Left(Name, 2) == "<?")
	{
		return;
	}
	SpeakerName = Name;
	SpeakerColor = NameColor(Code);
}

function SetText(string strSetText, float fSetTextDuration)
{
	TextAge = 0.0;
	ResolveSpeaker(strSetText);
	Super.SetText(strSetText, fSetTextDuration);
}

// A line normally goes away with the end of its voice (the cutscene clears it) or by its timer. Where the scene is cut short (a player is
// put somewhere else, two scenes overlap, the sound ends without the game noticing) it stayed on the screen for minutes. A line of 60 letters is
// let stay 13 seconds, of 120 letters 20 (the longest voice lines of the game last less).
event Tick(float DeltaTime)
{
	Super.Tick(DeltaTime);
	if (strText == "")
	{
		TextAge = 0.0;
		return;
	}
	TextAge += DeltaTime;
	if (TextAge > 6.0 + 0.12 * float(Len(strText)))
	{
		Log("[SDBG] subtitle: a line stayed " $ string(int(TextAge)) $ " s and is cleared");
		TextAge = 0.0;
		ClearText();
	}
}

function ClearText()
{
	TextAge = 0.0;
	SpeakerName = "";
	Super.ClearText();
}

// Breaks the text into lines no wider than MaxW with the canvas font.
function int Wrap(Canvas Canvas, string S, float MaxW, out array<string> Lines)
{
	local string Line, Word, Probe;
	local int P;
	local float W, H;

	Lines.Length = 0;
	Line = "";
	while (S != "")
	{
		P = InStr(S, " ");
		if (P < 0)
		{
			Word = S;
			S = "";
		}
		else
		{
			Word = Left(S, P);
			S = Mid(S, P + 1);
		}
		if (Line == "")
		{
			Probe = Word;
		}
		else
		{
			Probe = Line $ " " $ Word;
		}
		Canvas.TextSize(Probe, W, H);
		if (W > MaxW && Line != "")
		{
			Lines[Lines.Length] = Line;
			Line = Word;
		}
		else
		{
			Line = Probe;
		}
	}
	if (Line != "")
	{
		Lines[Lines.Length] = Line;
	}
	return Lines.Length;
}

function Put(Canvas Canvas, string S, float X, float Y, Color C)
{
	Canvas.SetDrawColor(C.R, C.G, C.B, C.A);
	Canvas.SetPos(X, Y);
	Canvas.DrawText(S, false);
}

// One piece of a line with its shadow (and outline, when switched on).
function Piece(Canvas Canvas, string S, float X, float Y, float Sh, Color C)
{
	local float D;

	D = float(OutlineSize);
	if (OutlineSize > 0)
	{
		Put(Canvas, S, X - D, Y, OutlineColor);
		Put(Canvas, S, X + D, Y, OutlineColor);
		Put(Canvas, S, X, Y - D, OutlineColor);
		Put(Canvas, S, X, Y + D, OutlineColor);
	}
	if (ShadowOffset > 0.0)
	{
		Canvas.Style = 5;
		Put(Canvas, S, X + Sh, Y + Sh, ShadowColor);
		Canvas.Style = 2;
	}
	Put(Canvas, S, X, Y, C);
}

// The layout of a subtitle (the wrapped lines and their sizes) depends only on the text, the screen size and the font: it is worked out once
// and kept (the word wrapping asks the canvas for the size of a growing string for every word, and every line again for its centring; that
// was repeated on every frame and cost most of a frame while a subtitle was up).
// PrefixLen > 0: the first PrefixLen characters of the first line (the speaker and the colon) get PrefixColor.
function DrawLines(Canvas Canvas, string S, int PrefixLen, Color PrefixColor, float Top, float Height)
{
	local Font Save;
	local byte StyleSave;
	local Color ColorSave;
	local float W, H, X, Y, Sh, Pad;
	local int i, N;
	local string Key;

	if (S == "")
	{
		return;
	}
	Save = Canvas.Font;
	StyleSave = Canvas.Style;
	ColorSave = Canvas.DrawColor;
	Canvas.Style = 2;
	Key = S $ "|" $ string(Canvas.SizeX) $ "|" $ string(Canvas.SizeY) $ "|" $ string(PrefixLen);
	if (Key != CacheKey)
	{
		CacheFrames = 0;
	}
	else
	{
		CacheFrames++;
	}
	// worked out again for the first frames of a text and once after about two seconds, then kept
	if (Key != CacheKey || CacheFrames <= 10 || CacheFrames == 120)
	{
		CacheKey = Key;
		bCacheSmall = false;
		if (fontMed != None)
		{
			Canvas.Font = fontMed;
		}
		N = Wrap(Canvas, S, TextWidth * float(Canvas.SizeX), CLines);
		Canvas.TextSize("Ag", W, H);
		if (fontSmall != None && float(N) * H > Height)
		{
			Canvas.Font = fontSmall;
			bCacheSmall = true;
			N = Wrap(Canvas, S, TextWidth * float(Canvas.SizeX), CLines);
			Canvas.TextSize("Ag", W, H);
		}
		CLineH = H;
		CMaxW = 0.0;
		CWid.Length = N;
		for (i = 0; i < N; i++)
		{
			Canvas.TextSize(CLines[i], W, H);
			CWid[i] = W;
			CMaxW = FMax(CMaxW, W);
		}
		CPrefixW = 0.0;
		if (N > 0 && PrefixLen > 0 && Len(CLines[0]) > PrefixLen && Left(CLines[0], PrefixLen) == Left(S, PrefixLen))
		{
			Canvas.TextSize(Left(CLines[0], PrefixLen), CPrefixW, H);
		}
	}
	if (bCacheSmall && fontSmall != None)
	{
		Canvas.Font = fontSmall;
	}
	else if (fontMed != None)
	{
		Canvas.Font = fontMed;
	}
	N = CLines.Length;
	H = CLineH;
	Sh = FMax(1.0, ShadowOffset * float(Canvas.SizeY) / 540.0);
	Y = Top + (Height - float(N) * H) * 0.5;
	if (BackAlpha > 0 && N > 0)
	{
		Pad = H * 0.3;
		Canvas.Style = 5;
		Canvas.SetDrawColor(0, 0, 0, BackAlpha);
		Canvas.SetPos((float(Canvas.SizeX) - CMaxW) * 0.5 - Pad * 2.0, Y - Pad);
		Canvas.DrawTile(textureBorder, CMaxW + Pad * 4.0, float(N) * H + Pad * 2.0, 1.0, 1.0, 1.0, 1.0);
		Canvas.Style = 2;
	}
	for (i = 0; i < N; i++)
	{
		X = (float(Canvas.SizeX) - CWid[i]) * 0.5;
		if (i == 0 && CPrefixW > 0.0)
		{
			Piece(Canvas, Left(CLines[0], PrefixLen), X, Y, Sh, PrefixColor);
			Piece(Canvas, Mid(CLines[0], PrefixLen), X + CPrefixW, Y, Sh, SubtitleColor);
		}
		else
		{
			Piece(Canvas, CLines[i], X, Y, Sh, SubtitleColor);
		}
		Y += H;
	}
	Canvas.Font = Save;
	Canvas.Style = StyleSave;
	Canvas.DrawColor = ColorSave;
}

function DrawText(Canvas Canvas)
{
	local float H;

	H = TextHeight * float(Canvas.SizeY);
	if (strText != "")
	{
		if (SpeakerName != "")
		{
			DrawLines(Canvas, SpeakerName $ ": " $ strText, Len(SpeakerName) + 2, SpeakerColor, TextTop * float(Canvas.SizeY), H);
		}
		else
		{
			DrawLines(Canvas, strText, 0, SubtitleColor, TextTop * float(Canvas.SizeY), H);
		}
	}
	if (strCutCommentText != "")
	{
		DrawLines(Canvas, strCutCommentText, 0, SubtitleColor, 5.0, H);
	}
}

defaultproperties
{
	SubtitleColor=(R=255,G=255,B=255,A=255)
	OutlineColor=(R=0,G=0,B=0,A=255)
	OutlineSize=0
	ShadowColor=(R=0,G=0,B=0,A=90)
	BackAlpha=110
	ShadowOffset=0.8
	TextTop=0.78
	TextHeight=0.14
	TextWidth=0.7
}

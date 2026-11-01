class EnhancedText extends Object;

// Text that has to cross the network: the engine sends a string as one-byte characters when it can, and the Cyrillic letters of a note or a subtitle
// were lost on the way (the client got "!  !" for a whole line). A string is sent as the four-digit hexadecimal codes of its characters and put
// together again on the other side.

// UCanvas.CreateNativeFont for the canvas it is given (the older Canvas class the mod is compiled against has no such member); the proxy library of the
// game (enhnative) forwards it to the engine. A Windows font with the Cyrillic letters, which the game's canvas fonts do not have.
native(3520) static final function Font NativeFont(Canvas C, string FontName, int Height);

static function string Encode(string S)
{
	local string R, D;
	local int i, c;

	D = "0123456789ABCDEF";
	for (i = 0; i < Len(S); i++)
	{
		c = Asc(Mid(S, i, 1));
		R = R $ Mid(D, (c >> 12) & 15, 1) $ Mid(D, (c >> 8) & 15, 1) $ Mid(D, (c >> 4) & 15, 1) $ Mid(D, c & 15, 1);
	}
	return R;
}

static function string Decode(string E)
{
	local string R, D;
	local int i, c;

	D = "0123456789ABCDEF";
	for (i = 0; i + 3 < Len(E); i += 4)
	{
		c = (InStr(D, Mid(E, i, 1)) << 12) | (InStr(D, Mid(E, i + 1, 1)) << 8) | (InStr(D, Mid(E, i + 2, 1)) << 4) | InStr(D, Mid(E, i + 3, 1));
		R = R $ Chr(c);
	}
	return R;
}

defaultproperties
{
}

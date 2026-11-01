class EnhancedEntry extends GUIButton;

// The entry box of the mod's pages. The stock GUIEditBox draws a frame of a fixed width whatever size it is given (it came out wider than the page of
// the book); a button with the same style is drawn to the size it is given, so this is a button that takes typed text itself: characters
// (Unicode, so the Russian nickname works), Backspace, a blinking cursor while it has the focus, and the text masked for a password.

var string TextStr;       // what has been typed
var bool bMaskText;
var int MaxLen;
var int KeyLogs;
var bool bActive;         // has the focus: a cursor is shown

function InitComponent(GUIController MyController, GUIComponent MyOwner)
{
	Super.InitComponent(MyController, MyOwner);
	OnKeyType = EntryKeyType;
	OnKeyEvent = EntryKeyEvent;
	OnClick = EntryClick;
	OnActivate = EntryActivate;
	OnDeActivate = EntryDeActivate;
	bNeverFocus = false;
}

function bool EntryClick(GUIComponent Sender)
{
	SetFocus(None);
	return true;
}

function bool EntryKeyType(out byte Key, optional string Unicode)
{
	if (KeyLogs < 12)
	{
		KeyLogs++;
		Log("[KEY] type key=" $ string(Key) $ " unicode='" $ Unicode $ "' text='" $ TextStr $ "'");
	}
	if (Unicode != "")
	{
		if (Len(TextStr) < MaxLen)
		{
			TextStr = TextStr $ Unicode;
			Refresh();
		}
		return true;
	}
	if (Key >= 32 && Key != 127)
	{
		if (Len(TextStr) < MaxLen)
		{
			TextStr = TextStr $ Chr(Key);
			Refresh();
		}
		return true;
	}
	return false;
}

function bool EntryKeyEvent(out byte Key, out byte State, float Delta)
{
	if (KeyLogs < 12)
	{
		KeyLogs++;
		Log("[KEY] event key=" $ string(Key) $ " state=" $ string(State));
	}
	if (State == 1 && Key == 8)
	{
		if (Len(TextStr) > 0)
		{
			TextStr = Left(TextStr, Len(TextStr) - 1);
			Refresh();
		}
		return true;
	}
	return false;
}

function string Shown()
{
	local string S;
	local int i;

	if (bMaskText)
	{
		for (i = 0; i < Len(TextStr); i++)
		{
			S = S $ "*";
		}
		return S;
	}
	return TextStr;
}

// The caption is what the button draws: it is kept equal to the text (and the cursor) whenever one of them changes.
function Refresh()
{
	if (bActive)
	{
		Caption = Shown() $ "|";
	}
	else
	{
		Caption = Shown();
	}
}

function SetValue(string S)
{
	TextStr = S;
	Refresh();
}

function EntryActivate()
{
	bActive = true;
	Refresh();
}

function EntryDeActivate()
{
	bActive = false;
	Refresh();
}

defaultproperties
{
	MaxLen=40
}

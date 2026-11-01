class EnhancedKeyTap extends Interaction;

// Typing into the entry boxes of the mod's pages. The characters and keys are offered to the interactions of the viewport as well as to the menu; this one takes
// them for the entry box that is active on the open page (EnhancedBookPage.ActiveEntry) when the menu itself did not handle them, so a typed nickname, address or
// password does not depend on how the menu hands the keys on. It does nothing while no entry box is active.

function Initialize()
{
	bActive = true;
	bVisible = false;
	bRequiresTick = false;
}

function EnhancedEntry Entry()
{
	local GUIController GC;

	if (ViewportOwner == None)
	{
		return None;
	}
	GC = GUIController(ViewportOwner.GUIController);
	if (GC == None || GC.ActivePage == None || EnhancedBookPage(GC.ActivePage) == None)
	{
		return None;
	}
	return EnhancedBookPage(GC.ActivePage).ActiveEntry();
}

function bool KeyType(out Interactions.EInputKey Key, optional string Unicode)
{
	local EnhancedEntry E;
	local byte B;

	E = Entry();
	if (E == None)
	{
		return false;
	}
	B = byte(int(Key));
	return E.EntryKeyType(B, Unicode);
}

function bool KeyEvent(out Interactions.EInputKey Key, out Interactions.EInputAction Action, float Delta)
{
	local EnhancedEntry E;
	local byte B, St;

	E = Entry();
	if (E == None)
	{
		return false;
	}
	B = byte(int(Key));
	St = byte(int(Action));
	return E.EntryKeyEvent(B, St, Delta);
}

defaultproperties
{
	bActive=true
}

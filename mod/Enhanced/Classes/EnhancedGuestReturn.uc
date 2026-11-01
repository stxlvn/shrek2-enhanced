class EnhancedGuestReturn extends SHReturnToFEYesNo
	config
	instanced;

// "Return to the main menu?" of the game's own pause menu for a joined player. The stock page zeroes the host hero's bonuses, saves and has the server
// load the front-end level; a joined player just leaves the session: the front-end level is opened as a plain menu.

function bool InternalOnClick(GUIComponent Sender)
{
	local MenuBook Mb;

	if (Sender == btnYes)
	{
		PlayerOwner().PlaySound(sfxClick);
		foreach PlayerOwner().AllActors(Class'GUI.MenuBook', Mb)
		{
			Mb.Destroy();
		}
		Controller.CloseAll(false);
		PlayerOwner().ConsoleCommand("open " $ Class'Enhanced.EnhancedGame'.static.PlainMenuURL());
	}
	else
	{
		PlayerOwner().PlaySound(sfxClick);
		Controller.ReplaceMenu("Enhanced.EnhancedGuestControls");
	}
	return true;
}

defaultproperties
{
}

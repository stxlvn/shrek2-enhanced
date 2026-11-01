class EnhancedGuestQuit extends SHInGamePageYesNo
	config
	instanced;

// "Quit the game?" of the game's own pause menu for a joined player: No goes back to the page of a joined player (the stock page would open the host's).

function bool InternalOnClick(GUIComponent Sender)
{
	PlayerOwner().PlaySound(sfxClick);
	if (Sender == btnYes)
	{
		PlayerOwner().ConsoleCommand("exit");
	}
	else
	{
		Controller.ReplaceMenu("Enhanced.EnhancedGuestControls");
	}
	return true;
}

defaultproperties
{
}

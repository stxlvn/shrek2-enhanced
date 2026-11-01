class EnhancedGuestControls extends ShInGameMenuControls
	config
	instanced;

// The page with the buttons of the game's own pause menu, for a joined player: the same page, without the two buttons that belong to the host's own
// game (the wanted posters he has collected and the saved game he loads), and with "main menu" and "quit" leading to the pages of a joined player.

function InitComponent(GUIController MyController, GUIComponent MyOwner)
{
	local float T;

	Super.InitComponent(MyController, MyOwner);
	btnWanterPoster.bVisible = false;
	btnWanterPoster.bNeverFocus = true;
	btnLoadSaved.bVisible = false;
	btnLoadSaved.bNeverFocus = true;
	T = btnPlay.WinTop + btnPlay.WinHeight + MenuControlsBut_VGAP;
	btnOptions.WinTop = T;
	T += btnOptions.WinHeight + MenuControlsBut_VGAP;
	btnMainMenu.WinTop = T;
	T += btnMainMenu.WinHeight + MenuControlsBut_VGAP;
	btnQuit.WinTop = T;
}

function bool InternalOnClick(GUIComponent Sender)
{
	if (Sender == btnMainMenu)
	{
		PlayerOwner().PlaySound(sfxClick);
		Controller.ReplaceMenu("Enhanced.EnhancedGuestReturn");
		return true;
	}
	if (Sender == btnQuit)
	{
		PlayerOwner().PlaySound(sfxClick);
		Controller.ReplaceMenu("Enhanced.EnhancedGuestQuit");
		return true;
	}
	return Super.InternalOnClick(Sender);
}

defaultproperties
{
}

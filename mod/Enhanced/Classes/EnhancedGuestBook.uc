class EnhancedGuestBook extends ShInGameMenuGUIPage
	config
	instanced;

// The game's own pause menu (the book that opens in front of the camera, then the page with the buttons) for a joined player. The stock page takes the
// camera and the book's place from the host's hero controller (KWHeroController) and pauses the game; a joined player has neither, so this page does
// the same steps with the camera of the joined player's own controller (held where it was when Escape was pressed, turned only as the player turns; the controller keeps the book in front of it) and does not pause anything.
// Everything else (the book, its turning, the buttons and their pictures) is the game's own.

function InitComponent(GUIController MyController, GUIComponent MyOwner)
{
	local EnhancedPlayerController P;

	Super(SHGUIPage).InitComponent(MyController, MyOwner);
	OnDraw = Internal_OnDraw;
	OnClose = InternalOnClose;
	OnKeyEvent = InternalOnKeyEvent;
	blackbox = Texture(DynamicLoadObject("storybookanimTX.black_box", Class'Engine.Texture'));
	P = EnhancedPlayerController(PlayerOwner());
	FEActor1 = PlayerOwner().Spawn(Class'GUI.MenuBook');
	FEActor1.SetRotation(MenuBookRotation);
	FEActor1.GotoState('OpenIdle');
	FEActor1.pc = PlayerOwner();
	if (P != None)
	{
		P.MenuBookActor = FEActor1;
		P.UpdateMenuBook();
	}
}

function InternalOnClose(optional bool bCanceled)
{
	local EnhancedPlayerController P;

	P = EnhancedPlayerController(PlayerOwner());
	if (P != None)
	{
		P.MenuClosed();
	}
	Super.InternalOnClose(bCanceled);
}

defaultproperties
{
}

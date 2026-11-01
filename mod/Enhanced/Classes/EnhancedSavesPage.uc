class EnhancedSavesPage extends ShGame.ShFEGUIPage;

// The save slots of the stock front-end page, moved to a page of their own: click a slot to start or continue,
// Delete to remove a save, Back to return to the main menu. Settings and Exit are not on this page.

var GUIButton btnBack;

function InitComponent(GUIController MyController, GUIComponent MyOwner)
{
	Super.InitComponent(MyController, MyOwner);
	btnOptions.bVisible = false;
	btnQuit.bVisible = false;
	btnBack = GUIButton(AddComponent("GUI.GUIButton"));
	btnBack.StyleName = "SHBTNOptionsStyle";
	btnBack.Style = Controller.GetStyle("SHBTNOptionsStyle");
	btnBack.Caption = Localize("Menu", "Back", "Enhanced");
	btnBack.bNeverFocus = true;
	btnBack.OnClick = InternalOnClick;
	RemapComponents();
	btnDelete.WinTop = btnOptions.WinTop;
	btnBack.WinLeft = btnOptions.WinLeft;
	btnBack.WinWidth = Mb.controlBut_W;
	btnBack.WinHeight = Mb.controlBut_H;
	btnBack.WinTop = btnDelete.WinTop + btnDelete.WinHeight + Mb.controlBut_VGAP;
	lblStartGame.Caption = Localize("Menu", "SavesTitle", "Enhanced");
}

// ---- The slots show the mod's checkpoint records ("slot0" .. "slot5", written by EnhancedGame.FinishCheckpoint), not the stock save files ----
// The stock page asks the native SaveGameExists about a file the mod never writes (the game's own save is out of the loop), so every cell stayed empty.

function EnhancedSaveData SlotRecord(int i)
{
	return new(None, "slot" $ string(i)) Class'Enhanced.EnhancedSaveData';
}

function bool SlotUsed(int i)
{
	return SlotRecord(i).Map != "";
}

function GUIButton SlotButton(int i)
{
	switch (i)
	{
		case 0:
			return ButtonSaveGame0;
		case 1:
			return ButtonSaveGame1;
		case 2:
			return ButtonSaveGame2;
		case 3:
			return ButtonSaveGame3;
		case 4:
			return ButtonSaveGame4;
	}
	return ButtonSaveGame5;
}

function SetSaveButtonText()
{
	local int i;
	local EnhancedSaveData R;

	for (i = 0; i < 6; i++)
	{
		if (SlotUsed(i))
		{
			R = SlotRecord(i);
			SlotButton(i).Caption = string(i + 1);
			SlotButton(i).Hint = R.Stamp @ R.Map;
		}
	}
}

function SetSaveButtonImage()
{
	local int i;
	local string Image;
	local GUIStyles S;

	for (i = 0; i < 6; i++)
	{
		if (!SlotUsed(i))
		{
			continue;
		}
		Image = ShHeroController(PlayerOwner()).GetPropertyText("Save" $ string(i) $ "Image");
		if (Image == "")
		{
			Image = "storybookanimTX.box_button";
		}
		S = Controller.GetStyle("SHBTN" $ string(i) $ "SaveStyle");
		if (S == None)
		{
			continue;
		}
		S.Images[0] = Texture(DynamicLoadObject(Image, Class'Engine.Texture'));
		S.Images[1] = Texture(DynamicLoadObject(Image $ "_hili", Class'Engine.Texture'));
		S.Images[2] = Texture(DynamicLoadObject(Image $ "_hili", Class'Engine.Texture'));
		S.Images[3] = Texture(DynamicLoadObject(Image, Class'Engine.Texture'));
		S.Images[4] = Texture(DynamicLoadObject(Image, Class'Engine.Texture'));
	}
}

function bool DoesASavedGameExist()
{
	local int i;

	for (i = 0; i < 6; i++)
	{
		if (SlotUsed(i))
		{
			return true;
		}
	}
	return false;
}

function DisableOptionalButtons()
{
	local int i;

	btnDelete.MenuStateChange(MSAT_Disabled);
	btnOptions.MenuStateChange(MSAT_Disabled);
	for (i = 0; i < 6; i++)
	{
		if (!SlotUsed(i))
		{
			SlotButton(i).MenuStateChange(MSAT_Disabled);
		}
	}
}

// -1 when the sender is not one of the six cells.
function int SlotOf(GUIComponent Sender)
{
	local int i;

	for (i = 0; i < 6; i++)
	{
		if (Sender == SlotButton(i))
		{
			return i;
		}
	}
	return -1;
}

function bool SlotClick(int n)
{
	local EnhancedSaveData R;

	GameSlot = n;
	PlayerOwner().SetPropertyText("iSaveSlotID", string(n));
	SaveConfig();
	if (SlotUsed(n))
	{
		if (AmDeleteing)
		{
			R = SlotRecord(n);
			R.Map = "";
			R.Stamp = "";
			R.Keys.Length = 0;
			R.Values.Length = 0;
			R.Heroes.Length = 0;
			R.SaveConfig();
			PlayerOwner().PlaySound(sfxClick);
			AmDeleteing = false;
			Controller.ReplaceMenu("Enhanced.EnhancedSavesPage");
			return true;
		}
		R = SlotRecord(n);
		PlayerOwner().StopAllMusic(0.0);
		UnPause();
		PlayerOwner().PlaySound(sfxClick);
		PlayerOwner().Level.ServerTravel(R.Map $ "?Game=Enhanced.EnhancedGame?EnhLoad=slot" $ string(n), false);
		Controller.CloseAll(false);
		return true;
	}
	if (AmDeleteing)
	{
		return true;
	}
	ShHeroController(PlayerOwner()).ShrekFirstStrengthPotion = 0;
	ShHeroController(PlayerOwner()).DonkeyFirstStrengthPotion = 0;
	ShHeroController(PlayerOwner()).SteedFirstStrengthPotion = 0;
	ShHeroController(PlayerOwner()).PibFirstStrengthPotion = 0;
	ShHeroController(PlayerOwner()).HumanFirstStrengthPotion = 0;
	ShHeroController(PlayerOwner()).SaveConfig();
	PlayerOwner().PlaySound(sfxClick);
	PlayerOwner().StopAllMusic(0.0);
	PlayerOwner().Level.ServerTravel(FirstLevel, false);
	Controller.CloseAll(false);
	return true;
}

function bool InternalOnClick(GUIComponent Sender)
{
	if (Sender == btnBack)
	{
		PlayerOwner().PlaySound(sfxClick);
		Mb.NextMenuPage = "Enhanced.EnhancedFEPage";
		Mb.GotoState('TurnPageBackward');
		Controller.CloseMenu(true);
		return true;
	}
	if (Sender == btnOptions || Sender == btnQuit)
	{
		return true;
	}
	if (SlotOf(Sender) >= 0)
	{
		return SlotClick(SlotOf(Sender));
	}
	return Super.InternalOnClick(Sender);
}

// Tests only: presses a button by name.
function bool TestClick(string What)
{
	if (What ~= "back")
	{
		return InternalOnClick(btnBack);
	}
	return false;
}

defaultproperties
{
}

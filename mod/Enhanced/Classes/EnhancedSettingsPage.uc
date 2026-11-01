class EnhancedSettingsPage extends EnhancedBookPage;

// The Settings of the book without the tabs: this page has three big buttons, one for each group (controls, sound, video); each opens the stock
// Settings page showing that group only, with everything of it on one page (see EnhancedHeroController.FixSettingsPage).

var GUIButton btnGame, btnSound, btnVideo, btnBack;
var GUILabel lblTitle;

function InitComponent(GUIController MyController, GUIComponent MyOwner)
{
	Super.InitComponent(MyController, MyOwner);
	lblTitle = MakeLabel(true);
	lblTitle.Caption = Loc("SettingsTitle");
	btnGame = MakeButton(Loc("SetGame"));
	btnSound = MakeButton(Loc("SetSound"));
	btnVideo = MakeButton(Loc("SetVideo"));
	btnBack = MakeButton(Loc("Back"));
	RemapComponents();
	Place(lblTitle, 0.20, 0.05);
	Place(btnGame, 0.25);
	Place(btnSound, 0.34);
	Place(btnVideo, 0.43);
	Place(btnBack, 0.58);
}

function OpenGroup(string Group)
{
	if (EnhancedHeroController(PlayerOwner()) != None)
	{
		EnhancedHeroController(PlayerOwner()).SettingsTab = Group;
	}
	TurnTo("SHGame.Tab_Options", true);
}

function bool InternalOnClick(GUIComponent Sender)
{
	if (Sender == btnGame)
	{
		OpenGroup("game");
	}
	else if (Sender == btnSound)
	{
		OpenGroup("sound");
	}
	else if (Sender == btnVideo)
	{
		OpenGroup("video");
	}
	else if (Sender == btnBack)
	{
		TurnTo("Enhanced.EnhancedFEPage", false);
	}
	return true;
}

// Tests only: presses a button by name.
function bool TestClick(string What)
{
	if (What ~= "game")
	{
		return InternalOnClick(btnGame);
	}
	if (What ~= "sound")
	{
		return InternalOnClick(btnSound);
	}
	if (What ~= "video")
	{
		return InternalOnClick(btnVideo);
	}
	return false;
}

defaultproperties
{
}

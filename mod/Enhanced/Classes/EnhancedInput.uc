class EnhancedInput extends PlayerInput within EnhancedPlayerController
	transient
	config(User);

// Player two's input. The stock Unreal PlayerInput sends the vertical mouse to "walk" unless the free look key is held, so the
// camera of a joined client could not look up or down, and it knows nothing of the arrow keys the game binds (aArrowRight/aArrowUp).
// This is the stock PlayerInput with the game's own choices: the mouse always looks, the arrow keys turn and walk.
event PlayerInput(float DeltaTime)
{
	local float FOVScale, MouseScale;

	Outer.BotInput(DeltaTime);
	bEdgeForward = bWasForward ^^ (Outer.aBaseY > 0);
	bEdgeBack = bWasBack ^^ (Outer.aBaseY < 0);
	bEdgeLeft = bWasLeft ^^ (Outer.aStrafe < 0);
	bEdgeRight = bWasRight ^^ (Outer.aStrafe > 0);
	bWasForward = Outer.aBaseY > 0;
	bWasBack = Outer.aBaseY < 0;
	bWasLeft = Outer.aStrafe < 0;
	bWasRight = Outer.aStrafe > 0;

	FOVScale = Outer.DesiredFOV * 0.01111;
	MouseScale = MouseSensitivity * FOVScale;
	Outer.aMouseX = SmoothMouse(Outer.aMouseX * MouseScale, DeltaTime, Outer.bXAxis, 0);
	Outer.aMouseY = SmoothMouse(Outer.aMouseY * MouseScale, DeltaTime, Outer.bYAxis, 1);
	Outer.aMouseX = AccelerateMouse(Outer.aMouseX);
	Outer.aMouseY = AccelerateMouse(Outer.aMouseY);

	if (Outer.aArrowRight != 0)
	{
		Outer.aTurn = Outer.aArrowRight;
	}
	if (Outer.aArrowUp != 0)
	{
		Outer.aForward = Outer.aArrowUp * 48;
	}

	Outer.aLookUp *= FOVScale;
	Outer.aTurn *= FOVScale;

	if (Outer.bStrafe != 0)
	{
		Outer.aStrafe += Outer.aBaseX * 7.5 + Outer.aMouseX;
	}
	else
	{
		Outer.aTurn += Outer.aBaseX * FOVScale + Outer.aMouseX;
	}
	Outer.aBaseX = 0;

	if (bInvertMouse)
	{
		Outer.aLookUp -= Outer.aMouseY;
	}
	else
	{
		Outer.aLookUp += Outer.aMouseY;
	}

	if (Outer.bFreeLook != 0)
	{
		Outer.aLookUp += 0.5 * Outer.aBaseY * FOVScale;
	}
	else
	{
		Outer.aForward += Outer.aBaseY;
	}
	Outer.aBaseY = 0;

	Outer.LastAT = Outer.aTurn;
	Outer.LastAL = Outer.aLookUp;
	Outer.LastAF = Outer.aForward;
	Outer.HandleWalking();
}

defaultproperties
{
}

class ObsMutator extends Mutator
	config(User);

// Test observer for the original game (no mod): writes the position and speed of the player's pawn while he is not standing, so the jump of the
// stock game can be measured. Added with the URL option ?Mutator=Obs.ObsMutator.

var float T;
var bool bNamed, bReady;
var float NextWalkLog, ReadyAt;
var bool bVolLogged;
var config float MenuAt;     // [Obs.ObsMutator] MenuAt=<seconds> in User.ini: the pause menu is opened that long after the hero is ready
var bool bMenuDone, bMenuRead, bCamLogged;
var float NextStrafeLog;
var float NextBanditLog;
var bool bBanditShot;        // one engine picture when the bandit who talks is near the hero     // URL option ?ObsBandit=1: every 3 s the state of every bandit-like pawn (hidden, animation, distance to the hero)

event Tick(float DeltaTime)
{
	local Controller C;
	local Pawn P, Q;
	local PhysicsVolume V;
	local name N0;
	local float F0, R0;

	for (C = Level.ControllerList; C != None; C = C.NextController)
	{
		if (PlayerController(C) != None && C.Pawn != None)
		{
			P = C.Pawn;
			break;
		}
	}
	if (P == None)
	{
		return;
	}
	if (!bNamed)
	{
		bNamed = true;
		Log("[OBS] hero is " $ string(P.Class) $ " controller " $ string(C.Class) $ " state " $ string(C.GetStateName()));
	}
	if (!bReady && string(C.GetStateName()) == "PlayerWalking")
	{
		bReady = true;
		ReadyAt = T;
		Log("[OBS3] water: instance WaterGroundSpeed=" $ P.GetPropertyText("WaterGroundSpeed") $ " Quicksand=" $ P.GetPropertyText("QuicksandGroundSpeed") $ " GroundSpeed=" $ string(P.GroundSpeed) $ " GroundRunSpeed=" $ P.GetPropertyText("GroundRunSpeed") $ " WaterSpeed=" $ string(P.WaterSpeed) $ " | class defaults: shpawn " $ string(Class'SHGame.shpawn'.default.WaterGroundSpeed) $ " Shrek " $ string(Class'SHGame.Shrek'.default.WaterGroundSpeed) $ " Donkey " $ string(Class'SHGame.Donkey'.default.WaterGroundSpeed) $ " PIB " $ string(Class'SHGame.PIB'.default.WaterGroundSpeed));
		Log("[OBS] READY pawn " $ string(P) $ " z=" $ string(P.Location.Z));
	}
	T += DeltaTime;
	if (T >= NextBanditLog && InStr(Level.GetLocalURL(), "ObsBandit=") >= 0)
	{
		NextBanditLog = T + 3.0;
		foreach AllActors(Class'Engine.Pawn', Q)
		{
			if (InStr(string(Q.Class), "Bandit") >= 0 || InStr(string(Q.Class), "WheelStealer") >= 0)
			{
				N0 = 'None';
				Q.GetAnimParams(0, N0, F0, R0);
				Log("[OBSB] t=" $ string(T) $ " " $ string(Q.Name) $ " cls=" $ string(Q.Class) $ " hid=" $ string(int(Q.bHidden)) $ " dt=" $ string(int(Q.DrawType)) $ " anim=" $ string(N0) $ " frame=" $ string(F0)
					$ " state=" $ string(Q.GetStateName()) $ " ctl=" $ string(Q.Controller) $ " dist=" $ string(int(VSize(Q.Location - P.Location))) $ " loc=" $ string(int(Q.Location.X)) $ "," $ string(int(Q.Location.Y)) $ "," $ string(int(Q.Location.Z))
					$ " hero=" $ string(int(P.Location.X)) $ "," $ string(int(P.Location.Y)) $ "," $ string(int(P.Location.Z)));
				if (!bBanditShot && InStr(string(Q.Class), "BanditSpecial") >= 0 && VSize(Q.Location - P.Location) < 1800.0 && T > 4.0)
				{
					bBanditShot = true;
					PlayerController(C).ConsoleCommand("shot");
					Log("[OBSB] picture taken at t=" $ string(T) $ " with " $ string(Q.Name) $ " at " $ string(int(VSize(Q.Location - P.Location))) $ " units");
				}
			}
		}
	}
	if (bReady && !bCamLogged && KWHeroController(C) != None)
	{
		bCamLogged = true;
		Log("[OBS5] camera: bUseBaseCam=" $ KWHeroController(C).GetPropertyText("bUseBaseCam") $ " Camera=" $ string(KWHeroController(C).Camera) $ " vCameraStart=" $ string(KWHeroController(C).vCameraStart()) $ " rCameraRot=" $ string(KWHeroController(C).rCameraRot()) $ " controller.Location=" $ string(C.Location) $ " Rotation=" $ string(C.Rotation) $ " class=" $ string(C.Class) $ " menuOption=" $ string(MenuAt));
	}
	if (MenuAt > 0.0 && !bMenuDone && bReady && T > ReadyAt + MenuAt && PlayerController(C) != None)
	{
		bMenuDone = true;
		Log("[OBS] opening the pause menu");
		PlayerController(C).ConsoleCommand("ShowInGameMenu");
	}
	if (bReady && !bVolLogged)
	{
		bVolLogged = true;
		foreach AllActors(Class'Engine.PhysicsVolume', V)
		{
			if (V.bWaterVolume)
			{
				Log("[OBS4] water volume " $ string(V) $ " at " $ string(V.Location) $ " fluidfriction=" $ string(V.FluidFriction) $ " groundfriction=" $ string(V.GroundFriction) $ " hero at " $ string(P.Location));
			}
		}
	}
	if (bReady && T > ReadyAt + 4.0 && T < ReadyAt + 400.0 && PlayerController(C) != None)
	{
		if (InStr(Level.GetLocalURL(), "ObsStrafe=") >= 0)
		{
			// test of the D / A keys: 3 s right, 3 s left (the axis the keys feed), then 3 s forward
			if (T < ReadyAt + 7.0)
			{
				PlayerController(C).aStrafe = 1200.0;
			}
			else if (T < ReadyAt + 10.0)
			{
				PlayerController(C).aStrafe = -1200.0;
			}
			else if (T < ReadyAt + 13.0)
			{
				PlayerController(C).aBaseY = 1200.0;
			}
			if (T >= NextStrafeLog)
			{
				NextStrafeLog = T + 0.5;
				Log("[OBS5] t=" $ string(T - ReadyAt) $ " pos=" $ string(P.Location) $ " vel=" $ string(P.Velocity) $ " yaw=" $ string(P.Rotation.Yaw & 65535) $ " aStrafe=" $ string(PlayerController(C).aStrafe) $ " aBaseY=" $ string(PlayerController(C).aBaseY) $ " aForward=" $ string(PlayerController(C).aForward));
			}
		}
		else
		{
			PlayerController(C).aBaseY = 1200.0;       // walk forward (the same axis the W key feeds)
		}
	}
	if (T >= NextWalkLog)
	{
		NextWalkLog = T + 0.5;
		Log("[OBS2] t=" $ string(T) $ " z=" $ string(P.Location.Z) $ " speed=" $ string(int(VSize(P.Velocity) - Abs(P.Velocity.Z) * 0.0)) $ " gs=" $ string(int(P.GroundSpeed)) $ " phys=" $ string(int(P.Physics)) $ " water=" $ string(P.PhysicsVolume.bWaterVolume) $ " inWater=" $ P.GetPropertyText("bInWater") $ " base=" $ string(P.Base) $ " vol=" $ string(P.PhysicsVolume) $ " state=" $ string(C.GetStateName()));
	}
	if (P.Physics != PHYS_Walking || P.Velocity.Z != 0.0)
	{
		Log("[OBS] t=" $ string(T) $ " z=" $ string(P.Location.Z) $ " vz=" $ string(P.Velocity.Z) $ " phys=" $ string(int(P.Physics)) $ " state=" $ string(C.GetStateName()));
	}
}

defaultproperties
{
}

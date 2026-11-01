class EnhancedDonkey extends ShGame.Donkey;

// A guest's Donkey (the hero of the level when the host plays him). The stock hero refuses every hit that comes from another hero, and a hero's attacks skip
// "friends". With friendly fire switched on (EnhancedGame.FriendlyFire > 0, a damage scale) hits between the
// two Shreks go through at that scale; with it off (the default) nothing changes.

function float FFScale()
{
	local EnhancedGame G;

	G = EnhancedGame(Level.Game);
	if (G == None)
	{
		return 0.0;
	}
	return G.FriendlyFire;
}

function TakeDamage(int Damage, Pawn instigatedBy, Vector HitLocation, Vector Momentum, Class<DamageType> DamageType)
{
	local float F;

	if (instigatedBy != None && instigatedBy != Self && instigatedBy.IsA('ShHeroPawn'))
	{
		F = FFScale();
		Damage = int(float(Damage) * F);
		if (F <= 0.0 || Damage <= 0)
		{
			return;
		}
		// without an instigator the stock hero check does not refuse the hit
		Super.TakeDamage(Damage, None, HitLocation, Momentum, DamageType);
		return;
	}
	Super.TakeDamage(Damage, instigatedBy, HitLocation, Momentum, DamageType);
}

// The other Shrek is hit with the damage scaled and no instigator, for the same reason.
function HitSHPawn(Actor HitActor, int HitDamage, array<Sound> SoundArray, Class<DamageType> DamageType)
{
	local float F;

	if (HitActor.IsA('ShHeroPawn'))
	{
		F = FFScale();
		if (F <= 0.0)
		{
			return;
		}
		HitActor.TakeDamage(int(float(HitDamage) * F), None, vect(0.0, 0.0, 0.0), vect(0.0, 0.0, 0.0), DamageType);
		return;
	}
	Super.HitSHPawn(HitActor, HitDamage, SoundArray, DamageType);
}

defaultproperties
{
	bRotateToDesired=False
}

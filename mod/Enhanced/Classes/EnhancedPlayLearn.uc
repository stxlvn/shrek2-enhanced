class EnhancedPlayLearn extends Object
	config(EnhancedPlayLearn);

// What the play bot has learned by playing (System\EnhancedPlayLearn.ini), kept across runs:
//   Climbs=<map>: sx sy sz yaw ex ey ez
// a place where a hero's climb (the game's Mount, KWPawn.Mount) began, the way the hero faced, and where it ended on top. The game takes a ledge only
// from some places and ways (the swamp's stump: from -13852,-1914 facing yaw 28773, tests lc13/lc14; runs nav6/nav7 tried it from other sides and
// never climbed), so the bot's map gets a climb only where one was seen. A climb the bot sees while it plays is added here.

var config array<string> Climbs;

defaultproperties
{
}

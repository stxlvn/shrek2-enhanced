class EnhancedSaveData extends Object
	config(EnhancedSave)
	PerObjectConfig;

// One checkpoint record. Replaces the stock save, which wrote the whole level package.
// PerObjectConfig: every slot is its own section "[<slot> EnhancedSaveData]" of EnhancedSave.ini.

var config int Format;
var config string Map;            // level package, for example 1_Shreks_Swamp
var config string GameState;      // KWGame.CurrentGameState, for example GSTATE000
var config string Checkpoint;     // name of the checkpoint that made the record
var config string Stamp;          // wall clock time of the record
var config array<string> Keys;    // PersistentStore, pairs of Keys[i] / Values[i]
var config array<string> Values;
var config int Coins;             // the shared inventory
var config string Title;          // the lobby name of the co-op game
var config string Players;        // the nicknames, joined with &
var config string Session;        // the id of the co-op game (one per playthrough)
var config array<string> Heroes;  // one entry per player: "x,y,z,yaw,health"

defaultproperties
{
	Format=1
}

class EnhancedPlayRoutes extends Object
	config(EnhancedPlay);

// The play test's walkthroughs (EnhancedPlayBot): System\EnhancedPlay.ini, section [Enhanced.EnhancedPlayRoutes], one line per step:
//   Steps=<map>: <step>
// in the order they are done. Steps:
//   goto X Y Z            walk there (jumps when it makes no headway; after a long stall the bot is put there, logged as HOP)
//   touch <ActorName>     walk to that actor of the map (a trigger, a cutscene mark)
//   fight <Class> [Prop=Value] [max N]   hit the nearest live actor of that class (with that property text) until none is left within 3000 units
//   pick <ActorName|Class>    walk up to it and press the action key (Fire): a hero picks up a prop he faces
//   carry X Y Z           walk there holding it, then press the action key (it is thrown or put down)
//   use                   the action key once
//   jump | doublejump     the jump key (twice for a double jump)
//   wait <seconds>        stand still
//   waitgone <ActorName>  wait until that actor is gone or hidden
//   exit                  walk the level's breadcrumbs to the exit (also what is done when the steps are over)
// The file is read when a level starts: a change needs no new build, only a new start of the level.

var config array<string> Steps;

defaultproperties
{
}

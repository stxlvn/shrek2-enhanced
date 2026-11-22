class EnhancedNav extends Object;

// The play test's map of where a hero can walk on this level, made with the engine's own traces (owner, 2026-11-22, watching the bot walk at
// guessed points through walls: "they do who knows what"). The level files give the actors but no shape of the ground, so the shape is felt out in
// the running game: from the hero's place, the next cell in each of 8 directions gets a floor under it (a trace down, a walkable slope) and a free way
// for a box of the hero's size from here to there. A rise up to 35 units is a walk, up to JumpUp a jump, up to DJumpUp a double jump; a step down up to
// MaxDrop is a drop (a hero survives falls up to 768). Cells near briars and other hazards are left out. The flood fill and the search for a way (A*)
// run a part per frame. What is not walking (bounce pads, ledges to climb, vines, lifts) is not in this map: across those the bot is put there and it
// is logged as the bot's limit.

var float Cell, R, H, JumpUp, DJumpUp, MaxDrop, OX, OY;
var int DX[8], DY[8];
var array<float> NX, NY, NZ;
var array<int> NIX, NIY, NFirst, NCount, NNext;
var array<int> HashHead;          // bucket -> first node + 1
var array<int> ETo;
var array<byte> EKind;            // 0 walk, 1 jump, 2 double jump, 3 drop, 4 climb, 8 a jump over a gap, 9 blocked (the hero could not get through it)
var float MaxMount;               // the game's Pawn.MaxMountHeight (heroes: 256)
var array<Vector> MountVols;
var PlayerController Tracer;      // whose traces make the map
var array<byte> NWater;           // 1 water (the hero wades slowly: the floor's material is water, ShHeroController.PlayerTick), 2 quicksand
// Ways that are not walking (owner, 2026-11-22: "teach it to jump on the lily pads"), kept apart from the cells' own ways and chained per cell:
// 1 a jump onto a lily pad or from one to the next (lily pads are actors: the world traces of the map do not see them), 5 a bounce pad (stand on it
// and jump: the landing fires it, the hero flies to its BounceTarget), 6 a vine (a double jump up to its first ShimmyNode, then sideways along it
// to its last one). Made again each time the map grows.
var array<int> SFrom, STo, SNext, SHead;
var array<byte> SKind;
var array<Actor> SVia;
var array<Vector> SPos;           // a learned climb (kind 7): where it begins
var array<int> SYaw;              // and the way the hero faces
var string MapName;
var array<Actor> Lilies;      // where the level's MountVolumes are (a ledge of the level's own geometry is climbed only inside one)
var int Expanded;                 // nodes below this index have their ways out
var bool bBaking, bBaked;
var int Traces, MaxNodes;
var float BakeTime;
var array<Actor> Hazards;
var array<float> HazardR;

// the search
var array<float> GS;
var array<int> From, Stamp, Shut;
var array<int> HeapN;
var array<float> HeapF;
var int SearchId, SStart, SGoal, SPops;
var bool bSearching;
var array<int> Path;

function Init(Pawn P)
{
	local int i;

	Cell = 48.0;
	R = FMax(12.0, P.CollisionRadius);
	H = FMax(16.0, P.CollisionHeight);
	JumpUp = 55.0;
	DJumpUp = 130.0;
	MaxDrop = 250.0;     // a hero on a 320 drop went down (h6, the Hunt); players do not jump into deep ravines
	MaxMount = 256.0;
	MaxNodes = 150000;
	DX[0] = 1;  DY[0] = 0;
	DX[1] = -1; DY[1] = 0;
	DX[2] = 0;  DY[2] = 1;
	DX[3] = 0;  DY[3] = -1;
	DX[4] = 1;  DY[4] = 1;
	DX[5] = 1;  DY[5] = -1;
	DX[6] = -1; DY[6] = 1;
	DX[7] = -1; DY[7] = -1;
	HashHead.Length = 0;
	HashHead.Length = 65536;
	for (i = 0; i < 65536; i++)
	{
		HashHead[i] = 0;
	}
}

function int CellOf(float V, float O)
{
	return int((V - O) / Cell + 100000.5) - 100000;
}

function int Bucket(int ix, int iy)
{
	return ((ix * 73856093) ^ (iy * 19349663)) & 65535;
}

// the node of cell ix,iy whose floor is within 30 units of Z, or -1
function int FindNode(int ix, int iy, float Z)
{
	local int n;

	n = HashHead[Bucket(ix, iy)] - 1;
	while (n >= 0)
	{
		if (NIX[n] == ix && NIY[n] == iy && Abs(NZ[n] - Z) < 30.0)
		{
			return n;
		}
		n = NNext[n] - 1;
	}
	return -1;
}

function int AddNode(int ix, int iy, float Z)
{
	local int n, b;

	n = NX.Length;
	NX[n] = OX + float(ix) * Cell;
	NY[n] = OY + float(iy) * Cell;
	NZ[n] = Z;
	NIX[n] = ix;
	NIY[n] = iy;
	NFirst[n] = 0;
	NCount[n] = 0;
	NWater[n] = 0;
	if (Tracer != None && Tracer.Pawn != None && KWPawn(Tracer.Pawn) != None)
	{
		b = int(KWPawn(Tracer.Pawn).TraceMaterial(vect(1, 0, 0) * NX[n] + vect(0, 1, 0) * NY[n] + vect(0, 0, 1) * (Z + 30.0), 60.0));
		if (b == 6)
		{
			NWater[n] = 1;
		}
		else if (b == 14)
		{
			NWater[n] = 2;
		}
	}
	b = Bucket(ix, iy);
	NNext[n] = HashHead[b];
	HashHead[b] = n + 1;
	return n;
}

function bool NearHazard(Vector L)
{
	local int i;
	local Vector D;

	for (i = 0; i < Hazards.Length; i++)
	{
		if (Hazards[i] == None || Hazards[i].bDeleteMe || Hazards[i].bHidden)
		{
			continue;
		}
		D = Hazards[i].Location - L;
		if (Abs(D.Z) > 150.0)
		{
			continue;
		}
		D.Z = 0;
		if (VSize(D) < HazardR[i])
		{
			return true;
		}
	}
	return false;
}

// starts the map from the hero's place (an old map is dropped)
function StartBake(PlayerController PC)
{
	local Actor A;
	local Vector HL, HN, L;

	NX.Length = 0;
	NY.Length = 0;
	NZ.Length = 0;
	NIX.Length = 0;
	NIY.Length = 0;
	NFirst.Length = 0;
	NCount.Length = 0;
	NNext.Length = 0;
	NWater.Length = 0;
	ETo.Length = 0;
	EKind.Length = 0;
	Path.Length = 0;
	Tracer = PC;
	MapName = string(PC.Level);
	MapName = Left(MapName, InStr(MapName, "."));
	Init(PC.Pawn);
	Expanded = 0;
	Traces = 0;
	BakeTime = 0.0;
	bBaked = false;
	bSearching = false;
	Hazards.Length = 0;
	HazardR.Length = 0;
	MountVols.Length = 0;
	MaxMount = FMax(DJumpUp + 20.0, float(PC.Pawn.GetPropertyText("MaxMountHeight")));
	foreach PC.AllActors(Class'Engine.Actor', A)
	{
		if (A.IsA('MountVolume'))
		{
			MountVols[MountVols.Length] = A.Location;
		}
	}
	foreach PC.DynamicActors(Class'Engine.Actor', A)
	{
		if (A.IsA('BriarPatch') || A.IsA('Hazard') || A.IsA('BallSpiked'))
		{
			Hazards[Hazards.Length] = A;
			HazardR[HazardR.Length] = A.CollisionRadius + R + 12.0;
		}
	}
	L = PC.Pawn.Location;
	OX = L.X;
	OY = L.Y;
	if (PC.Trace(HL, HN, L - vect(0, 0, 400), L, false) == None)
	{
		HL = L - vect(0, 0, 1) * PC.Pawn.CollisionHeight;
	}
	AddNode(0, 0, HL.Z);
	AddSeeds(PC);
	bBaking = true;
}

// the floor under L (a trace down to 700 units), -1000000 when there is none
function float FloorUnder(PlayerController PC, Vector L)
{
	local Vector HL, HN;

	if (PC.Trace(HL, HN, L - vect(0, 0, 700), L + vect(0, 0, 10), false) == None)
	{
		return -1000000.0;
	}
	return HL.Z;
}

// a cell at L with its floor at Z (the cell of an existing node there, or a new one): the flood fill goes on from it
function int SeedAt(Vector L, float Z)
{
	local int ix, iy, n;

	ix = CellOf(L.X, OX);
	iy = CellOf(L.Y, OY);
	n = FindNode(ix, iy, Z);
	if (n < 0)
	{
		n = AddNode(ix, iy, Z);
	}
	return n;
}

// the hero is somewhere the map does not reach (a cutscene put him there, a bounce, a vine): the map grows from there, nothing is dropped
function AddSeed(PlayerController PC, Vector L)
{
	local float F;

	F = FloorUnder(PC, L);
	if (F > -1000000.0)
	{
		SeedAt(L, F);
		bBaking = true;
	}
}

// the places the special ways lead to are cells from the start: the lily pads' tops, the floors under the BounceTargets and the vines' last nodes
function AddSeeds(PlayerController PC)
{
	local Actor A, T;
	local float F;
	local string Ev;
	local int i, LY;
	local Vector LS, LE;

	Lilies.Length = 0;
	for (i = 0; Learned(i, LS, LY, LE); i++)
	{
		F = FloorUnder(PC, LE);
		if (F > -1000000.0)
		{
			SeedAt(LE, F);
		}
	}
	foreach PC.AllActors(Class'Engine.Actor', A)
	{
		if (A.IsA('AmbientLily') || A.IsA('BounceLili'))
		{
			Lilies[Lilies.Length] = A;
			SeedAt(A.Location, A.Location.Z + A.CollisionHeight);
		}
		else if (A.IsA('BouncePad'))
		{
			Ev = string(A.Event);
			foreach PC.AllActors(Class'Engine.Actor', T)
			{
				if (T.IsA('BounceTarget') && string(T.Tag) ~= Ev)
				{
					F = FloorUnder(PC, T.Location);
					if (F > -1000000.0)
					{
						SeedAt(T.Location, F);
					}
				}
			}
		}
		else if (A.IsA('ShimmyNode') && A.GetPropertyText("LabelNext") == "")
		{
			F = FloorUnder(PC, A.Location - vect(0, 0, 60));
			if (F > -1000000.0)
			{
				SeedAt(A.Location, F);
			}
		}
	}
}

// the learned climbs of this map (EnhancedPlayLearn): i-th one's start, yaw and end; false when there is no i-th
function bool Learned(int i, out Vector S, out int Yaw, out Vector E)
{
	local string L, W;
	local int k, n;
	local array<float> F;

	n = -1;
	for (k = 0; k < Class'Enhanced.EnhancedPlayLearn'.default.Climbs.Length; k++)
	{
		L = Class'Enhanced.EnhancedPlayLearn'.default.Climbs[k];
		if (!(Left(L, Len(MapName) + 1) ~= (MapName $ ":")))
		{
			continue;
		}
		n++;
		if (n != i)
		{
			continue;
		}
		L = Mid(L, Len(MapName) + 1);
		F.Length = 0;
		while (L != "" && F.Length < 7)
		{
			while (Left(L, 1) == " ")
			{
				L = Mid(L, 1);
			}
			if (InStr(L, " ") >= 0)
			{
				W = Left(L, InStr(L, " "));
				L = Mid(L, InStr(L, " ") + 1);
			}
			else
			{
				W = L;
				L = "";
			}
			if (W != "")
			{
				F[F.Length] = float(W);
			}
		}
		if (F.Length < 7)
		{
			return false;
		}
		S.X = F[0];
		S.Y = F[1];
		S.Z = F[2];
		Yaw = int(F[3]);
		E.X = F[4];
		E.Y = F[5];
		E.Z = F[6];
		return true;
	}
	return false;
}

function AddSpecial(int a, int b, byte Kind, Actor Via)
{
	local int k;

	if (a < 0 || b < 0 || a == b)
	{
		return;
	}
	k = SFrom.Length;
	SFrom[k] = a;
	STo[k] = b;
	SKind[k] = Kind;
	SVia[k] = Via;
	SPos[k] = vect(0, 0, 0);
	SYaw[k] = 0;
	SNext[k] = SHead[a];
	SHead[a] = k + 1;
}

// the cells within Rad across of L whose floor is between Lo and Hi
function CellsNear(Vector L, float Rad, float Lo, float Hi, out array<int> Out)
{
	local int cx, cy, ix, iy, n, R2;
	local Vector V;

	Out.Length = 0;
	cx = CellOf(L.X, OX);
	cy = CellOf(L.Y, OY);
	R2 = int(Rad / Cell) + 1;
	for (ix = cx - R2; ix <= cx + R2; ix++)
	{
		for (iy = cy - R2; iy <= cy + R2; iy++)
		{
			n = HashHead[Bucket(ix, iy)] - 1;
			while (n >= 0)
			{
				if (NIX[n] == ix && NIY[n] == iy && NZ[n] >= Lo && NZ[n] <= Hi)
				{
					V.X = NX[n] - L.X;
					V.Y = NY[n] - L.Y;
					V.Z = 0;
					if (VSize(V) <= Rad)
					{
						Out[Out.Length] = n;
					}
				}
				n = NNext[n] - 1;
			}
		}
	}
}

function int LilyNode(Actor A)
{
	return FindNode(CellOf(A.Location.X, OX), CellOf(A.Location.Y, OY), A.Location.Z + A.CollisionHeight);
}

// the special ways, made again from the cells the map has now
function BuildSpecials(PlayerController PC)
{
	local int i, j, k, ln, ln2;
	local array<int> Near;
	local Actor A, T, E, N2, M;
	local float Top, F;
	local string Ev, NextLabel;
	local int LY;
	local Vector LS, LE;

	SFrom.Length = 0;
	STo.Length = 0;
	SNext.Length = 0;
	SKind.Length = 0;
	SVia.Length = 0;
	SPos.Length = 0;
	SYaw.Length = 0;
	SHead.Length = 0;
	SHead.Length = NX.Length;
	for (i = 0; i < NX.Length; i++)
	{
		SHead[i] = 0;
	}
	// learned climbs: from the cell at its start to the cell on top
	for (i = 0; Learned(i, LS, LY, LE); i++)
	{
		j = NearestSeen(PC, LS, 100.0, 120.0);
		k = Nearest(LE, 120.0, 200.0);
		if (j >= 0 && k >= 0)
		{
			AddSpecial(j, k, 7, None);
			SPos[SPos.Length - 1] = LS;
			SYaw[SYaw.Length - 1] = LY;
		}
	}
	// lily pads: a jump onto one from the water or the bank around it, and from one to the next
	for (i = 0; i < Lilies.Length; i++)
	{
		A = Lilies[i];
		ln = LilyNode(A);
		if (ln < 0)
		{
			continue;
		}
		Top = A.Location.Z + A.CollisionHeight;
		CellsNear(A.Location, A.CollisionRadius + 110.0, Top - JumpUp, Top + 20.0, Near);
		for (j = 0; j < Near.Length; j++)
		{
			AddSpecial(Near[j], ln, 1, A);
		}
		for (k = 0; k < Lilies.Length; k++)
		{
			if (k != i && VSize(Lilies[k].Location - A.Location) < 300.0 && Abs(Lilies[k].Location.Z - A.Location.Z) < JumpUp)
			{
				ln2 = LilyNode(Lilies[k]);
				AddSpecial(ln, ln2, 1, Lilies[k]);
			}
		}
	}
	foreach PC.AllActors(Class'Engine.Actor', A)
	{
		// bounce pads that are on: from the cells on them to the floor under their target
		if (A.IsA('BouncePad') && !(A.GetPropertyText("bEnabled") ~= "False"))
		{
			Ev = string(A.Event);
			foreach PC.AllActors(Class'Engine.Actor', T)
			{
				if (T.IsA('BounceTarget') && string(T.Tag) ~= Ev)
				{
					F = FloorUnder(PC, T.Location);
					k = Nearest(T.Location, 200.0, 700.0);
					if (k < 0)
					{
						continue;
					}
					// a jumping mushroom's pad (the Hunt) is a hidden point: the mushroom whose Event is the pad's Tag throws a hero who lands on its
					// top (JumpingMushroomLanding -> JumpingMushroomController -> the pad's OnBounce). The way goes from the cells round the mushroom,
					// by way of the mushroom (h4-h6: the bot jumped on the pad's point beside it for 48 s and was never thrown)
					M = None;
					if (A.IsA('MushroomBouncePad'))
					{
						foreach PC.AllActors(Class'Engine.Actor', E)
						{
							if (E.IsA('JumpingMushroom') && string(E.Event) ~= string(A.Tag))
							{
								M = E;
								break;
							}
						}
					}
					if (M != None)
					{
						CellsNear(M.Location, M.CollisionRadius + 130.0, M.Location.Z - M.CollisionHeight - 80.0, M.Location.Z + M.CollisionHeight, Near);
						for (j = 0; j < Near.Length; j++)
						{
							AddSpecial(Near[j], k, 5, M);
						}
						continue;
					}
					CellsNear(A.Location, 90.0, A.Location.Z - 120.0, A.Location.Z + 40.0, Near);
					for (j = 0; j < Near.Length; j++)
					{
						AddSpecial(Near[j], k, 5, A);
					}
				}
			}
		}
		// vines: from the cells under the first ShimmyNode to the floor under the last one
		else if (A.IsA('ShimmyNode') && A.GetPropertyText("LabelPrev") == "" && A.GetPropertyText("LabelNext") != "")
		{
			E = A;
			for (k = 0; k < 20; k++)
			{
				NextLabel = E.GetPropertyText("LabelNext");
				if (NextLabel == "")
				{
					break;
				}
				N2 = None;
				foreach PC.AllActors(Class'Engine.Actor', T)
				{
					if (T.IsA('ShimmyNode') && T != E && (string(T.Tag) ~= NextLabel || T.GetPropertyText("Label") ~= NextLabel))
					{
						N2 = T;
					}
				}
				if (N2 == None)
				{
					break;
				}
				E = N2;
			}
			if (E == A)
			{
				continue;
			}
			k = Nearest(E.Location - vect(0, 0, 60), 250.0, 700.0);
			if (k < 0)
			{
				continue;
			}
			CellsNear(A.Location, 160.0, A.Location.Z - 260.0, A.Location.Z - 30.0, Near);
			for (j = 0; j < Near.Length; j++)
			{
				AddSpecial(Near[j], k, 6, A);
			}
		}
	}
}

// the special way from a to b (its index), -1 when there is none
function int SpecialOf(int a, int b)
{
	local int k;

	if (a < 0 || a >= SHead.Length)
	{
		return -1;
	}
	k = SHead[a] - 1;
	while (k >= 0)
	{
		if (STo[k] == b)
		{
			return k;
		}
		k = SNext[k] - 1;
	}
	return -1;
}

function bool NearMountVolume(Vector L)
{
	local int i;

	for (i = 0; i < MountVols.Length; i++)
	{
		if (VSize(MountVols[i] - L) < 500.0)
		{
			return true;
		}
	}
	return false;
}

// a box of the hero's size can go from A to B
function bool Free(PlayerController PC, Vector A, Vector B)
{
	local Vector HL, HN, Ext;

	Ext.X = R * 0.8;
	Ext.Y = R * 0.8;
	Ext.Z = H * 0.5;
	Traces++;
	return PC.Trace(HL, HN, B, A, false, Ext) == None;
}

function AddEdge(int n, int ix, int iy, float Fz, byte Kind)
{
	local int m;
	local Vector P;

	m = FindNode(ix, iy, Fz);
	if (m < 0)
	{
		if (NX.Length >= MaxNodes)
		{
			return;
		}
		P.X = OX + float(ix) * Cell;
		P.Y = OY + float(iy) * Cell;
		P.Z = Fz;
		if (NearHazard(P))
		{
			return;
		}
		m = AddNode(ix, iy, Fz);
	}
	if (m == n)
	{
		return;
	}
	ETo[ETo.Length] = m;
	EKind[EKind.Length] = Kind;
}

// the ways out of node n
function Expand(PlayerController PC, int n)
{
	local int d, ix, iy;
	local Vector S, T, Top, End, HL, HN, W1, W2;
	local float Z, Fz, Hz;
	local bool bUp, bGap, bFlat;
	local Actor Wall;
	local int k;

	NFirst[n] = ETo.Length;
	Z = NZ[n];
	S.X = NX[n];
	S.Y = NY[n];
	S.Z = Z + H + 2.0;
	for (d = 0; d < 8; d++)
	{
		ix = NIX[n] + DX[d];
		iy = NIY[n] + DY[d];
		T.X = OX + float(ix) * Cell;
		T.Y = OY + float(iy) * Cell;
		// the floor there, from a step's height down to the deepest safe drop
		Top = T;
		Top.Z = Z + 35.0 + H;
		End = T;
		End.Z = Z - MaxDrop;
		Traces++;
		bGap = true;
		bFlat = false;
		if (PC.Trace(HL, HN, End, Top, false) != None && HN.Z >= 0.7)
		{
			Fz = HL.Z;
			bGap = Fz < Z - 40.0;      // lower than a step; a jump over it only to a floor about as high (nav12: one 87 lower was taken for a gap's far side)
			Hz = FMax(Z, Fz) + H + 2.0;
			Top.Z = Hz;
			if (Free(PC, S, Top))
			{
				if (Fz < Z - 40.0)
				{
					AddEdge(n, ix, iy, Fz, 3);
				}
				else
				{
					AddEdge(n, ix, iy, Fz, 0);
					// open ground: no higher floor to look for here (the jump and climb traces are most of the map's cost: 38 s on the carriage
					// level in co-op, n3)
					bFlat = Abs(Fz - Z) <= 35.0;
				}
			}
		}
		// a floor higher than a step: a jump or a double jump onto it
		Top.Z = Z + DJumpUp + H;
		End.Z = Z + 36.0;
		bUp = false;
		if (!bFlat)
		{
			Traces++;
		}
		if (!bFlat && PC.Trace(HL, HN, End, Top, false) != None && HN.Z >= 0.7 && HL.Z > Z + 35.0)
		{
			bUp = true;
			Fz = HL.Z;
			Hz = Fz + H + 2.0;
			End = S;
			End.Z = Hz;
			Top.Z = Hz;
			if (Free(PC, S, End) && Free(PC, End, Top))
			{
				if (Fz <= Z + JumpUp)
				{
					AddEdge(n, ix, iy, Fz, 1);
				}
				else
				{
					AddEdge(n, ix, iy, Fz, 2);
				}
			}
		}
		// a gap (a broken bridge's missing planks, a ditch): a running jump over it to a floor 2 to 4 cells on, about as high (a double jump for
		// the far ones). nav8: the way went down into the water under the swamp's broken bridge, the map had no jump over a gap
		if (bGap)
		{
			for (k = 2; k <= 4; k++)
			{
				T.X = OX + float(NIX[n] + DX[d] * k) * Cell;
				T.Y = OY + float(NIY[n] + DY[d] * k) * Cell;
				Top = T;
				Top.Z = Z + JumpUp + H;
				End = T;
				End.Z = Z - 150.0;
				Traces++;
				if (PC.Trace(HL, HN, End, Top, false) != None && HN.Z >= 0.7 && HL.Z > Z - 40.0)
				{
					Fz = HL.Z;
					// what a running double jump carries (measured: it rises about 147, so gravity is about 1000; at the run speed of 220 it goes
					// about 250 across to the same height): up to 220 across rising up to 30, 170 rising up to 55
					W1 = T - S;
					W1.Z = 0;
					if (VSize(W1) > 220.0 || (Fz > Z + 30.0 && VSize(W1) > 170.0))
					{
						break;
					}
					// the flight: up to the top of the jump, across, down onto the far floor (a beam over a bridge stops a jump: nav9's shots)
					W1 = S;
					W1.Z = Z + H + 100.0;
					W2 = T;
					W2.Z = W1.Z;
					End = T;
					End.Z = Fz + H + 2.0;
					if (Free(PC, S, W1) && Free(PC, W1, W2) && Free(PC, W2, End))
					{
						AddEdge(n, NIX[n] + DX[d] * k, NIY[n] + DY[d] * k, Fz, 8);
					}
					break;
				}
			}
			T.X = OX + float(ix) * Cell;
			T.Y = OY + float(iy) * Cell;
		}
		// a ledge higher than a jump: the game's Mount climbs it when the hero runs into it (KWPawn.Mount: a mountable actor, or the level's own
		// geometry inside a MountVolume), up to MaxMountHeight. owner, 2026-11-22: "the bot walked around the stump"
		if (!bUp && !bFlat)
		{
			Top.Z = Z + MaxMount + H;
			End.Z = Z + 36.0;
			Traces++;
			if (PC.Trace(HL, HN, End, Top, false) != None && HN.Z >= 0.7 && HL.Z > Z + DJumpUp)
			{
				Fz = HL.Z;
				W1 = S;
				W2 = T;
				W2.Z = S.Z;
				Traces++;
				Wall = PC.Trace(HL, HN, W2, W1, false);
				if (Wall != None && (Wall.GetPropertyText("bIsMountable") ~= "True" || (Wall.IsA('LevelInfo') && NearMountVolume(S))))
				{
					// room for the hero on top
					Top.Z = Fz + 2.0;
					End = Top;
					End.Z = Fz + 2.0 * H;
					Traces++;
					if (PC.FastTrace(End, Top))
					{
						AddEdge(n, ix, iy, Fz, 4);
					}
				}
			}
		}
	}
	NCount[n] = ETo.Length - NFirst[n];
}

// a part of the flood fill: true when it is over
function bool BakeStep(PlayerController PC, float DeltaTime, int Budget)
{
	local int Start;

	BakeTime += DeltaTime;
	Start = Traces;
	while (Expanded < NX.Length && Traces - Start < Budget)
	{
		Expand(PC, Expanded);
		Expanded++;
	}
	if (Expanded >= NX.Length)
	{
		bBaking = false;
		bBaked = true;
		BuildSpecials(PC);
		return true;
	}
	return false;
}

// the node nearest L (a point on the floor or the middle of a hero) within MaxXY across and MaxZ up or down, or -1
function int Nearest(Vector L, float MaxXY, float MaxZ)
{
	local int cx, cy, ix, iy, n, Best, Rad;
	local float D, BestD;
	local Vector V;

	cx = CellOf(L.X, OX);
	cy = CellOf(L.Y, OY);
	Rad = int(MaxXY / Cell) + 1;
	Best = -1;
	BestD = 1000000.0;
	for (ix = cx - Rad; ix <= cx + Rad; ix++)
	{
		for (iy = cy - Rad; iy <= cy + Rad; iy++)
		{
			n = HashHead[Bucket(ix, iy)] - 1;
			while (n >= 0)
			{
				if (NIX[n] == ix && NIY[n] == iy)
				{
					V.X = NX[n] - L.X;
					V.Y = NY[n] - L.Y;
					V.Z = 0;
					D = VSize(V);
					if (D <= MaxXY && NZ[n] > L.Z - MaxZ - H && NZ[n] < L.Z + MaxZ)
					{
						D += 0.5 * Abs(NZ[n] + H - L.Z);
						if (D < BestD)
						{
							BestD = D;
							Best = n;
						}
					}
				}
				n = NNext[n] - 1;
			}
		}
	}
	return Best;
}

// the nearest node that L sees (nav3: the nearest by distance was behind a rock wall, the way began on its other side and the hero jumped at the rock)
function int NearestSeen(PlayerController PC, Vector L, float MaxXY, float MaxZ)
{
	local int cx, cy, ix, iy, n, Best, Rad, k, t;
	local float D, BestD;
	local Vector V;
	local array<int> Tried;
	local bool bTried;

	cx = CellOf(L.X, OX);
	cy = CellOf(L.Y, OY);
	Rad = int(MaxXY / Cell) + 1;
	for (k = 0; k < 8; k++)
	{
		Best = -1;
		BestD = 1000000.0;
		for (ix = cx - Rad; ix <= cx + Rad; ix++)
		{
			for (iy = cy - Rad; iy <= cy + Rad; iy++)
			{
				n = HashHead[Bucket(ix, iy)] - 1;
				while (n >= 0)
				{
					if (NIX[n] == ix && NIY[n] == iy)
					{
						V.X = NX[n] - L.X;
						V.Y = NY[n] - L.Y;
						V.Z = 0;
						D = VSize(V);
						if (D <= MaxXY && NZ[n] > L.Z - MaxZ - H && NZ[n] < L.Z + MaxZ)
						{
							D += 0.5 * Abs(NZ[n] + H - L.Z);
							if (D < BestD)
							{
								bTried = false;
								for (t = 0; t < Tried.Length; t++)
								{
									if (Tried[t] == n)
									{
										bTried = true;
									}
								}
								if (!bTried)
								{
									BestD = D;
									Best = n;
								}
							}
						}
					}
					n = NNext[n] - 1;
				}
			}
		}
		if (Best < 0)
		{
			return -1;
		}
		if (PC.FastTrace(At(Best), L))
		{
			return Best;
		}
		Tried[Tried.Length] = Best;
	}
	return -1;
}

// the map around L as text (one character per cell, +Y up, +X right): ' ' no cell, '~' water, else the highest cell's floor against the hero's
// as a letter per 20 units (n = level, m one step below, o one above...); 'H' the hero, 'T' the point. For the log when the bot is stuck.
function Picture(Vector L, Vector Goal, int Rad, out array<string> Rows)
{
	local string Row, Ch;
	local int cx, cy, ix, iy, n, Best, gx, gy;
	local float Base, Hi, dz;

	cx = CellOf(L.X, OX);
	cy = CellOf(L.Y, OY);
	gx = CellOf(Goal.X, OX);
	gy = CellOf(Goal.Y, OY);
	Base = L.Z - H;
	for (iy = cy + Rad; iy >= cy - Rad; iy--)
	{
		Row = "";
		for (ix = cx - Rad; ix <= cx + Rad; ix++)
		{
			Best = -1;
			Hi = -1000000.0;
			n = HashHead[Bucket(ix, iy)] - 1;
			while (n >= 0)
			{
				if (NIX[n] == ix && NIY[n] == iy && NZ[n] > Hi)
				{
					Hi = NZ[n];
					Best = n;
				}
				n = NNext[n] - 1;
			}
			if (ix == cx && iy == cy)
			{
				Ch = "H";
			}
			else if (ix == gx && iy == gy)
			{
				Ch = "T";
			}
			else if (Best < 0)
			{
				Ch = " ";
			}
			else if (NWater[Best] != 0)
			{
				Ch = "~";
			}
			else
			{
				// a letter per 20 units of height: n = the hero's floor, a = 260 or more below, z = 240 or more above
				dz = (Hi - Base) / 20.0 + 13.5;
				Ch = Mid("abcdefghijklmnopqrstuvwxyz", Clamp(int(dz), 0, 25), 1);
			}
			Row = Row $ Ch;
		}
		Rows[Rows.Length] = Row;
	}
}

function Vector At(int n)
{
	local Vector V;

	V.X = NX[n];
	V.Y = NY[n];
	V.Z = NZ[n] + H;
	return V;
}

// ---- A* ----
function HeapPush(int n, float F)
{
	local int i, p, tn;
	local float tf;

	i = HeapN.Length;
	HeapN[i] = n;
	HeapF[i] = F;
	while (i > 0)
	{
		p = (i - 1) / 2;
		if (HeapF[p] <= HeapF[i])
		{
			break;
		}
		tn = HeapN[p]; HeapN[p] = HeapN[i]; HeapN[i] = tn;
		tf = HeapF[p]; HeapF[p] = HeapF[i]; HeapF[i] = tf;
		i = p;
	}
}

function int HeapPop()
{
	local int Top, i, c, Last, tn;
	local float tf;

	Top = HeapN[0];
	Last = HeapN.Length - 1;
	HeapN[0] = HeapN[Last];
	HeapF[0] = HeapF[Last];
	HeapN.Remove(Last, 1);
	HeapF.Remove(Last, 1);
	i = 0;
	while (true)
	{
		c = i * 2 + 1;
		if (c >= HeapN.Length)
		{
			break;
		}
		if (c + 1 < HeapN.Length && HeapF[c + 1] < HeapF[c])
		{
			c++;
		}
		if (HeapF[i] <= HeapF[c])
		{
			break;
		}
		tn = HeapN[c]; HeapN[c] = HeapN[i]; HeapN[i] = tn;
		tf = HeapF[c]; HeapF[c] = HeapF[i]; HeapF[i] = tf;
		i = c;
	}
	return Top;
}

function float Heur(int a, int b)
{
	local Vector V;

	V.X = NX[a] - NX[b];
	V.Y = NY[a] - NY[b];
	V.Z = NZ[a] - NZ[b];
	return VSize(V);
}

function StartSearch(int s, int g)
{
	SearchId++;
	if (GS.Length < NX.Length)
	{
		GS.Length = NX.Length;
		From.Length = NX.Length;
		Stamp.Length = NX.Length;
		Shut.Length = NX.Length;
	}
	HeapN.Length = 0;
	HeapF.Length = 0;
	SStart = s;
	SGoal = g;
	SPops = 0;
	Stamp[s] = SearchId;
	GS[s] = 0.0;
	From[s] = -1;
	HeapPush(s, Heur(s, g));
	Path.Length = 0;
	bSearching = true;
}

// a part of the search: 1 = a way is in Path, -1 = there is none, 0 = not over yet
function int SearchStep(int Budget)
{
	local int k, n, m, e, i;
	local float Cost, G2;

	for (k = 0; k < Budget; k++)
	{
		if (HeapN.Length == 0)
		{
			bSearching = false;
			return -1;
		}
		n = HeapPop();
		if (Shut[n] == SearchId)
		{
			continue;
		}
		Shut[n] = SearchId;
		SPops++;
		if (n == SGoal)
		{
			// the way, from the start to the goal
			i = 0;
			m = n;
			while (m >= 0 && i < 20000)
			{
				i++;
				m = From[m];
			}
			Path.Length = i;
			m = n;
			while (m >= 0 && i > 0)
			{
				i--;
				Path[i] = m;
				m = From[m];
			}
			bSearching = false;
			return 1;
		}
		if (n >= Expanded)
		{
			continue;
		}
		// the special ways out of n
		if (n < SHead.Length)
		{
			e = SHead[n] - 1;
			while (e >= 0)
			{
				m = STo[e];
				// the hero cannot jump while he wades (water, quicksand): no jump onto a lily pad from there (nav11: "rose 0" in the water)
				if (Shut[m] != SearchId && SKind[e] != 9 && !(SKind[e] == 1 && NWater[n] != 0))
				{
					Cost = Heur(n, m);
					if (SKind[e] == 5 || SKind[e] == 6 || SKind[e] == 7)
					{
						Cost = Cost * 0.5 + 300.0;
					}
					else
					{
						Cost = Cost * 1.2 + 20.0;
					}
					G2 = GS[n] + Cost;
					if (Stamp[m] != SearchId || G2 < GS[m])
					{
						Stamp[m] = SearchId;
						GS[m] = G2;
						From[m] = n;
						HeapPush(m, G2 + Heur(m, SGoal));
					}
				}
				e = SNext[e] - 1;
			}
		}
		for (e = NFirst[n]; e < NFirst[n] + NCount[n]; e++)
		{
			m = ETo[e];
			if (Shut[m] == SearchId || EKind[e] == 9)
			{
				continue;
			}
			// no jumps out of water or quicksand (the hero wades and cannot jump: nav11 planned a drop into the water under the broken bridge and a
			// jump back up)
			if (NWater[n] != 0 && (EKind[e] == 1 || EKind[e] == 2 || EKind[e] == 8))
			{
				continue;
			}
			Cost = Heur(n, m);
			if (EKind[e] == 1)
			{
				Cost *= 1.5;
			}
			else if (EKind[e] == 2)
			{
				Cost *= 3.0;
			}
			else if (EKind[e] == 3)
			{
				Cost *= 1.3;
			}
			else if (EKind[e] == 4)
			{
				Cost *= 3.0;
			}
			else if (EKind[e] == 8)
			{
				Cost = Cost * 1.5 + 40.0;
			}
			// wading in water or quicksand is slow (150 against 220)
			if (NWater[n] != 0 || NWater[m] != 0)
			{
				Cost *= 1.6;
			}
			G2 = GS[n] + Cost;
			if (Stamp[m] != SearchId || G2 < GS[m])
			{
				Stamp[m] = SearchId;
				GS[m] = G2;
				From[m] = n;
				HeapPush(m, G2 + Heur(m, SGoal));
			}
		}
	}
	return 0;
}

// the way from node a to node b is not taken again (the hero made no headway on it)
function Block(int a, int b)
{
	local int e;

	e = SpecialOf(a, b);
	if (e >= 0)
	{
		SKind[e] = 9;
	}

	if (a < 0 || a >= Expanded)
	{
		return;
	}
	for (e = NFirst[a]; e < NFirst[a] + NCount[a]; e++)
	{
		if (ETo[e] == b)
		{
			EKind[e] = 9;
		}
	}
}

// the kind of the way from node a to node b (the edge of a), -1 when there is none
function int KindOf(int a, int b)
{
	local int e;

	if (a < 0 || a >= Expanded)
	{
		return -1;
	}
	for (e = NFirst[a]; e < NFirst[a] + NCount[a]; e++)
	{
		if (ETo[e] == b)
		{
			return EKind[e];
		}
	}
	return -1;
}

defaultproperties
{
}

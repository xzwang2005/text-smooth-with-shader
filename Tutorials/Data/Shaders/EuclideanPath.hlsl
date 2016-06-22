// dummy vector shader
// define SHADER_DEBUG to 1 to run with shader_diag
#define SHADER_DEBUG 1
struct VS_INPUT
{
	float4 position : POSITION;
	float2 tex		: TEXCOORDS0;
};

struct VS_OUTPUT
{
	float4 position : SV_Position;
	float2 tex      : TEXCOORD0;
};

VS_OUTPUT VSMAIN(in VS_INPUT input)
{
	VS_OUTPUT output;

	output.position = input.position;
	output.tex = input.tex;
	return output;
};

cbuffer ImageViewingData
{
	float4	WindowSize;		// The left/top point of the window/viewport to be magnified, and width/height of the current texture
	float2	MagnifyLevel;	// xy components are the same
	float2	ShowOriginal;	// show unprocessed image
};

Texture2D			InputMap			: register(t0);
Texture2D			ViewportSurface		: register(t1);
Texture2D			DiscretePathSurface : register(t2);
Texture2D			FullConnectedDiscretePathSurface  : register(t3);
Texture2D			EucldeanSurface		: register(t4);
Texture2D			MagnifyedSurface	: register(t5);
Texture2D			DefectSurface		: register(t6);
Texture2D<uint2>	EncodeSurface		: register(t7);
Texture2D			SmoothEuclideanSurface : register(t8);

// the comparison is not exact by design, the neighboring
// pixels are considered of the same color if the difference is
// within a small range.  It is useful to pick out text in gradient
// background color.  In this case, the neighboring background pixels
// are slightly different, yet the text pixels are significantly different
static const float ColorDiffThreshold = 0.15f;
static const uint MAX_STEP = 5;
static const uint FLAT_NEIGHBOR = 3;
static const uint FLAT_NEIGHBOR_THRE = 3;
static const uint InvalidFreemanCode = 4;
static const uint MaxSearchStep = 5;

// delta[i]: movement in xy directions given freeman code is i
static int2 delta[5] = {
	int2(1, 0),
	int2(0, 1),
	int2(-1, 0),
	int2(0, -1),
	int2(1, 0)
};

// flip[i]: the opposite direction code of i, i.e., flip[flip[i]]=i
static int4 flip = int4(2, 3, 0, 1);

static int2 delta_near[5] = {
	int2(1, 1),
	int2(-1, 1),
	int2(-1, -1),
	int2(1, -1),
	int2(1, 1)
};

static int2 delta_far[8] = {
	int2(2, 1),
	int2(1, 2),
	int2(-1, 2),
	int2(-2, 1),
	int2(-2, -1),
	int2(-1, -2),
	int2(1, -2),
	int2(2, -1)
};

static int4 codeTemplate[5] = {
	int4(1, 2, 3, 0),		// if first quadrant, the direction is 1, 2, come from east, go north
	int4(2, 3, 0, 1),
	int4(1, 2, 3, 0),
	int4(2, 3, 0, 1),
	int4(1, 2, 3, 0)
};

static int4 pixelCoord[8] = {
	int4(0, 0, 1, 0),
	int4(0, 0, 0, 1),
	int4(-1, 0, -1, 1),
	int4(-1, 0, -2, 0),
	int4(-1, -1, -2, -1),
	int4(-1, -1, -1, -2),
	int4(0, -1, 0, -2),
	int4(0, -1, 1, -1)
};

// each pixel is surrounded by 4 interpixel:
/*
           |
(x, y + 1) | (x+1,y+1)
---------(x,y)----------
(x, y)     | (x+1, y)
           |
*/
static int2 px2interpx[4] = {
	int2(0, 0),
	int2(1, 0),
	int2(1, 1),
	int2(0, 1)
};

static const int2 offset[16] = {
	int2(-2, -2),
	int2(-1, -2),
	int2(0, -2),
	int2(1, -2),
	int2(-2, -1),
	int2(-1, -1),
	int2(0, -1),
	int2(1, -1),
	int2(-2, 0),
	int2(-1, 0),
	int2(0, 0),
	int2(1, 0),
	int2(-2, 1),
	int2(-1, 1),
	int2(0, 1),
	int2(1, 1)
};

static float3 Bezier_t = { 1.0f, 0.5f, 0.25f };		// t = 0.5
static float3x3 Bezier_M = {
	1.0f, 0.0f, 0.0f,
	-2.0f, 2.0f, 0.0f,
	1.0f, -2.0f, 1.0f
};

static float3 Bezier_3 = { 0.25f, 0.5f, 0.25f }; // Bezier_t * Bezier_M

//static float epsilon = 0.0009765625;		// 2e(-10)
static float epsilon = 0.00001;

bool isDiffColor(in float4 colDiff)
{
	return dot(colDiff, colDiff) > ColorDiffThreshold;
};


inline bool ColorsEqual(float4 leftPixel, float4 rightPixel)
{
	return (leftPixel.r == rightPixel.r && leftPixel.g == rightPixel.g && leftPixel.b == rightPixel.b);
}

uint MaskPixels(float4 sourcePixel, float4 colorPixel, uint mask)
{
	bool equal = ColorsEqual(sourcePixel, colorPixel);
	return equal ? mask : 0;
}

uint GetMask(const float2 position, float4 colorPixel)
{
	uint ret = 0;
	// IMPORTANT: the order of retrieved pixels must be consistent with
	// the order in method: void AutoDirDlg::encodeMask(bool defaultAnchor)

	int pos = 0;
	for (int dy = -2; dy <= 1; dy++)
		for (int dx = -2; dx <= 1; dx++) {
			uint msk = 1 << (15 - pos);
			int2 npos = position + int2(dx, dy);
			float4 srcPixel = InputMap[npos];
			ret |= MaskPixels(srcPixel, colorPixel, msk);
			pos++;
	}

	//for (int i = 0; i < 16; i++) {
	//	uint msk = 1 << (15 - i);
	//	float2 npos = position + offset[i];
	//	float4 srcPixel = InputMap[npos];
	//	uint m = MaskPixels(srcPixel, colorPixel, msk);
	//	ret |= m;
	//}
	return ret;
}


/*
*
*	first pass
*
*/
struct DISCRETE_PATH_OUTPUT
{
	float4	viewport		: SV_Target0;
	float4	discretePath	: SV_Target1;	
	uint2   codeSurf		: SV_Target2;
};

// use a different definition for "discretePath"
// x:  freemancode for first (forward) neighbor
// y:  freemancode for second (backward) neighbor, -1 if not exist
// z:  number of neighbors, <= 2
DISCRETE_PATH_OUTPUT PS_DISCRETE_PATH_FREEMAN(in VS_OUTPUT input)
{
	DISCRETE_PATH_OUTPUT discrete_output;

	uint2 pos = input.position.xy + WindowSize.xy;
		float4 srcPixel = InputMap[pos];
		discrete_output.viewport = srcPixel;

	int4 output = int4(10, 10, 0, 10);
		uint2 codes = uint2(0, 0);

	// assume current interpixel (x,y) is at origin, it has at most four surrounding pixels corresponding to four quadrants
	// first:	(x,y)
	// second:	(x-1,y)
	// third:	(x-1,y-1)
	// fourth:	(x, y-1);
	/*
	           |
	 (x-1, y)  | (x,y)
	---------(x,y)----------
	(x-1, y-1) | (x, y-1)
	           |
	*/
	// depending on the location of current interpixel (i.e., at the boundary of the interpixel surface), some of the neighboring
	// pixels may not exist.
	// in order to make sure that comparison is made between pixels that do exist, the boundary condition needs to be considered
	// e.g., when comparing first and second quadrant pixels, we need to verify:
	// 1) x < width so that first quadrant pixel exist;  
	// 2) x > 0 so that second quadrant pixel exist;
	// 3) y < height; otherwise neither pixels exist
	// these conditions can be combined and written as: (width - x) * x * (height - y) > 0;
	// this pattern is followed when comparing other pairs of pixels
	uint wMargin = WindowSize.z - pos.x;
	uint hMargin = WindowSize.w - pos.y;
	// check quadrant 1 and 2
	if (wMargin * pos.x * hMargin > 0) {	// check if both pixels exist
		// now compare the color of the two
		float4 color1 = InputMap[pos];
			uint2 pos2 = uint2(pos.x - 1, pos.y);
			float4 color2 = InputMap[pos2];
		if (isDiffColor(color1 - color2))
		{
			output.x = 1;		// freeman code for going up
			output.z++;
		}
	}

	// check quadrant 2 and 3
	if (pos.x * pos.y * hMargin > 0)
	{
		uint2 pos1 = uint2(pos.x - 1, pos.y);
			float4 color1 = InputMap[pos1];
			uint2 pos2 = uint2(pos.x - 1, pos.y - 1);
			float4 color2 = InputMap[pos2];
		if (isDiffColor(color1 - color2))
		{
			if (output.x < 10) {	// already has a neighbor, save to next slot
				output.y = 0;	// freemancode for going east
			}
			else {	// this is the first neighbor found
				output.x = 2;	// going west (from this interpixel)
			}
			output.z++;
		}
	}

	// check quadrant 3 and 4
	if (pos.x * pos.y * wMargin > 0)
	{
		uint2 pos1 = uint2(pos.x - 1, pos.y - 1);
			float4 color1 = InputMap[pos1];
			uint2 pos2 = uint2(pos.x, pos.y - 1);
			float4 color2 = InputMap[pos2];
		if (isDiffColor(color1 - color2))
		{
			if (output.x < 10) {
				output.y = 1;
			}
			else {
				output.x = 3;
			}
			output.z++;
		}
	}

	// check quadrant 4 and 1
	if (wMargin * hMargin * pos.y > 0)
	{
		uint2 pos1 = uint2(pos.x, pos.y - 1);
			float4 color1 = InputMap[pos1];
			uint2 pos2 = uint2(pos.x, pos.y);
			float4 color2 = InputMap[pos2];
		if (isDiffColor(color1 - color2))
		{
			if (output.x < 10) {
				output.y = 2;
			}
			else {
				output.x = 0;
			}
			output.z++;
		}
	}

	if (output.z == 4) {
		codes.x = GetMask(pos, srcPixel);
		uint2 p2 = int2(pos.x, pos.y - 1);
		float4 col2 = InputMap[p2];
		codes.y = GetMask(pos, col2);
	}

	// if found more than 2 neighbors, discard all found discrete paths
	// path > 2 indicate current interpixel is surrounded by noisy pixels,
	// i.e., pixels with all different color, or alternating color
	// this is more likely to be background, so discard
	//if (output.z == 3 || output.z == 1) output.xy = -1;
	discrete_output.discretePath = output;
	discrete_output.codeSurf = codes;

	return discrete_output;
}


/*
*
*	second pass
*
*/
struct FULL_CONNECTED_POINT_OUTPUT
{
	float4 discretePath		: SV_Target0;
};

bool InterpixelOnDiscretePath(int4 fcode)
{
	return fcode.x < 4;
}

static const int MAX_PASS2_STEPS = 20;

bool IsSamePoint(int2 pt1, int2 pt2) {
	return pt1.x == pt2.x && pt1.y == pt2.y;
}

/*
curr MUST be 2-connected points
return:   true :	if next point is 2-connected
		  false:	next point is 4-connected
*/
bool GetNextPoint(in int2 prev, in int2 curr, out int2 next) {
	int4 fcode = (int4)DiscretePathSurface[curr];
	int2 tmpPt = curr + delta[fcode.x];
	if (IsSamePoint(tmpPt, prev)) {
		next = curr + delta[flip[fcode.y]];
	}
	else {
		next = tmpPt;
	}
	fcode = (int4)DiscretePathSurface[next];
	return fcode.z == 2;
}

// check if the inter-pixel at pos is a flat point
// pos must be a 2-connected point
bool IsLocationFlatPoint(in int2 pos) {
	int4 fcode = (int4)DiscretePathSurface[pos];
	return fcode.x == fcode.y;
}

/*
All input points are in inter-pixel coordinates
both pt1 and pt2 MUST be 2-connected points, which is the neighbor of a 4-connected commonSrc
return:  1			pt1 and pt2 are connected
	     0			pt1 and pt2 reach different 4-connected point, pt1 and pt2 may or may not be connected, inconclusive
		-1			inconclusive, i.e., at least one point reaches max search steps
If pt1 and pt2 are connected, it can be one of the two possibilities:
1) pt1 reaches pt2
2) pt1 and pt2 reaches the same 4-connected point
starting from either point, the search stops if encountered a 4-connected point
out uint:		maxStep: if pt1 reaches pt2, it's the length of the path between them
						 if pt2 and pt2 reaches a same 4-connected point, it's the length of the longer path
If pt1 and pt2 reaches the same 4-connected point,
it is still possible that the paths form an inner hole
in this case, pt1 and pt2 is one flat point and one L point
check that the next point from L point has the same x/y (depends on whether the flat point is vertical or horizontal)
with the flat point
*/
int IsTwoPointConnected(int2 commonSrc, int2 pt1, int2 pt2, out uint maxStep)
{
	//bool done = false;
	// start from pt1
	int2 pt1_prev = commonSrc;
	int2 pt1_curr = pt1;
	bool pt1_term = false;
	uint step1 = 0;
	uint LpCountPath1 = 0;
	for (; step1 < MAX_PASS2_STEPS && pt1_term == false; step1++) {
		int2 tmpPt = int2(-1, -1);
		if (GetNextPoint(pt1_prev, pt1_curr, tmpPt) == false) {
			// reached a 4-connected point
			pt1_term = true;
		}
		else {
			// reached a 2-connected point
			// check if it is pt2
			if (IsSamePoint(tmpPt, pt2)) {
				pt1_term = true;
				if (LpCountPath1 < 4) {
					maxStep = step1;
					return 1;
				}
				else {	// most likely pt1 and pt2 forms an inner hole
					return -1;
				}
			}
			else {
				// update the L point count and the direction
				int4 fcode = (int4)DiscretePathSurface[tmpPt];
				if (fcode.x != fcode.y)
					LpCountPath1++;
			}
		}
		// update the point
		pt1_prev = pt1_curr;
		pt1_curr = tmpPt;
	}
	if (pt1_term == false)
		return -1;
	//if (done == true) {
	//	maxStep = step1;
	//	return 1;
	//}
	// pt1 reaches a 4-connected point, check if pt2 can also reach this point
	int2 pt2_prev = commonSrc;
	int2 pt2_curr = pt2;
	bool pt2_term = false;
	uint step2 = 0;
	for (; step2 < MAX_PASS2_STEPS && pt2_term == false; step2++)
	{
		int2 tmpPt = int2(-1, -1);
		if (GetNextPoint(pt2_prev, pt2_curr, tmpPt) == false) {
			// reached a 4-connected point
			pt2_term = true;
		}
		// update the point
		pt2_prev = pt2_curr;
		pt2_curr = tmpPt;
	}

	if (pt2_term) {
		// check if the 4-connected is the same as the one reached from pt1
		// and it must NOT be the starting point
		if (IsSamePoint(pt1_curr, pt2_curr) && IsSamePoint(pt1_curr, commonSrc) == false) {
			maxStep = max(step1, step2);	// return the max steps
			// check if the end point has same x or y value as the start 4-connected point
			if (pt1_curr.x == commonSrc.x || pt1_curr.y == commonSrc.y) {
				// handle differently if needed
				return 1;
			}
			else {
				// pt1 and pt2 reaches a same 4-connected point, which is not on the same vertical/horizontal line as the starting point
				bool pt1Flat = IsLocationFlatPoint(pt1);
				bool pt2Flat = IsLocationFlatPoint(pt2);
				if (pt1Flat && pt2Flat == false) {	// pt1 is flat, pt2 is L point
					int4 fCodePt1 = (int4)DiscretePathSurface[pt1];
					int2 tmpNext = int2(-1, -1);
					GetNextPoint(commonSrc, pt2, tmpNext);
					if (fCodePt1.x & 1) {
						// pt1 is vertical
						return tmpNext.y == pt1.y;
					}
					else {
						return tmpNext.x == pt1.x;
					}
				}
				if (pt2Flat && pt1Flat == false) {
					int4 fCodePt2 = (int4)DiscretePathSurface[pt2];
					int2 tmpNext = int2(-1, -1);
					GetNextPoint(commonSrc, pt1, tmpNext);
					if (fCodePt2.x & 1) {
						return tmpNext.y == pt2.y;
					}
					else {
						return tmpNext.x == pt2.x;
					}
				}
				return 1;
			}
		}
		else {
			return 0;	// pt1 and pt2 reaches two different 4-connected points, non-conclusive
		}
	}

	return -1;	// pt1 reaches a 4-connected && pt2 reaches search max step
}

/*
return		true:		can reach from pt_2Connected to pt_4Connected
			false:		otherwise
*/
bool reachFrom2ConnectedTo4connected(int2 commonSrc, int2 pt_2Connected, int2 pt_4Connected)
{
	int2 prev = commonSrc;
		int2 curr = pt_2Connected;
		bool term = false;
	for (uint i = 0; i < MAX_PASS2_STEPS && term == false; i++) {
		int2 tmpPt = int2(-1, -1);
			if (GetNextPoint(prev, curr, tmpPt) == false) {
				// find a 4-connected point, quit the loop
				term = true;
			}
		prev = curr;
		curr = tmpPt;
	}
	if (term) {
		// check if the reached 4-connected point is the same as input
		if (IsSamePoint(curr, pt_4Connected))
			return true;
		else
			return false;
	}
	return false;
}

struct lineSeg{
	float A;
	float B;
	float C;
};

lineSeg GetLine(float2 pt1, float2 pt2) {
	lineSeg ret;
	ret.A = pt2.y - pt1.y;
	ret.B = pt1.x - pt2.x;
	ret.C = ret.A*pt1.x + ret.B*pt1.y;
	return ret;
}

// ref: https://www.topcoder.com/community/data-science/data-science-tutorials/geometry-concepts-line-intersection-and-its-applications/#line_line_intersection
// check if the line segment of (pt1, pt2) intersect with line segment of (pt3, pt4)
// NOTE: pt2 must be curr_px, pt3 must be the current euclidean point, not prev or next
bool isLinesIntersect(float2 pt1, float2 pt2, float2 pt3, float2 pt4) {
	lineSeg line1 = GetLine(pt1, pt2);
	if (abs(pt2.x - pt2.y) < epsilon) {
		// pt2 is curr_px, if it's in diagnal, check its relationship with the current euclidean pt
		// check if the euclidean point is on this line segment
		float residule = line1.A*pt3.x + line1.B*pt3.y - line1.C;
		if (abs(residule) < epsilon) {
			// three points are on the same line
			return (pt1.x - pt3.x) * (pt3.x - pt2.x) > epsilon;
		}
	}

	lineSeg line2 = GetLine(pt3, pt4);
	float det = line1.A * line2.B - line2.A * line1.B;
	if (abs(det) > epsilon) {
		float x = (line2.B * line1.C - line1.B * line2.C) / det;
		float y = (line1.A * line2.C - line2.A * line1.C) / det;
		// check if the intersection point is in the line segments
		// must use epsilon as follow, simply comparison does not work on GPU, although it works on VS debugger
		if (min(pt1.x, pt2.x) - x > epsilon || x - max(pt1.x, pt2.x) > epsilon || min(pt3.x, pt4.x) - x > epsilon || x - max(pt3.x, pt4.x) > epsilon)
			return false;
		if (min(pt1.y, pt2.y) - y > epsilon || y - max(pt1.y, pt2.y) > epsilon || min(pt3.y, pt4.y) - y > epsilon || y - max(pt3.y, pt4.y) > epsilon)
			return false;

		//if (min(pt1.x, pt2.x) > x || x > max(pt1.x, pt2.x) || min(pt3.x, pt4.x) > x || x > max(pt3.x, pt4.x) )
		//	return false;
		//if (min(pt1.y, pt2.y) > y || y > max(pt1.y, pt2.y) || min(pt3.y, pt4.y) > y || y > max(pt3.y, pt4.y) )
		//	return false;
		return true;
	}
	else {
		// parallel
		return false;
	}
	return false;	// two lines parallel
}

// cross product of 2d vectors
// ref: http://allenchou.net/2013/07/cross-product-of-2d-vectors/
float cross2D(float2 pt1, float2 pt2) {
	float3 v1 = float3(pt1.xy, 0.0f);
		float3 v2 = float3(pt2.xy, 0.0f);

		return cross(v1, v2).z;
}


// the perpendicular distance from pt3 to the line segment of pt1 and pt2
// ref: https://www.topcoder.com/community/data-science/data-science-tutorials/geometry-concepts-basic-concepts/#line_point_distance
float linePointDist(float2 pt1, float2 pt2, float2 pt3) {
	float dist = (cross2D(pt2 - pt1, pt3 - pt1)) / sqrt(dot(pt2 - pt1, pt2 - pt1));
	return abs(dist);
}


// http://allenchou.net/2013/07/cross-product-of-2d-vectors/
// return true:  pt1 and pt2 are on the same side of line composed of linePt1 and linePt2
// NOTE: if pt1 or pt2 is on the line, then they should be considered as on the same side and return true
bool OnSameSide(float2 linePt1, float2 linePt2, float2 pt1, float2 pt2)
{
	float3 ln = float3(linePt1 - linePt2, 0);
		float3 v1 = float3(pt1 - linePt2, 0);
		float3 v2 = float3(pt2 - linePt2, 0);
		float prod = cross(ln, v1).z * cross(ln, v2).z;
	//return !(prod < 0.0f);		// return true if prod is non-negative (need to be careful when compare to zero), this line does NOT work
	return prod > -0.0001;
}

int4 Augment4ConnectedPoint(in int2 pos) {
	
	int4 conn_pass1 = (int4)DiscretePathSurface[pos];
	uint fullConnectNeighborCount = 0;
	uint neighborIs4Connected[5] = { 0, 0, 0, 0, 0 };
	uint flatPointNeighborCount = 0;
	uint neighborIsFlatPoint[5] = { 0, 0, 0, 0, 0 };
	if (conn_pass1.z == 4) {
		// how many neighbors are 4 connected?
		// and how many neighbors are flat point?
		for (uint i = 0; i < 4; i++) {
			int2 neighbor = pos + delta[i];
			int4 fcodeNeighbor = (int4)DiscretePathSurface[neighbor];
			if (fcodeNeighbor.z == 4) {
				fullConnectNeighborCount++;
				neighborIs4Connected[i] = 1;
			}
			else if (IsLocationFlatPoint(neighbor)) {
				flatPointNeighborCount++;
				neighborIsFlatPoint[i] = 1;
			}
		}
		// fill in neighbors for the last
		neighborIs4Connected[4] = neighborIs4Connected[0];
		neighborIsFlatPoint[4] = neighborIsFlatPoint[0];
		bool findNoConnection = true;
		uint neighborConnected[5] = { 0, 0, 0, 0, 0 };
		uint connectedPair = 0;
		if (fullConnectNeighborCount == 0) {
			// all neighbors are 2-connected
			// try to find pairs that are connected, if found connected, it is always true
			// but if found not connected, it can be non-conclusive
			uint id = 0;
			uint stepUsed = MAX_PASS2_STEPS;	// max steps between two points to meet
			uint idWithMinStep = 10;			// init with an invalid id
			uint connectionCount = 0;
			for (uint i = 0; i < 4 /*&& findNoConnection*/; i++) {	// try all pairs
				// check i, i+1 is connected or not
				int2 pt1 = pos + delta[i];
				int2 pt2 = pos + delta[i + 1];
				uint tmpStep = MAX_PASS2_STEPS;
				bool connected = IsTwoPointConnected(pos, pt1, pt2, tmpStep) == 1;
				if (connected) {
					connectionCount++;
					// check if at least one of the point is L point
					// if both are flat point, it's likely that they are connected through an inner hole
					if (neighborIsFlatPoint[i] == 0 || neighborIsFlatPoint[i + 1] == 0) {
						findNoConnection = false;
						neighborConnected[i] = 1;
						connectedPair++;
						if (stepUsed > tmpStep) {
							idWithMinStep = i;
							stepUsed = tmpStep;
						}
					}
				}
				if (connectionCount == 4 && flatPointNeighborCount < 2) {
					idWithMinStep = (idWithMinStep + 1) % 4;	// deal with 'd', 'p', 'b'
				}
			}
			bool bConnected1 = false;
			bool bConnected2 = false;
			if (connectedPair == 2 && flatPointNeighborCount == 1) {
				// check the flat point, this is for the 'e' special case
				// verify that the flat point neighbor is connected to both other two L points
				// first find the id of the flat point
				uint flatId = 0;
				for (uint k = 0; k < 4; k++) {
					if (neighborIsFlatPoint[k] == 1) {
						flatId = k;
					}
				}
				// use the saved data to check connectivity
				bConnected1 = neighborConnected[flatId] == 1;
				if (flatId == 0) {	// flat point is the first neighbor, it's 'prev' neighbor is 3
					bConnected2 = neighborConnected[3] == 1;
				}
				else {
					bConnected2 = neighborConnected[flatId - 1] == 1;
				}
			}

			if (bConnected1 && bConnected2) {
				// fall back to diagnoal neighbor method
				for (uint j = 0; j < 4; j++) {
					int2 dNeighbor = pos + delta_near[j];
						int4 fcodeNeighbor = (int4)DiscretePathSurface[dNeighbor];
						if (fcodeNeighbor.x < 10) {
							conn_pass1 = codeTemplate[j + 1];
						}
				}
			}
			else {
				
				//for (uint i = 0; i < 4; i++) {
				//	if (neighborConnected[i] == 1)
				//		id = i;
				//}
				// there might be more than one pair that are connected, e.g., 'P'
				// pick the pair that has the lowest steps
				if (idWithMinStep < 4)
					id = idWithMinStep + 1;
				if (!findNoConnection) {
					// assign the direction based on the index i
					conn_pass1 = codeTemplate[id];
				}
			}
		}

		// have one 4-connected neighbor, go thru all pairs until find connection
		// if two 2-connected point, same as above
		// if one is 2-connect, the other is 4-connected, check if 2-connected can reach 4-connected
		if (fullConnectNeighborCount == 1) {
			uint i = 0;
			for (; i < 4 && findNoConnection; i++) {
				bool isConnected = false;
				if (neighborIs4Connected[i] == neighborIs4Connected[i + 1]) {
					// both are 2-connected;
					int2 pt1 = pos + delta[i];
						int2 pt2 = pos + delta[i + 1];
						uint tmpStep = 0;
					isConnected = IsTwoPointConnected(pos, pt1, pt2, tmpStep) == 1;
					// check if at least one of the neighbor is L point
					// this is to prevent inner hole pass the test, e.g., 'B'
					if (isConnected && (neighborIsFlatPoint[i] == 0 || neighborIsFlatPoint[i + 1] == 0)) {
						findNoConnection = false;
					}
				}
				else {
					// one is 2-connected, the other is 4-connected
					int2 pt1 = pos + delta[i];
						int2 pt2 = pos + delta[i + 1];
						if (neighborIs4Connected[i] == 0) {
							// pt1 is 2-connected, further check if it's a L point
							isConnected = reachFrom2ConnectedTo4connected(pos, pt1, pt2);
							if (isConnected /*&& neighborIsFlatPoint[i] == 0 */) {
								findNoConnection = false;
							}
						}
						else {
							// pt2 is 2-connected
							isConnected = reachFrom2ConnectedTo4connected(pos, pt2, pt1);
							{
								if (isConnected /*&& neighborIsFlatPoint[i + 1] == 0 */) {
									findNoConnection = false;
								}
							}
						}
				}
				
			}
			if (!findNoConnection) {
				// assign directions
				conn_pass1 = codeTemplate[i];
			}
		}

		// if have two 4-connected neighbors, these two must defines a quadrant (they cannot be all vertical or horizontal), assign opposite quadrant direction
		if (fullConnectNeighborCount == 2) {
			uint i = 0;
			for (; i < 4 && findNoConnection; i++) {
				if (neighborIs4Connected[i] == 1 && neighborIs4Connected[i + 1] == 1) {
					findNoConnection = false;		// not sure if it's true, just use to stop the loop
					conn_pass1 = codeTemplate[i + 1];
				}
			}
		}

		// TODO: evil case
		if (fullConnectNeighborCount == 3) {

		}

		// devil case, chessboard pattern, no way to choose, unless text color information is available
		if (fullConnectNeighborCount == 4) {

		}

		// cannot find connection, likely inconclusive
		if (findNoConnection == true) {
			// all efforts so far fail to make some sense out of the grid pattern
			// fall back to use the diagnal neighbors
			for (uint i = 0; i < 4; i++) {
				int2 neighbor = pos + delta_near[i];
				int4 fcodeNeighbor = (int4)DiscretePathSurface[neighbor];
				if (fcodeNeighbor.x < 10) {
					conn_pass1 = codeTemplate[i + 1];
					findNoConnection = false;
				}
			}
			
		}

		// if still unprocessed, assign a value
		if (findNoConnection == true) {
			conn_pass1 = codeTemplate[1];
		}
	}
	else {
		conn_pass1.zw = 10;
		// if it is a L shape 2-connected point, determine whether it's a one-pixel corner point or two-pixel corner point
		if (IsLocationFlatPoint(pos) == false) {
			// get the two neighborsd
			int2 neighbor1 = pos + delta[conn_pass1.x];
			int2 neighbor2 = pos + delta[flip[conn_pass1.y]];
			// one-pixel corner point must have one L neighbor and one flat point neighbor
			bool isFlatPt1 = IsLocationFlatPoint(neighbor1);
			bool isFlatPt2 = IsLocationFlatPoint(neighbor2);
			if (isFlatPt2 == false && isFlatPt1) {
				// neighbor1 is flat point, check if neighbor2 is 2-connected
				int4 fCodeNeighbor2 = (int4)DiscretePathSurface[neighbor2];
					if (fCodeNeighbor2.z == 2) {
						int2 nextPt = int2(-1, -1);
						GetNextPoint(pos, neighbor2, nextPt);
						//check if nextPt and neighbor1 is at the same side of the line
						// comprised of pos and neighbor2
						if (OnSameSide(pos, neighbor2, neighbor1, nextPt) == true) {
							conn_pass1.w = 1;	// mark as a one-pixel corner point
						}
					}
			}
			else if (isFlatPt1 == false && isFlatPt2) {
				// neighbor2 is flat point, check if neighbor1 is 2-connected
				int4 fCodeNeighbor1 = (int4)DiscretePathSurface[neighbor1];
					if (fCodeNeighbor1.z == 2) {
						int2 nextPt = int2(-1, -1);
						GetNextPoint(pos, neighbor1, nextPt);
						if (OnSameSide(pos, neighbor1, neighbor2, nextPt) == true) {
							conn_pass1.w = 1;
						}
					}
			}
			else if (isFlatPt1 == false && isFlatPt2 == false) {
				// both are L point, like the four pixels in dot, or the sanrif of t, f etc.
				int4 fCodeNeighbor1 = (int4)DiscretePathSurface[neighbor1];
				int4 fCodeNeighbor2 = (int4)DiscretePathSurface[neighbor2];
				if (fCodeNeighbor1.z == 2) {
					// use the same approach above, but check twice, since there might be only
					// one case that's true
					int2 nextPt = int2(-1, -1);
						GetNextPoint(pos, neighbor1, nextPt);
					if (OnSameSide(pos, neighbor1, neighbor2, nextPt) == true) {
						conn_pass1.w = 1;
					}
				}
				if (fCodeNeighbor2.z == 2) {
					int2 nextPt = int2(-1, -1);
						GetNextPoint(pos, neighbor2, nextPt);
					if (OnSameSide(pos, neighbor2, neighbor1, nextPt) == true) {
						conn_pass1.w = 1;
					}
				}
			}
		}
	}
	return conn_pass1;
}

/*
*
*	third pass
*
*/
FULL_CONNECTED_POINT_OUTPUT PS_ADV_FULL_CONNECTED_POINT(in VS_OUTPUT input)
{
	FULL_CONNECTED_POINT_OUTPUT  discrete_output;
	int2 pos = (int2)input.position.xy;

	discrete_output.discretePath = Augment4ConnectedPoint(pos);
	return discrete_output;
}




struct PS_EUCLIDEAN_PATH_OUTPUT
{
	float4		euclidean		: SV_Target0;
	//float2		prev_euclidean	: SV_Target1;
	//float2		next_euclidean	: SV_Target2;
};
/*
struct DLine
{
	// a, b is determined by lean points in 1st octave
	// u is determined by UminR, LminR, a, b
	int		a;
	int		b;
	int		u;
	// lean points in 1st octave
	int2	Umin;	
	int2	Umax;
	int2	Lmin;
	int2	Lmax;
	// lean points in 1st quadrant
	int2	UminR;	// coordinates of upper min lean point on interpixel surface
	int2	UmaxR;
	int2	LminR;	// coordinates of Lower min lean upoint on interpixel surface
	int2	LmaxR;
	uint	directions;
};

// update based on 4 way freeman code, code ranges from 0 to 3
int2 nextForwardPoint(in int2 pt, in int code)
{
	int2 output = pt;
	if (code == 0) output.x++;
	if (code == 1) output.y++;
	if (code == 2) output.x--;
	if (code == 3) output.y--;
	return output;
}

// given the destination point 'pt' and freeman code 'code'
// output the start point
int2 nextBackwardPoint(in int2 pt, in int code)
{
	int2 output = pt;
	if (code == 0) output.x--;
	if (code == 1) output.y--;
	if (code == 2) output.x++;
	if (code == 3) output.y++;
	return output;
}

// update based on 8 way freeman code, code is either 0 or 1
int2 nextFwOctavePoint(in int2 pt, in int code)
{
	int2 output = pt;
	output.x++;
	if (code == 1) output.y++;
	return output;
}

int2 nextBkOctavePoint(in int2 pt, in int code)
{
	int2 output = pt;
	output.x--;
	if (code == 1) output.y--;
	return output;
}

// check if curr_pt can be reached from prev_pt with given freemanCode
// works both forward and backward, because it checks the only two possibly
// reachable points from current point
bool isRightPath(in int2 curr_pt, in int2 prev_pt, in int2 freemanCode) {
	int2 tmpLoc = curr_pt + delta[freemanCode.x];
		tmpLoc = tmpLoc - prev_pt;
	if (dot(tmpLoc, tmpLoc) == 0) return true;
	tmpLoc = curr_pt + delta[flip[freemanCode.y]];
	tmpLoc = tmpLoc - prev_pt;
	return dot(tmpLoc, tmpLoc) == 0;
}

float2 CalculateLineApproximation(in int2 curr_code, in int2 discretePt, bool isTwoConnected)
{
		bool isFlatItself = false;
	if (curr_code.x == curr_code.y)
		isFlatItself = true;
	int2 freemanCode = curr_code;

		// now get the quadrant, in fact we are only interested in knowing 
		// if it's in I, III quadrant or II IV quadrant
	uint quadrant = 1;		// I or III quadrant
	uint qSum = freemanCode.x + freemanCode.y;
	if (qSum == 3) quadrant = 2; // II or IV quadrant

	DLine tangent;
	tangent.u = 0;
	tangent.b = 1;
	tangent.Umin = int2(0, 0);
	tangent.Lmin = int2(0, 0);
	tangent.UminR = int2(0, 0);
	tangent.LminR = int2(0, 0);
	if (isFlatItself) {
		tangent.directions = 1;
	}
	else {
		tangent.directions = 2;
	}

	// this is the last point included in the discrete path
	// the following three points are for three different purpose
	// 1. fdPt is used to get the discrete path information for a particular interpixel
	// 2. fdPtInOctave is used to updatea, b, Umin, Umax, Lmin, Lmax
	// 3. fdPt_quad1 is used to update UminR, UmaxR, LminR, LmaxR, these are for calculate u later
	int2 fdPt = discretePt.xy;		// forward point in interpixel surface, update with true freeman code
		int2 fdPtInOctave = int2(0, 0);		// forward point in 1st octave, update with freeman code % 2  (8 connected way)
		int2 fdPt_quad1 = fdPtInOctave;		// forward point in 1st quadrant, update with freeman code % 2 (4 connected way)

		bool encounter4Connected = false;

		// keep a record of second to the last forward point
		// so that we know which neighbor has been visited already
		int2 prev_fdPt = fdPt;
		// this point is already included in segment
		fdPt = nextForwardPoint(prev_fdPt, freemanCode.x);

	// prepare initial condition
	if (((uint)freemanCode.x) % 2) {
		// first step is go north-east
		tangent.a = 1;
		tangent.Umax = int2(1, 1);
		tangent.Lmax = int2(1, 1);
	}
	else {
		// first step is go east
		tangent.a = 0;
		tangent.Umax = int2(1, 0);
		tangent.Lmax = int2(1, 0);
	}
	fdPt_quad1 = nextForwardPoint(fdPt_quad1, ((uint)freemanCode.x));
	fdPtInOctave = tangent.Umax;
	tangent.UmaxR = fdPt_quad1;
	tangent.LmaxR = fdPt_quad1;

	int2 bkPt = prev_fdPt;
		int2 prev_bkPt = fdPt;
		int2 bkPtInOctave = int2(0, 0);
		int2 bkPt_quad1 = bkPtInOctave;

		uint step;
	bool isSinglePixelCorner = false;
	uint2 neighborNonFlatPoint = uint2(10, 10);
	
	//At this point, right before entering the loop, the following variables contain:
	//fdPt: the next forward neighbor of the starting interpixel
	//prev_fdPt:  the starting interpixel
	//bkPt: the starting interpixel
	//prev_bkPt: same as fdPt
	
	for (step = 0; step < MAX_STEP; ++step)
	{
		int4 srcFdCode = (int4)FullConnectedDiscretePathSurface[fdPt];
			int2 fdCode = srcFdCode.xy;
			if (srcFdCode.z >= 0) {
				encounter4Connected = true;
				if (isRightPath(fdPt, prev_fdPt, srcFdCode.zw)) {
					fdCode = srcFdCode.zw;
				}
			}
		if (fdCode.x != fdCode.y && neighborNonFlatPoint.x == 10) {
			neighborNonFlatPoint.x = step + 1;
		}

		// update the forward freeman code based on last two forward points
		// first, retrieve the forward freeman code of current forward point
		if (freemanCode.x < 0) fdCode.x = -1;	// fdPt already visited but should not be included
		if (fdCode.x < 0) {
			freemanCode.x = -1;	// done
		}
		else {
			// get the coordinates of its first neighbor
			int2 firstNeighbor = nextForwardPoint(fdPt, fdCode.x);

				// check if first neighbor has not been visited (is not the previous forward point)
				if (any(firstNeighbor - prev_fdPt)) {
					freemanCode.x = fdCode.x;	// update the forward code, no need to flip
				}
				else {
					// second neighbor is the next forward point, since the freeman code is backward (in)
					// need to flip it to be forward
					//if (((uint)fdCode.y) % 2 == 0) freemanCode.x = 2 - fdCode.y;
					//else freemanCode.x = 4 - fdCode.y;
					freemanCode.x = flip[fdCode.y];
				}
				// stop if this neighbor changes quadrant, i.e., has freeman code different from current ones
				if (freemanCode.x != curr_code.x && freemanCode.x != curr_code.y)
				{
					if (curr_code.x != curr_code.y) {
						freemanCode.x = -1;
						if (step == 0)
							isSinglePixelCorner = true;
						tangent.directions++;
					}
					else {
						curr_code.y = freemanCode.x;
						qSum = curr_code.x + curr_code.y;
						if (qSum == 3) quadrant = 2;
						else quadrant = 1;
					}
				}
		}

		// search forward
		if (freemanCode.x >= 0) {
			// update forward points based on forward freeman code
			prev_fdPt = fdPt;
			fdPt = nextForwardPoint(prev_fdPt, freemanCode.x);

			// check if this point should be included in the discrete segment
			// first convert to 8 connected case
			fdPtInOctave = nextFwOctavePoint(fdPtInOctave, ((uint)freemanCode.x) % 2);
			// update 4 connected forward point
			fdPt_quad1 = nextForwardPoint(fdPt_quad1, (uint)freemanCode.x);

			bool sameSegment = false;
			int r = tangent.a * fdPtInOctave.x - tangent.b * fdPtInOctave.y;
			if (tangent.u < r && r < tangent.u + tangent.b - 1)
			{	// case 1: u < r < u + b -1
				sameSegment = true;
			}
			if (r == tangent.u + tangent.b - 1)
			{	// case 1a: r == u + b - 1
				tangent.Lmax = fdPtInOctave;
				tangent.LmaxR = fdPt_quad1;
				sameSegment = true;
			}
			if (r == tangent.u)
			{	// case 1b: r == u
				tangent.Umax = fdPtInOctave;
				tangent.UmaxR = fdPt_quad1;
				sameSegment = true;
			}
			if (r == tangent.u - 1)
			{	// case 2: r == u - 1
				tangent.Umax = fdPtInOctave;
				tangent.Lmin = tangent.Lmax;
				tangent.a = fdPtInOctave.y - tangent.Umin.y;
				tangent.b = fdPtInOctave.x - tangent.Umin.x;
				tangent.u = tangent.a * fdPtInOctave.x - tangent.b * fdPtInOctave.y;
				// update the 1st quadrant lean points
				tangent.UmaxR = fdPt_quad1;
				tangent.LminR = tangent.LmaxR;
				sameSegment = true;
			}
			if (r == tangent.u + tangent.b)
			{	// case 3: r == u + b
				tangent.Umin = tangent.Umax;
				tangent.Lmax = fdPtInOctave;
				tangent.a = fdPtInOctave.y - tangent.Lmin.y;
				tangent.b = fdPtInOctave.x - tangent.Lmin.x;
				tangent.u = tangent.a * fdPtInOctave.x - tangent.b * fdPtInOctave.y - tangent.b + 1;
				// update the 1st quadrant lean points
				tangent.UminR = tangent.UmaxR;
				tangent.LmaxR = fdPt_quad1;
				sameSegment = true;
			}
			if (!sameSegment)
			{
				freemanCode.x = -1;
			}
			//else {
			//	fd_step = step + 1;
			//}
		}

		// update the backward freeman code
		// first retrieve the backward freeman code of current backward point
		int4 srcBkCode = (int4)FullConnectedDiscretePathSurface[bkPt];
			int2 bkCode = srcBkCode.xy;
			if (srcBkCode.z >= 0) {
				encounter4Connected = true;
				if (isRightPath(bkPt, prev_bkPt, srcBkCode.zw))
					bkCode = srcBkCode.zw;
			}
		if (bkCode.x != bkCode.y && step > 0 && neighborNonFlatPoint.y == 10) {
			neighborNonFlatPoint.y = step;
		}
		if (freemanCode.y < 0) bkCode.x = -1;
		if (bkCode.x < 0) {
			freemanCode.y = -1;
		}
		else {
			// get first neighbor
			int2 firstNeighbor = nextBackwardPoint(bkPt, bkCode.y);

				if (any(firstNeighbor - prev_bkPt)) {
					freemanCode.y = bkCode.y;
				}
				else {
					//if ((uint)bkCode.x % 2 == 0) freemanCode.y = 2 - bkCode.x;
					//else freemanCode.y = 4 - bkCode.x;
					freemanCode.y = flip[bkCode.x];
				}
				if (freemanCode.y != curr_code.x && freemanCode.y != curr_code.y)
				{
					if (curr_code.x != curr_code.y) {
						freemanCode.y = -1;
						if (step == 1)
							isSinglePixelCorner = true;
						tangent.directions++;
					}
					else {
						curr_code.y = freemanCode.y;
						qSum = curr_code.x + curr_code.y;
						if (qSum == 3) quadrant = 2;
						else quadrant = 1;
					}
				}
		}

		// search backward
		if (freemanCode.y >= 0) {
			prev_bkPt = bkPt;
			bkPt = nextBackwardPoint(prev_bkPt, freemanCode.y);

			bkPtInOctave = nextBkOctavePoint(bkPtInOctave, (uint)freemanCode.y % 2);
			bkPt_quad1 = nextBackwardPoint(bkPt_quad1, (uint)freemanCode.y);

			bool sameSegment = false;
			int r = tangent.a * bkPtInOctave.x - tangent.b * bkPtInOctave.y;
			if (tangent.u < r && r < tangent.u + tangent.b - 1)
			{	// case 1: u < r < u + b -1
				sameSegment = true;
			}
			if (r == tangent.u + tangent.b - 1)
			{	// case 1a: r == u + b - 1
				tangent.Lmin = bkPtInOctave;
				tangent.LminR = bkPt_quad1;
				sameSegment = true;
			}
			if (r == tangent.u)
			{	// case 1b: r == u
				tangent.Umin = bkPtInOctave;
				tangent.UminR = bkPt_quad1;
				sameSegment = true;
			}
			if (r == tangent.u - 1)
			{
				tangent.Umin = bkPtInOctave;
				tangent.Lmax = tangent.Lmin;
				tangent.a = tangent.Umax.y - bkPtInOctave.y;
				tangent.b = tangent.Umax.x - bkPtInOctave.x;
				tangent.u = tangent.a * bkPtInOctave.x - tangent.b * bkPtInOctave.y;

				tangent.UminR = bkPt_quad1;
				tangent.LmaxR = tangent.LminR;
				sameSegment = true;
			}
			if (r == tangent.u + tangent.b)
			{
				tangent.Lmin = bkPtInOctave;
				tangent.Umax = tangent.Umin;
				tangent.a = tangent.Lmax.y - bkPtInOctave.y;
				tangent.b = tangent.Lmax.x - bkPtInOctave.x;
				tangent.u = tangent.a * bkPtInOctave.x - tangent.b * bkPtInOctave.y - tangent.b + 1;

				tangent.LminR = bkPt_quad1;
				tangent.UmaxR = tangent.UminR;
				sameSegment = true;
			}
			if (!sameSegment)
			{
				freemanCode.y = -1;
			}
			//else {
			//	bk_step = step;
			//}
		}
	}

	if (isFlatItself ) {
		return float2(0.0f, 0.0f);
	}

	if (isTwoConnected && isFlatItself == false) {

		// make one pixel corner square
		if (isSinglePixelCorner) {
			return float2(0.0f, 0.0f);
		}
		
		// make corner square
		if ( neighborNonFlatPoint.x >= FLAT_NEIGHBOR && neighborNonFlatPoint.y >= FLAT_NEIGHBOR) {
			return float2(0.0f, 0.0f);
		}

		//if (isFlatItself == true && encounter4Connected == false) {
		//	return float2(0.0f, 0.0f);
		//}
	}

	

	//// update the quadrant if the starting interpixel is vertical/horizontal
	//if (curr_code.x == curr_code.y)
	//{
	//	quadrant = 3;
	//}

	// for testing
	// update a, b for 4 connected
	// the special cases (horizontal, vertical) is included, no special treatment needed
	// if horizontal: a=b=0; return (0,0) in either case
	// if vertical: a=b=1; return (1,0) in either case
	int2 coeff = { 0, 0 };
		if (quadrant == 1) {
			coeff = int2(tangent.a, tangent.b - tangent.a);
		}
	if (quadrant == 2) {
		coeff = int2(tangent.a, tangent.a - tangent.b);
	}

	// calculate u with Umin and Lmin
	float c1 = coeff.x * tangent.UminR.x - coeff.y * tangent.UminR.y;
	float c2 = coeff.x * tangent.LminR.x - coeff.y * tangent.LminR.y;
	float real_u = (c1 + c2) / 2;
	float2 euPt = { 10.0f, 10.0f };

	// calculate the euclidean point for this interpixel
	if (quadrant == 1) {
		float val = real_u / (coeff.x + coeff.y);
		euPt = float2(val, -val);
	}
	else if (quadrant == 2) {
		float val = real_u / (coeff.x - coeff.y);
		euPt = float2(val, val);
	}
	if (tangent.a == 0 || tangent.a == tangent.b)
		euPt.xy = 0.0f;
	return euPt;
}

// output three (m+1) * (n+1) surfaces
// if this interpixel is not on discrete path, output 10.0f
PS_EUCLIDEAN_PATH_OUTPUT PS_EUCLIDEAN_PATH_FREEMAN(in VS_OUTPUT input)
{
	PS_EUCLIDEAN_PATH_OUTPUT output;

	int4 curr_code = (int4)FullConnectedDiscretePathSurface[input.position.xy];
		if (curr_code.x < 0 || curr_code.y < 0) {
			output.euclidean = float4(10.0f, 10.0f, 10.0f, 10.0f);
			return output;
		}

	// find the euclidean point for current interpixel,
	// which is the origin of the coordinate system
	// used to describe the corresponding euclidean point
	// First, find the freeman code for this interpixel
	// freemanCode.x is the forward freemancode (out), freemanCode.y is the backward freemancode (in)
	float2 eupt1 = CalculateLineApproximation(curr_code.xy, (int2)input.position.xy, curr_code.z == 10);
	float2 eupt2 = float2(10.0f, 10.0f);
	if (curr_code.z < 10) {
		eupt2 = CalculateLineApproximation(curr_code.zw, (int2)input.position.xy, false);
	}

	output.euclidean = float4(eupt1.xy, eupt2.xy);
	return output;

};

*/

bool IsValidFreemanCode(uint code) {
	return code < InvalidFreemanCode;
}



// check if curr_pt can be reached from prev_pt with given freemanCode
// works both forward and backward, because it checks the only two possibly
// reachable points from current point
// freemanCdoe is the freeman code associated with curr_pt
bool isRightPath(in int2 curr_pt, in int2 prev_pt, in uint2 freemanCode) {
	int2 tmpLoc = curr_pt + delta[freemanCode.x];
		tmpLoc = tmpLoc - prev_pt;
	if (dot(tmpLoc, tmpLoc) == 0) return true;
	// check the other possible direction
	tmpLoc = curr_pt + delta[flip[freemanCode.y]];
	tmpLoc = tmpLoc - prev_pt;
	return dot(tmpLoc, tmpLoc) == 0;
}

struct DLine
{
	// a, b is determined by lean points in 1st octave
	// u is determined by UminR, LminR, a, b
	int		a;
	int		b;
	int		u;
	// lean points in 1st octave
	int2	Umin;
	int2	Umax;
	int2	Lmin;
	int2	Lmax;
	// lean points in 1st quadrant
	int2	UminR;	// coordinates of upper min lean point on interpixel surface
	int2	UmaxR;
	int2	LminR;	// coordinates of Lower min lean upoint on interpixel surface
	int2	LmaxR;
	uint	directions;
};

// update based on 4 way freeman code, code ranges from 0 to 3
int2 nextForwardPoint(in int2 pt, in uint code)
{
	int2 output = pt;
		if (code == 0) output.x++;
	if (code == 1) output.y++;
	if (code == 2) output.x--;
	if (code == 3) output.y--;
	return output;
}

// given the destination point 'pt' and freeman code 'code'
// output the start point
int2 nextBackwardPoint(in int2 pt, in uint code)
{
	int2 output = pt;
		if (code == 0) output.x--;
	if (code == 1) output.y--;
	if (code == 2) output.x++;
	if (code == 3) output.y++;
	return output;
}

// update based on 8 way freeman code, code is either 0 or 1
int2 nextFwOctavePoint(in int2 pt, in uint code)
{
	int2 output = pt;
		output.x++;
	if (code == 1) output.y++;
	return output;
}

int2 nextBkOctavePoint(in int2 pt, in uint code)
{
	int2 output = pt;
		output.x--;
	if (code == 1) output.y--;
	return output;
}

float2 CalculateLineApproximation(in uint2 curr_code, in int2 discretePt, bool isTwoConnected)
{
	bool isFlatItself = curr_code.x == curr_code.y;
	uint2 freemanCode = curr_code;

		// try get the quadrant
		// quadrant is defined based on the freemancode of the line segment under investigation
		// a line segment (consists of inter-pixels) can only have (at most) two distinctive freeman code
		// a third freeman code will fail the test to be included in the line segment
		// therefore, with these two freeman code, we define the quadrant as follows:
		// i) inter-pixel line segment with freeman code sum up to 3 are considered I/III quadrant
		// this include paths like: 0 0 3 0 0 3 ... or 
		//in fact we are only interested in knowing 
		// if it's in I, III quadrant or II IV quadrant
		uint quadrant = 1;		// I or III quadrant
	uint qSum = freemanCode.x + freemanCode.y;
	if (qSum == 3) quadrant = 2; // II (1,2) or IV(0,3) quadrant

	uint2 neighborNonFlatPoint = uint2(MaxSearchStep + 1, MaxSearchStep + 1);		// steps to the first L point neighbor
	//bool onePixelCornerNearyBy[2] = { false, false };	// indicate if there is a one-pixel corner within range of MaxSearchStep
														// this bool is true only if the one-pixel corner is reached without encounting any L point

	DLine tangent;
	tangent.u = 0;
	tangent.b = 1;
	tangent.Umin = int2(0, 0);
	tangent.Lmin = int2(0, 0);
	tangent.UminR = int2(0, 0);
	tangent.LminR = int2(0, 0);
	if (isFlatItself) {
		tangent.directions = 1;
	}
	else {
		tangent.directions = 2;
	}

	// the following three points are for three different purpose
	// 1. fdPt is used to get the discrete path information for this interpixel from previous pass
	// 2. fdPtInOctave is used to updatea, b, Umin, Umax, Lmin, Lmax
	// 3. fdPt_quad1 is used to update UminR, UmaxR, LminR, LmaxR, these are for calculate u later
	int2 fdPt = discretePt.xy;			// forward point in interpixel surface, update with true freeman code
		int2 fdPtInOctave = int2(0, 0);		// forward point in 1st octave, update with freeman code % 2  (8 connected way)
		int2 fdPt_quad1 = fdPtInOctave;		// forward point in 1st quadrant, update with freeman code % 2 (4 connected way)

		bool encounter4Connected[2] = { false, false };

	// keep a record of second to the last forward point
	// so that we know which neighbor has been visited already
	int2 prev_fdPt = fdPt;
		// this point is already included in segment
		fdPt = nextForwardPoint(prev_fdPt, freemanCode.x);



	// prepare initial condition
	if (freemanCode.x % 2) {
		// first step is go north-east
		tangent.a = 1;
		tangent.Umax = int2(1, 1);
		tangent.Lmax = int2(1, 1);
	}
	else {
		// first step is go east
		tangent.a = 0;
		tangent.Umax = int2(1, 0);
		tangent.Lmax = int2(1, 0);
	}
	fdPt_quad1 = nextForwardPoint(fdPt_quad1, freemanCode.x);
	fdPtInOctave = tangent.Umax;
	tangent.UmaxR = fdPt_quad1;
	tangent.LmaxR = fdPt_quad1;

	int2 bkPt = prev_fdPt;
		int2 prev_bkPt = fdPt;
		int2 bkPtInOctave = int2(0, 0);
		int2 bkPt_quad1 = bkPtInOctave;

		uint step;
	bool isSinglePixelCorner = false;
	
		/*
		At this point, right before entering the loop, the following variables contain:
		fdPt: the next forward neighbor of the starting interpixel
		prev_fdPt:  the starting interpixel
		bkPt: the starting interpixel
		prev_bkPt: same as fdPt
		*/
		for (step = 0; step < MaxSearchStep; ++step)
		{
			uint4 srcFdCode = FullConnectedDiscretePathSurface[fdPt];
				uint2 fdCode = srcFdCode.xy;
				if (IsValidFreemanCode(srcFdCode.z)) {
					encounter4Connected[0] = true;
					//onePixelCornerNearyBy[0] = false;
					if (isRightPath(fdPt, prev_fdPt, srcFdCode.zw)) {
						fdCode = srcFdCode.zw;
					}
				}
				//else if (srcFdCode.w < 10 && neighborNonFlatPoint.x == MaxSearchStep + 1 && encounter4Connected[0] == false) {
						//onePixelCornerNearyBy[0] = true;
					//}
			if (fdCode.x != fdCode.y && neighborNonFlatPoint.x == MaxSearchStep+1 && srcFdCode.w != 1) {	// encounter first non-flat point
				neighborNonFlatPoint.x = step + 1;
			}

			// update the forward freeman code based on last two forward points
			// first, retrieve the forward freeman code of current forward point
			if (IsValidFreemanCode(freemanCode.x) == false ) fdCode.x = 10;	// fdPt already visited but should not be included
			if (IsValidFreemanCode(fdCode.x) == false) {
				freemanCode.x = 10;	// done
			}
			else {
				// get the coordinates of its first neighbor
				int2 firstNeighbor = nextForwardPoint(fdPt, fdCode.x);

					// check if first neighbor has not been visited (is not the previous forward point)
					if (any(firstNeighbor - prev_fdPt)) {
						freemanCode.x = fdCode.x;	// update the forward code, no need to flip
					}
					else {
						// second neighbor is the next forward point, since the freeman code is backward (in)
						// need to flip it to be forward
						freemanCode.x = flip[fdCode.y];
					}
					// stop if this neighbor changes quadrant, i.e., has freeman code different from current ones
					if (freemanCode.x != curr_code.x && freemanCode.x != curr_code.y)
					{
						if (curr_code.x != curr_code.y) {
							freemanCode.x = 10;
							if (step == 0)
								isSinglePixelCorner = true;
							tangent.directions++;
						}
						else {
							curr_code.y = freemanCode.x;
							qSum = curr_code.x + curr_code.y;
							if (qSum == 3) quadrant = 2;
							else quadrant = 1;
						}
					}
			}

			// search forward
			if (IsValidFreemanCode(freemanCode.x)) {
				// update forward points based on forward freeman code
				prev_fdPt = fdPt;
				fdPt = nextForwardPoint(prev_fdPt, freemanCode.x);

				// check if this point should be included in the discrete segment
				// first convert to 8 connected case
				fdPtInOctave = nextFwOctavePoint(fdPtInOctave, freemanCode.x % 2);
				// update 4 connected forward point
				fdPt_quad1 = nextForwardPoint(fdPt_quad1, freemanCode.x);

				bool sameSegment = false;
				int r = tangent.a * fdPtInOctave.x - tangent.b * fdPtInOctave.y;
				if (tangent.u < r && r < tangent.u + tangent.b - 1)
				{	// case 1: u < r < u + b -1
					sameSegment = true;
				}
				if (r == tangent.u + tangent.b - 1)
				{	// case 1a: r == u + b - 1
					tangent.Lmax = fdPtInOctave;
					tangent.LmaxR = fdPt_quad1;
					sameSegment = true;
				}
				if (r == tangent.u)
				{	// case 1b: r == u
					tangent.Umax = fdPtInOctave;
					tangent.UmaxR = fdPt_quad1;
					sameSegment = true;
				}
				if (r == tangent.u - 1)
				{	// case 2: r == u - 1
					tangent.Umax = fdPtInOctave;
					tangent.Lmin = tangent.Lmax;
					tangent.a = fdPtInOctave.y - tangent.Umin.y;
					tangent.b = fdPtInOctave.x - tangent.Umin.x;
					tangent.u = tangent.a * fdPtInOctave.x - tangent.b * fdPtInOctave.y;
					// update the 1st quadrant lean points
					tangent.UmaxR = fdPt_quad1;
					tangent.LminR = tangent.LmaxR;
					sameSegment = true;
				}
				if (r == tangent.u + tangent.b)
				{	// case 3: r == u + b
					tangent.Umin = tangent.Umax;
					tangent.Lmax = fdPtInOctave;
					tangent.a = fdPtInOctave.y - tangent.Lmin.y;
					tangent.b = fdPtInOctave.x - tangent.Lmin.x;
					tangent.u = tangent.a * fdPtInOctave.x - tangent.b * fdPtInOctave.y - tangent.b + 1;
					// update the 1st quadrant lean points
					tangent.UminR = tangent.UmaxR;
					tangent.LmaxR = fdPt_quad1;
					sameSegment = true;
				}
				if (!sameSegment)
				{
					freemanCode.x = 10;
				}
			}

			// update the backward freeman code
			// first retrieve the backward freeman code of current backward point
			uint4 srcBkCode = FullConnectedDiscretePathSurface[bkPt];
				uint2 bkCode = srcBkCode.xy;
				if (IsValidFreemanCode(srcBkCode.z)) {
					encounter4Connected[1] = true;
					//onePixelCornerNearyBy[1] = false;
					if (isRightPath(bkPt, prev_bkPt, srcBkCode.zw))
						bkCode = srcBkCode.zw;
				}
				//else if (srcBkCode.w < 10 && neighborNonFlatPoint.y == MaxSearchStep + 1 && encounter4Connected[1] == false) {
				//	onePixelCornerNearyBy[1] = true;
				//}
			if (bkCode.x != bkCode.y && step > 0 && neighborNonFlatPoint.y == MaxSearchStep+1 && srcBkCode.w != 1) {
				neighborNonFlatPoint.y = step;
			}
			if (IsValidFreemanCode(freemanCode.y) == false) bkCode.y = 10;
			if (IsValidFreemanCode(bkCode.y) == false) {
				freemanCode.y = 10;
			}
			else {
				// get first neighbor
				int2 firstNeighbor = nextBackwardPoint(bkPt, bkCode.y);

					if (any(firstNeighbor - prev_bkPt)) {
						freemanCode.y = bkCode.y;
					}
					else {
						freemanCode.y = flip[bkCode.x];
					}
					if (freemanCode.y != curr_code.x && freemanCode.y != curr_code.y)
					{
						if (curr_code.x != curr_code.y) {
							freemanCode.y = -1;
							if (step == 1)
								isSinglePixelCorner = true;
							tangent.directions++;
						}
						else {
							curr_code.y = freemanCode.y;
							qSum = curr_code.x + curr_code.y;
							if (qSum == 3) quadrant = 2;
							else quadrant = 1;
						}
					}
			}

			// search backward
			if (IsValidFreemanCode(freemanCode.y)) {
				prev_bkPt = bkPt;
				bkPt = nextBackwardPoint(prev_bkPt, freemanCode.y);

				bkPtInOctave = nextBkOctavePoint(bkPtInOctave, freemanCode.y % 2);
				bkPt_quad1 = nextBackwardPoint(bkPt_quad1, freemanCode.y);

				bool sameSegment = false;
				int r = tangent.a * bkPtInOctave.x - tangent.b * bkPtInOctave.y;
				if (tangent.u < r && r < tangent.u + tangent.b - 1)
				{	// case 1: u < r < u + b -1
					sameSegment = true;
				}
				if (r == tangent.u + tangent.b - 1)
				{	// case 1a: r == u + b - 1
					tangent.Lmin = bkPtInOctave;
					tangent.LminR = bkPt_quad1;
					sameSegment = true;
				}
				if (r == tangent.u)
				{	// case 1b: r == u
					tangent.Umin = bkPtInOctave;
					tangent.UminR = bkPt_quad1;
					sameSegment = true;
				}
				if (r == tangent.u - 1)
				{
					tangent.Umin = bkPtInOctave;
					tangent.Lmax = tangent.Lmin;
					tangent.a = tangent.Umax.y - bkPtInOctave.y;
					tangent.b = tangent.Umax.x - bkPtInOctave.x;
					tangent.u = tangent.a * bkPtInOctave.x - tangent.b * bkPtInOctave.y;

					tangent.UminR = bkPt_quad1;
					tangent.LmaxR = tangent.LminR;
					sameSegment = true;
				}
				if (r == tangent.u + tangent.b)
				{
					tangent.Lmin = bkPtInOctave;
					tangent.Umax = tangent.Umin;
					tangent.a = tangent.Lmax.y - bkPtInOctave.y;
					tangent.b = tangent.Lmax.x - bkPtInOctave.x;
					tangent.u = tangent.a * bkPtInOctave.x - tangent.b * bkPtInOctave.y - tangent.b + 1;

					tangent.LminR = bkPt_quad1;
					tangent.UmaxR = tangent.UminR;
					sameSegment = true;
				}
				if (!sameSegment)
				{
					freemanCode.y = 10;
				}
			}
		}

	//	if (isFlatItself && !(encounter4Connected[1] && encounter4Connected[0])) {
	//		return float2(0.0f, 0.0f);
	//	}

		if (isFlatItself && neighborNonFlatPoint.x > MaxSearchStep && neighborNonFlatPoint.y > MaxSearchStep /*&& !encounter4Connected[0] && !encounter4Connected[1]*/) {
			return float2(0.0f, 0.0f);
		}

	//// if it's L point
	//if (isTwoConnected && isFlatItself == false) {

	//	//// make one pixel corner square
	//	//if (isSinglePixelCorner) {
	//	//	return float2(0.0f, 0.0f);
	//	//}

	//	// make corner square
	//	if (neighborNonFlatPoint.x >= FLAT_NEIGHBOR_THRE && neighborNonFlatPoint.y >= FLAT_NEIGHBOR_THRE) {
	//		return float2(0.0f, 0.0f);
	//	}

	//	if (onePixelCornerNearyBy[0] && encounter4Connected[1] == false || onePixelCornerNearyBy[1] && encounter4Connected[0] == false) {
	//		return float2(0.0f, 0.0f);
	//	}

	//	//if (isFlatItself == true && encounter4Connected == false) {
	//	//	return float2(0.0f, 0.0f);
	//	//}
	//}

	//// update the quadrant if the starting interpixel is vertical/horizontal
	//if (curr.x == curr.y)
	//{
	//	quadrant = 3;
	//}

	// update a, b
	int2 coeff = { 0, 0 };
		if (quadrant == 1) {
			coeff = int2(tangent.a, tangent.b - tangent.a);
		}
	if (quadrant == 2) {
		coeff = int2(tangent.a, tangent.a - tangent.b);
	}

	// calculate u with Umin and Lmin
	float c1 = coeff.x * tangent.UminR.x - coeff.y * tangent.UminR.y;
	float c2 = coeff.x * tangent.LminR.x - coeff.y * tangent.LminR.y;
	float real_u = (c1 + c2) / 2;
	if (abs(real_u) < 0.0001) real_u = 0.15;
	float2 euPt = { 10.0f, 10.0f };		// initialize to invalid values

		// calculate the euclidean point for this interpixel
		if (quadrant == 1) {
			float val = real_u / (coeff.x + coeff.y);
			euPt = float2(val, -val);
		}
		else if (quadrant == 2) {
			float val = real_u / (coeff.x - coeff.y);
			euPt = float2(val, val);
		}
		if (tangent.a == 0 || tangent.a == tangent.b)
			euPt.xy = 0.0f;
		return euPt;
}

/*
*
*	fourth pass
*
*/
PS_EUCLIDEAN_PATH_OUTPUT PS_EUCLIDEAN_PATH_FREEMAN(in VS_OUTPUT input)
{
	PS_EUCLIDEAN_PATH_OUTPUT euclideanPath;
	uint4 curr_code = FullConnectedDiscretePathSurface[input.position.xy];
		if (IsValidFreemanCode(curr_code.x) == false) {
			euclideanPath.euclidean = float4(10.0f, 10.0f, 10.0f, 10.0f);
			return euclideanPath;
		}
	float2 eupt1 = float2(10.0f, 10.0f);
	if (curr_code.z == 10 && curr_code.w == 1) {
		eupt1.xy = 0.0f;
	}
	else {
		eupt1 = CalculateLineApproximation(curr_code.xy, (int2)input.position.xy, IsValidFreemanCode(curr_code.z) == false);
	}
	float2 eupt2 = float2(10.0f, 10.0f);
	if (IsValidFreemanCode(curr_code.z)) {
		eupt2 = CalculateLineApproximation(curr_code.zw, (int2)input.position.xy, false);
	}

	euclideanPath.euclidean = float4(eupt1.xy, eupt2.xy);
	return euclideanPath;
}


//concave: the previous, current and next euclidean point forms an angle less than 180 degrees, 
//in other words, use previous and current euclidean points to form a line
//the next euclidean point and the corner interpixel are on the same side of that line.
bool concaveContour(float2 endPt1, float2 euPt, float2 cornerPt, float2 endPt2)
{
	bool whichSide = OnSameSide(endPt1, euPt, cornerPt, endPt2);
	return whichSide;
}

// give currrent and next interpixel coordinate, return the euclidean point of the next interpixel
// intput 'interpx' is useful because
// it is possible that next interpixel has two euclidean point
// pick the right one by checking the direction of the next interpixel, so that the direction can reach
// back to current interpixel
// Note that the returned euclidean point is NOT adjusted
float2 getEuPt(uint2 interpx, uint2 next_interpx) {
	float4 nEuPts = EucldeanSurface[next_interpx];
		int4 directions = (int4)FullConnectedDiscretePathSurface[next_interpx];
		// check if there are 2 euclidean points for this interpixel
		if (nEuPts.z < 5.0f && isRightPath(next_interpx, interpx, directions.zw)) {
			// find the right one
			return nEuPts.zw;
		}
		else {
			return nEuPts.xy;
		}
}

float2 getEuPt2(uint2 interpx, uint2 next_interpx) {
	float4 nEuPts = SmoothEuclideanSurface[next_interpx];
		int4 directions = (int4)FullConnectedDiscretePathSurface[next_interpx];
		// check if there are 2 euclidean points for this interpixel
		if (nEuPts.z < 5.0f && isRightPath(next_interpx, interpx, directions.zw)) {
			// find the right one
			return nEuPts.zw;
		}
		else {
			return nEuPts.xy;
		}
}


float2 SmoothEuclideanPt(float2 euPt, uint2 interpx, bool firstPt) {
	int2 fCode = firstPt ? (int2)FullConnectedDiscretePathSurface[interpx].xy : (int2)FullConnectedDiscretePathSurface[interpx].zw;
		int2 next_interpx = interpx + delta[fCode.x];
		float2 next_euPt = getEuPt(interpx, next_interpx);
		next_euPt += delta[fCode.x];

	fCode.y = flip[fCode.y];
	int2 prev_interpx = interpx + delta[fCode.y];
		float2 prev_euPt = getEuPt(interpx, prev_interpx);
		prev_euPt += delta[fCode.y];
	float3x2 P = { prev_euPt, euPt, next_euPt };
		float2 sm_euPt = mul(Bezier_3, P);
		return sm_euPt;
}

PS_EUCLIDEAN_PATH_OUTPUT PS_SMOOTH_EUPT(in VS_OUTPUT input)
{
	const uint2 posDiscretePath = (uint2)(input.position.xy);
	PS_EUCLIDEAN_PATH_OUTPUT output;
	float4 smoothEuPt = EucldeanSurface[posDiscretePath];
	if (smoothEuPt.x < 10.0f && abs(smoothEuPt.x) > epsilon) {
		// check first euclideant point
		smoothEuPt.xy = SmoothEuclideanPt(smoothEuPt.xy, posDiscretePath, true);
		// check second euclidean point if it exist
		if (smoothEuPt.z < 10.0f && abs(smoothEuPt.z) > epsilon) {
			smoothEuPt.zw = SmoothEuclideanPt(smoothEuPt.zw, posDiscretePath, false);
		}
	}
	output.euclidean = smoothEuPt;
	return output;
}

struct PS_EUPT_SMOOTH_OUTPUT
{
	float4 visual			:SV_Target0;
};

PS_EUPT_SMOOTH_OUTPUT PS_EUCLIDEAN_SMOOTH_DIAG(in VS_OUTPUT input)
{
	PS_EUPT_SMOOTH_OUTPUT output;
	int2 posDiscretePath = (int2)(input.position.xy / MagnifyLevel);
		int4 curr_code = (int4)FullConnectedDiscretePathSurface[posDiscretePath];
		if (curr_code.x == 10 || curr_code.y == 10) {
			output.visual = ViewportSurface[posDiscretePath];
			return output;
		}

	uint2 localpos = (uint2)input.position.xy % (uint)MagnifyLevel;
		if (localpos.x == 0 || localpos.y == 0) {
			output.visual = float4(0.0f, 0.0f, 0.0f, 1.0f);
			return output;
		}

	float4 smoothEuPt = EucldeanSurface[posDiscretePath];
		if (smoothEuPt.x < 10.0f && abs(smoothEuPt.x) > epsilon) {
			// check first euclideant point
			smoothEuPt.xy = SmoothEuclideanPt(smoothEuPt.xy, posDiscretePath, true);
			// check second euclidean point if it exist
			if (smoothEuPt.z < 10.0f && abs(smoothEuPt.z) > epsilon) {
				smoothEuPt.zw = SmoothEuclideanPt(smoothEuPt.zw, posDiscretePath, false);
			}
		}

	float4 red = float4(1.0f, 0.0f, 0.0f, 1.0f);
		float4 green = float4(0.0f, 1.0f, 0.0f, 1.0f);
		float4 blue = float4(0.0f, 0.0f, 1.0f, 1.0f);
		float4 yellow = float4(1.0f, 1.0f, 0.0f, 1.0f);
		float4 purple = float4(0.3f, 0.1f, 0.3f, 1.0f);
		float2 eupt1 = smoothEuPt.xy;
		float2 eupt2 = smoothEuPt.zw;
		if (eupt2.x > 5.0f) {
			if (abs(eupt1.x) < 0.0001 && abs(eupt1.y) < 0.0001)
				output.visual = blue;
			else
				output.visual = yellow;
		}
		else {
			if (abs(eupt1.x) < 0.0001 && abs(eupt1.y) < 0.0001 || abs(eupt2.x) < 0.0001 && abs(eupt2.y) < 0.0001)
				output.visual = red;
			else output.visual = green;
		}
		output.visual = smoothEuPt;
		return output;
}


// return true if need to swap the color for px with opposite color
bool swapColor(float2 px, float2 prev_eu, float2 curr_eu, float2 next_eu, float2 interpx, bool concave) {
	if (concave) {
		if (OnSameSide(prev_eu, curr_eu, px, interpx) && OnSameSide(curr_eu, next_eu, px, interpx)) {
			return true;
		}
		else {
			return false;
		}
	}
	else {
		if (OnSameSide(prev_eu, curr_eu, px, interpx) || OnSameSide(curr_eu, next_eu, px, interpx)) {
			return true;
		}
		else {
			return false;
		}
	}
}

static int4 colorSampleDelta[4] = {
	int4(-1, 0, 0, -1), // corner point (0,0) -- left and below neighboring pixels
	int4(0, -1, 1, 0),	// corner point (1,0) -- below and right
	int4(1, 0, 0, 1),	// corner point (1,1) -- right and upper
	int4(0, 1, -1, 0)	// corner point (0,1) -- upper and left
};

// ensure to return a color different from the original color
// the pixels on the diagnols are ambiguious on which color to pick ( in case there are more than 2 colors)
// so just pick a random one
float4 getOppositeColor(uint cornerIdx, int2 origin, float4 srcColor) {
	int2 pos1 = origin + colorSampleDelta[cornerIdx].xy;
		float4 col1 = ViewportSurface[pos1];
		if (isDiffColor(col1 - srcColor)) return col1;
		else {
			pos1 = origin + colorSampleDelta[cornerIdx].zw;
			return ViewportSurface[pos1];
		}
}

// Note: euPt is adjusted (with unit length, not manify level)
bool swapColorBasedOnOneEuclideanPoint(in float2 euPt, in uint2 interpx, in int2 posDiscretePath, float2 curr_loc, uint2 fCode, out uint2 defectFlag)
{
	float2 euPtMag = euPt * MagnifyLevel;
	if (abs(euPtMag.x - curr_loc.x) < 0.0001 && abs(euPtMag.y - curr_loc.y) < 0.0001)
		return false;

	defectFlag = uint2(10, 10);

	// get the coordinates of next interpixel that's on the path
	int2 next_interpx = interpx + delta[fCode.x];
		float2 next_euPt = getEuPt(interpx, next_interpx);
		next_euPt += next_interpx - posDiscretePath;

	// get the coordinates of the previous interpixel 
	fCode.y = flip[fCode.y];
	int2 prev_interpx = interpx + delta[fCode.y];
		float2 prev_euPt = getEuPt(interpx, prev_interpx);
		prev_euPt += prev_interpx - posDiscretePath;

	bool convexity = concaveContour(prev_euPt, euPt, interpx - posDiscretePath, next_euPt);
	bool swap = swapColor(curr_loc, prev_euPt*MagnifyLevel, euPt*MagnifyLevel, next_euPt*MagnifyLevel, (interpx - posDiscretePath)*MagnifyLevel, convexity);
	// if concave case, further check if current the corner pixel is the corner ones
	uint magBoundary = MagnifyLevel - 1;
	if (convexity == true && swap == true) {
	
		// first check if this is a corner pixel
		if (curr_loc.x < 1 && curr_loc.y < 1) {
			// first corner
			defectFlag.x = 0;
		}
		if (curr_loc.x > magBoundary && curr_loc.y < 1) {
			// second corner
			defectFlag.x = 1;
		}
		if (curr_loc.x > magBoundary && curr_loc.y > magBoundary) {
			defectFlag.x = 2;
		}
		if (curr_loc.x < 1 && curr_loc.y > magBoundary) {
			defectFlag.x = 3;
		}
	}

	return swap;
}



struct MAGNIFY_PASS_OUTPUT
{
	float4	magnifiedSurf		: SV_Target0;
	float4	defectFlagSurf		: SV_Target1;
};

MAGNIFY_PASS_OUTPUT PS_MAGNIFY_BACK(in VS_OUTPUT input)
{
	MAGNIFY_PASS_OUTPUT output;
	//output.defectFlagSurf = uint2(10, 10);
	int displayMode = (int)ShowOriginal.x;
	// each pixel (x,y) is surrounded by four interpixels:
	// (x+1,y+1): 1st quadrant
	// (x, y+1):  2nd quadrant
	// (x,y):	  3rd quadrant
	// (x+1,y):	  4th quadrant
	// first, find a interpixel that is on the discrete path
	const uint2 posDiscretePath = (uint2)(input.position.xy) / (uint2)(MagnifyLevel);
	float4 srcCol = ViewportSurface[posDiscretePath];
		

	output.magnifiedSurf = srcCol;

	if (displayMode == 0)
		return output;

	uint2 localPos = (uint2)input.position.xy % (uint2)MagnifyLevel;
	float2 curr_px = (float2)localPos + 0.5;
	bool swapColor = false;
	uint colorId = 10;
	uint2 defectCode = uint2(10, 10);
	for (uint i = 0; i < 4 && swapColor == false; i++) {
		uint2 interpx = posDiscretePath + px2interpx[i];
		float4 euPt = EucldeanSurface[interpx];
		int4 fCode = (int4)FullConnectedDiscretePathSurface[interpx];

		euPt.xy += px2interpx[i];
		if (euPt.x * (1.0f - euPt.x) > 0 && euPt.y * (1.0f - euPt.y) > 0) {
			// find a non-zero euclidean point within this pixel, process it
			swapColor = swapColorBasedOnOneEuclideanPoint(euPt.xy, interpx, posDiscretePath, curr_px, fCode.xy, defectCode);
			if (swapColor) {
				colorId = i;
			}
		}
		if (abs(euPt.z) < 5.0f) {
			euPt.zw += px2interpx[i];
			if (euPt.z * (1.0f - euPt.z) > 0 && euPt.w*(1.0f - euPt.w) > 0) {
				swapColor = swapColorBasedOnOneEuclideanPoint(euPt.zw, interpx, posDiscretePath, curr_px, fCode.zw, defectCode);
				if (swapColor) {
					colorId = i;
				}
			}
		}

	}
	if (colorId < 4) {
		output.magnifiedSurf = getOppositeColor(colorId, posDiscretePath, srcCol);
		//output.magnifiedSurf = float4(1.0f, 0.0f, 0.0f, 1.0f);
	}
	//else
	output.defectFlagSurf.xy = defectCode;
	return output;
}

bool swapColorBasedOnLineIntersection(in float2 euPt, in uint2 interpx, float2 curr_px, in int2 posDiscretePath, uint2 fCode) {
	int2 next_interpx = interpx + delta[fCode.x];
	float2 next_euPt = getEuPt(interpx, next_interpx);
	next_euPt += next_interpx - posDiscretePath;
	next_euPt *= MagnifyLevel;

	fCode.y = flip[fCode.y];
	int2 prev_interpx = interpx + delta[fCode.y];
	float2 prev_euPt = getEuPt(interpx, prev_interpx);
	prev_euPt += prev_interpx - posDiscretePath;
	prev_euPt *= MagnifyLevel;
	euPt *= MagnifyLevel;
	float2 cen = float2((float)MagnifyLevel.x / 2.0, (float)MagnifyLevel.y / 2.0);
		// if there is intersection, means the curr_px is 'outside' of the boundary, swap color needed
	return isLinesIntersect(cen, curr_px, euPt, prev_euPt) | isLinesIntersect(cen, curr_px, euPt, next_euPt); 
}

int2 getNextInterPixelCoordWithCode(in int2 prev, in int2 curr, in int2 fCode) {
	int2 tmpPt = curr + delta[fCode.x];
		if (IsSamePoint(tmpPt, prev)) {
			return curr + delta[flip[fCode.y]];
		}
		else {
			return tmpPt;
		}
}

// given prev and current interpixel, get the next interpixel coord and its euclidean point value
// this function is to be used in the final pass, use the augmented discreate path map
int2 getNextInterPixelCoord(in int2 prev, in int2 curr, out float2 nextEuPt) {
	int4 fCode = (int4)FullConnectedDiscretePathSurface[curr];
		nextEuPt = float2(0.0f, 0.0f);
	int2 nextCoord = int2(0, 0);
		if (fCode.z < 10) {
			// curren point is a 4 connected interpixel, need to figure out which freeman is used
			// the way to check is see if one of curr's neighbor is the same as prev
			int2 tmpPt = curr + delta[fCode.x];
			int2 tmpPt2 = curr + delta[flip[fCode.y]];
			if (IsSamePoint(tmpPt, prev) || IsSamePoint(tmpPt2, prev)) {
				nextCoord = getNextInterPixelCoordWithCode(prev, curr, fCode.xy);
					nextEuPt = EucldeanSurface[nextCoord].xy;
			}
			else {
				nextCoord = getNextInterPixelCoordWithCode(prev, curr, fCode.zw);
				int4 fCode_next = (int4)FullConnectedDiscretePathSurface[nextCoord];
					if (fCode_next.z < 10) {
						// the next_next interpixel is 4 connected
						int2 tmpPt = nextCoord + delta[fCode_next.x];
							int2 tmpPt2 = nextCoord + delta[flip[fCode_next.y]];
							if (IsSamePoint(tmpPt, curr) || IsSamePoint(tmpPt, curr)) {
								nextEuPt = EucldeanSurface[nextCoord].xy;
							}
							else {
								nextEuPt = EucldeanSurface[nextCoord].zw;
							}
					}
					else {
						// the next_next interpixel is 2 connected
						nextEuPt = EucldeanSurface[nextCoord].xy;
					}
			}
		}
		else {
			nextCoord = getNextInterPixelCoordWithCode(prev, curr, fCode.xy);
			int4 fCode_next = (int4)FullConnectedDiscretePathSurface[nextCoord];
				if (fCode_next.z < 10) {
					// the next_next interpixel is 4 connected
					int2 tmpPt = nextCoord + delta[fCode_next.x];
						int2 tmpPt2 = nextCoord + delta[flip[fCode_next.y]];
						if (IsSamePoint(tmpPt, curr) || IsSamePoint(tmpPt, curr)) {
							nextEuPt = EucldeanSurface[nextCoord].xy;
						}
						else {
							nextEuPt = EucldeanSurface[nextCoord].zw;
						}
				}
				else {
					// the next_next interpixel is 2 connected
					nextEuPt = EucldeanSurface[nextCoord].xy;
				}
		}
		return nextCoord;
}

bool swapColorBasedOn3Segments(in float2 euPt, in uint2 interpx, float2 curr_px, in int2 posDiscretePath, uint2 fCode, bool euPtStreight, bool isLPt) {
	int2 next_interpx = interpx + delta[fCode.x];
	float2 next_euPt = getEuPt(interpx, next_interpx);
	next_euPt += next_interpx - posDiscretePath;

	fCode.y = flip[fCode.y];
	int2 prev_interpx = interpx + delta[fCode.y];
	float2 prev_euPt = getEuPt(interpx, prev_interpx);
	prev_euPt += prev_interpx - posDiscretePath;

	float2 cen = float2(0.5f, 0.5f);
		//curr_px = curr_px / MagnifyLevel;
		float2 mid1 = (prev_euPt + euPt) / 2.0f;
		float2 mid2 = (euPt + next_euPt) / 2.0f;
		bool colineary = linePointDist(prev_euPt, next_euPt, euPt) < epsilon;
		bool sameSides = OnSameSide(mid1, mid2, cen, euPt);

		// use prev_euPt, mid1, mid2, next_euPt to form three line segments for checking
		if (euPtStreight | colineary | sameSides == false && isLPt) {
			// three points on the same line, no smooth
			return isLinesIntersect(cen, curr_px, euPt, prev_euPt) || isLinesIntersect(cen, curr_px, euPt, next_euPt);
		}
		else {
			
			if (sameSides && linePointDist(mid1, mid2, cen) < linePointDist(mid1, mid2, euPt) ) {
				return isLinesIntersect(cen, curr_px, euPt, prev_euPt) || isLinesIntersect(cen, curr_px, euPt, next_euPt);
			}
			else {
				return isLinesIntersect(cen, curr_px, mid1, prev_euPt) || isLinesIntersect(cen, curr_px, mid1, mid2) || isLinesIntersect(cen, curr_px, mid2, next_euPt);
			}
			
		}
}

// check using on same side only to determine if color should be flipped
// if curr_px and central pixel is on different side of the boundary, return true
bool swapColorBasedOn3Segments2(in float2 euPt, in uint2 interpx, float2 curr_px, in int2 posDiscretePath, uint2 fCode, bool euPtStreight, bool isLPt) {
	int2 next_interpx = interpx + delta[fCode.x];
		float2 next_euPt = getEuPt(interpx, next_interpx);
		next_euPt += next_interpx - posDiscretePath;

	fCode.y = flip[fCode.y];
	int2 prev_interpx = interpx + delta[fCode.y];
		float2 prev_euPt = getEuPt(interpx, prev_interpx);
		prev_euPt += prev_interpx - posDiscretePath;

	float2 cen = float2(0.5f, 0.5f);		// purposely make the center off a bit
		//curr_px = curr_px / MagnifyLevel;
	float2 mid1 = (prev_euPt + euPt) / 2.0f;
		float2 mid2 = (euPt + next_euPt) / 2.0f;
		bool colineary = linePointDist(prev_euPt, next_euPt, euPt) < epsilon;
	bool sameSides = OnSameSide(mid1, mid2, cen, euPt);
	if (colineary) {
		return OnSameSide(prev_euPt, next_euPt, cen, curr_px) == false;
	}
	else {
		return OnSameSide(prev_euPt, mid1, cen, curr_px) == false || OnSameSide(mid1, mid2, cen, curr_px) == false || OnSameSide(mid2, next_euPt, cen, curr_px) == false;
	}
}


// check if point 'p' is inside the triangle consists of tp1, tp2, tp3
// ref: http://totologic.blogspot.com/2014/01/accurate-point-in-triangle-test.html
// use method 3 (same side technique)
bool isPointInTriangle(float2 tp1, float2 tp2, float2 tp3, float2 p) {
	return OnSameSide(tp2, tp3, p, tp1) && OnSameSide(tp1, tp3, p, tp2) && OnSameSide(tp1, tp2, p, tp3);
}

// in order to make the curve smooth over the pixel boundary, it is necessary to search the next/prev 2 neighbors for each inter-pixel
// let the current interpixel be point a, its coord is the input 'interpx', its immediate prev neighbor is b, its immediate next neighbor is c
// b's prev neighbor is d, c's next neighbor is e
// use m1, m2, m3, m4 to mark the three line segment to be tested
// m1 is between e and c
// m2 is between c and a
// m3 is between a and b
// m4 is between b and d
// to deal with zero interpixel, the alg goes as follows:
// if b is zero interpixel, m3 = a, m4 = b
// else (i.e, b non zero) m3 = mid(a,b),
//		if( d is zero) m4=d
//      else m4=mid(b,d)
// m1, m2 is calculated in similar way
bool swapColorBasedOn5Segments(in float2 euPt, in uint2 interpx, float2 curr_px, in int2 posDiscretePath, uint2 fCode, bool isLPt) {
	int2 next_interpx = interpx + delta[fCode.x];
	float2 next_euPt = getEuPt(interpx, next_interpx);
	next_euPt += next_interpx - posDiscretePath;

	fCode.y = flip[fCode.y];
	int2 prev_interpx = interpx + delta[fCode.y];
	float2 prev_euPt = getEuPt(interpx, prev_interpx);
	prev_euPt += prev_interpx - posDiscretePath;

	float2 next_next_euPt = float2(0.0f, 0.0f);
	int2 next_next_interpx = getNextInterPixelCoord(interpx, next_interpx, next_next_euPt);
	next_next_euPt += next_next_interpx - posDiscretePath;
	float2 prev_prev_euPt = float2(0.0f, 0.0f);
	int2 prev_prev_interpx = getNextInterPixelCoord(interpx, prev_interpx, prev_prev_euPt);
	prev_prev_euPt += prev_prev_interpx - posDiscretePath;

	float2 m1, m2, m3, m4;
	if (abs(next_euPt.x) < epsilon) {
		m3 = euPt;
		m4 = next_euPt;
	}
	else {
		m3 = (euPt + next_euPt) / 2.0f;
		if (abs(next_next_euPt.x) < epsilon) {
			m4 = next_next_euPt;
		}
		else {
			m4 = (next_euPt + next_next_euPt) / 2.0f;
		}
	}
	if (abs(prev_euPt.x) < epsilon) {
		m2 = euPt;
		m1 = prev_euPt;
	}
	else {
		m2 = (euPt + prev_euPt) / 2.0f;
		if (abs(prev_prev_euPt.x) < epsilon) {
			m1 = prev_prev_euPt;
		}
		else {
			m1 = (prev_prev_euPt + prev_euPt) / 2.0f;
		}
	}

	// check the three line segment: m1-m2, m2-m3, m3-m4
	float2 cen = float2(0.5f, 0.5f);
	//curr_px = curr_px / MagnifyLevel;
	bool colineary = linePointDist(prev_euPt, next_euPt, euPt) < epsilon;
	//bool sameSides1 = OnSameSide(m2, m3, cen, euPt) && linePointDist(m2, m3, cen) < linePointDist(m2, m3, euPt);
	bool triTest1 = false;
	if (!colineary) {
		triTest1 = isPointInTriangle(euPt, m2, m3, cen);
	}
	

	if (triTest1 == true && isLPt) {
		return isLinesIntersect(cen, curr_px, euPt, prev_euPt) || isLinesIntersect(cen, curr_px, euPt, next_euPt);
	}
	else {
		//bool sameSides2 = OnSameSide(m3, m4, cen, next_euPt) && linePointDist(m3, m4, cen) < linePointDist(m3, m4, next_euPt);
		//bool sameSides3 = OnSameSide(m1, m2, cen, prev_euPt) && linePointDist(m1, m2, cen) < linePointDist(m1, m2, prev_euPt);
		bool triTest2 = isPointInTriangle(next_euPt, m3, m4, cen);
		bool triTest3 = isPointInTriangle(prev_euPt, m1, m2, cen);
		if (triTest1 || triTest2 || triTest3) {
			return isLinesIntersect(cen, curr_px, euPt, prev_euPt) || isLinesIntersect(cen, curr_px, euPt, next_euPt);
		}
		else {
			return isLinesIntersect(cen, curr_px, m1, m2) || isLinesIntersect(cen, curr_px, m2, m3) || isLinesIntersect(cen, curr_px, m3, m4);
		}
	}
}

bool swapColorBasedOnLineIntersection2(in float2 euPt, in uint2 interpx, float2 curr_px, in int2 posDiscretePath, uint2 fCode) {
	int2 next_interpx = interpx + delta[fCode.x];
		float2 next_euPt = getEuPt2(interpx, next_interpx);
		next_euPt += next_interpx - posDiscretePath;
	next_euPt *= MagnifyLevel;

	fCode.y = flip[fCode.y];
	int2 prev_interpx = interpx + delta[fCode.y];
		float2 prev_euPt = getEuPt2(interpx, prev_interpx);
		prev_euPt += prev_interpx - posDiscretePath;
	prev_euPt *= MagnifyLevel;
	euPt *= MagnifyLevel;
	float2 cen = float2((float)MagnifyLevel.x / 2.0, (float)MagnifyLevel.y / 2.0);
		// if there is intersection, means the curr_px is 'outside' of the boundary, swap color needed
		return isLinesIntersect(cen, curr_px, euPt, prev_euPt) || isLinesIntersect(cen, curr_px, euPt, next_euPt);
}

bool isEuPtInPixel(float2 euPt) {
	return euPt.x * (1.0f - euPt.x) > 0 && euPt.y * (1.0f - euPt.y) > 0;
}

/*
*
*	fifth pass
*
*/
MAGNIFY_PASS_OUTPUT PS_MAGNIFY(in VS_OUTPUT input)
{
	MAGNIFY_PASS_OUTPUT output;
	//output.defectFlagSurf = uint2(10, 10);
	int displayMode = (int)ShowOriginal.x;
	// each pixel (x,y) is surrounded by four interpixels:
	// (x+1,y+1): 1st quadrant
	// (x, y+1):  2nd quadrant
	// (x,y):	  3rd quadrant
	// (x+1,y):	  4th quadrant
	// first, find a interpixel that is on the discrete path
	const uint2 posDiscretePath = (uint2)(input.position.xy / MagnifyLevel);
	float4 srcCol = ViewportSurface[posDiscretePath];


	output.magnifiedSurf = srcCol;

	if (displayMode == 0)
		return output;

	uint2 localPos = (uint2)input.position.xy % (uint2)MagnifyLevel;
		//float2 curr_px = (float2)localPos + 0.5;
		//curr_px = curr_px / MagnifyLevel;

		float2 curr_px = input.position.xy;
		curr_px -= posDiscretePath * MagnifyLevel;
		curr_px = curr_px / MagnifyLevel;

		bool swapColor = false;
	uint colorId = 10;
	uint2 defectCode = uint2(10, 10);
	for (uint i = 0; i < 4 && swapColor == false; i++) {
		uint2 interpx = posDiscretePath + px2interpx[i];
			float4 euPt = EucldeanSurface[interpx];
			int4 fCode = (int4)FullConnectedDiscretePathSurface[interpx];
			bool isZeroEupt = abs(euPt.x) < epsilon;
		
		// method 1
		//if (fCode.x < 10) {
		//	swapColor = swapColorBasedOnLineIntersection(euPt.xy, interpx, curr_px, posDiscretePath, fCode.xy);
		//	if (swapColor) {
		//		colorId = i;
		//	}
		//}
		//	
		//if (!swapColor && fCode.z < 10 && abs(euPt.z) < 5.0f) {
		//	euPt.zw += px2interpx[i];

		//	swapColor = swapColorBasedOnLineIntersection(euPt.zw, interpx, curr_px, posDiscretePath, fCode.zw);
		//	if (swapColor) {
		//		colorId = i;
		//	}
		//}
		
		// method 2
		euPt.xy += px2interpx[i];
		if (isEuPtInPixel(euPt.xy)) {
			bool isLPt = fCode.x != fCode.y && fCode.z == 10;
			swapColor = swapColorBasedOn5Segments(euPt.xy, interpx, curr_px, posDiscretePath, fCode.xy,  isLPt);
			if (swapColor) {
				colorId = i;
			}
		}
		else if (isZeroEupt) {	// this ensures that this is 2 connected point, since 4 connected interpixel must have non-zero euclidean point
			// this is a 2 connected interpixel with zero eupt
			// this is to deal with the nitch defect along the long i bean
			// the interpixels must satisfy:
			// 1) it has zero eupt
			// 2) its neighbor has non-zero eupt, and is outside of the current pixel
			int2 next_interpx = interpx + delta[fCode.x];
				float2 next_euPt = getEuPt(interpx, next_interpx);
				float2 cen = float2(0.5f, 0.5f);
				if (abs(next_euPt.x) > epsilon) {
					next_euPt += next_interpx - posDiscretePath;
					if (isEuPtInPixel(next_euPt) == false) {
						swapColor = isLinesIntersect(euPt.xy, next_euPt, cen, curr_px);
					}
				}
			
			int2 prev_interpx = interpx + delta[flip[fCode.y]];
				float2 prev_euPt = getEuPt(interpx, prev_interpx);
				
			if (abs(prev_euPt.x) > epsilon && swapColor == false) {
				prev_euPt += prev_interpx - posDiscretePath;
				if (isEuPtInPixel(prev_euPt) == false) {
					swapColor = isLinesIntersect(euPt.xy, prev_euPt, cen, curr_px);
				}
			}
			if (swapColor) {
				colorId = i;
			}
		}
		
		if (!swapColor && abs(euPt.z) < 5.0f) {
			//bool euPtStreight = abs(euPt.z) < epsilon;
			euPt.zw += px2interpx[i];
			if (isEuPtInPixel(euPt.zw)) {
				swapColor = swapColorBasedOn5Segments(euPt.zw, interpx, curr_px, posDiscretePath, fCode.zw, false);
				if (swapColor) {
					colorId = i;
				}
			}
		}
	}
	if (colorId < 4) {
		float4 rCol = getOppositeColor(colorId, posDiscretePath, srcCol);
		output.magnifiedSurf = rCol;
		//output.magnifiedSurf = float4(1.0f, 0.0f, 0.0f, 1.0f);
	}
	//else
	output.defectFlagSurf.xy = defectCode;
	return output;
}

// output an m * n image
float4 PS_FINAL(in VS_OUTPUT input) : SV_Target
{
	int displayMode = (int)ShowOriginal.x;
	// each pixel (x,y) is surrounded by four interpixels:
	// (x+1,y+1): 1st quadrant
	// (x, y+1):  2nd quadrant
	// (x,y):	  3rd quadrant
	// (x+1,y):	  4th quadrant
	// first, find a interpixel that is on the discrete path
	const uint2 pos = (uint2)(input.position.xy);
	float4 srcCol = MagnifyedSurface[pos];
	return srcCol;
};
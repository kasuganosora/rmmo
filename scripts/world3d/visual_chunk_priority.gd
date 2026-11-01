extends RefCounted
## Ring-first spatial order for ordinary visual work. No owners, queues,
## SceneTree state or callbacks; consumers retain their dependency priorities.
const DIRECTIONS:Array[Vector2i]=[Vector2i(0,-1),Vector2i(1,-1),Vector2i(1,0),Vector2i(1,1),Vector2i(0,1),Vector2i(-1,1),Vector2i(-1,0),Vector2i(-1,-1)]
const TURN_STEP:=PI/4.0
const TURN_HYSTERESIS:=PI/36.0 # Five degrees beyond each 22.5 degree boundary.

static func heading(direction:Vector3,current:int=-1)->int:
	if not direction.is_finite() or Vector2(direction.x,direction.z).length_squared()<.000001:return current
	var angle:=atan2(direction.x,-direction.z)
	if current>=0 and current<DIRECTIONS.size():
		var difference:=absf(wrapf(angle-float(current)*TURN_STEP,-PI,PI))
		if difference<=TURN_STEP*.5+TURN_HYSTERESIS:return current
	return posmod(roundi(angle/TURN_STEP),DIRECTIONS.size())

static func rank(offset:Vector2i,direction:int)->float:
	var ring:=maxi(absi(offset.x),absi(offset.y))
	if ring==0:return 0.0
	var forward:Vector2i=DIRECTIONS[posmod(direction,DIRECTIONS.size())]
	var right:=Vector2i(-forward.y,forward.x)
	var ahead:=offset.x*forward.x+offset.y*forward.y
	var side:=offset.x*right.x+offset.y*right.y
	# Within a ring: front row centre, left/right pairs, right/left at the
	# exact side row, then the back row centre and left/right pairs. The small
	# fractional key can never outrank a closer ring, even on diagonal views.
	var tie:=int(side<0) if ahead==0 else int(side>0)
	var width:=4*ring+3
	var within:float=float((2*ring-ahead)*width+2*absi(side)+tie)/float((4*ring+1)*width)
	return float(ring)+within

static func bounds_rank(bounds:AABB,origin:Vector3,chunk_m:float,direction:int)->float:
	var focus:=Vector2i(floori(origin.x/chunk_m),floori(origin.z/chunk_m))
	var low:=Vector2i(floori(bounds.position.x/chunk_m),floori(bounds.position.z/chunk_m))
	var high:=Vector2i(floori(bounds.end.x/chunk_m),floori(bounds.end.z/chunk_m))
	var nearest:=Vector2i(clampi(focus.x,low.x,high.x),clampi(focus.y,low.y,high.y))
	return rank(nearest-focus,direction)

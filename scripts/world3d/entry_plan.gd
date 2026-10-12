extends RefCounted
## One spatial contract for initial content, safety preparation and navigation.
## Neighbours are not part of the core milestone. Unknown/global dependencies
## remain explicit conservative costs until their spatial closures are proven.
const CHUNK_M := 32.0
const SAFETY_M := 14.0 # 12m camera + sweep margin; navigation source border 1.6m.

static func create(origin:Vector3)->Dictionary:
	if not origin.is_finite():return {}
	var cell:=Vector2i(floori(origin.x/CHUNK_M),floori(origin.z/CHUNK_M))
	var core:=AABB(Vector3(cell.x*CHUNK_M,-100000,cell.y*CHUNK_M),Vector3(CHUNK_M,200000,CHUNK_M))
	var safety:=core.merge(AABB(Vector3(origin.x-SAFETY_M,-100000,origin.z-SAFETY_M),Vector3(SAFETY_M*2,200000,SAFETY_M*2)))
	return {"version":1,"origin":origin,"cell":cell,"core_clip":core,"safety_clip":safety,"navigation_clip":safety,"core_resources_ready_us":0,"neighbours_started_us":0}

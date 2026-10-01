extends "res://scripts/world3d/building_geometry.gd"
## A shared spatial plan drives both sides of every wall, its openings and collision.
const Schema = preload("res://scripts/world3d/document_schema.gd")
const Geometry = preload("res://scripts/world_editor/selection_geometry.gd")
const VERSION := 2
const LABELS := {"house":"民居", "shop":"商住楼", "inn":"旅馆"}
const DOOR_H := 2.2
const STAIR_W := 1.4
const TREAD := .28

static func legacy_defaults() -> Dictionary:
	return {"template":"house", "width":12.0, "depth":14.0, "floors":2, "floor_height":3.0, "rooms_per_floor":2, "roof":"gable", "roof_height":2.0, "style":"timber", "seed":1}

static func defaults() -> Dictionary:
	return legacy_defaults().merged({"layout":"standard","roof_axis":"depth","roof_pitch":45.0,"eaves":.3,"jetty":0.0,"bay_width":2.4,"shutters":true,"compound":"none","annex_width":4.0,"annex_depth":6.0,"left_wall":"open","right_wall":"open"})

static func medieval_presets() -> Array:
	return [
		{"id":"townhouse","name":"窄店屋","parameters":defaults().merged({"layout":"townhouse","template":"shop","width":6.5,"depth":13.0,"jetty":.4},true)},
		{"id":"workshop","name":"后院作坊","parameters":defaults().merged({"layout":"townhouse","template":"shop","width":8.0,"depth":14.0,"compound":"rear_workshop","jetty":.3},true)},
		{"id":"courtyard","name":"围院旅馆","parameters":defaults().merged({"layout":"townhouse","template":"inn","width":13.0,"depth":14.0,"compound":"courtyard","roof_axis":"width","roof_pitch":35.0},true)},
		{"id":"hall","name":"大厅住宅","parameters":defaults().merged({"layout":"hall","width":9.0,"depth":15.0},true)}]

static func schema() -> Dictionary:
	return {"type":"object", "properties":{
		"template":{"type":"string","enum":LABELS.keys()}, "width":Schema.number(5.5,24), "depth":Schema.number(10,30),
		"floors":{"type":"integer","minimum":1,"maximum":3}, "floor_height":Schema.number(3,4),
		"rooms_per_floor":{"type":"integer","minimum":1,"maximum":4}, "roof":{"type":"string","enum":["gable","flat"]},
		"roof_height":Schema.number(.5,4), "style":{"type":"string","enum":["timber","plaster"]},
		"seed":{"type":"integer","minimum":0,"maximum":2147483647},
		"layout":{"type":"string","enum":["standard","townhouse","hall"]},
		"roof_axis":{"type":"string","enum":["depth","width"]}, "roof_pitch":Schema.number(25,60),
		"eaves":Schema.number(0,.6), "jetty":Schema.number(0,.65), "bay_width":Schema.number(1.8,3.2), "shutters":{"type":"boolean"},
		"compound":{"type":"string","enum":["none","rear_workshop","left_wing","courtyard"]},
		"annex_width":Schema.number(3,6), "annex_depth":Schema.number(4,10),
		"left_wall":{"type":"string","enum":["open","party"]}, "right_wall":{"type":"string","enum":["open","party"]}}, "additionalProperties":false}

static func fail(message: String) -> Dictionary: return {"ok":false,"error":message}

static func generate(parameters: Dictionary) -> Dictionary:
	var issue := Schema.validate(parameters,schema())
	if not issue.is_empty(): return fail(issue)
	var p := defaults(); p.merge(parameters,true)
	if p.layout!="standard": return preload("res://scripts/world3d/medieval_building.gd").generate(p)
	if p.width<9 or p.depth<12: return fail("普通模板至少需要 9 米宽、12 米深；窄店屋请使用中世纪布局")
	var w := float(p.width); var d := float(p.depth); var h := float(p.floor_height)
	var n := int(p.rooms_per_floor)
	if (d-WALL*2)/n < 2.8: return fail("房间进深不足 2.8 米，请增加建筑深度或减少房间")
	var steps := ceili(h/.17); var run := steps*TREAD
	var z0 := -d/2+1.6; var z1 := z0+run
	if int(p.floors)>1 and z1>d/2-1.4: return fail("楼梯与上下平台空间不足")
	var right := w/2-WALL
	var stair_right := right-.15; var stair_left := stair_right-STAIR_W
	var bay_left := stair_left-.15
	var partition := bay_left-1.9
	var hall_x := (partition+WALL/2+bay_left)/2
	var room_x := (-w/2+WALL+partition-WALL/2)/2
	var palette := {"wall":[.83,.77,.64], "trim":[.25,.16,.1], "floor":[.53,.39,.25], "roof":[.43,.18,.13], "glass":[.32,.48,.57]}
	if p.style == "plaster": palette = {"wall":[.79,.81,.76], "trim":[.35,.37,.34], "floor":[.57,.55,.49], "roof":[.22,.28,.33], "glass":[.33,.49,.54]}
	var tint := float(int(p.seed)%7-3)*.012
	for channel in 3: palette.wall[channel] = clampf(palette.wall[channel]+tint,0,1)
	var plan := {"ok":true,"version":VERSION,"parameters":p,"records":[],"rooms":[],"openings":[],"stairs":[],"routes":[],
		"entrance":[hall_x,0,-d/2-1],"size":[w+.6,int(p.floors)*h+(float(p.roof_height) if p.roof=="gable" else .2),d+.6]}
	var window_w := 1.25+float(int(p.seed)%3)*.12
	for floor_index in int(p.floors):
		var y := floor_index*h
		var prefix := "f%d/" % floor_index
		# Upper slabs are partitioned around the entire shared stair shaft.
		if floor_index==0:
			box(plan,prefix+"floor",Vector3(0,y-SLAB/2,0),Vector3(w,SLAB,d),palette.floor,floor_index,"floor")
		else:
			var hole_left := stair_left-.09; var hole_right := stair_right+.09
			slab(plan,prefix+"floor/left",-w/2,hole_left,-d/2,d/2,y,palette.floor,floor_index)
			slab(plan,prefix+"floor/right",hole_right,w/2,-d/2,d/2,y,palette.floor,floor_index)
			slab(plan,prefix+"floor/front",hole_left,hole_right,-d/2,z0-.08,y,palette.floor,floor_index)
			slab(plan,prefix+"floor/back",hole_left,hole_right,z1+.08,d/2,y,palette.floor,floor_index)
			# Landing bridges the small clearance at the final step without closing the shaft.
			box(plan,prefix+"landing",Vector3((stair_left+stair_right)/2,y-SLAB/2,z1+.06),Vector3(STAIR_W+.18,SLAB,.28),palette.floor,floor_index,"floor")
		var interior_openings: Array = []; var left_windows: Array = []
		var bounds: Array = []
		for room in n+1: bounds.append(-d/2+WALL+(d-2*WALL)*float(room)/n)
		for room in n:
			var a := float(bounds[room]); var b := float(bounds[room+1]); var center := (a+b)/2
			var room_id := prefix+"room%d" % room
			var title := room_label(str(p.template),floor_index,room)
			plan.rooms.append({"id":room_id,"name":title,"floor":floor_index,"bounds":[-w/2+WALL,a,partition-WALL/2,b],"center":[room_x,y,center]})
			interior_openings.append({"id":"door%d"%room,"u":center,"bottom":0.0,"width":1.4,"height":DOOR_H,"type":"door","room":room_id})
			left_windows.append({"id":"window%d"%room,"u":center,"bottom":1.0,"width":window_w,"height":1.25,"type":"window","room":room_id})
			plan.routes.append([[hall_x,y,center],[room_x,y,center]])
			if room>0:
				box(plan,prefix+"partition%d"%room,Vector3(room_x,y+h/2,a),Vector3(partition-WALL/2-(-w/2+WALL),h,WALL),palette.wall,floor_index,"partition")
		wall(plan,prefix+"interior", "z",partition,-d/2+WALL,d/2-WALL,y,h,interior_openings,palette,floor_index)
		wall(plan,prefix+"west","z",-w/2+WALL/2,-d/2,d/2,y,h,left_windows,palette,floor_index)
		wall(plan,prefix+"east","z",w/2-WALL/2,-d/2,d/2,y,h,[],palette,floor_index)
		var front: Array = [{"id":"front_window","u":room_x,"bottom":1.0,"width":window_w,"height":1.25,"type":"window","room":prefix+"room0"}]
		if floor_index==0: front.append({"id":"entrance","u":hall_x,"bottom":0.0,"width":1.6,"height":DOOR_H,"type":"door","room":"hall"})
		else: front.append({"id":"hall_window","u":hall_x,"bottom":1.0,"width":1.2,"height":1.25,"type":"window","room":"hall"})
		wall(plan,prefix+"north","x",-d/2+WALL/2,-w/2+WALL,w/2-WALL,y,h,front,palette,floor_index)
		wall(plan,prefix+"south","x",d/2-WALL/2,-w/2+WALL,w/2-WALL,y,h,[{"id":"back_window","u":room_x,"bottom":1.0,"width":window_w,"height":1.25,"type":"window","room":prefix+"room%d"%(n-1)}],palette,floor_index)
		if floor_index<int(p.floors)-1:
			plan.stairs.append({"floor":floor_index,"hole":[stair_left-.09,z0-.08,stair_right+.09,z1+.08],"bottom":[(stair_left+stair_right)/2,y,z0-.55],"top":[(stair_left+stair_right)/2,y+h,z1+.6]})
			for step in steps:
				var rise := h*(step+1)/steps
				# Thin treads preserve headroom below stacked flights.
				box(plan,prefix+"step%d"%step,Vector3((stair_left+stair_right)/2,y+rise-.07,z0+(step+.5)*TREAD),Vector3(STAIR_W,.14,TREAD+.004),palette.floor,floor_index,"stairs")
				for x in [stair_left-.04,stair_right+.04]:
					box(plan,prefix+"rail%d_%d"%[step,0 if x<stair_left else 1],Vector3(x,y+rise+.5,z0+(step+.5)*TREAD),Vector3(.08,1,TREAD),palette.trim,floor_index,"rail")
		# A top-floor guard surrounds the exposed stair well; openings remain at the landing.
		if floor_index==int(p.floors)-1 and floor_index>0:
			box(plan,prefix+"well/front",Vector3((stair_left+stair_right)/2,y+.5,z0-.08),Vector3(STAIR_W+.18,1,.08),palette.trim,floor_index,"rail")
			for x in [stair_left-.09,stair_right+.09]: box(plan,prefix+"well/side%d"%(0 if x<stair_left else 1),Vector3(x,y+.5,(z0+z1)/2),Vector3(.08,1,run),palette.trim,floor_index,"rail")
		# Exterior bands and posts respect the same floor levels, without obstructing openings.
		for x in [-w/2-.025,w/2+.025]: box(plan,prefix+"band/side%d"%(0 if x<0 else 1),Vector3(x,y+h-.1,0),Vector3(.08,.2,d+.1),palette.trim,floor_index,"trim")
		for z in [-d/2-.025,d/2+.025]: box(plan,prefix+"band/end%d"%(0 if z<0 else 1),Vector3(0,y+h-.1,z),Vector3(w+.1,.2,.08),palette.trim,floor_index,"trim")
		for x in [-w/2+.02,w/2-.02]:
			for z in [-d/2+.02,d/2-.02]: box(plan,prefix+"post/%d%d"%[0 if x<0 else 1,0 if z<0 else 1],Vector3(x,y+h/2,z),Vector3(.27,h,.27),palette.trim,floor_index,"trim")
	var roof_y := int(p.floors)*h
	box(plan,"roof/ceiling",Vector3(0,roof_y-SLAB/2,0),Vector3(w,SLAB,d),palette.wall,int(p.floors),"roof")
	if p.roof=="flat": box(plan,"roof/flat",Vector3(0,roof_y+.06,0),Vector3(w+.5,.12,d+.5),palette.roof,int(p.floors),"roof")
	else:
		var half := w/2+.3; var rise := float(p.roof_height); var length := sqrt(half*half+rise*rise)
		for side in [-1,1]:
			box(plan,"roof/slope%d"%side,Vector3(side*half/2,roof_y+rise/2,0),Vector3(length,.16,d+.6),palette.roof,int(p.floors),"roof",Vector3(0,0,-side*rad_to_deg(atan2(rise,half))))
		for side in [-1,1]:
			box(plan,"roof/gable%d"%side,Vector3(0,roof_y+rise/2,side*(d/2-WALL/2)),Vector3(w,rise,WALL),palette.wall,int(p.floors),"roof")
			plan.records.back().building_shape = "gable"
	# Explicit elevation is independent of tread bottoms or pitched roof bounds.
	for record in plan.records: record.building.floor_y = int(record.building.floor)*h
	return plan

static func room_label(type: String, floor_: int, index: int) -> String:
	if type=="shop" and floor_==0: return "店铺" if index==0 else "储物间"
	if type=="inn": return ("接待厅" if index==0 else "厨房 / 储藏") if floor_==0 else "客房 %d"%(index+1)
	return ("起居室" if index==0 else "厨房 / 餐厅") if floor_==0 else "卧室 %d"%(index+1)

static func geometry_signature(record: Dictionary) -> String:
	var fields := {}
	for key in ["kind","position","rotation","size","building_shape","collision"]:
		if not record.has(key): continue
		if record[key] is Array:
			# glTF/JSON roundtrips must not turn binary floating-point noise into a hand edit.
			fields[key] = record[key].map(func(value): return snappedf(float(value),.00001)+0.0)
		else: fields[key] = record[key]
	return JSON.stringify(fields)

static func valid_record(record: Dictionary) -> bool:
	if record.has("building_shape") and (record.building_shape != "gable" or record.get("kind")!="box" or record.has("tile3d")): return false
	if not record.has("building"): return true
	var b: Variant = record.building
	return b is Dictionary and b.get("id") is String and b.get("part") is String and b.get("role") is String and (b.get("floor") is int or b.get("floor") is float) and b.floor>=0 and b.floor<=3 and b.floor==floor(b.floor) and (b.get("floor_y") is int or b.get("floor_y") is float) and is_finite(float(b.floor_y))

static func valid_meta(meta: Dictionary) -> bool:
	if not meta.has("building_instances"): return true
	if not meta.building_instances is Dictionary or meta.building_instances.size()>4096: return false
	for id in meta.building_instances:
		var b: Variant = meta.building_instances[id]
		if not id is String or not b is Dictionary or (b.get("version")!=1 and b.get("version")!=VERSION) or not b.get("parameters") is Dictionary: return false
		if not Schema.validate(b.parameters,schema()).is_empty(): return false
		for key in (legacy_defaults() if b.version==1 else defaults()):
			if not b.parameters.has(key): return false
		if not Schema.validate(b.get("position"),Schema.vector(-100000,100000)).is_empty(): return false
		if not Schema.validate(b.get("yaw"),Schema.number(-180,180)).is_empty(): return false
		if not b.get("parts") is Dictionary or not b.get("signatures") is Dictionary or b.parts.size()>2000: return false
		for part in b.parts:
			if not part is String or not b.parts[part] is String or not b.signatures.get(part) is String: return false
	return true

static func valid_ownership(meta: Dictionary, records: Array) -> bool:
	var registry: Dictionary = meta.get("building_instances",{}); var by_id := {}
	for record in records:
		if not record is Dictionary or not valid_record(record): return false
		by_id[str(record.get("uuid",""))] = record
		if not record.has("building"): continue
		var b: Dictionary = record.building
		if not registry.has(b.id) or registry[b.id].parts.get(b.part)!=record.get("uuid"): return false
	for id in registry:
		for part in registry[id].parts:
			var uuid: String = registry[id].parts[part]
			# Missing parts may be intentional hand edits; regeneration then reports a conflict.
			if by_id.has(uuid) and (by_id[uuid].get("building",{}).get("id")!=id or by_id[uuid].building.part!=part): return false
	return true

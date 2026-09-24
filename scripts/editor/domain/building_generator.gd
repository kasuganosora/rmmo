extends RefCounted
## Tile-based architectural grammar: fixed-size openings, repeated facade bays.
static func compose(kit: Dictionary,args: Dictionary) -> Dictionary:
	var bays:=int(args.get("bays",1));var floors:=int(args.get("floors",2))
	var roof:=str(args.get("roof","red"))
	if bays<1 or bays>3 or floors<1 or floors>3 or roof not in ["red","slate"]:
		return {"ok":false,"error":"bays/floors must be 1..3; roof must be red or slate"}
	var w:=bays*3+2;var h:=3+floors*2+1
	var cells: Array=[];var parts: Dictionary=kit.get("parts",{})
	for part in ["wall","wall_left","wall_right","foundation","window","door","roof_"+roof+"_left","roof_"+roof+"_middle","roof_"+roof+"_right"]:
		if not parts.has(part):return {"ok":false,"error":"incomplete building kit: "+part}
	for y in range(3,h):
		for x in range(w):
			var name: String="foundation" if y==h-1 else ("wall_left" if x==0 else ("wall_right" if x==w-1 else "wall"))
			_put(cells,parts[name],x,y,1)
	for x in range(w):
		var side: String="left" if x==0 else ("right" if x==w-1 else "middle")
		_put(cells,parts["roof_"+roof+"_"+side],x,0,3)
	for floor_index in range(floors):
		for bay in range(bays):
			if floor_index==floors-1 and bay==bays/2:continue
			if bool(args.get("windows",true)):_put(cells,parts.window,2+bay*3,3+floor_index*2,2)
	_put(cells,parts.door,w/2-1,h-2,2)
	return {"ok":true,"w":w,"h":h,"cells":cells,"door":{"x":w/2,"y":h},
		"parameters":{"kit":str(kit.get("id","")),"bays":bays,"floors":floors,"roof":roof,"windows":bool(args.get("windows",true))}}

static func _put(cells: Array,part: Dictionary,x: int,y: int,z: int) -> void:
	for dy in range(int(part.h)):
		for dx in range(int(part.w)):
			cells.append({"x":x+dx,"y":y+dy,"z":z,"tile_id":int(part.tiles[dy*int(part.w)+dx])})

static func place(doc,kit: Dictionary,args: Dictionary) -> Dictionary:
	var built:=compose(kit,args)
	if not built.ok:return built
	var x0:=int(args.get("x",0));var y0:=int(args.get("y",0))
	if x0<0 or y0<0 or x0+int(built.w)>doc.width or y0+int(built.h)>=doc.height:
		return {"ok":false,"error":"building or entrance lies outside map"}
	var id:=str(args.get("instance_id","house_%d_%d"%[x0,y0]))
	var previous: Dictionary=doc.building_instances.get(id,{})
	var owned: Dictionary={}
	for c in previous.get("cells",[]):owned["%d,%d,%d"%[int(c.x),int(c.y),int(c.z)]]=int(c.tile_id)
	for y in range(y0,y0+int(built.h)):
		for x in range(x0,x0+int(built.w)):
			for z in range(1,4):
				var existing: int=doc.tile(x,y,z)
				if existing!=0 and owned.get("%d,%d,%d"%[x,y,z],-1)!=existing:
					return {"ok":false,"error":"building overlaps existing map objects at %d,%d layer %d"%[x,y,z]}
	if bool(args.get("dry_run",false)):return built
	var before: Dictionary=doc.building_instances.duplicate(true)
	var dirty: Array[Vector2i]=[]
	doc.begin_undo_batch()
	for c in previous.get("cells",[]):
		if doc.tile(int(c.x),int(c.y),int(c.z))==int(c.tile_id):doc.set_tile(int(c.x),int(c.y),int(c.z),int(c.get("under",0)))
		else:
			# Do not erase hand edits outside the new footprint.
			continue
		dirty.append(Vector2i(int(c.x),int(c.y)))
	for c in previous.get("meta",[]):
		if doc.ext_tile("meta",int(c.x),int(c.y))==int(c.value):doc.set_ext_tile("meta",int(c.x),int(c.y),int(c.under))
	var placed: Array=[];var meta: Array=[]
	for c in built.cells:
		var x:=x0+int(c.x);var y:=y0+int(c.y);var z:=int(c.z)
		placed.append({"x":x,"y":y,"z":z,"tile_id":int(c.tile_id),"under":doc.tile(x,y,z)})
		doc.set_tile(x,y,z,int(c.tile_id));dirty.append(Vector2i(x,y))
	for y in range(y0,y0+int(built.h)):
		for x in range(x0,x0+int(built.w)):
			var under: int=doc.ext_tile("meta",x,y)
			var value:=under|4
			meta.append({"x":x,"y":y,"under":under,"value":value})
			doc.set_ext_tile("meta",x,y,value)
	doc.building_instances[id]={"x":x0,"y":y0,"w":built.w,"h":built.h,"parameters":built.parameters,"cells":placed,"meta":meta}
	doc._push_undo({"t":"building_instances","old":before,"new":doc.building_instances.duplicate(true)})
	doc.end_undo_batch();doc.dirty=true
	built["instance_id"]=id;built["dirty"]=dirty
	return built

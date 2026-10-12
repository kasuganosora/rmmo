extends "res://tools/residential_bridge_street.gd"
## Apply the shared continuous kerb generator to the existing hand-shaped street.
## Preserve detached road ownership, paint targets, plazas and bridge cutouts.
const EDGE_OUT="D:/code/rmmo_runtime/review_artifacts/bridge_road_edges_20261007"
const PRIOR_OUT="D:/code/rmmo_runtime/review_artifacts/bridge_house_spacing_20261007"
const Kerb=preload("res://scripts/world3d/road_kerb.gd")
const RoadSurface=preload("res://scripts/world3d/road_surface.gd")
const AREA=Rect2(240,88,168,176)
func run()->void:
	OUT=EDGE_OUT
	if "--publish" in OS.get_cmdline_user_args():await super.run();return
	DirAccess.make_dir_recursive_absolute(OUT)
	var baseline:=FileAccess.get_sha256(FORMAL);var d=Doc.new()
	var extras:Dictionary=Doc.authoritative_extras(FORMAL).extras
	d.records=extras.rmmo_records;d.map_meta=extras.duplicate(true);d.map_meta.erase("rmmo_records")
	check(d!=null,"latest native town opened")
	if failed:quit(1);return
	var p:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(PRIOR_OUT+"/plan.json"))
	d._next=int(p.next)
	var original:Array=d.records.duplicate(true);var metadata:Dictionary=d.map_meta.duplicate(true)
	var ports:Dictionary=preload("res://scripts/world3d/road_bridges.gd").resolve(d.map_meta.editor_layout)
	check(ports.ok,"existing bridge portals resolved")
	var options:=Kerb.defaults();options.kerb_enabled=true;options.kerb_width=.24;options.kerb_height=.035
	options.kerb_material_id="pack:default:paving/automatic_limestone_kerb_readable/material"
	var material:Dictionary=preload("res://scripts/world_editor/surface_material_library.gd").new().find(options.kerb_material_id)
	check(not material.is_empty() and Paint.missing([{"road_kerb_material":material}]).is_empty(),"published limestone kerb material available")
	var roads:Array=[];var targets:Dictionary={}
	for r:Dictionary in d.records:
		if not r.has("road_mesh"):continue
		var at:=Vector2(r.position[0],r.position[2])
		if AREA.grow(64).has_point(at):roads.append(r.duplicate(true))
		if not AREA.has_point(at):continue
		if not r.get("surface_paint",[]).all(func(face):return "石板" in face.material.get("name","")):continue
		check(not r.get("editor_locked",false) and not r.get("editor_hidden",false) and not r.has("event"),"road editable "+r.uuid)
		targets[r.uuid]=true
	if failed:quit(1);return
	# Keep a one-metre collar beyond all selected cells for seam cancellation.
	# Its artificial cut planes are open portals, never new pavement edges.
	# This avoids solving unrelated sharp junctions far outside this scene.
	var selected_bounds:=Rect2();var first:=true
	for r:Dictionary in roads:
		if not targets.has(r.uuid):continue
		var cell:=Rect2(Vector2(r.position[0]-r.size[0]/2,r.position[2]-r.size[2]/2),Vector2(r.size[0],r.size[2]))
		selected_bounds=cell if first else selected_bounds.merge(cell);first=false
	var collar:=selected_bounds.grow(1.0)
	var clip:Array=preload("res://scripts/world3d/roof_plan.gd").rect([collar.position.x,collar.position.y,collar.end.x,collar.end.y])
	for r:Dictionary in roads:
		if targets.has(r.uuid):continue
		var polys:Array=[]
		for raw:Array in r.road_mesh.polygons:
			var polygon:Array=raw.map(func(v):return Vector2(r.position[0]+v[0]*r.size[0],r.position[2]+v[1]*r.size[2]))
			var cut:Array=preload("res://scripts/world3d/road_plan.gd").intersection(polygon,clip)
			var normalized:Array=preload("res://scripts/world3d/road_plan.gd").normalized_patch(cut,Blueprint.vec(r.position))
			if not normalized.is_empty():polys.append(normalized)
		r.road_mesh.polygons=polys
	roads=roads.filter(func(r):return not r.road_mesh.polygons.is_empty())
	var solver_ports:Array=ports.portals.duplicate(true)
	for side:Array in [[Vector2(collar.position.x,collar.get_center().y),Vector2.LEFT],[Vector2(collar.end.x,collar.get_center().y),Vector2.RIGHT],[Vector2(collar.get_center().x,collar.position.y),Vector2.UP],[Vector2(collar.get_center().x,collar.end.y),Vector2.DOWN]]:
		var at:Vector2=side[0];var other:Vector2=at+side[1]
		solver_ports.append({"endpoints":[[at.x,.025,at.y],[other.x,.025,other.y]],"width":10000})
	FileAccess.open(OUT+"/solver_input.json",FileAccess.WRITE).store_string(JSON.stringify({"records":roads,"options":options,"portals":solver_ports}))
	var built:=Kerb.attach(roads,options,solver_ports)
	if not built.ok:print("BOUNDARY_ISSUE ",JSON.stringify(built))
	check(built.ok,"shared boundary solver: "+str(built.get("error","")))
	if failed:quit(1);return
	var replacements:Dictionary={};var starts:Dictionary={};var ends:Dictionary={};var total:=0.;var segments:=0
	for r:Dictionary in roads:
		if not targets.has(r.uuid) or not r.road_mesh.has("kerbs"):continue
		r.road_kerb_material=material.duplicate(true);replacements[r.uuid]=r
		for part:Dictionary in r.road_mesh.kerbs:
			starts[Kerb.key(Kerb.vec(r.position)+Kerb.vec(part.a[0]))]=true
			ends[Kerb.key(Kerb.vec(r.position)+Kerb.vec(part.b[0]))]=true
			total+=part.length;segments+=1
	for r:Dictionary in replacements.values():
		for part:Dictionary in r.road_mesh.kerbs:
			part.cap_a=not ends.has(Kerb.key(Kerb.vec(r.position)+Kerb.vec(part.a[0])))
			part.cap_b=not starts.has(Kerb.key(Kerb.vec(r.position)+Kerb.vec(part.b[0])))
		check(RoadSurface.valid(r) and Paint.valid(r),"native kerb and unchanged paint targets valid "+r.uuid)
		var unchanged:=r.duplicate(true);unchanged.road_mesh.erase("kerbs");unchanged.erase("road_kerb_material")
		check(equivalent(unchanged,d._find(r.uuid)),"pavement footprint, material and identity unchanged "+r.uuid)
	if failed:quit(1);return
	d.checkpoint_recovery()
	for i in d.records.size():
		if replacements.has(d.records[i].uuid):d.records[i]=replacements[d.records[i].uuid]
	for r:Dictionary in original:
		if not replacements.has(r.uuid) and not equivalent(r,d._find(r.uuid)):check(false,"unrelated record changed "+r.uuid)
	check(equivalent(metadata,d.map_meta),"road graph, terrain and building metadata preserved")
	var final:Array=d.records.duplicate(true)
	check(d.undo() and equivalent(d.records,original),"street edging undo")
	check(d.redo() and equivalent(d.records,final),"street edging redo")
	p.records=d.records;p.metadata=d.map_meta;p.next=d._next;p.failures=failed;p.formal_sha256=baseline
	p.road_edges={"settings":options,"changed":replacements.keys(),"segments":segments,"length_m":total,"context_chunks":roads.size(),"footprints_preserved":true,"ownership":"existing detached hand-shaped pavement"}
	FileAccess.open(OUT+"/plan.json",FileAccess.WRITE).store_string(JSON.stringify(p))
	print("STREET_EDGES ",JSON.stringify(p.road_edges)," failures=",failed);quit(failed)

extends SceneTree
const Doc=preload("res://scripts/world3d/world_document.gd")
const Stream=preload("res://scripts/world3d/world_stream.gd")
const Geometry=preload("res://scripts/world_editor/selection_geometry.gd")
const OUT="D:/code/rmmo_runtime/review_artifacts/nonperformance_fixes_20261012"
func _initialize()->void:run.call_deferred()
func run()->void:
	var published:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUT+"/access_published.json"))
	var path:="D:/code/rmmo_runtime/maps/medieval_river_town/map.gltf"
	if FileAccess.get_sha256(path)!=published.sha256:quit(1);return
	var doc=Doc.open_file(path);var clip:=AABB(Vector3(300,-2,200),Vector3(125,8,90))
	doc.records=doc.records.filter(func(r):return r.has("road_mesh") and Geometry.bounds([r]).intersects(clip))
	var host:=Node3D.new();root.add_child(host);var scene:Node3D=doc.build();host.add_child(scene)
	Stream.sync(scene,host,Vector3(360,0,240));await physics_frame;await physics_frame
	var batcher=scene.get_node_or_null("GroundRenderBatches");var stats:Dictionary=batcher.stats() if batcher!=null else {}
	var count:=0;var rendered:=0
	if batcher!=null:
		for key:String in batcher._member_groups:
			if key.begins_with("residential_access_"):count+=1
	var resident:Dictionary=scene.get_meta("stream_meshes",{})
	for key:String in resident:
		if not key.begins_with("residential_access_"):continue
		var node:MeshInstance3D=resident[key]
		if batcher._member_groups.has(key) or (node.mesh!=null and node.is_visible_in_tree()):rendered+=1
	# Isolated spatial cells remain individual draws; never merge the whole map
	# merely to force a source into a multi-object group.
	var ok:bool=rendered==7 and count>0 and stats.get("source_surfaces",0)>stats.get("render_surfaces",0)
	FileAccess.open(OUT+"/access_batches.json",FileAccess.WRITE).store_string(JSON.stringify({"ok":ok,"new_road_members":count,"new_road_rendered":rendered,"stats":stats,"formal_sha256":published.sha256},"\t"))
	print("ACCESS_BATCHES ",JSON.stringify({"ok":ok,"new_road_members":count,"new_road_rendered":rendered,"stats":stats}));host.free();quit(0 if ok else 1)

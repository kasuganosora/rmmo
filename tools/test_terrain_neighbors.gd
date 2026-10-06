extends SceneTree
const Doc=preload("res://scripts/world3d/world_document.gd")
const Terrain=preload("res://scripts/world3d/terrain_surface.gd")
const Neighbors=preload("res://scripts/world3d/terrain_neighbors.gd")
var failed:=0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label_: String) -> void:
	if not ok: failed+=1; push_error(label_)
	else: print("PASS: ",label_)
func errors(records: Array,context) -> Vector2:
	var buckets:={}; var before:=0.; var after:=0.
	for r in records:
		if not r.has("terrain_mesh"): continue
		var t: Dictionary=r.terrain_mesh; var world:=Terrain.transform(r)
		for z in int(t.rows)+1:
			for x in int(t.columns)+1:
				if x>0 and x<int(t.columns) and z>0 and z<int(t.rows): continue
				var k:=Vector3i((world*Terrain.point(r,x,z)*1000.).round()); var old:=world.basis*Terrain.normal(r,x,z)
				var fixed: Vector3=world.basis*context.data[r.uuid].normals.get(z*(int(t.columns)+1)+x,Terrain.normal(r,x,z))
				if buckets.has(k): before=maxf(before,old.angle_to(buckets[k][0])); after=maxf(after,fixed.angle_to(buckets[k][1]))
				else: buckets[k]=[old,fixed]
	return Vector2(rad_to_deg(before),rad_to_deg(after))
func run() -> void:
	var doc=Doc.open_file("D:/code/rmmo_runtime/maps/medieval_river_town/map.gltf")
	var original:=var_to_bytes(doc.records).hex_encode().sha256_text(); var context:=Neighbors.new(); var start:=Time.get_ticks_usec()
	context.update(doc.records); var elapsed:=(Time.get_ticks_usec()-start)/1000.
	var measured:=errors(doc.records,context)
	check(measured.y<.001 and measured.x>1.,"town shared normals: %.5f -> %.5f degrees"%[measured.x,measured.y])
	check(original==var_to_bytes(doc.records).hex_encode().sha256_text(),"seam context leaves every authoring height/record unchanged")
	check(context.update(doc.records).is_empty(),"unchanged context rebuilds nothing")
	var matched:=0; var max_height_error:=0.
	for id: String in context.data:
		var c: Dictionary=context.data[id]; var r: Dictionary=context.sources[id]; var t: Dictionary=r.terrain_mesh
		var world:=Terrain.transform(r); var pad:=Vector2i(c.padding)
		for other: String in c.neighbors:
			var n: Dictionary=context.sources[other]; var inverse:=Terrain.transform(n).affine_inverse()
			for z in [0,int(t.rows)/2,int(t.rows)]:
				for x in [-1,int(t.columns)+1]:
					var p:=world*Vector3((float(x)/t.columns-.5)*r.size[0],0,(float(z)/t.rows-.5)*r.size[2])
					var expected:=Terrain.sample(n,inverse*p)
					if not is_finite(expected): continue
					matched+=1; max_height_error=maxf(max_height_error,absf(c.image.get_pixel(x+pad.x,z+pad.y).r-(expected+n.position[1]-r.position[1])))
	check(matched>0 and max_height_error<.0001,"shader height halo reads adjacent ground: "+str(max_height_error))
	var modified: Array=doc.records.duplicate(true)
	var chosen: String=context.data.keys()[0]
	for r in modified:
		if r.uuid==chosen: r.terrain_mesh.heights[int(r.terrain_mesh.heights.size()/2)]+=.1
	var expected_changed: Array=context.data[chosen].neighbors.duplicate(); expected_changed.append(chosen)
	var actual_changed:=context.update(modified)
	check(actual_changed.size()==expected_changed.size() and actual_changed.all(func(id):return expected_changed.has(id)),"editing one patch refreshes only itself and its neighbors")
	var turning: Array=[]; var rotated:=Neighbors.new(); var rotation:=Basis(Vector3.UP,deg_to_rad(31.))
	for r in doc.records:
		if not r.has("terrain_mesh"): continue
		var copy: Dictionary=r.duplicate(true); var p: Vector3=rotation*Vector3(r.position[0],r.position[1],r.position[2])+Vector3(90,7,-42)
		copy.position=[p.x,p.y,p.z]; copy.rotation=[0,31.,0]; turning.append(copy)
	rotated.update(turning)
	check(errors(turning,rotated).y<.001,"shared normals remain seamless after group yaw and translation")
	var report:={"failures":failed,"before_normal_degrees":measured.x,"after_normal_degrees":measured.y,"halo_height_error":max_height_error,"initial_context_ms":elapsed}
	DirAccess.make_dir_recursive_absolute("D:/code/rmmo_runtime/review_artifacts/terrain_furrows")
	var file:=FileAccess.open("D:/code/rmmo_runtime/review_artifacts/terrain_furrows/seams.json",FileAccess.WRITE); file.store_string(JSON.stringify(report,"\t")); file.close()
	print("TERRAIN_NEIGHBORS ",JSON.stringify(report)); quit(1 if failed else 0)

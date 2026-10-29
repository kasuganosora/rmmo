extends SceneTree
const T=preload("res://scripts/world3d/terrain_surface.gd")
const L=preload("res://scripts/world3d/terrain_render_lod.gd")
const G=preload("res://scripts/world3d/ground_batch_geometry.gd")
var checks:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
static func boundary(vertices:PackedVector3Array,indices:PackedInt32Array,width:float,depth:float)->Dictionary:
	var result:Dictionary={}
	for i in range(0,indices.size(),3):
		for edge in 3:
			var a:Vector3=vertices[indices[i+edge]];var b:Vector3=vertices[indices[i+(edge+1)%3]]
			if (is_equal_approx(a.x,b.x) and is_equal_approx(absf(a.x),width/2)) or (is_equal_approx(a.z,b.z) and is_equal_approx(absf(a.z),depth/2)):
				var pair:Array=[var_to_str(a),var_to_str(b)];pair.sort();result[str(pair)]=true
	return result
func run()->void:
	for size:int in [16,31,32,64]:
		var record:Dictionary=preload("res://tools/test_terrain_incremental.gd").fixture(size)
		for z in size+1:
			for x in size+1:record.terrain_mesh.heights[z*(size+1)+x]=.04*sin(float(x)*.25)+.03*cos(float(z)*.32)
		var arrays:Array=T.arrays(record);var original:=var_to_bytes(arrays)
		var derived:=L.derive(record,arrays[0]);check(derived.indices.size()==3,"derive three bounded levels "+str(size))
		var vertices:PackedVector3Array=arrays[0][Mesh.ARRAY_VERTEX];var before:=boundary(vertices,arrays[0][Mesh.ARRAY_INDEX],record.size[0],record.size[2])
		for level in 3:
			var indices:PackedInt32Array=derived.indices[level]
			var valid:=true;var area:=0.
			var incidence:Dictionary={}
			for i in range(0,indices.size(),3):
				var a:Vector3=vertices[indices[i]];var b:Vector3=vertices[indices[i+1]];var c:Vector3=vertices[indices[i+2]]
				var signed:float=(b.x-a.x)*(c.z-a.z)-(b.z-a.z)*(c.x-a.x)
				valid=valid and signed>0;area+=signed/2
				for e in 3:
					var pair:Array=[indices[i+e],indices[i+(e+1)%3]];pair.sort()
					incidence[pair]=int(incidence.get(pair,0))+1
			check(valid and is_equal_approx(area,record.size[0]*record.size[2]),"LOD triangles preserve winding and exact full surface coverage %d/%d"%[size,level])
			check(boundary(vertices,indices,record.size[0],record.size[2])==before,"every original perimeter segment survives independent LOD %d/%d"%[size,level])
			var manifold:=true
			for pair:Array in incidence:
				var a:Vector3=vertices[pair[0]];var b:Vector3=vertices[pair[1]]
				var outer:bool=(is_equal_approx(a.x,b.x) and is_equal_approx(absf(a.x),record.size[0]/2)) or (is_equal_approx(a.z,b.z) and is_equal_approx(absf(a.z),record.size[2]/2))
				manifold=manifold and incidence[pair]==(1 if outer else 2)
			check(manifold,"no internal T junctions even with odd grid dimensions %d/%d"%[size,level])
			check(indices.size()<arrays[0][Mesh.ARRAY_INDEX].size(),"render triangle reduction %d/%d"%[size,level])
			var bound_ok:=true
			for i in range(0,indices.size(),maxi(3,int(indices.size()/120./3.)*3)):
				var a:Vector3=vertices[indices[i]];var b:Vector3=vertices[indices[i+1]];var c:Vector3=vertices[indices[i+2]]
				for weights:Vector3 in [Vector3(.2,.3,.5),Vector3(.7,.2,.1)]:
					var p:Vector3=a*weights.x+b*weights.y+c*weights.z
					bound_ok=bound_ok and absf(p.y-T.sample(record,p))<=derived.errors[level]+.000001
			check(bound_ok,"measured coarse surface deviations stay inside declared conservative bound %d/%d"%[size,level])
		check(var_to_bytes(arrays)==original,"base render and collision arrays remain byte exact "+str(size))
		record.terrain_mesh.holes[0]=true;check(L.derive(record,arrays[0]).is_empty(),"real holes remain exact and never get filled by LOD")
	var shifted:Dictionary=preload("res://tools/test_terrain_incremental.gd").fixture(16)
	var malformed:Array=T.arrays(shifted)[0].duplicate(true);var bad_vertices:PackedVector3Array=malformed[Mesh.ARRAY_VERTEX].duplicate();bad_vertices[0].x+=.1;malformed[Mesh.ARRAY_VERTEX]=bad_vertices
	check(L.derive(shifted,malformed).is_empty(),"unknown non-grid topologies keep exact fallback without missing lookup keys")
	var material:=StandardMaterial3D.new();material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	check(G.static_scatter_instances_enabled,"verified guarded cutout instancing is enabled by default")
	G.static_scatter_instances_enabled=false
	check(G.material_key(material,true).is_empty(),"explicitly disabled cutout instancing rejects vegetation materials")
	G.static_scatter_instances_enabled=true
	check(G.material_key(material).is_empty() and not G.material_key(material,true).is_empty(),"alpha cutout accepted only for explicit vegetation instancing")
	material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;check(G.material_key(material,true).is_empty(),"blended transparency retains independent ordering")
	material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR;material.billboard_mode=BaseMaterial3D.BILLBOARD_ENABLED;check(G.material_key(material,true).is_empty(),"billboard per-view geometry remains independent")
	G.static_scatter_instances_enabled=true
	var doc:=preload("res://scripts/world3d/world_document.gd").new();var host:=Node3D.new();root.add_child(host)
	var r:Dictionary=preload("res://tools/test_terrain_incremental.gd").fixture(16);var source:MeshInstance3D=doc._mesh(r);host.add_child(source)
	var batch:=preload("res://scripts/world3d/ground_batcher.gd").new();host.add_child(batch);batch.set_process(false);batch.sync([source]);batch.flush()
	check(batch.groups.size()==1 and batch.terrain_lod_visuals.size()==1,"one isolated native heightfield also receives render LODs")
	var visual:MeshInstance3D=batch.groups.values()[0].visual
	L.update(host,Vector3(0,5,0));check(visual.lod_bias==1000000.,"near camera retains original geometry")
	L.update(host,Vector3(0,5,400));check(visual.lod_bias==2.,"far camera uses conservative screen-error selection")
	batch.clear();check(batch.terrain_lod_visuals.is_empty(),"clear releases every registered weak LOD visual")
	var adapter:=preload("res://scripts/world3d/local_entry_authority.gd").new();var first:=doc.export_root();var second:=doc.export_root()
	check(adapter.register_root("map","revision",first).ok and adapter.registered_root_current("map","revision",first),"authority binds reusable catalogue to the actual root and revision")
	check(not adapter.registered_root_current("map","revision",second) and not adapter.registered_root_current("map","changed",first),"equal paths or roots alone cannot reuse another catalogue")
	first.free();check(not adapter.registered_root_current("map","revision",second),"catalogue weak owner never retains a retired map")
	second.free();host.free()
	print("STAGED_FAR_CONTRACT checks=",checks," failures=",failures);quit(1 if failures else 0)

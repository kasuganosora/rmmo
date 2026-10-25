extends SceneTree
## Differential CPU stress against the pre-change source supplied by --baseline.
## Outputs stay outside the project; this fixture never creates GPU resources.
const Paint=preload("res://scripts/world3d/surface_materials.gd")
var failures:=0
var checks:=0
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures+=1;push_error(label)
func _initialize()->void:run.call_deferred()
func fixture(side:int)->Dictionary:
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	var vertices:=PackedVector3Array();var uvs:=PackedVector2Array();var indices:=PackedInt32Array()
	for z:int in side+1:
		for x:int in side+1:
			vertices.append(Vector3(x*.3,0,z*.2));uvs.append(Vector2(x*.07+.123,z*.031-.8))
	for z:int in side:
		for x:int in side:
			var i:=z*(side+1)+x
			indices.append_array(PackedInt32Array([i,i+1,i+side+1,i+1,i+side+2,i+side+1]))
	arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_TEX_UV]=uvs
	var triangles:Array=[]
	for i:int in indices.size()/3:triangles.append(i)
	return {"arrays":arrays,"indices":indices,"faces":{0:{"normal":Vector3.UP,"triangles":triangles}}}
func run()->void:
	var baseline_path:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--baseline="):baseline_path=arg.trim_prefix("--baseline=")
	if baseline_path.is_empty():push_error("--baseline is required");quit(2);return
	var baseline:Script=load(baseline_path)
	if baseline==null:quit(2);return
	var entry:Dictionary={"face":0,"mapping":"uv","rotation":37.5,"scale":[2.3,-.7],"offset":[.15,-.33],"material":{"tile_size":[.8,1.25]}}
	var timings:Array=[]
	for side:int in [8,32,128]:
		var data:=fixture(side);var frozen:=var_to_bytes(data)
		for mapping:String in ["uv","planar","meters"]:
			entry.mapping=mapping
			for angle:float in [0.,37.5,-91.]:
				entry.rotation=angle
				var expected:PackedVector2Array=baseline._uvs(data,entry)
				check(var_to_bytes(Paint._uvs(data,entry))==var_to_bytes(expected),"all UV bits match %s/%d/%s"%[mapping,side,angle])
		entry.mapping="uv";entry.rotation=37.5
		for candidate:bool in [false,true,true,false]:
			var script:Script=Paint if candidate else baseline
			var samples:Array=[];var checksum:=0.0
			for iteration:int in 5:
				var began:=Time.get_ticks_usec()
				var result:PackedVector2Array=script._uvs(data,entry)
				samples.append(Time.get_ticks_usec()-began);checksum+=result[result.size()-1].x
			timings.append({"candidate":candidate,"side":side,"vertices":data.arrays[Mesh.ARRAY_VERTEX].size(),"face_triangles":data.indices.size()/3,"samples_us":samples,"checksum":checksum})
		check(var_to_bytes(data)==frozen,"source arrays and topology unchanged")
		# Internal callers without valid UV channels keep projection fallback.
		for missing:Variant in [null,PackedVector2Array([Vector2.ONE])]:
			data.arrays[Mesh.ARRAY_TEX_UV]=missing
			check(var_to_bytes(Paint._uvs(data,entry))==var_to_bytes(baseline._uvs(data,entry)),"missing/partial UV keeps planar fallback")
	# This source has valid UVs and no geometric face description. A UV-only
	# transform must not require topology; the production caller checks face IDs.
	var uv_only:=fixture(8);uv_only.faces={}
	var valid:=fixture(8)
	if "--uv-only" in OS.get_cmdline_user_args():
		check(Paint._uvs(uv_only,entry)==baseline._uvs(valid,entry),"UV transform does not read unused face geometry")
	print("UV_PROJECTION_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"timings":timings}))
	quit(1 if failures else 0)

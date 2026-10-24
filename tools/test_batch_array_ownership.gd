extends SceneTree
const Geometry=preload("res://scripts/world3d/ground_batch_geometry.gd")
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func surface(count:int,indexed:bool)->Array:
	var result:Array=[];result.resize(Mesh.ARRAY_MAX)
	var vertices:=PackedVector3Array();vertices.resize(count)
	var normals:=PackedVector3Array();normals.resize(count);normals.fill(Vector3.UP)
	var tangents:=PackedFloat32Array();tangents.resize(count*4)
	var uv:=PackedVector2Array();uv.resize(count)
	var colors:=PackedColorArray();colors.resize(count);colors.fill(Color(.1,.2,.3,1))
	for i:int in count:
		vertices[i]=Vector3(i%17,i%3,i/17);uv[i]=Vector2(i%5,i%7)
		tangents[i*4]=1;tangents[i*4+3]=-1
	result[Mesh.ARRAY_VERTEX]=vertices;result[Mesh.ARRAY_NORMAL]=normals;result[Mesh.ARRAY_TANGENT]=tangents;result[Mesh.ARRAY_TEX_UV]=uv;result[Mesh.ARRAY_TEX_UV2]=uv.duplicate();result[Mesh.ARRAY_COLOR]=colors
	if indexed:
		var indices:=PackedInt32Array();indices.resize(count)
		for i:int in count:indices[i]=count-1-i
		result[Mesh.ARRAY_INDEX]=indices
	return result
func run()->void:
	var hashes:Array=[]
	for layered:bool in [false,true]:
		var row:Dictionary={"arrays":[],"layered":layered};var originals:Array=[];var inputs:Array=[];var poses:Array=[]
		for part:int in 4:
			var arrays:=surface(768,part%2==0);inputs.append(arrays);originals.append(var_to_bytes(arrays))
			var pose:=Transform3D(Basis(Vector3.UP,.25*part),Vector3(part*2,part,-part));poses.append(pose)
			Geometry.append_arrays(row,arrays,pose,part)
		var exact:=true
		for part:int in 4:
			var source:Array=inputs[part];var pose:Transform3D=poses[part];var offset:=part*768
			for i:int in 768:
				exact=exact and row.arrays[Mesh.ARRAY_VERTEX][offset+i]==pose*source[Mesh.ARRAY_VERTEX][i] and row.arrays[Mesh.ARRAY_NORMAL][offset+i]==pose.basis*Vector3.UP
				exact=exact and row.arrays[Mesh.ARRAY_TEX_UV][offset+i]==source[Mesh.ARRAY_TEX_UV][i] and row.arrays[Mesh.ARRAY_COLOR][offset+i]==source[Mesh.ARRAY_COLOR][i]
				var tangent:=pose.basis*Vector3.RIGHT;var at:=(offset+i)*4
				exact=exact and Vector3(row.arrays[Mesh.ARRAY_TANGENT][at],row.arrays[Mesh.ARRAY_TANGENT][at+1],row.arrays[Mesh.ARRAY_TANGENT][at+2])==tangent and row.arrays[Mesh.ARRAY_TANGENT][at+3]==-1
				exact=exact and row.arrays[Mesh.ARRAY_INDEX][offset+i]==offset+(767-i if part%2==0 else i)
				if layered:exact=exact and row.arrays[Mesh.ARRAY_CUSTOM0][offset+i]==float(part)
			check(var_to_bytes(source)==originals[part],"append leaves every source channel unchanged")
		check(exact,"exact transformed attributes, mixed index rebasing and layer order")
		var digest:=HashingContext.new();digest.start(HashingContext.HASH_SHA256);digest.update(var_to_bytes(row.arrays));hashes.append(digest.finish().hex_encode())
		for channel:int in Mesh.ARRAY_MAX:
			if row.arrays[channel]!=null and not row.arrays[channel].is_empty():row.arrays[channel].clear()
		for part:int in 4:check(var_to_bytes(inputs[part])==originals[part],"output buffers never alias source ownership")
	var big:=surface(60000,true);var before:=var_to_bytes(big);var trials:Array=[]
	for trial:int in 6:
		var row:Dictionary={"arrays":[],"layered":false};var began:=Time.get_ticks_usec()
		for part:int in 16:Geometry.append_arrays(row,big,Transform3D(Basis.IDENTITY,Vector3(part,0,0)),part)
		trials.append(Time.get_ticks_usec()-began)
		check(row.arrays[Mesh.ARRAY_VERTEX].size()==960000,"large batch completes all vertices")
	check(var_to_bytes(big)==before,"repeated large batches preserve shared input")
	print("BATCH_ARRAY_OWNERSHIP ",JSON.stringify({"hashes":hashes,"vertices_per_trial":960000,"trials_us":trials,"failures":failures}));quit(1 if failures else 0)

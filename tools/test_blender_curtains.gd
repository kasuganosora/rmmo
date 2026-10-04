extends SceneTree
const Curtain=preload("res://scripts/world3d/curtain_mesh.gd")
const OUT="D:/code/rmmo_runtime/review_artifacts/blender_curtains"
var failed:=0
func check(ok:bool,label:String)->void:
	if ok:print("PASS: ",label)
	else:failed+=1;push_error(label)
func _initialize()->void:run.call_deferred()
func box(parent:Node,pos:Vector3,size:Vector3,color:Color)->void:
	var n:=MeshInstance3D.new();var b:=BoxMesh.new();b.size=size;n.mesh=b;n.position=pos
	var m:=StandardMaterial3D.new();m.albedo_color=color;b.material=m;parent.add_child(n)
func run()->void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var viewport:=SubViewport.new();viewport.size=Vector2i(1280,1024);viewport.own_world_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color(.2,.24,.28);env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color.WHITE;env.environment.ambient_light_energy=.5;viewport.add_child(env)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-35,-38,0);light.shadow_enabled=true;viewport.add_child(light)
	var linen:=StandardMaterial3D.new();linen.albedo_texture=ImageTexture.create_from_image(Image.load_from_file("D:/code/rmmo_runtime/packs/default/assets/materials/details/linen_curtain/linen_v2.png"));linen.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var meshes:Array=[]
	for side in [-1,1]:
		var record:Dictionary={"size":[.44,1.8,.16],"collision":"none","cloth":{"axis":"x","side":side}}
		check(Curtain.valid(JSON.parse_string(JSON.stringify(record))),"JSON roundtrip side "+str(side))
		var mesh:=Curtain.mesh(record,linen);meshes.append(mesh)
		check(mesh.get_faces().size()==378,"126 triangles within 128 painted faces")
		check(mesh.get_surface_count()==1,"one continuous cloth surface")
		var arrays:=mesh.surface_get_arrays(0);var normals:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
		check(normals.size()==80 and normals.to_byte_array().size()>0,"shared smooth vertices include sleeve")
		var n:=MeshInstance3D.new();n.mesh=mesh;n.position=Vector3(side*.62,1.15,.13);viewport.add_child(n)
		var geometry:Dictionary=preload("res://scripts/world3d/surface_materials.gd").geometry(n)
		check(geometry.ok and geometry.surfaces[0].faces.size()<=128,"paint face IDs fit persisted override budget")
		var positions:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
		var linked:Dictionary={0:true};var changes:=true
		while changes:
			changes=false
			for t in range(0,indices.size(),3):
				if linked.has(indices[t]) or linked.has(indices[t+1]) or linked.has(indices[t+2]):
					for k in 3:
						if not linked.has(indices[t+k]):linked[indices[t+k]]=true;changes=true
		check(linked.size()==positions.size(),"entire sleeve and hanging cloth are one connected mesh")
		var sane:=true
		for t in range(0,indices.size(),3):
			var a:=positions[indices[t]];var b:=positions[indices[t+1]];var c:=positions[indices[t+2]]
			if (b-a).cross(c-a).length()<.000001:sane=false
		check(sane,"no degenerate triangles")
		var definition:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("D:/code/rmmo_runtime/packs/default/assets/materials/details/linen_curtain/material.json")).material
		definition.texture_path="D:/code/rmmo_runtime/packs/default/assets/materials/details/linen_curtain/linen_v2.png"
		record.surface_paint=[]
		for face in geometry.surfaces[0].faces:
			record.surface_paint.append({"mesh":".","surface":0,"face":face,"geometry":geometry.surfaces[0].signature,"material":definition,"scale":[1,1],"offset":[0,0],"rotation":0,"mapping":"uv"})
		preload("res://scripts/world3d/surface_materials.gd").apply(n,JSON.parse_string(JSON.stringify(record)))
		check(not n.has_meta("paint_error"),"real surface paint applies after JSON roundtrip")
		var double_sided:=true
		for slot in n.mesh.get_surface_count():
			if n.mesh.surface_get_material(slot).cull_mode!=BaseMaterial3D.CULL_DISABLED:double_sided=false
		check(double_sided,"painted cloth remains visible from both sides")
		var invalid:=record.duplicate(true);invalid.cloth.side=0;check(not Curtain.valid(invalid),"invalid side rejected")
		invalid=record.duplicate(true);invalid.cloth.axis="y";check(not Curtain.valid(invalid),"invalid axis rejected")
		var zrecord:=record.duplicate(true);zrecord.size=[.16,1.8,.44];zrecord.cloth.axis="z";check(Curtain.mesh(zrecord,linen).get_faces().size()==378,"other wall axis supported")
	box(viewport,Vector3(0,2.05,.13),Vector3(1.9,.045,.045),Color(.19,.105,.055))
	box(viewport,Vector3(0,1.05,-.05),Vector3(.075,1.75,.1),Color(.19,.105,.055))
	for y in [.175,1.925]:box(viewport,Vector3(0,y,-.05),Vector3(1.45,.075,.1),Color(.19,.105,.055))
	for x in [-.725,.725]:box(viewport,Vector3(x,1.05,-.05),Vector3(.075,1.75,.1),Color(.19,.105,.055))
	box(viewport,Vector3(0,1.2,-.18),Vector3(3.5,3.2,.1),Color(.73,.70,.63))
	box(viewport,Vector3(0,1.05,-.1),Vector3(1.38,1.68,.01),Color(.19,.28,.32))
	var camera:=Camera3D.new();viewport.add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=2.75
	for angle in ["front","oblique","side","pocket"]:
		camera.size=1.05 if angle=="pocket" else 2.75
		camera.position={"front":Vector3(0,1.2,4),"oblique":Vector3(2,1.55,3.8),"side":Vector3(3,1.3,1.4),"pocket":Vector3(.85,2.5,1.3)}[angle]
		camera.look_at(Vector3(.62,2.02,.13) if angle=="pocket" else Vector3(0,1.15,.1))
		for i in 8:await process_frame
		await RenderingServer.frame_post_draw;viewport.get_texture().get_image().save_png(OUT.path_join(angle+".png"))
	print("BLENDER_CURTAINS_RESULT failures=",failed);quit(1 if failed else 0)

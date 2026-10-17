extends "res://tools/prepare_axel_town_house_templates.gd"
## Offline authored variant, using current production walls, doors, roof and PBR.
const BASE10="D:/code/rmmo_runtime/art_sources/s10_court_variants_20261017"
const MODEL10="s10_court_shutter_house"
const Med10=preload("res://scripts/world3d/medieval_building.gd")
const G10=preload("res://scripts/world3d/building_geometry.gd")
const IO10=preload("res://scripts/world3d/gltf_map_io.gd")
func write10(path:String,value:Variant)->void:
	FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify(value,"\t"))
func louvers10(plan:Dictionary)->void:
	var result:Array=[]
	for r:Dictionary in plan.records:
		if r.building.role!="shutter":result.append(r);continue
		# Real overlapping tilted slats inside a timber perimeter. One family per house.
		var axis:String="x" if float(r.size[0])>float(r.size[2]) else "z"
		var side_axis:int=0 if axis=="x" else 2
		var width:float=r.size[side_axis];var height:float=r.size[1]
		var pivot_world:=G10.vec(r.position)+G10.vec(r.fixture.pivot)
		for side in [-1,1]:
			var stile:Dictionary=r.duplicate(true);stile.uuid+="_stile"+str(side);stile.building.part+="/stile"+str(side)
			stile.position[side_axis]+=side*(width/2-.035);stile.size[side_axis]=.07
			stile.fixture.pivot=G10.arr(pivot_world-G10.vec(stile.position));result.append(stile)
		var count:int=ceili((height-.16)/.11)
		for i in count:
			var slat:Dictionary=r.duplicate(true);slat.uuid+="_slat"+str(i);slat.building.part+="/slat"+str(i)
			slat.position[1]+=(-height/2+.10)+(height-.20)*(i+.5)/count
			slat.size=[width-.13,.13,.026] if axis=="x" else [.026,.13,width-.13]
			slat.rotation=[-32,0,0] if axis=="x" else [0,0,32]
			var basis:=Basis.from_euler(G10.vec(slat.rotation)*PI/180)
			slat.fixture.pivot=G10.arr(basis.inverse()*(pivot_world-G10.vec(slat.position)));result.append(slat)
	plan.records=result
func run()->void:
	var version:="v1"
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--version="):version=arg.trim_prefix("--version=")
	if not version.is_valid_filename():quit(2);return
	var folder:=BASE10.path_join(version);DirAccess.make_dir_recursive_absolute(folder)
	var output:=folder.path_join(MODEL10+".glb")
	if FileAccess.file_exists(output):push_error("Existing candidate");quit(2);return
	var source:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(BASE10+"/source_house.json"))
	var params:Dictionary=Blueprint.defaults().merged(source.instance.parameters,true)
	params.window_style="tall_shutter";params.template="house";params.front_canopy=false
	var plan:Dictionary=Med10.generate(params)
	if not plan.get("ok",false):push_error(str(plan));quit(2);return
	plan.records=plan.records.filter(func(r):return not str(r.building.part).begins_with("f0/north/"))
	plan.openings=plan.openings.filter(func(o):return o.wall!="f0/north")
	var palette:={"wall":[.86,.84,.79],"trim":[.27,.19,.12],"floor":[.49,.34,.21],"roof":[.43,.17,.105],"glass":[.29,.39,.38],"stone":[.64,.59,.47],"shutter":[.32,.20,.12]}
	var openings:Array=[]
	for x in [5.0,-.8,-3.4]:openings.append(Med10.opening("court_window_"+str(openings.size()),x,"window","f0/room0"))
	openings.append(Med10.opening("entrance",2.5,"door","f0/room0"))
	Med10.framed_wall(plan,"f0/north","x",-5.4,-6.05,6.05,0,3.5,openings,palette,0,params)
	plan.entrance=[2.5,0,-6.5]
	louvers10(plan)
	for r:Dictionary in plan.records:
		r.building.floor_y=int(r.building.floor)*3.5
		if r.has("fixture") and r.fixture.kind=="door":r.fixture.open=0
	plan=G10.finish_plan(plan)
	if not plan.get("ok",false):push_error(str(plan));quit(2);return
	for row:Dictionary in preload("res://scripts/world_editor/surface_material_library.gd").new().entries():definitions[row.material_id]=row.material
	editor=PaintHost.new();root.add_child(editor)
	var local:Array=plan.records
	for i in local.size():local[i].uuid="s10part_"+str(i);local[i].building.id=MODEL10
	var paintdoc=Doc.new();paintdoc.records=local;editor._view=paintdoc.build();editor.add_child(editor._view)
	editor._buildings.values={MODEL10:{"parameters":params,"yaw":0}}
	var validation:Dictionary={}
	for r:Dictionary in local:
		if r.building.role=="light_sconce" or r.get("building_shape","") in ["timber_door","interior_door","interior_door_frame"]:continue
		var faces:Dictionary=author_faces(r)
		if not faces.ok:push_error("Invalid face "+r.uuid);quit(2);return
		var entries:Array=[]
		for face:Dictionary in faces.faces:
			var role:=material_role(r,face);var entry:Dictionary=face.target.duplicate(true)
			entry.merge({"mapping":"meters","scale":[1,1],"rotation":0,"offset":[0,0]});entry.merge(settings_for(r,face,role),true)
			var mid:String="pack:default:walls/exterior_limewash/material" if role=="plaster" else IDS[role]
			entry.material=definitions[mid].duplicate(true);entries.append(entry)
		r.surface_paint=entries
		if not Paint.valid(r,false,"",validation):push_error("Invalid paint "+r.uuid);quit(2);return
	var frozen:=Prefab.bake(local)
	if not frozen.ok:push_error(str(frozen));quit(2);return
	write10(folder.path_join(MODEL10+"_recipe.json"),{"parameters":params,"entrance":plan.entrance,"openings":plan.openings,"rooms":plan.rooms,"records":frozen.records})
	var model:=Node3D.new();model.name=MODEL10
	var regions:Array=[]
	for room:Dictionary in plan.rooms:regions.append({"id":room.id,"floor":int(room.floor),"min":[room.bounds[0],.3,room.bounds[1]],"max":[room.bounds[2],3.8,room.bounds[3]]})
	# Semantic room boundaries use authored millimetres, not intermediate float tails.
	for region:Dictionary in regions:
		for key:String in ["min","max"]:
			for axis in 3:region[key][axis]=snappedf(float(region[key][axis]),0.001)
	model.set_meta("extras",{"rmmo_model_components":{"version":1},"rmmo_building":{"version":1,"regions":regions},"asset_id":MODEL10})
	var meshes=Doc.new()
	for r:Dictionary in frozen.records:
		var mesh:MeshInstance3D=meshes._mesh(r,true)
		# The GLB contains authored solids; runtime effects are reconstructed separately.
		for child in mesh.get_children():child.free()
		var extra:Dictionary=mesh.get_meta("extras",{}).duplicate(true)
		var role:String=str(r.building.role)
		role="roof" if role.begins_with("roof") or r.building.floor>0 else "floor" if role=="floor" else "body"
		if str(r.building.part).ends_with("/ceiling"):role="ceiling"
		if r.has("fixture"):
			extra.rmmo_hinge=r.fixture.duplicate(true);extra.rmmo_hinge.erase("kind");role="door"
		# Authored floor datums use millimetres, not Vector3 float32 roundoff.
		# Stable numeric metadata must survive catalog JSON and source verification.
		extra.rmmo_part={"floor":int(r.building.floor),"floor_y":snappedf(float(r.building.floor_y),0.001),"role":role,"part":str(r.building.part)}
		extra.uuid=r.uuid;extra.erase("fixture");extra.erase("building");mesh.set_meta("extras",extra)
		model.add_child(mesh);mesh.owner=model
	var descriptor:=preload("res://scripts/world3d/imported_building.gd").describe(model)
	if descriptor.is_empty():push_error("Invalid generic descriptor");quit(2);return
	check(IO10.save_scene(model,output)==OK,"GLB export")
	write10(folder.path_join(MODEL10+"_authoring.json"),{"id":MODEL10,"path":output,"sha256":FileAccess.get_sha256(output),"source_bytes":FileAccess.get_file_as_bytes(output).size(),"recipe":folder.path_join(MODEL10+"_recipe.json"),"source_house":BASE10+"/source_house.json","source_parts":local.size(),"frozen_parts":frozen.records.size(),"descriptor":descriptor,"anchors":{"ground_origin":[0,0,0],"front_axis":"-Z","entry_center":[2.5,.3,-5.5],"entry_approach":[2.5,0,-6.5],"lamp_wall_anchor":[1.37,2.45,-5.51],"front_window_centres":[[5,2.025,-5.4],[-.8,2.025,-5.4],[-3.4,2.025,-5.4]]},"scope":"S10 project variant. Existing room/roof/door pipeline reused; complete louver shutters; facade revised. Lamp is an independent reusable fixture at the supplied anchor. No tree/planter embedded."})
	model.free();editor.free();print("S10_HOUSE_BUILT ",output);quit(1 if failed else 0)

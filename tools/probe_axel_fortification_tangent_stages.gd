extends "res://tools/probe_axel_fortification_tangents.gd"
const Art=preload("res://scripts/world3d/fortification_art.gd")
const Lib=preload("res://scripts/world_editor/surface_material_library.gd")
const KIT="D:/code/rmmo_runtime/packs/default/assets/fortifications/medieval_stone/medieval_wall.glb"
func mesh_info(mesh:Mesh)->Array:
	var result:Array=[]
	var cpu=Frozen.Cpu.capture(mesh)
	for a:Array in cpu.surfaces:
		var row:=inspect(a,Transform3D.IDENTITY);row.invalid_basis=0
		if a[Mesh.ARRAY_TANGENT]!=null:
			var t:PackedFloat32Array=a[Mesh.ARRAY_TANGENT]
			for i in a[Mesh.ARRAY_VERTEX].size():
				if preload("res://scripts/world3d/mesh_tangent_repair.gd").invalid(Vector3(t[4*i],t[4*i+1],t[4*i+2]),t[4*i+3],a[Mesh.ARRAY_NORMAL][i]):row.invalid_basis+=1
		result.append(row)
	return result
func run()->void:
	var input:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUT+"/fortification_tangent_probe.json"))
	report={"read_only":true,"map_sha256":FileAccess.get_sha256(MAP),"kit_sha256":FileAccess.get_sha256(KIT),"stages":[]}
	var source:Dictionary=input.rows[0].sources[0].record
	var library:=Lib.new();var materials:Dictionary={}
	for pair:Array in [["stone","pack:default:walls/castle_rubble/material"],["trim","pack:default:walls/stone_tiles_facade/material"],["door","pack:default:wood/worn_planks/material"]]:materials[pair[0]]=library.find(pair[1])
	materials.iron={"name":"锻铁","color":[.075,.068,.055,1.0],"roughness":.78,"metallic":.72}
	source.fortification_art={"version":1,"module":source.fortification.role,"asset_path":KIT};source.fortification_materials=materials
	report.source=source
	var art:=Art.new();var kit:=art.kit(KIT)
	report.stages.append({"stage":"original_kit_wall","surfaces":mesh_info(kit.wall.mesh)})
	var mesh:Mesh=art.build(source)
	report.stages.append({"stage":"art_build_cpu","surfaces":mesh_info(mesh)})
	var reads:Array=[]
	for si in mesh.get_surface_count():reads.append(inspect(mesh.surface_get_arrays(si),Transform3D.IDENTITY))
	report.stages.append({"stage":"art_build_arraymesh_readback","surfaces":reads})
	var slope:=Fit.deform(mesh,source.terrain_grade)
	report.stages.append({"stage":"terrain_deform_cpu","surfaces":mesh_info(slope)})
	var raw=source.duplicate(true);raw.erase("terrain_grade")
	for row:Dictionary in [{"stage":"freeze_flat","record":raw},{"stage":"freeze_sloped","record":source}]:
		var baked:=preload("res://scripts/world3d/structure_prefab.gd").fortification([row.record])
		if not baked.ok:report.error=baked;break
		var d:=Frozen.decode(baked.records[0].house_prefab);var infos:Array=[]
		for entry:Array in d.entries:
			for a:Array in d.meshes[entry[1][0]].surfaces:infos.append(inspect(a,Transform3D.IDENTITY))
		report.stages.append({"stage":row.stage,"surfaces":infos})
	report.map_unchanged=FileAccess.get_sha256(MAP)==report.map_sha256;report.kit_unchanged=FileAccess.get_sha256(KIT)==report.kit_sha256
	var output:="fortification_tangent_stages.json"
	for arg:String in OS.get_cmdline_user_args():
		if arg=="--fixed":output="fortification_tangent_stages_fixed.json"
	FileAccess.open(OUT+"/"+output,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	for stage:Dictionary in report.stages:print(stage.stage," ",JSON.stringify(stage.surfaces.map(func(s):return {"bad":s.bad_count,"effective":s.bad_effective_triangles,"vertices":s.vertices})))
	quit(0)

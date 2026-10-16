extends SceneTree
const Ranges=preload("res://scripts/world3d/asset_visibility_range.gd")
const OUT="D:/code/rmmo_runtime/review_artifacts/axel_town_layout_20261016/lod_boundary_gpu.json"
var world:Node3D
var camera:Camera3D
func _initialize()->void:run.call_deferred()
func run()->void:
	if DisplayServer.get_name()=="headless":quit(2);return
	root.size=Vector2i(640,480);root.use_taa=false;world=Node3D.new();root.add_child(world)
	camera=Camera3D.new();world.add_child(camera);camera.current=true
	var results:Array=[];var failures:=0
	for legacy:bool in [true,false]:
		for distances:Array in [[25.,24.5,25.5,26.,24.,25.,65.,64.5,65.5,66.],[5.,24.,24.5,25.,25.5,26.,66.,65.5,65.,64.5,64.]]:
			var models:Array=[]
			for level:int in 3:
				var node:=MeshInstance3D.new();node.mesh=BoxMesh.new()
				var material:=StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;material.albedo_color=[Color.RED,Color.GREEN,Color.BLUE][level];node.material_override=material
				node.set_meta("extras",{"rmmo_visibility_range":{"begin":[0.,25.,65.][level],"end":[25.,65.,180.][level],"bounds":[-.5,-.5,-.5,1.,1.,1.]}})
				Ranges.register(node)
				if legacy:node.visibility_range_begin_margin=1. if level>0 else 0.;node.visibility_range_end_margin=1.
				world.add_child(node);models.append(node)
			for distance_:float in distances:
				camera.position=Vector3(0,0,distance_);camera.look_at(Vector3.ZERO)
				for frame in 4:await process_frame
				await RenderingServer.frame_post_draw
				var count:=root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)
				results.append({"legacy":legacy,"distance":distance_,"primitives":count})
				# Godot includes the exact endpoint on both independent ranges.
				# Only that zero-width boundary may submit two levels; never zero.
				var boundary:bool=distance_==25. or distance_==65.
				if not legacy and (count<12 or count>(24 if boundary else 12)):failures+=1
			for node:MeshInstance3D in models:node.free()
			await process_frame
	var reproduced:bool=results.any(func(r):return r.legacy and r.primitives==0)
	if not reproduced:failures+=1
	FileAccess.open(OUT,FileAccess.WRITE).store_string(JSON.stringify({"phase":"complete","failures":failures,"passed":failures==0,"legacy_gap_reproduced":reproduced,"samples":results,"source_sha256":FileAccess.get_sha256("res://scripts/world3d/asset_visibility_range.gd"),"scope":"Actual GPU primitive submission at two shared LOD boundaries, cold camera jumps and both travel directions; no authored model changes"},"  "))
	print("LOD_BOUNDARY_GPU_FAILURES ",failures);quit(1 if failures else 0)

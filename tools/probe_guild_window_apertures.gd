extends "res://tools/review_axel_guild_finish.gd"
const DEST="D:/code/rmmo_runtime/review_artifacts/axel_guild_finish_20261012/full_review"
func run()->void:
	var evidence:=read_json(DEST+'/building/baseline.json')
	var packed:PackedScene=load(evidence.native.payload);var scene:=packed.instantiate();root.add_child(scene)
	for n:MeshInstance3D in scene.find_children('*','MeshInstance3D',true,false):
		var group:String=n.get_meta('extras',{}).get('semantic_group','')
		if group not in ['11_Exterior_Upper','30_Rooms_L1']:continue
		var body:=StaticBody3D.new();var shape:=CollisionShape3D.new();shape.shape=n.mesh.create_trimesh_shape();body.add_child(shape);n.add_child(body);body.set_meta('mesh_path',str(scene.get_path_to(n)))
	for i in 3:await physics_frame
	var rows:Array=[]
	for probe in [
		['203 east',Vector3(31.2,6.2,-3.7),Vector3(32.5,6.2,-3.7)],
		['204 east',Vector3(31.2,6.2,-6.7),Vector3(32.5,6.2,-6.7)],
		['washroom east',Vector3(31.2,6.2,-10.8),Vector3(32.5,6.2,-10.8)],
		['washroom rear',Vector3(29.7,6.2,-13.2),Vector3(29.7,6.2,-14.5)]
	]:
		var hit:=root.world_3d.direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(probe[1],probe[2]))
		rows.append({"label":probe[0],"from":vec(probe[1]),"to":vec(probe[2]),"blocked":not hit.is_empty(),"mesh":hit.collider.get_meta('mesh_path','') if not hit.is_empty() else '',"hit":vec(hit.position) if not hit.is_empty() else []})
	put(DEST+'/window_apertures.json',{"sha256":evidence.original_sha,"scope":"Geometry ray probe against upper exterior and room wall meshes; temporary trimeshes only, not gameplay collision acceptance.","probes":rows})
	print('WINDOW_PROBES ',JSON.stringify(rows));quit()

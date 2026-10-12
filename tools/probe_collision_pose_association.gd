extends SceneTree
## Pure CPU arithmetic probe; no GLB, Mesh, physics or render resources.
const Prepare=preload("res://scripts/world3d/collision_instance_preparation.gd")
func _initialize()->void:run.call_deferred()
static func absolute_error(a:Transform3D,b:Transform3D)->Dictionary:
	var basis_error:=0.;var origin_error:=0.
	for at:int in 3:
		origin_error=maxf(origin_error,absf(a.origin[at]-b.origin[at]))
		for axis:int in 3:basis_error=maxf(basis_error,absf(a.basis[at][axis]-b.basis[at][axis]))
	var bounds_error:=0.
	for x:float in [-1.,1.]:
		for y:float in [-1.,1.]:
			for z:float in [-1.,1.]:
				bounds_error=maxf(bounds_error,(a*Vector3(x,y,z)-b*Vector3(x,y,z)).length())
	return {"basis":basis_error,"origin":origin_error,"unit_bounds":bounds_error}
func run()->void:
	var random:=RandomNumberGenerator.new();random.seed=20261011
	var mismatches:=0;var collector_mismatches:=0;var canonical_mismatches:=0
	var max_basis:=0.;var max_origin:=0.;var max_bounds:=0.
	for sample:int in 256:
		var record:Dictionary={"position":[321.2,.9,160.3],"rotation":[12.345,136.088,-4.321],"size":[.7,.85,1.13]}
		var holder:=Node3D.new();holder.transform=Prepare.record_pose(record);root.add_child(holder)
		var parent:Node3D=holder;var flattened:=Transform3D.IDENTITY;var runtime:=Transform3D.IDENTITY*holder.transform
		var locals:Array=[]
		for depth:int in 3:
			var node:=Node3D.new()
			node.position=Vector3(random.randf_range(-10,10),random.randf_range(-2,4),random.randf_range(-10,10))
			node.rotation_degrees=Vector3(random.randf_range(-180,180),random.randf_range(-180,180),random.randf_range(-180,180))
			node.scale=Vector3(random.randf_range(.2,2),random.randf_range(.2,2),random.randf_range(.2,2))
			parent.add_child(node);parent=node;locals.append(node.transform)
			flattened=flattened*node.transform;runtime=runtime*node.transform
		var adapter:=Prepare.record_pose(record)*flattened
		var actual:Transform3D=parent.global_transform
		if runtime!=actual:collector_mismatches+=1
		# Canonical rendering computes the source-local chain exactly once, then
		# applies the author pose after that local traversal, as the adapter does.
		var source_local:=Transform3D.IDENTITY
		for local:Transform3D in locals:source_local=source_local*local
		if Prepare.record_pose(record)*source_local!=adapter:canonical_mismatches+=1
		if adapter!=runtime:
			mismatches+=1
			var error:=absolute_error(adapter,runtime)
			max_basis=maxf(max_basis,error.basis);max_origin=maxf(max_origin,error.origin);max_bounds=maxf(max_bounds,error.unit_bounds)
			if sample<3:print("POSE_ASSOCIATION_SAMPLE ",JSON.stringify({"sample":sample,"record":record,"locals":locals,"adapter":adapter,"runtime":runtime,"actual_global":actual,"absolute_error":error}))
		holder.free()
	print("POSE_ASSOCIATION ",JSON.stringify({"samples":256,"strict_mismatches":mismatches,"runtime_vs_actual_Node3D_mismatches":collector_mismatches,"source_local_then_author_mismatches":canonical_mismatches,"max_absolute_basis_error":max_basis,"max_absolute_origin_error_m":max_origin,"max_unit_bounds_error_m":max_bounds}))
	quit(0 if mismatches>0 and collector_mismatches==0 and canonical_mismatches==0 else 1)

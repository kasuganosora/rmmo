extends Node3D
## Slot changes are transactional and do not recreate the actor or reset its pose.
const Garment=preload("res://scripts/char/character_surface_garment.gd")
const Art=preload("res://scripts/asset/art_paths.gd")
var body:Node3D
var slots:Dictionary={}
var garments:Dictionary={}
func ordered_garments()->Array:
	var keys:Array=garments.keys();keys.sort()
	var result:Array=[]
	for slot:String in keys:result.append(garments[slot])
	return result
func step_cloth()->void:
	var inner:Array=[]
	for garment:Node3D in ordered_garments():
		if garment.cloth:
			garment.cloth.step(body,false,3,inner);inner.append(garment.cloth)
func warm_start_cloth()->bool:
	# Dress against a continuous body sweep instead of starting with a hand
	# already embedded in a skirt. No frame is yielded and the actor pose/identity
	# is restored before returning. This expensive path is review-only for now.
	var requested_angles:Dictionary=body.angles_by_name.duplicate(true)
	# Animation and SkeletonModifier poses do not rewrite the test-pose recipe.
	# Warm-start from the actual final surface pose, then restore that same pose.
	var angles:Dictionary={}
	for node:Dictionary in body.nodes:angles[node.name]=node.angles*180.0/PI
	var original_position:Vector3=body.position
	var original_offset:Vector3=body.world_offset
	var root_offset:Vector3=body.root_offset
	var active:Array=[]
	for garment:Node3D in ordered_garments():
		if garment.cloth==null and garment.cloth_enabled:active.append(garment)
	if active.is_empty():return true
	body.set_angles({},root_offset)
	var success:=true
	for garment:Node3D in active:
		if not garment.enable_cloth():success=false;break
	if success:
		for step in 80:
			var pose:Dictionary={}
			for bone:String in angles:pose[bone]=angles[bone]*minf(float(step+1)/60.0,1.0)
			body.set_angles(pose,root_offset)
			var points:PackedVector3Array=body.read_gpu_points() if body.use_compute else body.posed_points
			var bottom:=INF
			for p:Vector3 in points:bottom=minf(bottom,p.y+root_offset.y)
			body.position.y=-bottom
			var inner:Array=[]
			for garment:Node3D in active:
				garment.cloth.step(body,false,3,inner);inner.append(garment.cloth)
	else:
		for garment:Node3D in active:garment.disable_cloth()
	body.set_angles(angles,root_offset);body.position=original_position;body.world_offset=original_offset
	body.angles_by_name=requested_angles
	return success
func configure(target:Node3D)->void:body=target
func set_equipment_snapshot(snapshot:Array,catalog)->bool:
	return set_equipment(preload("res://scripts/char/paperdoll_look.gd").equipment_to_surface_parts("female_base_v2",snapshot,catalog))
func set_slot(slot:String,id:String)->bool:
	var recipe:Dictionary=slots.duplicate()
	if id.is_empty():recipe.erase(slot)
	else:recipe[slot]=id
	return set_equipment(recipe)
func set_equipment(recipe:Dictionary)->bool:
	var catalog:Variant=JSON.parse_string(FileAccess.get_file_as_string(Art.path("characters/equipment/surface_bound/catalog.json")))
	if not catalog is Array:return false
	var allowed:Dictionary={}
	for entry:Dictionary in catalog:allowed[entry.id]=true
	for slot:Variant in recipe:
		if not slot is String or not recipe[slot] is String or not allowed.has(recipe[slot]):return false
	var staged:Dictionary={}
	for slot:String in recipe:
		if slots.get(slot)==recipe[slot]:continue
		var garment:=Garment.new()
		if not garment.initialize(body,recipe[slot]):
			garment.free()
			for node:Node in staged.values():node.free()
			return false
		staged[slot]=garment
	for slot:String in garments.keys():
		if not recipe.has(slot) or recipe[slot]!=slots[slot]:garments[slot].free();garments.erase(slot)
	for slot:String in staged:add_child(staged[slot]);garments[slot]=staged[slot]
	slots=recipe.duplicate();return true

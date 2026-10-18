extends RefCounted
## Presentation of server entity snapshots; no AI, movement or respawn timers.
var combat:Node
func _init(owner:Node)->void:combat=owner

func sync()->void:
	var transport=combat.Net.server()
	var rows:Dictionary=transport.gameplay.projection.entities
	for id:String in combat.actors.keys():
		if rows.has(id):continue
		combat.actors[id].queue_free();combat.actors.erase(id);combat.targets.erase(id)
	for id:String in rows:
		var row:Dictionary=rows[id]
		var point:Dictionary=row.get("position_m",{})
		var feet:=Vector3(point.get("x",0.),point.get("y",0.),point.get("z",0.))
		if not feet.is_finite():continue
		var generation:=int(row.get("state",{}).get("generation",0))
		if combat.actors.has(id) and int(combat.actors[id].get_meta("server_generation",-1))!=generation:
			combat.actors[id].queue_free();combat.actors.erase(id)
		if not combat.actors.has(id):
			var bounds:=BoxMesh.new();bounds.size=Vector3(.6,1.8,.6)
			var details:Dictionary=row.get("details",{})
			var spec:Dictionary={"uuid":id,"mesh":bounds,"transform":Transform3D(Basis.IDENTITY,feet+Vector3.UP*.9),"position":feet+Vector3.UP*.9,"extras":{"hostile":bool(row.get("combat_enabled",false)),"ally":false,"name":str(details.get("name",id)),"appearance":{}}}
			var actor=preload("res://scripts/world3d/world_npc.gd").new()
			actor.configure(spec);combat.add_child(actor);actor.set_physics_process(false);actor.set_meta("server_generation",generation)
			combat.actors[id]=actor;combat.targets[id]=spec
		var actor:CharacterBody3D=combat.actors[id]
		actor.global_position=feet+Vector3.UP*.9;actor.rotation.y=float(row.get("facing_radians",0.))
		var dead:=bool(row.get("state",{}).get("dead",false))
		actor.collision_layer=0 if dead else 1;actor.collision_mask=0
		actor.model.play("death" if dead else ("walk" if str(row.get("behavior","")) in ["chase","return","wander"] else "idle"),"front")
	if not rows.has(combat.selected):combat.selected=""

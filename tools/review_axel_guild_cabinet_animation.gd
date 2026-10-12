extends SceneTree

var errors:Array=[]
var reports:Array=[]
const OUT="D:/code/rmmo_runtime/art_sources/axel_guild/guestroom_v1"

func _initialize()->void:
	call_deferred("run")

func check(ok:bool,label:String)->void:
	if not ok:errors.append(label);push_error(label)

func run()->void:
	for kind:String in ["guest_nightstand","guest_low_cabinet"]:
		var path:=OUT+"/game/guild_"+kind+".glb"
		var doc:=GLTFDocument.new();var state:=GLTFState.new()
		check(doc.append_from_file(path,state)==OK,kind+" load")
		var scene:=doc.generate_scene(state);root.add_child(scene)
		for index in state.json.get("nodes",[]).size():
			var node:=state.get_scene_node(index)
			if node==null:continue
			for key:String in state.json.nodes[index].get("extras",{}):node.set_meta(key,state.json.nodes[index].extras[key])
		var players:=scene.find_children("*","AnimationPlayer",true,false)
		check(players.size()==1,kind+" animation player")
		if players.is_empty():scene.queue_free();continue
		var player:AnimationPlayer=players[0]
		var initial:Dictionary={}
		for node in scene.find_children("*","Node3D",true,false):initial[node]=node.transform
		var count:=1 if kind=="guest_nightstand" else 2
		var tested:Array=[]
		for door in count:
			var group:="door_"+str(door)
			for clip:String in ["Open","Close"]:
				var name:=group+"_"+clip
				check(player.has_animation(name),kind+" "+name)
				if not player.has_animation(name):continue
				var animation:=player.get_animation(name)
				var animated:Array=[]
				for track in animation.get_track_count():
					var target_path:=NodePath(animation.track_get_path(track).get_concatenated_names())
					var target:=player.get_node(player.root_node).get_node(target_path)
					if target not in animated:animated.append(target)
				player.play(name);player.seek(player.get_animation(name).length,true);player.advance(0)
				var moving:=0
				for node:Node3D in initial:
					if node in animated:
						moving+=1
						var delta:Basis=initial[node].basis.inverse()*node.basis
						var angle:float=rad_to_deg(delta.get_rotation_quaternion().get_angle())
						check(absf(angle-(95.0 if clip=="Open" else 0.0))<.15,kind+" "+name+" rotation")
						check(node.position.distance_to(initial[node].origin)<.0001,kind+" hinge remains fixed")
					else:check(node.transform.is_equal_approx(initial[node]),kind+" stationary body/other door")
				check(moving==3,kind+" separate material groups move together")
				tested.append(name)
			player.pause()
		reports.append({"asset":kind,"sha256":FileAccess.get_sha256(path),"clips":tested,"open_angle_degrees":95,"closed_restored":true})
		scene.queue_free();await process_frame
	var f:=FileAccess.open(OUT+"/cabinet_animation_review.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"failures":errors,"assets":reports,"scope":"Actual GLB import and Open/Close playback; input binding and moving collisions not implemented"},"  "));f.close()
	print("CABINET_ANIMATION errors=",errors.size());quit(0 if errors.is_empty() else 1)

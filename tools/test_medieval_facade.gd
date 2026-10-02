extends SceneTree
const Blueprint=preload("res://scripts/world3d/building_blueprint.gd")
const Medieval=preload("res://scripts/world3d/medieval_building.gd")
var failed:=0

func check(value: bool, label: String) -> void:
	if not value: failed+=1; push_error(label)

func _initialize() -> void:
	var cases:=0; var braces:=0
	for preset in Blueprint.medieval_presets():
		for style in ["timber","plaster"]:
			for width in [.18,.24,.32]:
				for roof_axis in ["depth","width"]:
					var parameters: Dictionary=preset.parameters.merged({"style":style,"timber_width":width,"roof_axis":roof_axis},true)
					var plan:=Blueprint.generate(parameters)
					check(plan.ok,"valid facade fixture"); if not plan.ok: continue
					cases+=1
					check(plan.records.all(func(r):return r.size.all(func(v):return v>0)),"roof cuts never create zero-size parts")
					var records:={}
					for record in plan.records: records[record.building.part]=record
					for o in plan.openings:
						if o.id=="stair_window": check(o.u+o.width/2<float(plan.stairs[0].hole[1]),"stair window stays in the lower landing, clear of treads and handrails")
						for side in [-1,1]:
							var jamb: Dictionary=records[o.wall+"/"+o.id+"/jamb"+str(side)]
							var transform:=Transform3D(Basis.from_euler(Blueprint.vec(jamb.rotation)*PI/180),Blueprint.vec(jamb.position))
							var bounds: AABB=transform*AABB(-Blueprint.vec(jamb.size)/2,Blueprint.vec(jamb.size))
							var axis:=0 if o.axis=="x" else 2
							check(is_equal_approx(absf(bounds.get_center()[axis]-o.u)-bounds.size[axis]/2,o.width/2-.05),"rotated dormer and facade frames overlap their own reveal")
					for joint in plan.frame_joints:
						braces+=1
						var brace: Dictionary=records[joint.part]
						var tangent:=Vector3.RIGHT if absf(brace.rotation[2])>.1 else Vector3.BACK
						var half: float=brace.size[0 if tangent==Vector3.RIGHT else 2]/2
						var direction:=Basis.from_euler(Blueprint.vec(brace.rotation)*PI/180)*tangent
						check((Blueprint.vec(brace.position)-direction*half).distance_to(Blueprint.vec(joint.start))<.0001,"actual brace mesh starts at joint")
						check((Blueprint.vec(brace.position)+direction*half).distance_to(Blueprint.vec(joint.end))<.0001,"actual brace mesh ends at joint")
						for i in 2:
							var support: Dictionary=records[joint.supports[i]]
							var size:=Blueprint.vec(support.size)
							check(AABB(Blueprint.vec(support.position)-size/2,size).grow(.001).has_point(Blueprint.vec(joint.start if i==0 else joint.end)),"both joints meet solid supports")
						var wall: String=joint.part.get_slice("/brace",0)
						for o in plan.openings:
							if o.wall!=wall: continue
							var u:=0 if o.axis=="x" else 2
							check(not Medieval.diagonal_hits(Vector2(joint.start[u],joint.start[1]),Vector2(joint.end[u],joint.end[1]),Rect2(o.u-o.width/2,o.floor_y+o.bottom,o.width,o.height).grow(.1)),"brace leaves window/door aperture clear")
					# Missing optional v4 fields in old saved recipes are accepted after JSON.
					for version in [2,3,4]:
						var p: Dictionary=plan.parameters.duplicate(true)
						if version<4: p.erase("timber_width"); p.erase("chimney")
						var meta: Dictionary={"building_instances":{"test":{"version":version,"parameters":p,"position":[0,0,0],"yaw":0,"parts":{},"signatures":{}}}}
						check(Blueprint.valid_meta(JSON.parse_string(JSON.stringify(meta))),"JSON version %d remains readable"%version)
	check(cases==84 and braces>0,"matrix exercises 84 facades and real bracing")
	print("MEDIEVAL_FACADE_TEST cases=",cases," braces=",braces," failures=",failed)
	quit(1 if failed else 0)

extends "res://tools/test_stream_index_append.gd"
const Preparation=preload("res://scripts/world3d/stream_index_preparation.gd")
func matches(value:Dictionary,snapshot:Array)->bool:
	Preparation.shared_signature_defaults_enabled=false;var before:bool=Preparation.signature(value)==snapshot
	Preparation.shared_signature_defaults_enabled=true;var after:bool=Preparation.signature(value)==snapshot
	check(before==after,"shared empty defaults preserve native strict signature equality")
	return after
func run()->void:
	for field:String in ["uuid","mesh","pose","low","high","aabb","extra_group","record_group","lamp","crystal","collision","wind","landscape","ground","fixture","fixture_owner"]:
		var value:=spec("building__part",Vector2i.ZERO,Vector2i.ZERO,{}, {"fixture":{"id":"door"}})
		var captured:=Preparation.signature(value)
		check(matches(value,captured),"unchanged private source matches: "+field)
		match field:
			"uuid":value.uuid="replacement__part"
			"mesh":value.mesh=value.mesh.duplicate()
			"pose":value.transform.origin+=Vector3.RIGHT
			"low":value.chunk_min-=Vector2i.ONE
			"high":value.chunk_max+=Vector2i.ONE
			"aabb":value.mesh.size+=Vector3.ONE
			"extra_group":value.extras.building={"id":"new"}
			"record_group":value.ground_batch_record.building={"id":"new"}
			"lamp":value.extras.rmmo_streetlamp_instance="lamp"
			"crystal":value.extras.rmmo_streetlamp_crystal=true
			"collision":value.extras.rmmo_collision="none"
			"wind":value.extras.rmmo_wind={}
			"landscape":value.extras.rmmo_landscape_kind="channel"
			"ground":value.ground_batch_record.terrain_mesh={}
			"fixture":value.extras.fixture.id="window"
			"fixture_owner":value.extras.fortification={"id":"wall"}
		var result:bool=matches(value,captured)
		check(not result and result==(Preparation.signature(value)==captured),"fresh comparison preserves old rejection: "+field)
	var value:=spec("plain",Vector2i.ZERO,Vector2i.ZERO)
	var captured:=Preparation.signature(value);var frozen:=value.duplicate(true)
	check(matches(value,captured) and value==frozen,"matching creates no source annotations")
	value.extras.unrelated={"text":"authoring"}
	check(matches(value,captured)==(Preparation.signature(value)==captured),"unrelated author metadata retains existing semantics")
	check(not matches(value,[]),"invalid private signature fails gracefully")
	for field:String in ["rmmo_streetlamp_crystal","rmmo_collision"]:
		for original:Variant in [false,0,0.0,1.0,NAN,"",StringName(""),[],{"nested":[1]},null]:
			value=spec("plain",Vector2i.ZERO,Vector2i.ZERO);value.extras[field]=original;captured=Preparation.signature(value)
			check(matches(value,captured)==(Preparation.signature(value)==captured),"legacy scalar/container equality remains exact: "+field+" type "+str(typeof(original)))
			value.extras[field]=true
			check(matches(value,captured)==(Preparation.signature(value)==captured),"legacy type mutation remains exact: "+field+" type "+str(typeof(original)))
	value=spec("nonfinite",Vector2i.ZERO,Vector2i.ZERO);value.transform.origin.x=NAN;captured=Preparation.signature(value)
	check(matches(value,captured)==(Preparation.signature(value)==captured),"nonfinite geometry retains original signature equality; downstream validators still decide acceptance")
	print("INDEX_SIGNATURE_COMPARISON failures=",failures);quit(1 if failures else 0)

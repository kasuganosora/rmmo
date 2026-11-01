extends SceneTree
var Weather:GDScript
var Oracle:GDScript
const Settings=preload("res://scripts/world3d/environment_settings.gd")
const Profile=preload("res://scripts/world3d/weather_profile.gd")
const Authority=preload("res://scripts/net/server/sky_module.gd")
const NAMES=["cloud_seed_offset","star_seed","star_intensity","star_time","meteor_heads","meteor_tails","meteor_energies","meteor_kinds","meteor_brightness"]
var checks:Array=[]
var work:Dictionary={}
var failed:=0
var sequence:=10
var scene:Node3D
var counted:=false

class Leaf:
	extends Node3D
	var camera:Camera3D
	var light:OmniLight3D
	var enabled:=true
	var wetness:=0.0
	var puddles:=0.0
	var rain:=0.0
	var snow:=0.0
	var storm:=0.0
	var time:=0.0
	var wind:=Vector3.ZERO
	var brightness:=0.0
	var refreshes:=0
	func refresh()->void:refreshes+=1
	func clear()->void:pass
	func reset()->void:pass
	func advance(_a:Variant,_b:Variant=null,_c:Variant=null,_d:Variant=null,_e:Variant=null,_f:Variant=null)->void:pass

func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks.append({"ok":ok,"label":label})
	if not ok:failed+=1;print("FAIL ",label)
func material()->ShaderMaterial:
	var result:=ShaderMaterial.new()
	var shader:=Shader.new()
	shader.code="shader_type sky; uniform vec3 cloud_seed_offset; uniform int star_seed; uniform float star_intensity; uniform float star_time; uniform vec3 meteor_heads[8]; uniform vec3 meteor_tails[8]; uniform float meteor_energies[8]; uniform float meteor_kinds[8]; uniform float meteor_brightness[8]; uniform vec4 cloud_flash; void sky(){COLOR=vec3(0.0);}"
	result.shader=shader;result.get_rid();return result
func make(script:Script)->Node:
	var rig:Node=script.new();scene.add_child(rig);rig.set_process(false);rig.set_physics_process(false)
	rig.values=Settings.updated({}, {"preset":"night","time_speed":0.0,"weather_transition":0.0,"meteor_frequency":0.0,"environment_audio":false})
	rig.current=Profile.sample(rig.values);rig.target=rig.current.duplicate(true);rig.source=rig.current.duplicate(true)
	rig.sky_material=material();rig.sky=Sky.new();rig.sky.sky_material=rig.sky_material
	rig.environment=Environment.new()
	rig.camera=Camera3D.new();rig.add_child(rig.camera);rig.observer=rig
	rig.sun=DirectionalLight3D.new();rig.add_child(rig.sun)
	rig.moon=DirectionalLight3D.new();rig.add_child(rig.moon)
	for field:String in ["precipitation","wet_surfaces","wind_objects","streetlamps","lightning"]:
		var leaf:=Leaf.new();rig.add_child(leaf);rig.set(field,leaf)
	rig.lightning.light=OmniLight3D.new();rig.lightning.add_child(rig.lightning.light);rig.lightning.light.light_energy=0.0;rig.flash=rig.lightning.light
	for field:String in ["audio","roof_audio","wind_audio"]:
		var audio:=AudioStreamPlayer.new();rig.add_child(audio);rig.set(field,audio)
	rig.set("_sky63_now",100.0)
	return rig
func packet(events:Array=[],hours:float=0.0,speed:float=0.0,seed_:int=321,epoch_:String="sky63")->Dictionary:
	var authority:=Authority.new();authority.rng.seed=77
	check(authority.configure("sky63",seed_,0.0),"authority fixture configure")
	check(authority.set_environment("sky63",{"preset":"night","time_hours":hours,"time_speed":speed,"weather_transition":0.0,"meteor_frequency":0.0},100.0).ok,"authority fixture environment")
	var result:Dictionary=authority.snapshot("sky63",100.0)
	sequence+=1;result.sequence=sequence;result.epoch=epoch_;result.environment_revision=1;result.events=events.duplicate(true)
	return result
func deliver(pair:Array,p:Dictionary,stamp:float=100.0)->void:
	# The fixture selects a server/local instant with zero offset. Use a valid
	# matching packet stamp; receive() still performs its real clock math.
	p=p.duplicate(true);p.server_time=stamp
	for rig:Node in pair:
		rig.set("_sky63_now",stamp)
		var receipt:={"packet":p.duplicate(true),"calls":0}
		rig.set_meta("provider_receipt",receipt)
		rig.sky_map="sky63";rig.sky_provider=func():receipt.calls+=1;return receipt.packet
		rig.sky_poll=0.0
	tick(pair,stamp,"packet %d"%int(p.sequence))
	for rig:Node in pair:check(rig.night_sky.ready and rig.night_sky.sequence==int(p.sequence),"valid packet accepted with actual client")
func pair_new()->Array:
	var pair:Array=[make(Weather),make(Oracle)];deliver(pair,packet());return pair
func compare(pair:Array,label:String)->void:
	for name_:String in NAMES:
		var actual:Variant=pair[0].sky_material.get_shader_parameter(name_)
		var expected:Variant=pair[1].sky_material.get_shader_parameter(name_)
		check(actual==expected,label+" uniform "+name_)
	check(pair[0].celestial==pair[1].celestial,label+" celestial dictionary")
	check(pair[0].night_sky.meteors==pair[1].night_sky.meteors,label+" actual sampled events")
func tick(pair:Array,stamp:float,label:String,apply_:bool=false)->void:
	for rig:Node in pair:
		rig.set("_sky63_now",stamp)
		if apply_:rig._apply()
		else:rig._tick_night_sky_impl(0.0)
	compare(pair,label)
func reset_counts(rig:Node)->void:
	if counted:rig._sky63_count.clear()
func counts(rig:Node)->Dictionary:return rig._sky63_count.duplicate(true) if counted else {}
func value(row:Dictionary,key:String)->int:return int(row.get(key,0))
func event(id:String,start:float,duration:float=1.2,kind:String="meteor")->Dictionary:
	var a:=Vector3(-.18,.62,-.76).normalized();var b:=Vector3(.15,.45,-.88).normalized()
	return {"id":id,"start_at":start,"duration":duration,"from":[a.x,a.y,a.z],"to":[b.x,b.y,b.z],"kind":kind,"brightness":2.5 if kind=="fireball" else 1.0}
func close_pair(pair:Array)->void:
	for rig:Node in pair:rig.free()
func run()->void:
	counted=OS.get_environment("RMMO_SKY63_COUNTED")!="0"
	if not _prepare_scripts():quit(2);return
	scene=Node3D.new();root.add_child(scene)
	var pair:=pair_new();reset_counts(pair[0])
	for i in 32:tick(pair,100.0,"fixed idle %d"%i)
	work.fixed_idle=counts(pair[0])
	if counted:
		check(value(work.fixed_idle,"cycle_sample")==0,"WORK fixed hour repeats zero Cycle.sample")
		check(value(work.fixed_idle,"seed_offset")==0,"WORK fixed seed repeats zero seed_offset")
		check(value(work.fixed_idle,"array_construct")==0,"WORK empty repeats zero PackedArray construction")
		check(value(work.fixed_idle,"setter_total")==0,"WORK identical nine outputs repeat zero setters")
		check(value(work.fixed_idle,"sky_sample")==32,"fixed empty still samples every tick")
	reset_counts(pair[0])
	for i in 16:tick(pair,100.125+float(i)*.125,"moving star clock %d"%i)
	work.fixed_hour_moving_clock=counts(pair[0])
	if counted:
		check(value(work.fixed_hour_moving_clock,"cycle_sample")==0,"WORK moving twinkle fixed hour repeats zero Cycle.sample")
		check(value(work.fixed_hour_moving_clock,"seed_offset")==0 and value(work.fixed_hour_moving_clock,"array_construct")==0,"WORK moving twinkle retains seed and empty arrays")
		check(value(work.fixed_hour_moving_clock,"set_star_time")==16,"moving twinkle still submits every distinct time")
	for rig:Node in pair:rig.current.cloud=.65;rig.current.fog=.02
	tick(pair,102.0,"mid-frame cloud fog changed",true)
	check(float(pair[0].sky_material.get_shader_parameter("star_intensity"))<.3,"new current weights reach material within same-frame apply")
	for rig:Node in pair:rig.current.cloud=.18;rig.current.fog=0.0
	tick(pair,102.0,"mid-frame weights restored",true)
	reset_counts(pair[0])
	for rig:Node in pair:rig.sky_material=material()
	tick(pair,102.0,"new material same values")
	work.material_replacement=counts(pair[0])
	if counted:check(value(work.material_replacement,"setter_total")==9,"new material receives all nine fields once")
	for flag:String in ["sky_enabled","meteors_enabled"]:
		for enabled:bool in [false,true]:
			for rig:Node in pair:rig.values[flag]=enabled
			tick(pair,102.0,"empty toggle "+flag+str(enabled))
	var fresh:=packet([],0.0,0.0,987)
	deliver(pair,fresh,102.0)
	check(int(pair[0].sky_material.get_shader_parameter("star_seed"))==987,"new seed same revision updates material")
	fresh=packet([event("future",110.0),event("second",110.3,2.5,"fireball")],0.0,0.0,987)
	deliver(pair,fresh,102.0)
	for stamp:float in [109.0,110.2,110.7,111.5]:tick(pair,stamp,"future/two event %.3f"%stamp)
	check(pair[0].night_sky.meteors.size()==1,"first expires while second remains")
	for enabled:bool in [false,true]:
		for rig:Node in pair:rig.visuals_enabled=enabled
		tick(pair,111.5,"active visual gate "+str(enabled))
	for flag:String in ["sky_enabled","meteors_enabled"]:
		for enabled:bool in [false,true]:
			for rig:Node in pair:rig.values[flag]=enabled
			tick(pair,111.5,"active toggle "+flag+str(enabled))
	for rig:Node in pair:rig.sky_material=material()
	tick(pair,111.5,"replace active material")
	reset_counts(pair[0]);tick(pair,113.1,"active to empty")
	work.active_to_empty=counts(pair[0]);reset_counts(pair[0])
	for i in 4:tick(pair,113.1,"empty after expiry %d"%i)
	work.after_expiry=counts(pair[0])
	if counted:
		check(value(work.active_to_empty,"array_construct")==5,"active expiry constructs complete neutral arrays once")
		check(value(work.after_expiry,"array_construct")==0,"WORK expired empty repeats zero arrays")
	var events:Array=[]
	for i in 8:events.append(event("eight%d"%i,120.0,2.0 if i==7 else .8))
	deliver(pair,packet(events),119.0);tick(pair,120.4,"eight active")
	check(pair[0].night_sky.meteors.size()==8,"all eight simultaneous slots sampled")
	tick(pair,121.0,"eight to one")
	var energies:PackedFloat32Array=pair[0].sky_material.get_shader_parameter("meteor_energies")
	check(energies.size()==8 and energies[0]>0.0 and Array(energies.slice(1)).all(func(x):return x==0.0),"eight to one clears trailing seven energies")
	tick(pair,123.0,"one to empty")
	check(Array(pair[0].sky_material.get_shader_parameter("meteor_heads")).all(func(x):return x==Vector3.UP),"expired heads use legacy neutral UP")
	deliver(pair,packet([event("same-revision-new-event",130.0)],0.0,0.0,321),125.0)
	tick(pair,130.5,"new sequence same revision starts future event")
	check(pair[0].night_sky.meteors.size()==1,"same revision does not suppress new future events")
	deliver(pair,packet([],0.0,0.0,654,"new-epoch"),140.0)
	check(pair[0].night_sky.epoch=="new-epoch","new epoch accepted and old active output cleared")
	for rig:Node in pair:rig.sky_provider=Callable();rig.night_sky.reset()
	tick(pair,140.0,"client reset without ready")
	check(float(pair[0].sky_material.get_shader_parameter("star_intensity"))==0.0,"not ready resets star strength")
	for rig:Node in pair:rig.bind_sky("new-map",Callable())
	tick(pair,141.0,"bind sky clears readiness")
	for rig:Node in pair:rig.configure(rig.values.duplicate(true),true)
	compare(pair,"configure instant resets ready and output")
	close_pair(pair)
	pair=pair_new()
	deliver(pair,packet([],12.0,360.0),100.0)
	reset_counts(pair[0])
	for stamp:float in [100.000001,100.000002,100.1,102.0]:tick(pair,stamp,"dynamic hour %.6f"%stamp)
	if counted:check(value(counts(pair[0]),"cycle_sample")==4,"dynamic hour including tiny changes recomputes celestial")
	deliver(pair,packet([],23.9,360.0),100.0)
	for stamp:float in [100.5,101.5]:tick(pair,stamp,"dynamic midnight %.3f"%stamp)
	deliver(pair,packet(),100.0)
	for stamp:float in [3599.999,3600.0,3600.001]:tick(pair,stamp,"twinkle wraps %.3f"%stamp)
	check(is_equal_approx(float(pair[0].sky_material.get_shader_parameter("star_time")),.001),"independent twinkle wraps at one hour")
	close_pair(pair)
	flash_case()
	remaining_contracts()
	scene.free()
	var report:={"checks":checks,"passed":checks.size()-failed,"failed":failed,"work":work,"counted":counted,"scope":"Real ShaderMaterial values, valid server packets and real NightSky sampling. External deterministic clock and optional actual-call counters only; no timing/FPS assertion."}
	var path:=OS.get_environment("RMMO_SKY63_OUTPUT")
	if not path.is_empty():
		var file:=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	print("SKY63_RESULT passed=",report.passed," failed=",failed," work=",JSON.stringify(work))
	quit(0 if failed==0 else 1)

func flash_case()->void:
	var pair:=pair_new()
	for rig:Node in pair:rig.sky_provider=Callable();rig.target=rig.current.duplicate(true)
	for rig:Node in pair:rig._process(.016)
	reset_counts(pair[0])
	for i in 12:
		for rig:Node in pair:rig._process(.016)
		compare(pair,"real process fixed flash %d"%i)
	work.fixed_flash=counts(pair[0])
	if counted:check(value(work.fixed_flash,"set_cloud_flash")==0,"WORK fixed flash repeats zero cloud_flash setter")
	for configuration:Array in [[Vector3(1,2,3),4.0],[Vector3(2,3,4),4.0],[Vector3(2,3,4),0.0]]:
		for rig:Node in pair:
			rig.lightning.light.global_position=configuration[0];rig.lightning.light.light_energy=configuration[1]
			rig._process(.016)
		check(pair[0].sky_material.get_shader_parameter("cloud_flash")==pair[1].sky_material.get_shader_parameter("cloud_flash"),"flash position/energy/active-to-zero reaches shader in current process")
	for rig:Node in pair:rig.sky_material=material();rig._process(.016)
	check(pair[0].sky_material.get_shader_parameter("cloud_flash")==Vector4(2,3,4,0),"new material receives same zero-energy flash position")
	close_pair(pair)

const SKY63_REFERENCE_SHA="557b587bc27d5c7aa6c67e3ba013962378e1d36af916087a7de6cf50c31b3f4a"
const SKY63_COUNT_HELPERS="\nfunc _sky63_add(key:String)->void:_sky63_count[key]=int(_sky63_count.get(key,0))+1\nfunc _sky63_submit(key:StringName,value_:Variant)->void:\n\t_sky63_add(\"setter_total\");_sky63_add(\"set_\"+str(key))\n\tsky_material.set_shader_parameter(key,value_)\nfunc _sky63_cycle(hour:float)->Dictionary:\n\t_sky63_add(\"cycle_sample\");return Cycle.sample(hour)\nfunc _sky63_seed(seed_:int)->Vector3:\n\t_sky63_add(\"seed_offset\");return Clouds.seed_offset(seed_)\nfunc _sky63_vector_array()->PackedVector3Array:\n\t_sky63_add(\"array_construct\");return PackedVector3Array()\nfunc _sky63_float_array()->PackedFloat32Array:\n\t_sky63_add(\"array_construct\");return PackedFloat32Array()\nfunc _sky63_sample(stamp:float)->void:\n\t_sky63_add(\"sky_sample\");night_sky.sample(stamp)\n"
const SKY63_REPLACEMENTS=[["sky_material.set_shader_parameter(", "_sky63_submit("], ["Cycle.sample(", "_sky63_cycle("], ["Clouds.seed_offset(", "_sky63_seed("], ["PackedVector3Array()", "_sky63_vector_array()"], ["PackedFloat32Array()", "_sky63_float_array()"], ["night_sky.sample(", "_sky63_sample("]]
const SKY63_CANDIDATE_COUNTS={"sky_material.set_shader_parameter(": 25, "Cycle.sample(": 2, "Clouds.seed_offset(": 1, "PackedVector3Array()": 2, "PackedFloat32Array()": 3, "night_sky.sample(": 1, "night_sky.local_time()": 5}
const SKY63_REFERENCE_CLOCK_COUNT=5

func _prepare_scripts()->bool:
	const REFERENCE="res://tools/fixtures/night_sky63_reference_methods.gd.txt"
	if FileAccess.get_sha256(REFERENCE)!=SKY63_REFERENCE_SHA:
		check(false,"historical method oracle SHA unchanged");return false
	var source:=FileAccess.get_file_as_string("res://scripts/world3d/weather_controller.gd")
	Weather=_derive_script(source,counted,false)
	Oracle=_derive_script(FileAccess.get_file_as_string(REFERENCE),false,true)
	return Weather!=null and Oracle!=null

func _derive_script(source:String,with_counts:bool,is_reference:bool)->GDScript:
	# All edits are to a private in-memory GDScript string. No FileAccess WRITE,
	# production injection, persistent cache or global test API is involved.
	var expected_clock:int=SKY63_REFERENCE_CLOCK_COUNT if is_reference else int(SKY63_CANDIDATE_COUNTS["night_sky.local_time()"])
	if source.count("night_sky.local_time()")!=expected_clock:
		check(false,"exact deterministic clock replacement count");return null
	var line_end:=source.find("\n")
	source=source.insert(line_end+1,"var _sky63_now:float=100.0\n"+("var _sky63_count:Dictionary={}\n" if with_counts else ""))
	source=source.replace("night_sky.local_time()","_sky63_now")
	if with_counts:
		for pair:Array in SKY63_REPLACEMENTS:
			var from_:String=pair[0]
			if source.count(from_)!=int(SKY63_CANDIDATE_COUNTS[from_]):
				check(false,"exact actual-call counter replacement count "+from_);return null
			source=source.replace(from_,pair[1])
		source+=SKY63_COUNT_HELPERS
	var script:=GDScript.new();script.source_code=source
	var error:=script.reload()
	if error!=OK:check(false,"in-memory derived script compiles");return null
	return script

func remaining_contracts()->void:
	var pair:=pair_new()
	for rig:Node in pair:rig.editor_preview=true;rig.sky_poll=0.0
	tick(pair,101.0,"real editor preview authority")
	check(pair[0].night_sky.map_id=="editor-preview" and pair[0].night_sky.seed==7321,"editor preview creates and accepts real authority packet")
	for rig:Node in pair:rig.sky_poll=0.0
	tick(pair,102.0,"editor preview polls again")
	for rig:Node in pair:rig.editor_preview=false;rig.bind_sky("sky63",Callable())
	deliver(pair,packet(),103.0)
	check(pair[0].night_sky.map_id=="sky63" and pair[0].night_sky.seed==321,"preview to runtime restores real map clock and seed")
	close_pair(pair)
	pair=pair_new()
	var continuous:=packet([],5.9,360.0)
	continuous.environment.celestial_cycle=true;continuous.environment_revision=2
	deliver(pair,continuous,100.0)
	var before:float=pair[0].sky_material.get_shader_parameter("star_intensity")
	tick(pair,102.0,"continuous dawn changes night weight")
	var after:float=pair[0].sky_material.get_shader_parameter("star_intensity")
	check(before!=after and pair[0].values.celestial_cycle,"continuous celestial night factor reaches final star intensity")
	close_pair(pair)
	pair=pair_new()
	for rig:Node in pair:
		rig.set_meta("profile_frame",true);rig.set_meta("profile_sky_details",true)
		rig._tick_night_sky(0.0);rig._tick_night_sky(0.0)
	compare(pair,"profiled empty cache path")
	var snapshot:Dictionary=pair[0].sky_profile_snapshot()
	check(snapshot.calls.size()==2 and snapshot.dropped==0,"profiled empty path retains both call records")
	var complete:=true
	for call:Dictionary in snapshot.calls:
		complete=complete and call.begin_us>0 and call.star_uniform_end_us>0 and call.arrays_end_us>=call.star_uniform_end_us and call.meteor_uniform_end_us==call.arrays_end_us and call.return_end_us>=call.meteor_uniform_end_us
	check(complete,"empty fast path completes arrays/meteor/return profile stamps")
	close_pair(pair)

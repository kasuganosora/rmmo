extends "res://tools/review_guild_repaired.gd"
## Same final GLB: raw baseline versus derived LOD + production static batches.
## Only explicit derived LOD table differences are expected; native roundtrips
## in each inherited case still require complete exact semantics.
func runtime_identity()->Dictionary:
	var result:Dictionary={}
	for name:String in ["model_components.gd","runtime_mesh_cache.gd","ground_batcher.gd","model_lod_preparation.gd","wind_material.gd","gltf_map_io.gd","tinted_glass.gd","world_document.gd"]:
		result[name]=FileAccess.get_sha256("res://scripts/world3d/"+name)
	return result

func finish()->void:
	check(stable(report.get("runtime_implementation",{}))==stable(runtime_identity()),"optimization runtime implementation unchanged during verification")
	super.finish()

func without_derived_lod(value:Variant)->Variant:
	if value is Dictionary:
		var result:Dictionary={}
		for key in value:
			if key!="lods_sha256":result[key]=without_derived_lod(value[key])
		return result
	if value is Array:
		var result:Array=[]
		for item in value:result.append(without_derived_lod(item))
		return result
	return value

func compare_reports()->void:
	var a:=read_json(out.path_join("baseline.json"));var b:=read_json(out.path_join("candidate.json"))
	if not check(a.get("passed",false) and b.get("passed",false),"both native/GPU cases passed"):finish();return
	var source_sha:=FileAccess.get_sha256(source)
	check(source_sha==FileAccess.get_sha256(candidate),"optimization pair uses identical final authored source")
	check(a.get("original_sha")==source_sha and b.get("original_sha")==source_sha,"both reports bind current source SHA")
	check(a.get("generator")==Compiled.generator() and b.get("generator")==Compiled.generator(),"both cases bind current native generator")
	check(stable(a.get("runtime_implementation",{}))==stable(runtime_identity()) and stable(b.get("runtime_implementation",{}))==stable(runtime_identity()),"both cases bind current optimization runtime implementation")
	check(a.get("camera_views")==b.get("camera_views") and a.get("dimensions")==b.get("dimensions"),"same camera framing and dimensions")
	check(stable(without_derived_lod(a.semantic))==stable(without_derived_lod(b.semantic)),"all authored geometry/material pixels/extras equal excluding derived LOD index tables")
	check(b.get("batching",{}).get("groups",0)>0,"candidate actually used production static batches")
	report.source_sha256=source_sha;report.batching=b.get("batching",{});report.lod_derivation=b.get("lod_derivation",{})
	report.images=[]
	for shot:Dictionary in a.screenshots:
		var filename:String=shot.name
		var delta:=image_difference(out.path_join("baseline").path_join(filename),out.path_join("candidate").path_join(filename))
		delta.name=filename;report.images.append(delta);check(delta.get("valid",false),"paired optimization image "+filename)
	report.baseline_native=a.get("native",{});report.candidate_native=b.get("native",{})
	report.baseline_render=a.screenshots;report.candidate_render=b.screenshots
	report.visual_acceptance="pending manual same-camera review; image metrics alone do not accept visible LOD/batching loss"
	report.note="This pair tests existing optimization on the same final authored asset, not v2/v3 art changes. No RSS/VRAM or formal integration claim."
	finish()

func run()->void:
	if "--syntax-only" in OS.get_cmdline_user_args():print("GUILD_REFERENCE_OPTIMIZATION syntax only");quit();return
	report.runtime_implementation=runtime_identity()
	await super.run()

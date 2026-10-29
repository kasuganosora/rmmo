extends SceneTree
const Capability=preload("res://scripts/world3d/native_texture_capability.gd")
const Initial=preload("res://scripts/world3d/model_parse_preparation.gd")
const Deferred=preload("res://scripts/world3d/deferred_asset_loader.gd")
var failures:Array[String]=[]
var checks:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures.append(label)
func run()->void:
	var available:=ClassDB.class_has_method("StreamedTexture2D","is_streaming_active")
	check(Capability.error_for({"textures":1}).is_empty()==available,"native texture readiness requires the actual registration query")
	check(Capability.error_for({"textures":0}).is_empty(),"zero-texture native geometry does not require a texture API")
	check(Capability.error_for({"textures":1},true).is_empty(),"controlled CPU preparation keeps its explicit test channel")
	if not available:
		var prep:=Initial.new();prep.require_native_products=true
		var candidate:={"estimated_bytes":4096,"exclusive":false,"source_sha":"b".repeat(64),"texture_table":{"version":1,"sha256":"a".repeat(64),"bytes":1,"textures":1,"image_bytes":64}}
		prep.candidate_provider=func(_path:String)->Dictionary:return candidate
		prep.memory_estimator=func(_path:String)->Dictionary:return {"estimated_bytes":4096,"exclusive":false}
		var result:Dictionary=prep.run(["missing_capability.glb"],Callable(),2,Callable(),"user://private_native_capability")
		check(result.error!=OK and result.error_message==Capability.MISSING_REGISTRATION_QUERY,"initial production loading fails with the actionable engine capability error")
		check(result.threads_started==0,"initial capability failure starts no geometry, metadata or pixel work")
		preload("res://scripts/world3d/asset_worker_drainer.gd").dispose_result(result)
		var queue:=Deferred.new();root.add_child(queue)
		var plan:Dictionary=queue._native_model_plan("missing_capability.glb",candidate,"user://private_native_capability",self)
		check(plan.is_empty() and queue.error==Capability.MISSING_REGISTRATION_QUERY,"deferred production loading reports the same engine capability before metadata work")
		check(queue._native_plan_claims.is_empty() and queue._texture_plan_catalog.snapshot().pending_native_tables==0,"capability failure owns no metadata pin or pending worker")
		queue.free()
	print("NATIVE_TEXTURE_ENGINE_CAPABILITY ",JSON.stringify({"checks":checks,"failures":failures,"query_available":available}))
	quit(0 if failures.is_empty() else 1)

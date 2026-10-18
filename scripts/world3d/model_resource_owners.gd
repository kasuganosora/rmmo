extends RefCounted
## Exclusively owned transient model handoff. This is not a serialized asset
## format. Fields transfer together after the worker joins and renderer syncs.
## No borrowed author/index/record data belongs here.
var document:GLTFDocument
var state:GLTFState
var packed:PackedScene
var visuals:Array[Resource]=[]
func transfer_template(accepted:PackedScene)->void:
	# Called only after the cache accepted this exact template. Cancellation
	# before acceptance retains the template for full dependency retirement.
	if accepted!=null and packed==accepted:packed=null
func release_now()->void:
	# Shutdown/no SceneTree fallback; caller has already synchronized rendering.
	packed=null
	visuals.clear()
	state=null
	document=null

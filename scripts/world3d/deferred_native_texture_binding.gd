extends RefCounted
## Continuation borrows the already-admitted private packet. The token keeps
## that same packet alive for main-thread disposal if its queue disappears.
const Binding=preload("res://scripts/world3d/model_texture_bindings.gd")
static func prepare(result:Dictionary,plan:Dictionary,token:RefCounted)->Dictionary:
	var began:=Time.get_ticks_usec()
	if token.is_cancelled():result.error="Native texture binding cancelled";result.cancelled=true;return result
	var state:=Binding.begin_scene(result.get("scene"),plan["keys"],plan.table_sha)
	if not state.ok or not Binding.adopt(state,result.get("prefab_texture_packet",{}).get("uploaded_textures",{})):
		result.error=state.get("error","Native texture binding failed");Binding.release(state);return result
	while not token.is_cancelled():
		var status:=Binding.step(state)
		if status==Binding.READY:break
		if status==Binding.FAILED:result.error=state.get("error","Native texture binding failed");break
	if token.is_cancelled():result.error="Native texture binding cancelled";result.cancelled=true
	result.native_binding_profile={"elapsed_us":Time.get_ticks_usec()-began,"sets":int(state.sets),"unchanged":int(state.unchanged)}
	result.elapsed_us=int(result.get("elapsed_us",0))+int(result.native_binding_profile.elapsed_us)
	# The packet owns its actual scene/materials; its pixel packet and shared
	# pool own the textures. Clearing redundant binding aliases is not final
	# resource disposal, including when cancellation interrupts a partial bind.
	Binding.release(state)
	return result

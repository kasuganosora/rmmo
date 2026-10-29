extends SceneTree
## CPU contract: real scene/material graphs and controls, fake readiness/draw
## callbacks. This does not prove native registration or completed GPU frames.
const Observer=preload("res://scripts/world_editor/streamed_preview_observer.gd")
const Preview=preload("res://scripts/world_editor/asset_preview.gd")
const Thumbnails=preload("res://scripts/world_editor/asset_thumbnails.gd")
var checks:=0
var failures:=0

class Audit extends RefCounted:
	var reads:=0
	var images:=0
	var released:=0

class TextureProbe extends Texture2D:
	var mip:=3
	var reads:=0
	var audit:Audit
	var backing:=PlaceholderTexture2D.new()
	func _get_width()->int:return 4
	func _get_height()->int:return 4
	func _get_rid()->RID:return backing.get_rid()
	func _get_image()->Image:audit.images+=1;return null
	func get_streaming_mip_level()->int:reads+=1;audit.reads+=1;return mip
	func _notification(what:int)->void:
		if what==NOTIFICATION_PREDELETE and audit!=null:audit.released+=1

class ObserverProbe extends Observer:
	func _is_streamed(texture:Texture2D)->bool:return texture is TextureProbe

class Protocol extends RefCounted:
	var next_id:=0
	var ids:Dictionary={}
	var queries:Array=[]
	var draws:Array=[]
	var cancelled:Array=[]
	func begin_texture_observation(textures:Array[Texture2D])->int:
		next_id+=1;ids[next_id]=[]
		for texture:Texture2D in textures:ids[next_id].append(texture.get_instance_id())
		return next_id
	func query_texture_observation(id:int,callback:Callable)->void:
		queries.append({"id":id,"callback":callback,"ids":ids[id].duplicate()})
	func cancel_texture_observation(id:int)->void:cancelled.append(id);ids.erase(id)
	func after(callback:Callable)->void:draws.append(callback)
	func drawn()->void:
		var callback:Callable=draws.pop_front()
		if callback.is_valid():callback.call()
	func respond(ready:bool=true,version:int=2)->void:
		var query:Dictionary=queries.pop_front();var rows:Array=[]
		for id:int in query.ids:
			rows.append({"texture_id":id,"valid":true,"visible_demand":true,"status":"ready" if ready else "streaming","ready":ready,"request_mip":1,"desired_mip":1,"fit_mip":1,"current_mip":1 if ready else 3,"pending_mip":-1 if ready else 1,"executing":false,"stable":true,"decision_version":version,"reload_version":version,"budget_limited":false})
		query.callback.call({"observation_id":query.id,"target_generation":1,"completed_generation":1,"covered":true,"ready":ready,"textures":rows})

class ThumbnailProbe extends Thumbnails:
	var captures:=0
	func _finish(_serial:int)->void:
		captures+=1;_dispose_model();_busy=false

func check(ok:bool,label:String)->void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1

func _initialize()->void:run.call_deferred()

func make_texture(audit:Audit)->TextureProbe:
	var texture:=TextureProbe.new();texture.audit=audit;return texture

func material(texture:Texture2D)->StandardMaterial3D:
	var value:=StandardMaterial3D.new();value.albedo_texture=texture;return value

func fixture()->Dictionary:
	var audit:=Audit.new();var textures:Array=[]
	for i:int in 7:textures.append(make_texture(audit))
	var scene:=Node3D.new()
	var mesh:=ArrayMesh.new();var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.UP])
	for i:int in 2:mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	mesh.surface_set_material(0,material(textures[5]));mesh.surface_set_material(1,material(textures[1]))
	var atlas:=AtlasTexture.new();atlas.atlas=textures[2];atlas.region=Rect2(0,0,4,4)
	var override:=material(atlas);var overlay:=material(textures[3])
	var shader:=Shader.new()
	shader.code="shader_type spatial; uniform sampler2D sampled; uniform sampler2D fallback; uniform sampler2D alias; void fragment(){ALBEDO=texture(sampled,UV).rgb+texture(fallback,UV).rgb+texture(alias,UV).rgb;}"
	shader.set_default_texture_parameter("fallback",textures[4])
	var custom:=ShaderMaterial.new();custom.shader=shader
	custom.set_shader_parameter("sampled",textures[0]);custom.set_shader_parameter("alias",textures[2])
	custom.set_meta("unbound_texture",textures[6]);override.next_pass=custom;overlay.next_pass=custom
	var first:=MeshInstance3D.new();first.mesh=mesh;first.set_surface_override_material(0,override);scene.add_child(first)
	var second:=MeshInstance3D.new();second.mesh=mesh;second.material_override=override;second.material_overlay=overlay;scene.add_child(second)
	var multi:=MultiMeshInstance3D.new();multi.multimesh=MultiMesh.new();multi.multimesh.mesh=mesh
	multi.material_override=override;multi.material_overlay=overlay;scene.add_child(multi)
	return {"scene":scene,"textures":textures,"audit":audit,"uniform_count":RenderingServer.get_shader_parameter_list(shader.get_rid()).size()}

func collection_case()->void:
	var value:=fixture();var observer:=ObserverProbe.new()
	observer.capture(value.scene)
	check(value.uniform_count==3,"real shader reflection includes the default-texture uniform")
	check(observer.snapshot().textures==5,"active surface/override/overlay/next-pass/shader/default/atlas textures deduplicate")
	var live:Array[Texture2D]=observer.live_textures()
	check(not live.has(value.textures[5]) and not live.has(value.textures[6]),"overridden and metadata-only textures are excluded")
	live.clear()
	check(value.audit.reads==0 and value.audit.images==0,"collecting weak identities reads neither atomic mip nor image pixels")
	value.scene.free();value.erase("scene");value.textures.clear()
	check(value.audit.released==7,"observer weak descriptors keep no texture or material owner alive")
	check(observer.live_textures().is_empty(),"expired weak descriptors expose no stale owners")
	observer.clear();check(observer.snapshot().textures==0,"clear removes all weak descriptors")

func preview_case()->void:
	var preview:=Preview.new();root.add_child(preview)
	preview._streamed_observer=ObserverProbe.new()
	var protocol:=Protocol.new();preview._readiness.backend=protocol;preview._readiness.after_drawn=protocol.after
	var value:=fixture();preview.scene=value.scene;preview.current_path="fixture";preview.visible=true;preview._show_scene();preview.set_process(false)
	check(protocol.next_id==0,"showing a scene queues begin for normal processing")
	preview._process(0)
	check(preview.visible and preview.viewport_.render_target_update_mode==SubViewport.UPDATE_ONCE and protocol.draws.size()==1,"preview allows its first progressive draw after observation begins")
	protocol.drawn();preview._process(0);protocol.respond(false);preview._process(0)
	check(protocol.queries.size()==1 and preview.visible,"pending streaming keeps the progressive preview visible")
	protocol.respond();preview._process(0);protocol.drawn();preview._process(0);protocol.respond()
	check(not preview.is_processing() and not preview._readiness.active() and preview.visible,"verified redraw freezes the visible preview and stops processing")
	var draws:int=preview._readiness.profile.draws
	value.textures[2].mip=3;preview._process(0);value.textures[2].mip=2;preview._process(0)
	check(preview._readiness.profile.draws==draws and value.audit.reads==0,"idle mip downgrade and partial upgrade cannot restart a frozen preview")
	preview.hide();preview.show();preview._process(0);protocol.drawn();preview._process(0)
	preview.hide();protocol.respond()
	check(not preview.is_processing() and protocol.cancelled.has(2),"hidden preview cancels its ticket and ignores late query delivery")
	preview.show();preview._process(0)
	check(protocol.next_id==3,"showing again begins a fresh feedback observation")
	preview._process(0)
	check(preview._streamed_observer.profile.scene_scans==1,"showing a hidden preview reuses weak descriptors without scanning")
	preview.show_asset("")
	check(preview.scene==null and not preview.is_processing() and preview._streamed_observer.snapshot().textures==0,"selection cancellation clears the observer and private scene")
	value.textures.clear();value.erase("scene")
	var deadline:=Time.get_ticks_msec()+3000
	while value.audit.released<7 and Time.get_ticks_msec()<deadline:await process_frame
	check(value.audit.released==7,"cancelled preview observation pins neither geometry nor textures")
	var replacement:=fixture();preview.scene=replacement.scene;preview.visible=true;preview._show_scene()
	var observer:RefCounted=preview._streamed_observer;preview.free();replacement.textures.clear();replacement.erase("scene")
	while not protocol.draws.is_empty():protocol.drawn()
	deadline=Time.get_ticks_msec()+3000
	while replacement.audit.released<7 and Time.get_ticks_msec()<deadline:await process_frame
	check(observer.snapshot().textures==0 and replacement.audit.released==7,"exiting preview clears observers before final resource retirement")
	var failed:=Preview.new();root.add_child(failed);failed._streamed_observer=ObserverProbe.new();failed._readiness.backend=RefCounted.new()
	var unsupported:=fixture();failed.scene=unsupported.scene;failed.visible=true;failed._show_scene();failed._process(0)
	check(not failed.streaming_error.is_empty() and not failed.visible and not failed.is_processing(),"missing engine observation API explicitly fails the real preview")
	failed.free();unsupported.textures.clear();unsupported.erase("scene")

func thumbnail_case()->void:
	var thumbnails:=ThumbnailProbe.new();root.add_child(thumbnails);thumbnails.set_process(false)
	thumbnails._streamed_observer=ObserverProbe.new()
	var protocol:=Protocol.new();thumbnails._readiness.backend=protocol;thumbnails._readiness.after_drawn=protocol.after
	var value:=fixture();thumbnails._busy=true;thumbnails._present_model(value.scene,"fixture",true)
	process_frame.disconnect(thumbnails._render);thumbnails._render();thumbnails._process(0)
	protocol.drawn();thumbnails._process(0);protocol.respond();thumbnails._process(0)
	check(thumbnails.captures==0 and thumbnails._busy,"thumbnail does not capture the first progressive image or the first ready sample")
	protocol.drawn();thumbnails._process(0);protocol.respond(true,3)
	check(thumbnails.captures==0,"changed reload version after redraw prevents permanent low-mip capture")
	thumbnails._process(0);protocol.drawn();thumbnails._process(0);protocol.respond(true,3)
	check(thumbnails.captures==1 and not thumbnails._busy and thumbnails._streamed_observer.snapshot().textures==0,"thumbnail captures exactly once after matching completed-draw proof and clears weak descriptors")
	value.textures.clear();value.erase("scene")
	var cancelled:=fixture();thumbnails._busy=true;thumbnails._active_idle=true;thumbnails._present_model(cancelled.scene,"cancelled",true)
	process_frame.disconnect(thumbnails._render);thumbnails._render();thumbnails._process(0)
	thumbnails.set_visible_entries([]);protocol.drawn()
	check(thumbnails.captures==1 and not thumbnails._busy and protocol.cancelled.has(2),"scrolling cancels an idle observation without a late thumbnail capture")
	thumbnails.free();cancelled.textures.clear();cancelled.erase("scene")
	var deadline:=Time.get_ticks_msec()+3000
	while (value.audit.released<7 or cancelled.audit.released<7) and Time.get_ticks_msec()<deadline:await process_frame
	check(value.audit.released==7 and cancelled.audit.released==7,"thumbnail completion and cancellation retain no geometry or texture owners")

func run()->void:
	create_timer(15).timeout.connect(func():printerr("STREAMED_PREVIEW_OBSERVER watchdog");quit(2))
	await collection_case();await preview_case();await thumbnail_case()
	print("STREAMED_PREVIEW_OBSERVER checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)

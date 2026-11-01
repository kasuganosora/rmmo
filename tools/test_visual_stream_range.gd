extends SceneTree
const VisualRange=preload("res://scripts/world3d/visual_stream_range.gd")
const Stream=preload("res://scripts/world3d/world_stream.gd")
const Errors=preload("res://tools/test_prefab_texture_preparation.gd").Errors
var failures:=0
var checks:=0
class Queue extends Node:
	var visual_render_radius:=0
	var calls:=0
	func set_view_direction(_direction:Vector3)->void:pass
	func prioritize(_position:Vector3)->void:calls+=1

func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)

func run()->void:
	var logger:=Errors.new();OS.add_logger(logger)
	for aspect:float in [1.0,16.0/9.0,32.0/9.0]:
		var far:=4000.0
		var projection:=Projection.create_perspective(55,aspect,.05,far)
		var expected:=sqrt(far*far+pow(far*tan(deg_to_rad(27.5)),2)*(1+aspect*aspect))
		var radius:=VisualRange.projection_radius(projection)
		check(radius*Stream.CHUNK_M>=expected+12.,"all far-plane corners and camera arm covered at aspect "+str(aspect))
		check(radius*Stream.CHUNK_M<=expected+96.,"projection envelope stays within rounding/precision margin")
	var offset:=Projection.create_frustum(-.2,.4,-.1,.3,.1,4000.)
	check(VisualRange.projection_radius(offset)*Stream.CHUNK_M>=sqrt(4000.*4000.+16000.*16000.+12000.*12000.)+12.,"asymmetric lens covers its farthest corner")
	var orthogonal:=Projection.create_orthogonal(-400,400,-200,200,.1,1000.)
	check(VisualRange.projection_radius(orthogonal)*Stream.CHUNK_M>=sqrt(1000.*1000.+400.*400.+200.*200.)+12.,"orthogonal projection also covers all corners")
	check(VisualRange.projection_radius(Projection.create_perspective(55,1.,10.,200000.))*Stream.CHUNK_M>200000.,"small valid homogeneous coordinates do not become a hidden distance cap")
	check(VisualRange.projection_radius(Projection(Vector4.ZERO,Vector4.ZERO,Vector4.ZERO,Vector4.ZERO))==-1,"invalid projection is explicit rather than a one-cell fallback")
	var viewport:=SubViewport.new();viewport.size=Vector2i(1280,720);root.add_child(viewport)
	var camera:=Camera3D.new();camera.far=4000.;camera.fov=55.;viewport.add_child(camera)
	var map_root:=Node3D.new();viewport.add_child(map_root)
	var queue:=Queue.new();queue.name="DeferredAssets";map_root.add_child(queue)
	check(VisualRange.sync(map_root,camera,Vector3.ZERO),"first projection installs visual range")
	var first_radius:=Stream.render_radius(map_root);var first_calls:=queue.calls
	check(queue.visual_render_radius==first_radius,"request and publication share one computed range")
	camera.rotation.y=PI*.5
	check(not VisualRange.sync(map_root,camera,Vector3.ZERO) and queue.calls==first_calls,"turning preserves coverage without rebuilding membership")
	viewport.size=Vector2i(2560,720)
	VisualRange.sync(map_root,camera,Vector3.ZERO)
	check(Stream.render_radius(map_root)>first_radius and queue.calls==first_calls+1,"wider viewport expands demand and publication together")
	camera.far=1500.
	VisualRange.sync(map_root,camera,Vector3.ZERO)
	check(Stream.render_radius(map_root)<first_radius and queue.visual_render_radius==Stream.render_radius(map_root),"actual shorter far plane updates both consumers")
	check(camera.far==1500.,"coverage does not change camera settings")
	viewport.free()
	check(logger.errors.is_empty(),"zero engine or script errors")
	OS.remove_logger(logger)
	print("VISUAL_STREAM_RANGE checks=",checks," failures=",failures)
	quit(1 if failures else 0)

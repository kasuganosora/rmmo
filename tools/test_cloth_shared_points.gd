extends SceneTree
const Body=preload("res://scripts/char/female_axis_body.gd")
var captured:=PackedByteArray()
func capture(packet:RefCounted)->void:captured=packet.rd.buffer_get_data(packet.output_buffer)
func read_packet(packet:RefCounted)->PackedByteArray:
 RenderingServer.call_on_render_thread(capture.bind(packet));RenderingServer.force_sync();return captured.duplicate()
func _initialize()->void:call_deferred("run")
func run()->void:
 create_timer(120).timeout.connect(func():push_error("Shared points timeout");quit(2))
 Body.default_gpu_display=false
 var body=Body.new();root.add_child(body);body.initialize();assert(body.enable_compute());body.set_angles({})
 for i in 2:await process_frame
 var source=preload("res://scripts/char/female_axis_display.gd").new()
 assert(source.initialize(preload("res://scripts/asset/art_paths.gd").path("characters/base/female_base_v2")))
 var points:PackedVector3Array=body.posed_points
 source.update(points,Vector3.ZERO)
 var indices:=PackedInt32Array()
 for face:Array in body.topology.base_faces:
  var a:int=face[0];var b:int=face[1];var c:int=face[2]
  if (points[b]-points[a]).cross(points[c]-points[a]).length_squared()>1e-16:indices=PackedInt32Array([a,b,c]);break
 assert(indices.size()==3)
 var packet=preload("res://addons/godot_gpu_cloth/src/cloth_resident_packet.gd").new()
 var reference=preload("res://addons/godot_gpu_cloth/src/cloth_indexed_packet.gd").new()
 assert(packet.initialize(indices,points.size(),0));assert(reference.initialize(indices,points.size(),0));packet.set_point_source(source)
 var extras:=PackedVector3Array();var offset:=Vector3(.2,-.13,.7)
 assert(packet.build(points,offset,extras));assert(reference.build(points,offset,extras))
 assert(read_packet(packet)==reference.output);assert(packet.point_upload_bytes==0 and packet.shared_point_read_bytes==points.size()*12)
 # Mutating the exact array passed to update must not change the upload snapshot.
 var mutable:=points.duplicate();source.update(mutable,Vector3.ZERO)
 mutable[indices[0]]+=Vector3(.001,0,0)
 assert(not source.shared_points_buffer(mutable).is_valid(),"Caller mutation changed the submitted snapshot")
 # A changed CPU snapshot must not consume a previously submitted GPU pose.
 var next:=points.duplicate();next[indices[0]]+=Vector3(.01,.02,0)
 assert(packet.build(next,offset,extras));assert(reference.build(next,offset,extras));assert(read_packet(packet)==reference.output)
 assert(packet.point_upload_bytes==points.size()*12)
 var accepted:=read_packet(packet);var bad:=next.duplicate();bad[indices[0]]=Vector3(NAN,0,0)
 assert(not packet.build(bad,offset,extras));assert(read_packet(packet)==accepted)
 # Queue expansion then release source before the render thread drains the queue.
 source.update(next,Vector3.ZERO)
 assert(packet.build(next,offset,extras));source.close()
 assert(read_packet(packet)==reference.output)
 assert(packet.shared_point_read_bytes==points.size()*24)
 # Closed provider must fall back, without touching its stale RIDs.
 assert(packet.build(points,offset,extras));assert(reference.build(points,offset,extras));assert(read_packet(packet)==reference.output)
 assert(packet.point_upload_bytes==points.size()*24)
 var replacement=preload("res://scripts/char/female_axis_display.gd").new()
 assert(replacement.initialize(preload("res://scripts/asset/art_paths.gd").path("characters/base/female_base_v2")))
 replacement.update(points,Vector3.ZERO);packet.set_point_source(replacement)
 assert(packet.build(points,offset,extras));assert(read_packet(packet)==reference.output)
 assert(packet.shared_point_read_bytes==points.size()*36)
 packet.close();replacement.close();reference.close();body.queue_free()
 for i in 4:await process_frame
 print("PASS shared body points exact, stale fallback, invalid atomic rejection, queued source release, closed fallback, replacement binding");quit()

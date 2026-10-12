extends SceneTree
## CPU-only: prove the frame-boundary deletion race and the production retire contract.
const Cover=preload("res://scripts/world3d/transfer_loading.gd")
var failures:=0

func _initialize()->void:call_deferred("run")

func check(value:bool,label_:String)->void:
	print(("PASS " if value else "FAIL ")+label_)
	if not value:failures+=1

func run()->void:
	var host:=Node.new();root.add_child(host)
	var legacy:=Cover.new();host.add_child(legacy)
	legacy.queue_free()
	check(host.get_node_or_null("TransferLoading")==legacy and legacy.is_inside_tree() and legacy.is_queued_for_deletion(),"queue_free leaves a named live cover until frame deletion flush")
	check(legacy.visible and legacy.is_processing_input(),"queued live cover retains visibility and input callback")
	await process_frame
	await process_frame
	check(not is_instance_valid(legacy),"queued legacy cover is actually released after frame flush")
	var cover:=Cover.new();host.add_child(cover)
	await cover.finish()
	cover.retire()
	check(host.get_node_or_null("TransferLoading")==null and not cover.is_inside_tree(),"retire removes cover from the transaction tree before returning")
	check(not cover.visible and not cover.is_processing_input() and not cover.is_processing(),"retire disables visibility, input and updates immediately")
	check(cover.is_queued_for_deletion(),"detached cover retains scheduled ownership cleanup")
	var next:=Cover.new();host.add_child(next)
	check(host.get_node_or_null("TransferLoading")==next,"same-frame next transfer obtains its own unambiguous cover")
	cover.retire()
	check(host.get_node_or_null("TransferLoading")==next,"idempotent old-cover retirement cannot detach the next cover")
	next.retire()
	await process_frame
	await process_frame
	check(not is_instance_valid(cover) and not is_instance_valid(next),"retired covers are freed at the following frame flush")
	host.free()
	print("TRANSFER_COVER_LIFECYCLE_FINISHED failures=",failures)
	quit(0 if failures==0 else 1)

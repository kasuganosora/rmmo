extends "res://tools/profile_axel_predictive_official.gd"
## Diagnostic capture only: retain object-free scheduling inputs, never meshes,
## prepared outputs or leases. Capture work is not a production timing result.
var demand_snapshot_saved:=false
func source_snapshot(folder:String="res://scripts")->Dictionary:
	var result:=super.source_snapshot(folder)
	if folder=="res://scripts":result["res://tools/profile_axel_demand_snapshot.gd"]=FileAccess.get_sha256("res://tools/profile_axel_demand_snapshot.gd")
	return result
func tick_geometry()->void:
	var queue:Node=mesh_map.get_node("DeferredAssets")
	if not demand_snapshot_saved and phase=="white_native_return" and queue._demanded.size()>=700:
		var destination:=""
		for argument:String in OS.get_cmdline_user_args():
			if argument.begins_with("--demand-snapshot="):destination=argument.trim_prefix("--demand-snapshot=")
		if not destination.is_empty():_capture_demands(queue,destination)
		demand_snapshot_saved=true
	super.tick_geometry()
func _capture_demands(queue:Node,destination:String)->void:
	var started:=Time.get_ticks_usec();var rows:Array=[]
	for item:Dictionary in queue.pending:
		rows.append({"record":{"uuid":item.record.uuid},"path":item.path,"bounds":item.bounds,"group_id":item.get("group_id",""),"reference_entry":{"reason":item.get("reference_entry",{}).get("reason","")},"published":item.get("published",false)})
	var packet:Dictionary={"map_sha":report.map_sha,"phase":phase,"priority":queue._priority,"pending":rows,"demands":queue._demands,"scope":queue._demand_scope,"buildings":queue._runtime_building_records,"supports":queue._runtime_building_supports,"instance_errors":queue.instance_errors,"path_errors":queue.path_errors,"demanded":queue._demanded.size(),"reference_index_present":not queue._reference_index.is_empty()}
	var file:=FileAccess.open(destination,FileAccess.WRITE)
	if file==null:check(false,"diagnostic scheduling snapshot can be written");return
	file.store_buffer(var_to_bytes(packet));file.close()
	report.demand_snapshot={"path":destination,"sha256":FileAccess.get_sha256(destination),"pending":rows.size(),"demanded":queue._demanded.size(),"capture_us":Time.get_ticks_usec()-started,"scope":"Diagnostic-only CPU scheduler inputs; capture frame excluded from production performance claims"}
	print("DEMAND_SNAPSHOT ",JSON.stringify(report.demand_snapshot))

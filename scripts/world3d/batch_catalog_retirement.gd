extends RefCounted
## GroundBatcher's exact cache layers. Keep final owners through clear(), then
## release them in bounded MAIN slices. Do not mutate borrowed dictionaries.
static func owners(batcher:Node)->Array:
	# _prepare_node registers each descriptor here before either preparation
	# table borrows it; source invalidation also removes/invalidates those tables.
	# Snapshot this registry once, not each prepared-descriptor alias again.
	var leaves:Array=batcher._residency_descriptors.values()
	var roots:Array=[];var groups:Array=[];var seen_tables:Array=[]
	for state:Dictionary in [batcher._preparation,batcher._residency_bins,batcher._next_residency]:
		for field:String in ["desired","raw_desired"]:
			if not state.has(field):continue
			var table:Dictionary=state[field];var seen:=false
			for previous:Dictionary in seen_tables:
				if is_same(previous,table):seen=true;break
			if seen:continue
			seen_tables.append(table);groups.append_array(table.values())
		roots.append_array(state.values())
	# ResourceRetirement pops from the back: outer tables, raw groups, then
	# individual descriptors/WeakRefs. Never let one table drop all final leaves.
	leaves.append_array(groups);leaves.append_array(roots)
	return leaves

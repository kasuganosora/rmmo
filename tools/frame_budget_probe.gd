extends RefCounted
## Read-only diagnostic counters. No queue, resources or budget mutation.
const FIELDS:=["elapsed_us","publication_us","publication_units","frames"]
const EXTRA_COLUMNS:=["budget_last_mode","budget_sample_baseline","budget_counter_reset",
	"covered_deferred_service_us","covered_publication_us","covered_publication_units",
	"interactive_deferred_service_us","interactive_publication_us","interactive_publication_units",
	"covered_deferred_service_cumulative_us","covered_publication_cumulative_us","covered_publication_cumulative_units",
	"interactive_deferred_service_cumulative_us","interactive_publication_cumulative_us","interactive_publication_cumulative_units"]
const CONTRACT:="v2: original service/publication columns are deltas summed across all recorded budget modes; per-mode delta and cumulative columns distinguish covered_loading from interactive. First observation is a baseline, not this frame's work. budget_last_mode is the queue's last serviced mode, not a claim that the interval used only that mode. A decreasing counter marks a reset and invalidates that mode's interval delta (zero); cumulative values remain raw. Publication is contained in service wall time, not additive CPU time. Engine/render timings may describe the previous frame."
var previous:Dictionary={}
var initialized:=false

static func snapshot(profile:Dictionary)->Dictionary:
	var modes:Dictionary=profile.get("main_thread_budgets",{})
	var totals:Dictionary={};var by_mode:Dictionary={}
	for field:String in FIELDS:totals[field]=0
	# Counters retain both modes after transitions. Never subtract the current
	# mode from a previous different mode, or discard work done under cover.
	for mode:String in modes:
		var counters:Dictionary=modes.get(mode,{})
		var values:Dictionary={}
		for field:String in FIELDS:
			values[field]=int(counters.get(field,0));totals[field]+=values[field]
		by_mode[mode]=values
	return {"last_mode":str(profile.get("main_thread_budget_mode","unobserved")),"totals":totals,"by_mode":by_mode}

func sample(profile:Dictionary)->Dictionary:
	var current:=snapshot(profile);var delta:Dictionary={};var by_mode:Dictionary={};var reset:=false
	for field:String in FIELDS:delta[field]=0
	for mode:String in previous:
		if not current.by_mode.has(mode):reset=true
	for mode:String in current.by_mode:
		var values:Dictionary=current.by_mode[mode];var old:Dictionary=previous.get(mode,{})
		var mode_reset:=false
		for field:String in FIELDS:
			if initialized and int(values[field])<int(old.get(field,0)):mode_reset=true
		var change:Dictionary={}
		for field:String in FIELDS:
			change[field]=int(values[field])-int(old.get(field,0)) if initialized and not mode_reset else 0
			delta[field]+=change[field]
		by_mode[mode]=change;reset=reset or mode_reset
	var result:={"last_mode":current.last_mode,"baseline":not initialized,"counter_reset":reset,"delta":delta,"by_mode_delta":by_mode,"cumulative":current.totals,"by_mode_cumulative":current.by_mode}
	previous=current.by_mode;initialized=true
	return result

static func extra_values(observation:Dictionary)->Array:
	var values:Array=[observation.last_mode,observation.baseline,observation.counter_reset]
	for kind:String in ["by_mode_delta","by_mode_cumulative"]:
		for mode:String in ["covered_loading","interactive"]:
			var counters:Dictionary=observation[kind].get(mode,{})
			for field:String in ["elapsed_us","publication_us","publication_units"]:values.append(int(counters.get(field,0)))
	return values

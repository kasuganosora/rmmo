extends "res://tools/test_deferred_loading_budget.gd"
func run()->void:
	var trials:Array=[]
	for mode:bool in [false,true,true,false]:
		Deferred.phase_budget_guard_enabled=mode
		for count:int in [6,2048]:
			var f:=fixture(count);var service:Probe=f.service
			service.set_demand("transfer:7",AABB(Vector3(-1,-1,-1),Vector3(count+2,3,3)));service.set_process(false)
			service.acceptance_delay_usec=3000;f.document.delay_usec=4000
			if count>6:service._demand_revision+=1
			var began:=Time.get_ticks_usec();service._process(0);var elapsed:=Time.get_ticks_usec()-began
			var metrics:Dictionary=service.profile.main_thread_budgets.interactive
			trials.append({"guard":mode,"records":count,"elapsed_us":elapsed,"bookkeeping_us":service.profile.frame_bookkeeping_us,"acceptance_units":metrics.acceptance_units,"publication_units":metrics.publication_units,"instance_calls":f.document.calls.size()})
			check(metrics.publication_units==0 if mode else metrics.publication_units==1,"phase guard defers an exhausted publication without skipping baseline work")
			if mode and count>6:check(metrics.acceptance_units==0,"large demand scan cannot stack acceptance after exhausting the frame")
			check(service._admission.reserved_bytes==32,"overrun retains the completed job reservation")
			service.acceptance_delay_usec=0;f.document.delay_usec=0
			var steps:=0
			while not service.is_complete() and steps<1000:
				service._process(0);steps+=1
			check(service.is_complete() and f.document.calls.size()==count and service._admission.reserved_bytes==0,"fresh budgets finish every instance exactly once without starvation")
			f.host.free()
	Deferred.phase_budget_guard_enabled=true
	print("DEFERRED_PHASE_BUDGET ",JSON.stringify({"trials":trials,"failures":failures}))
	quit(1 if failures else 0)

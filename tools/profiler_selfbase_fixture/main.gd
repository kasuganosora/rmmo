extends SceneTree
## Draft fixture; run headless with the official remote profiler after coordination.
const Base=preload("res://base.gd")
const Leaf=preload("res://leaf.gd")
var rows:Array=[]
var failures:Array=[]
var loops:int=60000
var repeats:int=8
func _initialize()->void:
    call_deferred("run")
func record(label:String,started:int,result:Variant)->void:
    rows.append({"phase":label,"engine_frame":Engine.get_process_frames(),"wall_us":Time.get_ticks_usec()-started,"result":result})
func run()->void:
    var base:=Base.new()
    var leaf:=Leaf.new()
    leaf.native_work.connect(leaf._on_native_work)
    print("SELFBASE_FIXTURE_BEGIN")
    # The external receiver enables profiling on the marker above.
    await create_timer(1.).timeout
    for mode:String in ["direct_script","two_super_levels","direct_native_signal","super_native_signal","builtin_signal"]:
        print("SELFBASE_PHASE ",mode)
        for iteration:int in repeats:
            await process_frame
            var started:=Time.get_ticks_usec()
            match mode:
                "direct_script":
                    record(mode,started,base.inherited_work(loops))
                "two_super_levels":
                    record(mode,started,leaf.inherited_work(loops))
                "direct_native_signal":
                    var error:int=leaf.native_direct_emit(loops)
                    if error!=OK:failures.append({"mode":mode,"error":error})
                    record(mode,started,leaf.sink)
                "super_native_signal":
                    var error:int=leaf.native_selfbase_emit(loops)
                    if error!=OK:failures.append({"mode":mode,"error":error})
                    record(mode,started,leaf.sink)
                "builtin_signal":
                    leaf.builtin_signal_emit(loops)
                    record(mode,started,leaf.sink)
    if leaf.native_selfbase_id()!=leaf.get_instance_id():failures.append("native_selfbase_id")
    if leaf.inherited_work(loops)!=base.inherited_work(loops)+2:failures.append("inheritance_return")
    await process_frame
    await process_frame
    print("SELFBASE_FIXTURE_RESULT ",JSON.stringify({"rows":rows,"failures":failures}))
    print("SELFBASE_FIXTURE_DONE")
    await create_timer(.5).timeout
    quit(0 if failures.is_empty() else 1)

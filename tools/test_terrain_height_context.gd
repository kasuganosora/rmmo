extends SceneTree
## CPU-only fixed-work test for height context lookup. GPU publication remains
## covered separately on a private Windows desktop.
const River=preload("res://scripts/world3d/river_materials.gd")
var checks:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures+=1;printerr("FAIL ",label)
static func legacy_height_image(record:Dictionary,context:Dictionary)->Image:
	var terrain:Dictionary=record.terrain_mesh
	var heights:=PackedFloat32Array()
	for height in terrain.heights:heights.append(float(height)*record.size[1])
	return context.get("image",Image.create_from_data(int(terrain.columns)+1,int(terrain.rows)+1,false,Image.FORMAT_RF,heights.to_byte_array()))
func gpu_semantics(record:Dictionary,prepared:Image)->void:
	check(DisplayServer.get_name()!="headless" and RenderingServer.get_rendering_device()!=null,"GPU test uses a real private renderer")
	var definition:Dictionary={"name":"fixture","color":[1.,1.,1.,1.],"roughness":.7}
	var terrain:Dictionary=record.duplicate(true)
	terrain.terrain_slope_blend={"transition_width":1.,"transition_material":definition}
	for kind:String in ["prepared","geometry_only","empty"]:
		River.cache.clear()
		var context:Dictionary={}
		if kind=="prepared":context={"image":prepared,"signature":["prepared"],"padding":Vector2(1,2)}
		elif kind=="geometry_only":context={"signature":["geometry"],"normals":{},"padding":Vector2(2,3),"neighbors":[]}
		River.terrain_height_context_hits=0;River.terrain_height_fallback_generations=0
		var material:ShaderMaterial=River.terrain(terrain,context)
		var image:Image=material.get_meta("terrain_height_image")
		var texture:Texture2D=material.get_shader_parameter("terrain_heights")
		check(material.get_shader_parameter("terrain_padding")==context.get("padding",Vector2.ZERO),kind+" shader padding is preserved")
		check(texture!=null and image!=null,kind+" publishes image and texture")
		if image==null or texture==null:continue
		check((image==prepared) if kind=="prepared" else (image.get_width()==3 and image.get_height()==3),kind+" keeps selected image identity/dimensions")
		check(River.terrain_height_context_hits==int(kind=="prepared") and River.terrain_height_fallback_generations==int(kind!="prepared"),kind+" produces exactly the expected image work")
		RenderingServer.force_sync()
		var pixels:Image=texture.get_image()
		check(pixels!=null and pixels.get_format()==image.get_format() and pixels.get_width()==image.get_width() and pixels.get_height()==image.get_height() and pixels.get_data()==image.get_data(),kind+" GPU image pixels match selected owner")
		var again:ShaderMaterial=River.terrain(terrain,context)
		check(again==material and River.terrain_height_fallback_generations==int(kind!="prepared"),kind+" material cache hit does not repeat work")
	River.cache.clear()
func run()->void:
	var record:Dictionary={"terrain_mesh":{"columns":2,"rows":2,"heights":[0.,.1,.2,.3,.4,.5,.6,.7,.8]},"size":[3.,10.,4.]}
	River.terrain_height_profile_enabled=true
	for context:Dictionary in [{},{"normals":{},"neighbors":[],"signature":[],"padding":Vector2(2,3)}]:
		River.terrain_height_fallback_generations=0;River.terrain_height_context_hits=0
		var fallback:Image=River._terrain_height_image(record,context)
		var legacy:Image=legacy_height_image(record,context)
		check(fallback!=null and fallback.get_width()==3 and fallback.get_height()==3 and fallback.get_format()==Image.FORMAT_RF,"missing image creates expected RF dimensions")
		check(fallback.get_data()==legacy.get_data(),"fallback bytes match legacy implementation")
		for i:int in 9:check(absf(fallback.get_pixel(i%3,i/3).r-float(i))<.00001,"fallback height sample %d"%i)
		check(River.terrain_height_fallback_generations==1 and River.terrain_height_context_hits==0,"empty/geometry-only context creates exactly one fallback")
	var prepared:=Image.create_empty(5,7,false,Image.FORMAT_RF)
	prepared.fill(Color(7.,0.,0.))
	var signature:Array=["fixture"]
	var context:Dictionary={"image":prepared,"signature":signature,"padding":Vector2(1,2)}
	River.terrain_height_fallback_generations=0;River.terrain_height_context_hits=0
	var selected:Image=River._terrain_height_image(record,context)
	check(selected==prepared and selected.get_width()==5 and selected.get_height()==7,"prepared image identity, format and padded size are preserved")
	check(context.signature==signature and context.padding==Vector2(1,2),"input context is not mutated")
	check(River.terrain_height_fallback_generations==0 and River.terrain_height_context_hits==1,"prepared image does not construct an unused fallback")
	River.terrain_height_fallback_generations=0;River.terrain_height_context_hits=0
	var explicit_null:Image=River._terrain_height_image(record,{"image":null})
	check(explicit_null==null,"explicit null is preserved instead of synthesizing a fallback")
	check(River.terrain_height_fallback_generations==0 and River.terrain_height_context_hits==1,"explicit null does not construct an unused fallback")
	# Fixed work deliberately measures only CPU image selection/construction.
	# It does not represent terrain GPU publication or whole-map performance.
	var heights:Array=[]
	for i:int in 129*129:heights.append(float(i%101)/100.)
	var large:Dictionary={"terrain_mesh":{"columns":128,"rows":128,"heights":heights},"size":[128.,5.,128.]}
	var large_image:=Image.create_empty(131,131,false,Image.FORMAT_RF)
	var cached:Dictionary={"image":large_image}
	var samples:Array=[]
	for optimized:bool in [false,true,true,false]:
		River.lazy_terrain_height_enabled=optimized
		River.terrain_height_context_hits=0;River.terrain_height_fallback_generations=0
		var began:=Time.get_ticks_usec();var owners_match:=true
		for i:int in 40:
			var result:Image=River._terrain_height_image(large,cached)
			owners_match=owners_match and result==large_image
		var elapsed:=Time.get_ticks_usec()-began
		check(owners_match,"benchmark preserves prepared owner")
		if optimized:check(River.terrain_height_fallback_generations==0 and River.terrain_height_context_hits==40,"prepared fixed work skips every fallback")
		else:check(River.terrain_height_fallback_generations==40 and River.terrain_height_context_hits==40,"legacy control constructs every fallback")
		samples.append({"optimized":optimized,"iterations":40,"heights_per_fallback":heights.size(),"elapsed_us":elapsed,"context_hits":River.terrain_height_context_hits,"fallback_generations":River.terrain_height_fallback_generations})
	print("TERRAIN_HEIGHT_CONTEXT_BENCH ",JSON.stringify(samples))
	River.lazy_terrain_height_enabled=true
	if "--gpu" in OS.get_cmdline_user_args():gpu_semantics(record,prepared)
	River.terrain_height_profile_enabled=false
	print("TERRAIN_HEIGHT_CONTEXT checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)

extends SceneTree
## CPU contract/parse by default. --gpu verifies real tiny GPU owners on the
## private desktop; no map, image files, authored resources or scene are loaded.
const House=preload("res://scripts/world3d/house_prefab.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const PATH="ticket-fixture/albedo.png"
const NORMAL="ticket-fixture/normal.png"
const SHA_A="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
const SHA_B="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
var passed:=0
var failed:=0
class Errors extends Logger:
	var errors:Array[String]=[]
	func _log_error(function:String,_file:String,_line:int,code:String,rationale:String,_editor_notify:bool,_type:int,_backtraces:Array)->void:
		errors.append(function+": "+code+" "+rationale)

func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if ok:passed+=1
	else:failed+=1
func texture(digest:Variant,color:Color)->ImageTexture:
	var image:=Image.create(4,4,false,Image.FORMAT_RGBA8);image.fill(color)
	var result:=ImageTexture.create_from_image(image);result.set_meta("runtime_source_sha256",digest)
	return result
func material(owner:Texture2D,path:String=PATH,normal:bool=false,flip:bool=false)->StandardMaterial3D:
	var result:=StandardMaterial3D.new()
	var definition:Dictionary={"normal_path" if normal else "texture_path":path}
	if normal:definition.normal_format="directx" if flip else "opengl";result.normal_texture=owner
	else:result.albedo_texture=owner
	result.set_meta("runtime_paint_definition",definition)
	return result
func mesh(owner:Material)->Mesh:
	var result:=Cpu.new();result.materials.append(owner);return result

func run()->void:
	var logger:=Errors.new();OS.add_logger(logger)
	check(House._texture_digest_valid(SHA_A) and not House._texture_digest_valid("z".repeat(64)) and not House._texture_digest_valid("a".repeat(63)) and not House._texture_digest_valid(123),"only complete canonical SHA strings can identify a resident ticket")
	check(House.texture_tickets({}).is_empty() and House._texture_ticket(null).is_empty(),"empty source scope and missing owner produce no tickets")
	if "--gpu" in OS.get_cmdline_user_args():
		check(DisplayServer.get_name()!="headless","GPU cases require the private renderer")
		if DisplayServer.get_name()!="headless":gpu_cases()
	else:print("GPU owner cases not run; use --gpu through the background launcher")
	OS.remove_logger(logger);check(logger.errors.is_empty(),"zero script/engine errors")
	print("HOUSE_TEXTURE_TICKETS passed=",passed," failures=",failed)
	quit(1 if failed else 0)

func gpu_cases()->void:
	var before:Dictionary={"textures":Paint._textures,"materials":Paint._materials,"prepared":Paint.prepared_images,"meshes":House._meshes,"renders":House._render_meshes}
	Paint._textures={};Paint._materials={};Paint.prepared_images={};House._meshes={};House._render_meshes={}
	var sources:Dictionary={PATH:[PATH,false,false]}
	var a:=texture(SHA_A,Color.RED);var b:=texture(SHA_B,Color.BLUE)
	var owner_a:=material(a);var owner_b:=material(b)
	var pool:Dictionary={"schema":{"albedo_texture":TYPE_OBJECT},"a":owner_a,"again":owner_a}
	var sentinel:=Image.create(1,1,false,Image.FORMAT_RGBA8);Paint.prepared_images[PATH]=sentinel
	var tickets:=House.texture_tickets(sources,pool)
	check(tickets.size()==1 and tickets[PATH].texture==a and tickets[PATH].source_sha==SHA_A and a.get_rid().is_valid(),"load material pool alone retains a consumable GPU owner, deduplicated by key")
	check(Paint._textures.is_empty() and Paint._materials.is_empty() and Paint.prepared_images.get(PATH)==sentinel and pool.size()==3,"ticket lookup does not upload, install, invalidate or consume prepared pixels")
	# End the sentinel scope before checking ordinary owner precedence. A
	# prepared Image without source identity must not authorize a cached texture.
	Paint.prepared_images={}
	Paint._materials["global"]=owner_b
	check(House.texture_tickets(sources,pool)[PATH].texture==a,"current caller pool precedes a duplicate global material key")
	check(House.texture_tickets(sources)[PATH].texture==b,"global material alone supplies the key after texture LRU eviction")
	Paint._textures[PATH]=b
	check(House.texture_tickets(sources,pool)[PATH].texture==b,"current texture table remains the first owner for duplicate keys")
	Paint._textures.clear();Paint._materials.clear()
	var render:=mesh(owner_a);House._render_meshes["render"]=render
	check(House.texture_tickets(sources)[PATH].texture==a and House._meshes.is_empty(),"render mesh cache alone supplies pixels after prefab entry eviction")
	var prefab:=mesh(owner_b);House._meshes["prefab"]={"mesh":prefab,"source":prefab}
	check(House.texture_tickets(sources)[PATH].texture==b,"prefab material owner precedes duplicate render cache key")
	House._meshes.clear();House._render_meshes.clear()
	var flipped:=material(a,NORMAL,true,true);var regular:=material(b,NORMAL,true,false)
	var oriented:Dictionary={NORMAL+"|normal":[NORMAL,false,true],NORMAL+"|normal|flip_y":[NORMAL,true,true]}
	var variants:=House.texture_tickets(oriented,{"flip":flipped,"plain":regular,"unrelated":owner_a})
	check(variants.size()==2 and variants[NORMAL+"|normal"].texture==b and variants[NORMAL+"|normal|flip_y"].texture==a and not variants.has(PATH),"path and normal orientation remain distinct and unrelated material keys are excluded")
	var invalid:=texture("z".repeat(64),Color.WHITE);Paint._textures[PATH]=invalid
	check(House.texture_tickets(sources).is_empty(),"64 non-hex metadata characters cannot become a ticket")
	check(House.texture_tickets(sources,pool)[PATH].texture==a,"invalid texture metadata does not hide a valid material owner")
	Paint._textures.clear()
	tickets=House.texture_tickets(sources,pool)
	check(House.tickets_valid(tickets,{PATH:SHA_A}),"valid GPU owner still requires matching verified source proof")
	check(not House.tickets_valid(tickets,{PATH:SHA_B}),"changed source proof invalidates a retained old material ticket")
	Paint._textures[PATH]=b
	check(not House.tickets_valid(tickets,{PATH:SHA_A}),"newer live texture generation invalidates the old snapshot before publication")
	Paint._textures.clear();a.set_meta("runtime_source_sha256",SHA_B)
	check(not House.tickets_valid(tickets,{PATH:SHA_A}),"ticket owner metadata changes cannot inherit the prior proof")
	# Restore whole dictionaries instead of clearing another caller's state.
	Paint._textures=before.textures;Paint._materials=before.materials;Paint.prepared_images=before.prepared
	House._meshes=before.meshes;House._render_meshes=before.renders
	RenderingServer.force_sync()

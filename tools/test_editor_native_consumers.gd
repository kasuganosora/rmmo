extends "res://tools/test_full_native_without_source.gd"
## Actual native products; author GLB removed before ordinary consumption.
## Requires private GPU desktop and isolated content root.
const Kits=preload("res://scripts/world3d/auto_tile_kit.gd")
const Imported=preload("res://scripts/world3d/imported_building.gd")
const Membership=preload("res://scripts/world3d/building_membership.gd")
const Contact=preload("res://scripts/world3d/asset_road_contact.gd")
const Surfaces=preload("res://scripts/world3d/surface_materials.gd")

func run()->void:
	create_timer(180).timeout.connect(func():quit(2))
	if DisplayServer.get_name()=="headless":check(false,"private GPU renderer required");quit(1);return
	gpu=true;Policy.verify_packages=false;Controls.discard_map_textures=false
	directory="D:/code/rmmo_runtime/review_artifacts/native_consumers_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(directory)
	var manager:=root.get_node("AssetManager");var previous_root:String=manager.content_root_override;manager.content_root_override=directory
	var sample:=make_sample(directory.path_join("plain.glb"))
	if sample.is_empty():manager.content_root_override=previous_root;quit(1);return
	var plain_contract:=FullFootprint.ensure_imported_building(sample.path,directory)
	check(plain_contract.get("ok",false) and not plain_contract.get("present",true) and plain_contract.get("reused",false),"ordinary native publishes reusable no-building contract")
	var asset:={"uuid":"tree","kind":"asset","asset_path":sample.path,"position":[0,0,0],"rotation":[0,0,0],"size":[1,1,1]}
	var contact:=Contact.geometry(asset,{})
	check(contact.get("known",false) and not contact.get("faces",[]).is_empty(),"road contact collects real native triangles without author GLB")
	var missing_asset:=asset.duplicate();missing_asset.asset_path=directory.path_join("absent.glb")
	check(not Contact.geometry(missing_asset,{}).get("known",false),"missing native road contact stays conservatively unknown")
	check(Surfaces.missing([{"fortification_art":{"asset_path":sample.path}}]).is_empty(),"fortification dependency accepts published native without GLB")
	check(not Surfaces.missing([{"fortification_art":{"asset_path":missing_asset.asset_path}}]).is_empty(),"missing fortification native remains an explicit dependency failure")
	var kit_dir:=directory.path_join("kits");DirAccess.make_dir_recursive_absolute(kit_dir)
	var input:=directory.path_join("author.glb");write(input,data())
	var manifest:=directory.path_join("author_kit.json")
	var f:=FileAccess.open(manifest,FileAccess.WRITE);f.store_string(JSON.stringify({"version":1,"family":"stairs","name":"native stairs","pieces":{"default":input}}));f.close()
	var kit:=Kits.new(kit_dir);var imported:Dictionary=kit.import_kit(manifest)
	check(imported.get("ok",false),"authoring kit import publishes each native model before success")
	if imported.get("ok",false):
		var loaded:Dictionary=kit.read(imported.kit_id)
		check(loaded.get("ok",false),"imported kit opens from native product")
		if loaded.get("ok",false):
			var piece:String=loaded.kit.pieces.default
			check(Library.native_available(piece) and DirAccess.remove_absolute(piece)==OK,"remove imported kit GLB while retaining native product")
			var reopened:Dictionary=kit.read(imported.kit_id)
			check(reopened.get("ok",false) and Kits.piece_mesh(piece)!=null,"kit reopens and resolves native geometry without GLB")
			check(Kits.valid(reopened.kit),"logical kit key validates without its GLB leaf")
			var outside:Dictionary=reopened.kit.duplicate(true);outside.pieces.default=directory.get_base_dir().path_join("outside.glb")
			check(not Kits.valid(outside),"kit rejects logical model keys outside the content root")
			if reopened.get("ok",false):
				var tile:={"family":"stairs","options":{"direction":0,"kit":reopened.kit}}
				check(Kits.build(tile)!=null and Kits.missing([{"tile3d":tile}]).is_empty(),"native stairs retain rendered geometry and save dependency")
				check(not Kits.missing([{"tile3d":{"options":{"kit":{"pieces":{"default":missing_asset.asset_path}}}}}]).is_empty(),"missing kit product is rejected")
	var source:=data()
	var regions:Array=[{"id":"inside","floor":0,"min":[8.2,2.0,-1.8],"max":[11.8,6.0,1.8]}]
	var floor_part:Dictionary={"floor":0,"floor_y":2.0,"role":"floor","part":"floor"}
	var door_part:Dictionary={"floor":0,"floor_y":2.0,"role":"door","part":"door"}
	source.nodes[0].extras={"rmmo_model_components":{"version":1},"rmmo_building":{"version":1,"regions":regions}}
	source.nodes[0].children=[1,2];source.nodes[1].extras={"uuid":"floor_mesh","rmmo_part":floor_part}
	source.nodes.append({"name":"Door","mesh":0,"extras":{"uuid":"door_mesh","rmmo_part":door_part,"rmmo_hinge":{"id":"entry","pivot":[0,0,0],"angle":90,"open":0.0}}})
	var building:=make_sample(directory.path_join("building.glb"),source)
	if not building.is_empty():
		var expected:Dictionary={"version":1,"regions":regions,"members":{"floor_mesh":floor_part,"door_mesh":door_part},"fixtures":{"entry":0.0},"source_sha":building.sha}
		var descriptor:=Imported.read_source_descriptor(building.path,building.sha,directory)
		check(Imported.same(descriptor,expected),"native SceneState descriptor matches authored components without GLB")
		var record:Dictionary={"uuid":"building","kind":"asset","position":[0,0,0],"rotation":[0,0,0],"size":[1,1,1],"asset_path":building.path,"model_building":expected,"model_building_states":{"entry":0.0}}
		var membership:=Membership.build({"rmmo_records":[record]})
		check(membership.get("ok",false) and membership.buildings.building.members.size()==2,"native descriptor preserves real membership and two component IDs")
		var strict_extras:={"rmmo_records":[{"rmmo_state":{"model_building":expected}}]}
		check(DependencyIndex._imported_sources_valid(strict_extras,[{"order":0,"asset_path":building.path}],1,Callable(),directory),"strict dependency index reads source-less published building descriptor")
		var changed:=record.duplicate(true);changed.model_building.members.erase("door_mesh")
		check(not Membership.build({"rmmo_records":[changed]}).get("ok",false),"record cannot forge or omit native component identity")
		var metadata_path:=FullFootprint.building_descriptor_path(building.path,directory)
		var metadata_bytes:=FileAccess.get_file_as_bytes(metadata_path)
		var envelope:Dictionary=JSON.parse_string(metadata_bytes.get_string_from_utf8())
		var body:Dictionary=JSON.parse_string(envelope.body);body.payload_sha="0".repeat(64)
		envelope.body=JSON.stringify(body);save_bytes(metadata_path,JSON.stringify(envelope).to_utf8_buffer())
		check(Imported.read_source_descriptor(building.path,building.sha,directory).is_empty(),"building metadata for a different native payload is not used")
		save_bytes(metadata_path,metadata_bytes)
		check(DirAccess.remove_absolute(metadata_path)==OK and Imported.read_source_descriptor(building.path,building.sha,directory).is_empty(),"missing native building metadata fails without GLB fallback")
		var refreshed:=FullFootprint.refresh_imported_building(building.path,directory)
		check(refreshed.get("ok",false) and refreshed.get("present",false) and Imported.same(Imported.read_source_descriptor(building.path,building.sha,directory),expected),"offline migration restores building metadata from published SCN alone")
	Library.evict_cached_scene(sample.path)
	if not building.is_empty():Library.evict_cached_scene(building.path)
	manager.content_root_override=previous_root
	print("EDITOR_NATIVE_CONSUMERS passed=",passed," failures=",failures," fixture=",directory)
	quit(1 if failures else 0)

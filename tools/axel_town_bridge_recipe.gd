extends RefCounted
## Project supplementary dimensions fitted to the published terrain (2026-10-14).
## Only produces ordinary preview_bridge/generate_bridge arguments; never edits a map.
const ENDPOINTS=[[[219.,8.,83.],[244.,8.,60.]],[[301.,6.19090032577515,165.],[329.,6.23050832748413,159.]],[[274.,5.5,235.],[296.,5.5,256.]],[[229.,5.60427761077881,275.],[247.,5.80000019073486,295.]],[[200.,5.69999980926514,325.],[230.,5.69999980926514,325.]]]
const WIDTHS=[7.2,7.2,8.2,6.2,6.2]
const CAMBERS=[.25,.25,.710,.540,.510]
const ARCHES=[4,3,3,3,3]
const RAISED_HEADS=[0.,0.,0.,1.,1.5]
const ORIGINAL_MAP_SHA="ad16100ace2c6573fe1bd39f2e2bdbf010d3354e7fe0efbf1f8d0fd71883cd34"

static func requests(lift:float=.025)->Array:
	var result:Array=[]
	for i in 5:
		var ends:Array=ENDPOINTS[i].duplicate(true)
		for p:Array in ends:p[1]+=lift
		# Measured bed y=2.2m. A fixed foundation bottom at y=1.7m embeds 0.5m.
		result.append({"id":"axel_bridge_%d"%(i+1),"name":"石桥%d%s"%[i+1," · 居民街主镜头" if i==2 else ""],"prefab_id":"stone_segmental","start":ends[0],"end":ends[1],"width":WIDTHS[i],"depth":(ends[0][1]+ends[1][1])*.5-1.7,"camber":CAMBERS[i],"arches":ARCHES[i],"wing_length":1.5,"wear":.12,"moss":.12,"variation_seed":14100+i,"auto_clearance":false,"deck_material_id":"pack:default:paving/outdoor_flagstone/material","masonry_material_id":"pack:default:walls/castle_rubble/material","trim_material_id":"pack:default:walls/stone_tiles_facade/material"})
	return result

static func notes()->Dictionary:
	return {"scope":"Planning and headless geometry validation only; current native preview must validate actual roads/terrain before generation.","terrain_baseline_sha256":ORIGINAL_MAP_SHA,"road_lift":.025,"clear_widths_m":[6.,6.,7.,5.,5.],"raised_heads_m":RAISED_HEADS,"bridge_4_5_approaches":"Keep 3m bridgehead landing, then at least 15m / 22m gradual landward ramp; local width plus 2-3m feather only, retain riverbed and broad banks.","bridge_2_east":"Native ground across the future deck ranges 5.7775..6.3798m; locally level the 7.2m-wide landing to 6.230508m before placement.","bridge_binding":"road_edge_id supplied by road recipe; straight bridge edge must extend at least 2m beyond both physical ends, recommended3m, exact same longitudinal plane before road lift.","style":"Bridge3 uses the classic residential-street stone arch reference; other bridge identities/dimensions are project supplementary design.","sources":["https://historicengland.org.uk/listing/the-list/list-entry/1020741","https://historicengland.org.uk/listing/the-list/list-entry/1021018","res://docs/world_editor_stone_bridges.md","res://docs/bridge_spire_courtyard_20261007.md"],"white_edge":"Existing bridge_deck_rim generator retains paving only within parapets; sides/underside/exposed outer rim masonry. Check actual new frozen bridge sides in GPU views."}

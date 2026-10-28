extends Node
## Published native-model envelopes, independent of an editor/load operation.
## Transfer on main, without await: preflight -> cache_packed -> adopt -> release
## the queue lease. This is a conservative published baseline, NOT a process cap
## or RSS measurement. Unadopted/legacy caches and later allocations are outside
## this scope. No Resource metadata is added and no GPU data is read back here.
## Identity is NativePreparation.read's reader-completion snapshot (full product
## and final source SHA), NOT a publication-time source freshness revalidation.
const NODE_NAME := "PreparedModelOwnership"
const SCRIPT_PATH := "res://scripts/world_editor/prepared_model_ownership.gd"
const Compiled = preload("res://scripts/world3d/compiled_asset_cache.gd")
const Drainer = preload("res://scripts/world3d/asset_worker_drainer.gd")
const MAX_ENVELOPE_BYTES := 1024 * 1024 * 1024 * 1024
const MAX_VISITS := 2000000
const RETIRE_INTERVAL := 0.5
const SUCCESS_FIELDS := ["error", "packed", "compiled", "source_digest", "compiled_payload_bytes", "cache_us", "elapsed_us"]

# Opaque, tracker-issued capability. Its sealed snapshot lives in _issued and
# contains only scalar identity and WeakRefs; abandoning a ticket pins nothing.
class Ticket extends RefCounted:
	pass

var _entries: Dictionary = {}
var _order: Array[int] = []
var _issued: Dictionary = {}
var _published_bytes := 0
var _weak_owners := 0
var _peak_published_bytes := 0
var _retired_entries := 0
var _retired_bytes := 0
var _scan_cursor := 0
var _retire_elapsed := 0.0

static func for_tree(tree: SceneTree) -> Node:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or tree == null: return null
	var existing := tree.root.get_node_or_null(NODE_NAME)
	if existing != null:
		var script: Script = existing.get_script()
		return existing if script != null and script.resource_path == SCRIPT_PATH else null
	var tracker := new()
	tracker.name = NODE_NAME
	tracker.process_mode = Node.PROCESS_MODE_ALWAYS
	tree.root.add_child(tracker)
	return tracker

func _ready() -> void:
	set_process(not _entries.is_empty())

func preflight(candidate: Dictionary, packet: Dictionary, envelope_bytes: int) -> Dictionary:
	if not _on_main(): return _failure("main_thread_required")
	var reason := _validate_identity(candidate, packet, envelope_bytes)
	if not reason.is_empty(): return _failure(reason)
	var packed: PackedScene = packet.packed
	var graph := _collect_graph(packed)
	if not graph.ok: return _failure(graph.reason)
	_prune_tickets()
	var identity := {}
	for key: String in ["source_path", "source_sha", "payload_sha", "generator", "bytes", "product"]:
		identity[key] = candidate[key]
	identity.make_read_only()
	var ticket := Ticket.new()
	var owners: Array = graph.owners
	owners.make_read_only()
	_issued[ticket.get_instance_id()] = {"ticket":weakref(ticket), "identity":identity, "packed":weakref(packed), "packed_id":packed.get_instance_id(), "envelope_bytes":envelope_bytes, "owners":owners}
	return {"ok":true, "ticket":ticket, "weak_owner_count":owners.size()}

func adopt(ticket: Variant) -> Dictionary:
	if not _on_main(): return _failure("main_thread_required")
	if not ticket is Ticket or not _issued.has(ticket.get_instance_id()): return _failure("unissued_ticket")
	var snapshot: Dictionary = _issued[ticket.get_instance_id()]
	if snapshot.ticket.get_ref() != ticket: return _failure("unissued_ticket")
	var packed: PackedScene = snapshot.packed.get_ref() as PackedScene
	if packed == null: return _failure("packed_owner_expired")
	# cache_packed stamps this source digest before publishing. The caller keeps
	# the transient reservation if this handoff fails, even after cache insertion.
	var validated: Variant = packed.get_meta("compiled_asset_validated", false)
	if not validated is bool or not validated or packed.get_meta("_rmmo_source_digest", "") != snapshot.identity.source_sha:
		return _failure("cache_publication_identity")
	var allocation: int = snapshot.packed_id
	if _entries.has(allocation):
		var previous: Dictionary = _entries[allocation]
		if previous.identity != snapshot.identity or previous.envelope_bytes != snapshot.envelope_bytes:
			return _failure("allocation_identity_conflict")
		return {"ok":true, "entry_id":allocation, "reused":true}
	# Different CACHE_MODE_IGNORE_DEEP loads of the same source are independent
	# allocations and must each be charged. Shared children conservatively keep
	# every original allocation envelope alive until their final owner disappears.
	_entries[allocation] = {"identity":snapshot.identity, "envelope_bytes":snapshot.envelope_bytes, "owners":snapshot.owners}
	_order.append(allocation)
	_published_bytes += int(snapshot.envelope_bytes)
	_weak_owners += snapshot.owners.size()
	_peak_published_bytes = maxi(_peak_published_bytes, _published_bytes)
	set_process(true)
	return {"ok":true, "entry_id":allocation, "reused":false}

func report() -> Dictionary:
	if not _on_main(): return _failure("main_thread_required")
	return {"ok":true, "published_envelope_bytes":_published_bytes, "entries":_entries.size(), "weak_owner_count":_weak_owners, "peak_published_envelope_bytes":_peak_published_bytes, "retired_entries":_retired_entries, "retired_envelope_bytes":_retired_bytes,
		"accounting":"full_native_peak_envelopes; conservative published baseline, not RSS or a hard process cap",
		"coverage":"explicit fixed-native adoptions and their original closed resource graphs only",
		"weak_owner_count_scope":"references across entries; shared resources may be counted more than once",
		"untracked_legacy_cache_bytes":null, "untracked_scope":"legacy/unadopted caches, later resource allocations, renderer/engine overhead",
		"source_proof_scope":"reader-completion snapshot; no publication-time source rehash"}

func collect_retired(max_entries: int = 8) -> Dictionary:
	if not _on_main(): return _failure("main_thread_required")
	_prune_tickets()
	if _order.is_empty() or max_entries <= 0: return {"ok":true, "retired":0, "retired_envelope_bytes":0}
	var scanned := mini(max_entries, _order.size())
	var retiring: Array[int] = []
	for offset in scanned:
		var allocation: int = _order[(_scan_cursor + offset) % _order.size()]
		if _all_dead(_entries[allocation].owners): retiring.append(allocation)
	_scan_cursor = (_scan_cursor + scanned) % _order.size()
	if retiring.is_empty(): return {"ok":true, "retired":0, "retired_envelope_bytes":0}
	# Resource destruction can enqueue renderer work after CPU refcounts reach
	# zero. Keep all envelopes charged until main has flushed that final work.
	_synchronize_retirement()
	var bytes := 0
	for allocation: int in retiring:
		var entry: Dictionary = _entries[allocation]
		bytes += int(entry.envelope_bytes)
		_weak_owners -= entry.owners.size()
		_entries.erase(allocation)
		_order.erase(allocation)
	_published_bytes -= bytes
	_retired_entries += retiring.size()
	_retired_bytes += bytes
	_scan_cursor = _scan_cursor % _order.size() if not _order.is_empty() else 0
	if _order.is_empty(): set_process(false)
	return {"ok":true, "retired":retiring.size(), "retired_envelope_bytes":bytes}

func _process(delta: float) -> void:
	_retire_elapsed += delta
	if _retire_elapsed < RETIRE_INTERVAL: return
	_retire_elapsed = 0.0
	collect_retired()

func _synchronize_retirement() -> void:
	Drainer.synchronize_transfer()

func _prune_tickets() -> void:
	for id: int in _issued.keys():
		if _issued[id].ticket.get_ref() == null: _issued.erase(id)

static func _on_main() -> bool:
	return OS.get_thread_caller_id() == OS.get_main_thread_id()

static func _failure(reason: String) -> Dictionary:
	return {"ok":false, "reason":reason}

static func _validate_identity(candidate: Dictionary, packet: Dictionary, envelope_bytes: int) -> String:
	if envelope_bytes <= 0 or envelope_bytes > MAX_ENVELOPE_BYTES or not candidate.get("estimated_bytes") is int or candidate.estimated_bytes != envelope_bytes or not candidate.get("resident_bytes") is int or candidate.resident_bytes != envelope_bytes:
		return "full_native_envelope_required"
	for key: String in ["source_path", "product"]:
		if not candidate.get(key) is String or candidate[key].is_empty(): return "candidate_path"
	for key: String in ["source_sha", "payload_sha", "generator"]:
		if not Compiled._sha(candidate.get(key)): return "candidate_identity"
	if not candidate.get("bytes") is int or not Compiled.valid_payload_size(candidate.bytes) or candidate.product.get_file() != candidate.payload_sha + ".scn": return "candidate_payload"
	for key: Variant in packet:
		if key not in SUCCESS_FIELDS: return "unexpected_packet_field:" + str(key)
	if not packet.get("error") is int or packet.error != OK or not packet.get("compiled") is bool or not packet.compiled: return "native_success_required"
	if not packet.get("packed") is PackedScene: return "native_packed_required"
	if packet.get("source_digest") != candidate.source_sha or not packet.get("compiled_payload_bytes") is int or packet.compiled_payload_bytes != candidate.bytes: return "native_identity_mismatch"
	for key: String in ["elapsed_us", "cache_us"]:
		if packet.has(key) and (not packet[key] is int or packet[key] < 0): return "native_timing_schema"
	var packed: PackedScene = packet.packed
	var validated: Variant = packed.get_meta("compiled_asset_validated", false)
	if not validated is bool or not validated or packed.get_script() != null: return "native_validation_required"
	var previous: Variant = packed.get_meta("_rmmo_source_digest", "")
	if not previous is String or (not previous.is_empty() and previous != candidate.source_sha): return "cached_source_identity"
	return ""

static func _all_dead(owners: Array) -> bool:
	for owner: WeakRef in owners:
		if owner.get_ref() != null: return false
	return true

static func _collect_graph(packed: PackedScene) -> Dictionary:
	var context := {"ok":true, "reason":"", "owners":[], "seen":{}, "visits":0}
	_remember(packed, context)
	_walk_metadata(packed, context, 0)
	var state := packed.get_state()
	_remember(state, context)
	_walk_metadata(state, context, 0)
	if state.get_node_count() < 1: _reject_graph(context, "native_node_count")
	for node in state.get_node_count():
		if not context.ok: break
		if state.get_node_type(node) not in [&"Node3D", &"MeshInstance3D"] or state.get_node_instance(node) != null:
			_reject_graph(context, "native_node_schema"); break
		for property in state.get_node_property_count(node):
			_walk_value(state.get_node_property_value(node, property), context, 0)
	return context

static func _remember(value: RefCounted, context: Dictionary) -> bool:
	var id := value.get_instance_id()
	if context.seen.has(id): return false
	context.seen[id] = true
	context.owners.append(weakref(value))
	return true

static func _walk_metadata(value: Object, context: Dictionary, depth: int) -> void:
	for key in value.get_meta_list():
		_walk_value(value.get_meta(key), context, depth + 1)
		if not context.ok: return

static func _walk_value(value: Variant, context: Dictionary, depth: int) -> void:
	if not context.ok: return
	context.visits += 1
	if depth > 32 or context.visits > MAX_VISITS: _reject_graph(context, "native_graph_limit"); return
	if value is Resource:
		if value.get_script() != null: _reject_graph(context, "scripted_resource"); return
		if context.seen.has(value.get_instance_id()): return
		if not value is ArrayMesh and not value is StandardMaterial3D and not value is ImageTexture and not value is Image:
			_reject_graph(context, "unsupported_resource:" + value.get_class()); return
		_remember(value, context)
		_walk_metadata(value, context, depth)
		if value is ArrayMesh:
			# _surfaces serializes vertex/index/LOD arrays and material references.
			# Query only actual material/shadow ownership, never those geometry arrays.
			for surface in value.get_surface_count():
				_walk_value(value.surface_get_material(surface), context, depth + 1)
			_walk_value(value.shadow_mesh, context, depth + 1)
		elif value is StandardMaterial3D:
			for info in value.get_property_list():
				if int(info.usage) & PROPERTY_USAGE_STORAGE:
					_walk_value(value.get(info.name), context, depth + 1)
		# ImageTexture owns its renderer allocation. get_image() creates a CPU
		# readback copy, not a resource owner, so it must never be used here.
		return
	if value is Object or value is Callable or value is Signal or value is RID:
		_reject_graph(context, "unsupported_owned_value"); return
	if value is Dictionary:
		for key: Variant in value:
			_walk_value(key, context, depth + 1)
			_walk_value(value[key], context, depth + 1)
			if not context.ok: return
	elif value is Array:
		for item: Variant in value:
			_walk_value(item, context, depth + 1)
			if not context.ok: return

static func _reject_graph(context: Dictionary, reason: String) -> void:
	if context.ok:
		context.ok = false
		context.reason = reason

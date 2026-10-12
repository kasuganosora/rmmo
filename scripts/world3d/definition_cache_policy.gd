extends RefCounted
## Process-wide retained definitions are separate from per-task working memory.
## Configure before dispatch; never resize this policy during a load transaction.
const Store=preload("res://scripts/world3d/map_resource_store.gd")
static var enabled:=false # No demonstrated whole-entry gain yet; opt-in for A/B.

static func configure()->void:
	Store.configure_definition_cache(Store.DEFINITION_CACHE_MAX_BYTES if enabled else 0)

static func reserved_bytes()->int:
	return int(Store.definition_cache_stats().budget_bytes)

static func work_budget(total:int)->int:
	# Reserve capacity, not today's occupancy: a later task can fill the cache.
	# This is not an admission entry, so exclusive tasks can still make progress.
	return maxi(1,total-reserved_bytes())

static func snapshot()->Dictionary:
	var result:Dictionary=Store.definition_cache_stats()
	result.scope="process-wide retained definitions; conservative accounted bytes, not RSS"
	return result

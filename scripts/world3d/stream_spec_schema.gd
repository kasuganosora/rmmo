extends RefCounted
## A read-only validation scope, discarded before returning/yielding/callbacks.
## Parts of one imported object share the authored record. Validate each run
## of identical dictionaries once without trusting equality, hashes or a
## previous frame. Never cache Mesh/transform/bounds or spec identity checks.
const DEFAULT_SIZE:Array=[1,3,1]
var extra:Variant=null
var record:Variant=null
var extra_checks:=0
var record_checks:=0

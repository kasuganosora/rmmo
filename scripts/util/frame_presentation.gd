extends RefCounted
## Main-thread notification that the renderer finished a submitted frame.
##
## With the separate render thread model, the render thread runs a frame behind
## the main thread and returns RenderingServer.frame_post_draw to the main
## thread with call_deferred. A post-draw seen during processing therefore
## usually belongs to an older frame, not the one containing the latest changes.
## Each submitted frame carries a serial through the render command queue ahead
## of its draw; the render thread returns it through the same main-thread call
## queue, so it always arrives just before that frame's post-draw.
## In the safe model every step runs synchronously, like frame_post_draw itself.
## Servers that never draw (headless) never complete a frame.

signal presented(serial:int)

static var _clock:RefCounted
var submitted:=0
var completed:=0
var _waiting:Array=[]
var _drawing:=0

static func clock()->RefCounted:
	assert(Thread.is_main_thread())
	if _clock==null:
		_clock=load("res://scripts/util/frame_presentation.gd").new()
		RenderingServer.frame_pre_draw.connect(_clock._submitted)
		RenderingServer.frame_post_draw.connect(_clock._drawn)
	return _clock

## Resumes on the main thread after a frame containing all changes made so far.
static func drawn()->void:
	var frames:RefCounted=clock()
	var target:int=frames.submitted+1
	while frames.completed<target:await frames.presented

## Calls back on the main thread after a frame containing all changes made so
## far. Callbacks whose object was freed are skipped.
static func after_drawn(callback:Callable)->void:
	var frames:RefCounted=clock()
	frames._waiting.append([frames.submitted+1,callback])

## First serial whose frame contains changes made from now on.
static func next_serial()->int:
	return clock().submitted+1

func _submitted()->void:
	submitted+=1
	RenderingServer.call_on_render_thread(_mark.bind(submitted))

func _mark(serial:int)->void:
	if Thread.is_main_thread():_drawing=serial
	else:call_deferred("_begin",serial)

func _begin(serial:int)->void:
	_drawing=serial

func _drawn()->void:
	if _drawing<=completed:return
	completed=_drawing
	if not _waiting.is_empty():
		var due:Array=[];var later:Array=[]
		for row:Array in _waiting:(due if row[0]<=completed else later).append(row)
		_waiting=later
		for row:Array in due:
			if row[1].is_valid():row[1].call()
	presented.emit(completed)

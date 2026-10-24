extends RefCounted
## Diagnostic-only loopback heartbeat. No disk writes or production scheduling.
## Eight little-endian uint64 fields: seq, ticks, stage, phase, pid, Godot thread
## ID (NOT Windows TID), process frame, map-load origin ticks.
const OBSERVE_BEGIN:=1
const OBSERVE_END:=2
const GEOMETRY_BEGIN:=3
const GEOMETRY_END:=4
const PRE_DRAW:=5
const POST_DRAW:=6
const STOP:=7
var udp:=PacketPeerUDP.new()
var packet:=PackedByteArray()
var sequence:=0
var active:=false
var owner_thread:=0
var previous_phase:=-1
var previous_send:=0
var profile:Dictionary={"sent":0,"errors":0,"wrong_thread":0,"unarmed_skipped":0,"total_us":0,"max_us":0}

func start(port:int)->Error:
	if port<1024 or port>65535:return ERR_INVALID_PARAMETER
	packet.resize(64)
	owner_thread=OS.get_thread_caller_id()
	var result:=udp.set_dest_address("127.0.0.1",port)
	active=result==OK
	return result

func mark(stage:int,phase_name:String,origin:int)->void:
	if not active:return
	# RenderingServer post-draw callbacks are dispatched on main even when the
	# actual draw runs elsewhere. This marker describes signal delivery only.
	if OS.get_thread_caller_id()!=owner_thread:
		profile.wrong_thread+=1
		return
	var started:=Time.get_ticks_usec()
	var phase_id:=0
	if phase_name=="white_origin_steady":phase_id=1
	elif phase_name=="white_native_reload":phase_id=2
	elif phase_name=="white_native_return":phase_id=3
	elif phase_name=="white_return_steady":phase_id=4
	elif phase_name=="white_stream_origin":phase_id=5
	# High-FPS empty-map travel is not armed. Preserve every phase transition
	# but send only a 10 Hz liveness marker there instead of six packets/frame.
	if phase_id==0 and previous_phase==0 and stage!=STOP and started-previous_send<100000:
		profile.unarmed_skipped+=1
		return
	previous_phase=phase_id;previous_send=started
	sequence+=1
	packet.encode_u64(0,sequence)
	packet.encode_u64(8,started)
	packet.encode_u64(16,stage)
	packet.encode_u64(24,phase_id)
	packet.encode_u64(32,OS.get_process_id())
	packet.encode_u64(40,owner_thread)
	packet.encode_u64(48,Engine.get_process_frames())
	packet.encode_u64(56,maxi(0,origin))
	var result:=udp.put_packet(packet)
	if result==OK:profile.sent+=1
	else:profile.errors+=1
	var elapsed:=Time.get_ticks_usec()-started
	profile.total_us+=elapsed;profile.max_us=maxi(profile.max_us,elapsed)

func stop(origin:int)->void:
	mark(STOP,"",origin)
	active=false;udp.close()

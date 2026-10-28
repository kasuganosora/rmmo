extends "res://tools/test_world3d_mcp.gd"
## Two actual HTTP clients share a gated source import. Disconnect and stop
## must retire their own subscriptions while retaining the worker's budget.
var gate:=Semaphore.new()

func start_gated(thread:Thread,task:Callable)->int:
	return thread.start(run_gated.bind(task),Thread.PRIORITY_LOW)
func run_gated(task:Callable)->Variant:
	gate.wait();return task.call()

func request_import(path:String,id:int)->StreamPeerTCP:
	var peer:=StreamPeerTCP.new();peer.connect_to_host("127.0.0.1",port)
	var deadline:=Time.get_ticks_msec()+10000
	while Time.get_ticks_msec()<deadline:
		peer.poll()
		if peer.get_status()==StreamPeerTCP.STATUS_CONNECTED:break
		await process_frame
	var body:=JSON.stringify({"jsonrpc":"2.0","id":id,"method":"tools/call","params":{"name":"import_surface_material","arguments":{"path":path,"name":"shared source","compression":"source"}}}).to_utf8_buffer()
	var headers:=("POST /mcp HTTP/1.1\r\nHost: 127.0.0.1:%d\r\nContent-Type: application/json\r\nContent-Length: %d\r\n\r\n"%[port,body.size()]).to_utf8_buffer();headers.append_array(body)
	check(peer.put_data(headers)==OK,"write real pending import request")
	return peer

func run()->void:
	create_timer(90).timeout.connect(func():quit(2));rpc_timeout_ms=30000
	var folder:=Paths.cache_directory("surface_disconnect_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(folder)
	var source:=folder.path_join("source.png");var image:=Image.create(32,32,false,Image.FORMAT_RGB8);image.fill(Color(.2,.4,.7));image.save_png(source)
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_doc=Doc.new();session.world3d_editor_path=""
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._material_directory=folder.path_join("materials");editor._draft_directory=folder.path_join("drafts")
	root.add_child(editor);editor._safety.enabled=false;await settle()
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"start real MCP server")
	var service:Node=editor._surface_texture_imports;var queue:Node=service._queue;queue.thread_starter=start_gated
	var first:=await request_import(source,101);var second:=await request_import(source,102)
	var deadline:=Time.get_ticks_msec()+10000
	while editor._mcp._pending_imports.size()<2 and Time.get_ticks_msec()<deadline:await process_frame
	check(editor._mcp._pending_imports.size()==2 and editor._mcp._import_peers.size()==2,"two distinct HTTP requests are independently registered")
	print("DISCONNECT_BEFORE_ADMISSION ",JSON.stringify({"groups":service.snapshot().groups,"leases":queue.ledger.count(),"started":queue.metrics.started}))
	# HTTP registration can precede the queue's next processing slice. The
	# cancellation contract here explicitly requires an admitted blocked worker.
	deadline=Time.get_ticks_msec()+10000
	while queue.ledger.count()==0 and Time.get_ticks_msec()<deadline:await process_frame
	check(service.snapshot().groups==1 and queue.ledger.count()>0,"same-path same-quality clients share one admitted group")
	var listener_count:=0
	for connection:Dictionary in service.finished.get_connections():
		if connection.callable.get_method()=="_imported_http":listener_count+=1
	check(listener_count==1,"concurrent HTTP requests use one signal connection")
	first.disconnect_from_host();deadline=Time.get_ticks_msec()+10000
	while editor._mcp._pending_imports.size()!=1 and Time.get_ticks_msec()<deadline:await process_frame
	check(editor._mcp._pending_imports.size()==1 and editor._mcp._import_peers.size()==1,"disconnect removes only its own request indices")
	check(service.snapshot().groups==1,"surviving subscriber keeps the shared import")
	await call_tool("editor_state")
	editor._mcp.stop()
	check(editor._mcp._pending_imports.is_empty() and editor._mcp._import_peers.is_empty(),"server stop clears both request indices")
	listener_count=0
	for connection:Dictionary in service.finished.get_connections():
		if connection.callable.get_method()=="_imported_http":listener_count+=1
	check(listener_count==0 and queue.ledger.count()>0,"stop disconnects handler without prematurely returning blocked worker budget")
	queue.thread_starter=Callable()
	for i:int in 4:gate.post()
	deadline=Time.get_ticks_msec()+15000
	while (service.snapshot().requests>0 or queue.ledger.count()>0) and Time.get_ticks_msec()<deadline:await process_frame
	check(service.snapshot().requests==0 and service.snapshot().groups==0 and queue.ledger.count()==0 and queue.ledger.reserved_bytes==0,"cancelled shared preparation drains fully after release")
	check(not DirAccess.dir_exists_absolute(editor._material_directory),"cancellation before preparation publishes no material files")
	second.disconnect_from_host();editor.queue_free();await settle();session.world3d_editor_doc=null;session.world3d_editor_path=""
	print("SURFACE_IMPORT_DISCONNECT_FAILED=",failed);quit(1 if failed else 0)

extends RefCounted
## Main-thread display updates. Re-submitting identical values can invalidate
## the Vulkan swapchain and block the next draw in the display driver.
## Compare actual state, not cached preferences: OS/user changes must reconcile.


static func set_vsync_mode(mode: DisplayServer.VSyncMode, window: int = DisplayServer.MAIN_WINDOW_ID) -> bool:
	if DisplayServer.get_name() == "headless" or DisplayServer.window_get_vsync_mode(window) == mode:
		return false
	DisplayServer.window_set_vsync_mode(mode, window)
	return true


static func set_window_mode(mode: DisplayServer.WindowMode, window: int = DisplayServer.MAIN_WINDOW_ID) -> bool:
	if DisplayServer.get_name() == "headless" or DisplayServer.window_get_mode(window) == mode:
		return false
	DisplayServer.window_set_mode(mode, window)
	return true


static func set_window_size(size: Vector2i, window: int = DisplayServer.MAIN_WINDOW_ID) -> bool:
	if DisplayServer.get_name() == "headless" or DisplayServer.window_get_size(window) == size:
		return false
	DisplayServer.window_set_size(size, window)
	return true

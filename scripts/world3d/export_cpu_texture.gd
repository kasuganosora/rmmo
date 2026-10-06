extends Texture2D
## An export-only image snapshot. Workers never read textures back from the GPU.
var pixels: Image
func _get_image() -> Image: return pixels
func _get_width() -> int: return pixels.get_width()
func _get_height() -> int: return pixels.get_height()
func _has_alpha() -> bool: return pixels.detect_alpha() != Image.ALPHA_NONE
func _get_rid() -> RID: return RID()

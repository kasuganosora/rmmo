# Godot 4.7.2 native profiler lifetime fix

Base: official `4.7.2-stable`, commit `ed1daf0bf001b61586d9930840f2f1394092c079`.
The GDScript VM calls `_profile_count_as_native(base_obj, ...)` after invoking
the method, which may have freed `base_obj`. Reuse the `StringName base_class`
already captured before dispatch. Native-call profiling remains enabled.

From an unmodified matching engine source checkout, substitute the absolute
path to this patch. Disable automatic line-ending conversion for this command
so the resulting source bytes match the compiled source recorded in the report:

```powershell
git -c core.autocrlf=false apply --check C:/path/to/godot-4.7.2-profiler-free.patch
git -c core.autocrlf=false apply C:/path/to/godot-4.7.2-profiler-free.patch
$env:GODOT_VERSION_STATUS='stable'
python -m SCons platform=windows arch=x86_64 target=editor use_mingw=yes debug_symbols=yes separate_debug_symbols=yes dev_build=no optimize=speed lto=none d3d12=no accesskit=no angle=no -j6
```

The fixture `tools/test_profiler_free.gd` runs in an empty external Godot
project with the official remote servers profiler and native-call statistics
enabled. It frees 61440 parents with children. A successful stress run alone
does not prove the absence of a dangling access: the report also records GDB
evidence of the ObjectDB slot being empty at the helper, before and after the
fix. This patches the local diagnostic engine only.

Evidence, binary/symbol hashes, full-route checks and limits:
[`docs/axel_white_longframes_20261019.md`](../../docs/axel_white_longframes_20261019.md).

$ErrorActionPreference = 'Stop'
foreach ($test in @(
    @{ Name='test_cpu_river_materials_gpu'; Timeout=120 },
    @{ Name='test_same_map_transfer_gpu'; Timeout=330 },
    @{ Name='test_transfer_loading_gpu'; Timeout=270 },
    @{ Name='test_reference_map_http'; Timeout=630 }
)) {
    $arguments = @('tools/run_godot_background.py', '--timeout', $test.Timeout, '--log', "review_artifacts/loading_s1_20261010/$($test.Name)_final.log", '--', 'D:/tools/godot/Godot_v4.7.2-stable_win64.exe', '--path', 'D:/code/rmmo', '--script', "res://tools/$($test.Name).gd")
    if ($test.Name -eq 'test_reference_map_http') { $arguments += @('--', '--compiled-assets', '--output=D:/code/rmmo_runtime/review_artifacts/loading_s1_reference_http_20261010.json') }
    & 'C:/Users/luna/AppData/Local/Programs/Python/Python312/python.exe' @arguments
    if ($LASTEXITCODE -ne 0) { throw "$($test.Name) failed: $LASTEXITCODE" }
}

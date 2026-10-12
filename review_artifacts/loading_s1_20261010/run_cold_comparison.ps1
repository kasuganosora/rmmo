$ErrorActionPreference = 'Stop'
foreach ($label in @('cold_a1', 'cold_b1', 'cold_b2', 'cold_a2')) {
    $reportPath = "D:/code/rmmo_runtime/review_artifacts/loading_s1_${label}_20261010.json"
    $arguments = @('tools/profile_load_hardware.py', '--timeout', '180',
        '--log', "review_artifacts/loading_s1_20261010/${label}.log",
        '--hardware', "review_artifacts/loading_s1_20261010/${label}.hardware.json",
        '--', 'D:/tools/godot/Godot_v4.7.2-stable_win64.exe', '--path', 'D:/code/rmmo',
        '--script', 'res://tools/profile_game_entry.gd', '--', "--label=loading_s1_${label}",
        '--map=D:/code/rmmo_runtime/cache/world3d/reference_pennant_checkpoint_20261009/map.gltf',
        '--spawn=321.2,0.9,160.3', '--monitor', '--reset-dependency-index', '--reset-derived-cache', "--output=$reportPath")
    if ($label -like 'cold_a*') { $arguments += '--without-cold-index-rebuild' }
    & 'C:/Users/luna/AppData/Local/Programs/Python/Python312/python.exe' @arguments
    if ($LASTEXITCODE -ne 0) { throw "Cold index probe $label failed: $LASTEXITCODE" }
    $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json -Depth 100
    if ($report.failures -ne 0 -or $report.map_profile.reference_index_hit) { throw "Invalid cold index probe $label" }
    [pscustomobject]@{Label=$label;EntryMs=$report.entry_ms;CoreReadyMs=$report.entry_core_ready_ms;Rebuilt=$report.map_profile.reference_index_rebuilt_before_models;CookedMeshes=$report.map_profile.cooked_meshes;Failures=$report.failures} | ConvertTo-Json -Compress
}

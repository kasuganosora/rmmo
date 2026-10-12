$ErrorActionPreference = 'Stop'
foreach ($label in @('water_a1', 'water_native_b1', 'water_native_b2', 'water_a2')) {
    $output = "D:/code/rmmo_runtime/review_artifacts/loading_s1_${label}_20261010.json"
    $arguments = @('tools/profile_load_hardware.py', '--timeout', '180',
        '--log', "review_artifacts/loading_s1_20261010/${label}.log", '--hardware', "review_artifacts/loading_s1_20261010/${label}.hardware.json",
        '--', 'D:/tools/godot/Godot_v4.7.2-stable_win64.exe', '--path', 'D:/code/rmmo', '--script', 'res://tools/profile_game_entry.gd', '--',
        "--label=loading_s1_${label}", '--map=D:/code/rmmo_runtime/cache/world3d/reference_pennant_checkpoint_20261009/map.gltf',
        '--spawn=321.2,0.9,160.3', '--monitor', '--without-prefab-texture-preparation', "--output=$output")
    if ($label -like 'water_a*') { $arguments += '--without-native-entry-prefetch' }
    else { $arguments += '--with-native-entry-prefetch' }
    & 'C:/Users/luna/AppData/Local/Programs/Python/Python312/python.exe' @arguments
    if ($LASTEXITCODE -ne 0) { throw "Variant $label failed: $LASTEXITCODE" }
    $p = Get-Content -LiteralPath $output -Raw | ConvertFrom-Json -Depth 100
    if ($p.failures -ne 0 -or -not $p.map_profile.reference_index_hit -or $p.map_profile.cooked_meshes -eq 0) { throw "Invalid warm variant $label" }
    [pscustomobject]@{Label=$label;EntryMs=$p.entry_ms;CoreReadyMs=$p.entry_core_ready_ms;Failures=$p.failures} | ConvertTo-Json -Compress
}

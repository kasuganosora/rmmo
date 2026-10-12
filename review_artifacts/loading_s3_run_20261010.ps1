$ErrorActionPreference = 'Stop'
foreach ($label in @('prewarm', 'a1', 'b1', 'b2', 'a2')) {
    $output = "D:/code/rmmo_runtime/review_artifacts/loading_s3_${label}_20261010.json"
    $arguments = @('tools/profile_load_hardware.py', '--timeout', '210',
        '--log', "review_artifacts/loading_s3_${label}_20261010.log", '--hardware', "review_artifacts/loading_s3_${label}_20261010.hardware.json",
        '--', 'D:/tools/godot/Godot_v4.7.2-stable_win64.exe', '--path', 'D:/code/rmmo', '--script', 'res://tools/profile_game_entry.gd', '--',
        "--label=loading_s3_${label}", '--map=D:/code/rmmo_runtime/cache/world3d/reference_pennant_checkpoint_20261009/map.gltf',
        '--spawn=321.2,0.9,160.3', '--monitor', "--output=$output", '--without-frame-budget',
        '--without-prefab-texture-preparation', '--without-native-entry-prefetch')
    if ($label -like 'b*') { $arguments += @('--with-background-navigation', '--with-background-wind') }
    else { $arguments += @('--without-background-navigation', '--without-background-wind') }
    & 'C:/Users/luna/AppData/Local/Programs/Python/Python312/python.exe' @arguments
    if ($LASTEXITCODE -ne 0) { throw "Variant $label failed: $LASTEXITCODE" }
    $p = Get-Content -LiteralPath $output -Raw | ConvertFrom-Json -Depth 100
    $log = Get-Content -LiteralPath "review_artifacts/loading_s3_${label}_20261010.log" -Raw
    if ($p.failures -ne 0 -or $log -match '(?m)SCRIPT ERROR|^ERROR:' -or ($label -ne 'prewarm' -and $p.map_profile.cooked_meshes -eq 0)) { throw "Invalid warm variant $label" }
    [pscustomobject]@{Label=$label;EntryMs=$p.entry_ms;CoreReadyMs=$p.entry_core_ready_ms;Failures=$p.failures} | ConvertTo-Json -Compress
}

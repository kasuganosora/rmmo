param([string]$Prefix = 'final')
$ErrorActionPreference = 'Stop'
$runs = @(
    @{ Label = 'prewarm_full'; Legacy = $true },
    @{ Label = 'prewarm_selected'; Legacy = $true },
    @{ Label = 'a1'; Legacy = $true },
    @{ Label = 'b1'; Legacy = $false },
    @{ Label = 'b2'; Legacy = $false },
    @{ Label = 'a2'; Legacy = $true }
)
foreach ($run in $runs) {
    $label = $Prefix + '_' + $run.Label
    $reportPath = "D:/code/rmmo_runtime/review_artifacts/loading_s1_${label}_20261010.json"
    $arguments = @(
        'tools/profile_load_hardware.py', '--timeout', '180',
        '--log', "review_artifacts/loading_s1_20261010/${label}.log",
        '--hardware', "review_artifacts/loading_s1_20261010/${label}.hardware.json",
        '--', 'D:/tools/godot/Godot_v4.7.2-stable_win64.exe', '--path', 'D:/code/rmmo',
        '--script', 'res://tools/profile_game_entry.gd', '--', "--label=loading_s1_${label}",
        '--map=D:/code/rmmo_runtime/cache/world3d/reference_pennant_checkpoint_20261009/map.gltf',
        '--spawn=321.2,0.9,160.3', '--monitor', "--output=$reportPath"
    )
    if ($run.Legacy) {
        $arguments += @('--without-water-cpu-normals', '--without-water-cpu-index', '--without-prefab-texture-preparation', '--without-native-entry-prefetch')
    } else {
        $arguments += @('--with-prefab-texture-preparation', '--with-native-entry-prefetch')
    }
    & 'C:/Users/luna/AppData/Local/Programs/Python/Python312/python.exe' @arguments
    if ($LASTEXITCODE -ne 0) { throw "Entry probe $label failed: $LASTEXITCODE" }
    $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json -Depth 100
    if ($report.failures -ne 0) { throw "Entry probe $label has assertion failures" }
    if ($run.Label -notlike 'prewarm*' -and ($report.map_profile.cooked_meshes -eq 0 -or -not $report.map_profile.reference_index_hit)) {
        throw "Entry probe $label was not warm; exclude it and warm the selected closure before comparing"
    }
    [pscustomobject]@{Label=$label;EntryMs=$report.entry_ms;CoreReadyMs=$report.entry_core_ready_ms;CookedMeshes=$report.map_profile.cooked_meshes;IndexHit=$report.map_profile.reference_index_hit;Failures=$report.failures} | ConvertTo-Json -Compress
}

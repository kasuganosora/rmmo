# Read assembly metadata only; never load or execute the game's managed code.
$ErrorActionPreference = 'Stop'
Add-Type -Path 'D:/tools/dnSpyEx_6.5.1_win64/bin/dnlib.dll'
$sourceAssembly = 'D:/Games/Koikatu/Koikatu_Data/Managed/Assembly-CSharp.dll'
$outputDirectory = 'D:/code/rmmo_runtime/assets/characters/source_hair/koikatu/lighting'
$module = [dnlib.DotNet.ModuleDefMD]::Load($sourceAssembly)
$selected = @{
    'ChaFileHair' = @('MemberInit')
    'ChaControl' = @('LoadHairGlossMask', 'ChangeSettingHairGlossMask')
    'ChaShader' = @('ChangeRampTexture', 'ChangeAmbientShaodwColor')
    'Manager.Character' = @('UpdateGlobalShader')
    'Config.EtceteraSystem' = @('.ctor', 'Init')
}
$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add('Source SHA256: ' + (Get-FileHash -LiteralPath $sourceAssembly -Algorithm SHA256).Hash)
foreach ($type in $module.GetTypes()) {
    if (-not $selected.ContainsKey($type.FullName)) { continue }
    foreach ($method in $type.Methods) {
        if (-not $method.HasBody -or $method.Name.ToString() -notin $selected[$type.FullName]) { continue }
        $lines.Add($method.FullName)
        foreach ($instruction in $method.Body.Instructions) { $lines.Add($instruction.ToString()) }
        $lines.Add('')
    }
}
[System.IO.File]::WriteAllLines((Join-Path $outputDirectory 'source_lighting.il.txt'), $lines)
$module.Dispose()
Write-Output ('Saved source lighting initialization evidence: ' + $lines.Count + ' lines')

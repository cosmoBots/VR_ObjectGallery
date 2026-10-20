# All arguments are forwarded to the exported application.
$applicationArgs = $args
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

function Get-SourceFiles([string]$Directory) {
    foreach ($item in Get-ChildItem -LiteralPath $Directory -Force) {
        if ($item.PSIsContainer) {
            if ($item.Name -in @('.git', '.godot') -or
                $item.FullName -in @((Join-Path $root 'build'), (Join-Path $root 'android\build'), (Join-Path $root 'web'))) { continue }
            Get-SourceFiles $item.FullName
        } elseif ($item.Extension -in @('.gd', '.tscn', '.tres', '.godot', '.cfg', '.yaml', '.yml') -or
                  $item.FullName.StartsWith((Join-Path $root 'models') + '\', [StringComparison]::OrdinalIgnoreCase)) {
            if ($item.Extension -notin @('.import', '.md5', '.apk', '.exe', '.dll', '.pck')) { $item }
        }
    }
}

try {
    $presetName = if ($env:EXPORT_PRESET_NAME) { $env:EXPORT_PRESET_NAME } else { 'Windows' }
    $mode = if ($env:EXPORT_MODE) { $env:EXPORT_MODE } else { 'debug' }
    if ($mode -notin @('debug', 'release')) { throw 'EXPORT_MODE debe ser debug o release.' }
    $presets = Get-Content -LiteralPath (Join-Path $root 'export_presets.cfg') -Raw
    $preset = @([regex]::Matches($presets, '(?ms)^\[preset\.\d+\]\s*\r?\n(.*?)(?=^\[|\z)') |
        Where-Object { $_.Groups[1].Value -match ('(?m)^name="' + [regex]::Escape($presetName) + '"\s*$') -and
                      $_.Groups[1].Value -match '(?m)^platform="Windows Desktop"\s*$' })
    if ($preset.Count -ne 1 -or $preset[0].Value -notmatch '(?m)^export_path="([^"]+)"') {
        throw "No encuentro export_path del preset Windows Desktop '$presetName'."
    }
    $exportPath = $Matches[1]
    if ([IO.Path]::GetExtension($exportPath) -ne '.exe') { throw 'La ruta de exportacion debe terminar en .exe.' }
    $binary = if ([IO.Path]::IsPathRooted($exportPath)) { $exportPath } else { Join-Path $root $exportPath }
    $binary = [IO.Path]::GetFullPath($binary)
    $stamp = "$binary.export-mode"
    $buildIdentity = "$presetName|$mode"
    $newest = Get-SourceFiles $root | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
    if (-not $newest) { throw 'No he encontrado ficheros fuente a comparar.' }
    $needsBuild = -not (Test-Path -LiteralPath $binary -PathType Leaf)
    if (-not $needsBuild) {
        $needsBuild = $newest.LastWriteTimeUtc -gt (Get-Item -LiteralPath $binary).LastWriteTimeUtc
    }
    if (-not (Test-Path -LiteralPath $stamp) -or (Get-Content -LiteralPath $stamp -Raw).Trim() -ne $buildIdentity) { $needsBuild = $true }

    if ($needsBuild) {
        $godot = $env:GODOT_BIN
        if (-not $godot) {
            $candidates = @(Get-ChildItem -LiteralPath (Split-Path $root -Parent) -Filter 'Godot*_win64*.exe' -File |
                Sort-Object @{ Expression = { $_.Name -like '*_console.exe' }; Descending = $true }, LastWriteTime -Descending)
            if ($candidates.Count) { $godot = $candidates[0].FullName }
        }
        if (-not $godot -or -not (Test-Path -LiteralPath $godot -PathType Leaf)) {
            throw 'No encuentro Godot en ..; configura GODOT_BIN con la ruta del ejecutable.'
        }
        $log = if ($env:BUILD_LOG) { $env:BUILD_LOG } else { Join-Path $env:TEMP 'vr_objectgallery_windows_build.log' }
        New-Item -ItemType Directory -Path (Split-Path $binary -Parent) -Force | Out-Null
        Write-Host "Exportando '$presetName' ($mode) -> $binary"
        Write-Host "Godot: $godot"
        Write-Host "Log build: $log"
        if (Test-Path -LiteralPath $stamp) { Remove-Item -LiteralPath $stamp }
        $previousConsoleEncoding = [Console]::OutputEncoding
        try {
            [Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
            $ErrorActionPreference = 'Continue'
            & $godot --headless --path $root "--export-$mode" $presetName $binary 2>&1 |
                ForEach-Object { $_.ToString() } | Tee-Object -FilePath $log
            $buildExit = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = 'Stop'
            [Console]::OutputEncoding = $previousConsoleEncoding
        }
        if ($buildExit -ne 0 -or -not (Test-Path -LiteralPath $binary -PathType Leaf)) {
            throw "La exportacion fallo. Revisa $log. Instala las plantillas de exportacion de la misma version que Godot desde el editor."
        }
        Set-Content -LiteralPath $stamp -Value $buildIdentity -Encoding ASCII
    } else { Write-Host 'Binario actualizado, no recompilo.' }

    Write-Host "Lanzando: $binary $applicationArgs"
    Push-Location -LiteralPath $root
    try {
        & $binary @applicationArgs
        $applicationExit = $LASTEXITCODE
    } finally { Pop-Location }
    exit $applicationExit
} catch {
    [Console]::Error.WriteLine('ERROR: ' + $_.Exception.Message)
    exit 1
}

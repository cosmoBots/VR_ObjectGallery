param(
    [Parameter(Mandatory = $true)][ValidateSet('Pico', 'Meta')][string]$Target,
    [Parameter(Position = 0)][string]$Apk,
    [switch]$Check,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$presetName = if ($Target -eq 'Pico') { 'PicoVR' } else { 'Meta Quest 3' }
$serialKey = $Target.ToUpperInvariant() + '_SERIAL'
$packageName = 'eu.cosmobots.vr_objectgallery'

function Resolve-ProjectPath([string]$Path) {
    if ([IO.Path]::IsPathRooted($Path)) { return [IO.Path]::GetFullPath($Path) }
    return [IO.Path]::GetFullPath((Join-Path $root $Path))
}

function Invoke-Adb {
    & $script:adb @args
    if ($LASTEXITCODE -ne 0) { throw "ADB fallo (codigo $LASTEXITCODE)." }
}

function Get-SourceFiles([string]$Directory) {
    foreach ($item in Get-ChildItem -LiteralPath $Directory -Force) {
        if ($item.PSIsContainer) {
            if ($item.Name -in @('.git', '.godot') -or $item.FullName -eq (Join-Path $root 'android\build')) { continue }
            Get-SourceFiles $item.FullName
        } elseif ($item.Extension -in @('.gd', '.tscn', '.tres', '.godot', '.cfg', '.yaml', '.yml') -or
                  $item.FullName.StartsWith((Join-Path $root 'models') + '\', [StringComparison]::OrdinalIgnoreCase)) {
            if ($item.Extension -notin @('.import', '.md5', '.apk')) { $item }
        }
    }
}

try {
    if ($Help) {
        Write-Host "deploy_$($Target.ToLowerInvariant()).bat [ruta.apk] [-Check] [-Help]"
        Write-Host 'Sin APK: exporta debug si falta o hay fuentes mas recientes, instala y lanza.'
        Write-Host 'Con APK: instala y lanza el fichero existente, sin compilar.'
        Write-Host '-Check: comprueba herramientas y configuracion sin compilar ni tocar el visor.'
        exit 0
    }

    $godot = $env:GODOT_BIN
    if (-not $godot) {
        $candidates = @(Get-ChildItem -LiteralPath (Split-Path $root -Parent) -Filter 'Godot*_win64*.exe' -File |
            Sort-Object @{ Expression = { $_.Name -like '*_console.exe' }; Descending = $true }, LastWriteTime -Descending)
        if ($candidates.Count) { $godot = $candidates[0].FullName }
    }
    $sdk = $env:ANDROID_HOME
    if (-not $sdk) { $sdk = $env:ANDROID_SDK_ROOT }
    if (-not $sdk) { $sdk = Join-Path $env:LOCALAPPDATA 'Android\Sdk' }
    $adb = $env:ADB_BIN
    if (-not $adb -and (Test-Path -LiteralPath (Join-Path $sdk 'platform-tools\adb.exe'))) {
        $adb = Join-Path $sdk 'platform-tools\adb.exe'
    }
    if (-not $adb) {
        $command = Get-Command adb.exe -ErrorAction SilentlyContinue
        if ($command) { $adb = $command.Source }
    }

    $serial = [Environment]::GetEnvironmentVariable($serialKey)
    $targetsPath = Join-Path $root '.targets'
    if (Test-Path -LiteralPath $targetsPath) {
        foreach ($line in Get-Content -LiteralPath $targetsPath) {
            if ($line -match ('^\s*(?:export\s+)?' + $serialKey + '\s*=\s*(.*?)\s*$')) {
                $value = $Matches[1]
                if ($value -match '^"([^"]*)"\s*(?:#.*)?$' -or $value -match "^'([^']*)'\s*(?:#.*)?$") {
                    $serial = $Matches[1]
                } else { $serial = ($value -replace '\s+#.*$', '').Trim() }
            }
        }
    }

    $explicitApk = -not [string]::IsNullOrWhiteSpace($Apk)
    if (-not $explicitApk) {
        $presets = Get-Content -LiteralPath (Join-Path $root 'export_presets.cfg') -Raw
        $preset = @([regex]::Matches($presets, '(?ms)^\[preset\.\d+\]\s*\r?\n(.*?)(?=^\[|\z)') |
            Where-Object { $_.Groups[1].Value -match ('(?m)^name="' + [regex]::Escape($presetName) + '"\s*$') })
        if ($preset.Count -ne 1 -or $preset[0].Value -notmatch '(?m)^export_path="([^"]+)"') {
            throw "No encuentro export_path del preset '$presetName'."
        }
        $Apk = $Matches[1]
    }
    if (-not $Apk.EndsWith('.apk', [StringComparison]::OrdinalIgnoreCase)) { $Apk += '.apk' }
    $apkPath = Resolve-ProjectPath $Apk

    Write-Host "Preset: $presetName"
    Write-Host "Godot: $godot"
    Write-Host "SDK: $sdk"
    Write-Host "ADB: $adb"
    Write-Host "${serialKey}: $serial"
    Write-Host "APK: $apkPath"
    $problems = @()
    if (-not $adb -or -not (Test-Path -LiteralPath $adb -PathType Leaf)) {
        $problems += 'Falta adb.exe. Instala Android SDK Platform-Tools o define ADB_BIN en android.env.bat.'
    }
    if (-not $serial) { $problems += "Copia .targets.example a .targets y configura $serialKey (usa adb devices -l)." }
    $needsBuild = $false
    if ($explicitApk) {
        if (-not (Test-Path -LiteralPath $apkPath -PathType Leaf)) { $problems += "No existe el APK: $apkPath" }
    } else {
        $newest = Get-SourceFiles $root | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
        $needsBuild = -not (Test-Path -LiteralPath $apkPath -PathType Leaf)
        if (-not $needsBuild -and $newest) { $needsBuild = $newest.LastWriteTimeUtc -gt (Get-Item -LiteralPath $apkPath).LastWriteTimeUtc }
        if ($needsBuild) {
            if (-not $godot -or -not (Test-Path -LiteralPath $godot -PathType Leaf)) { $problems += 'No encuentro Godot en ..; define GODOT_BIN en android.env.bat.' }
            if (-not (Test-Path -LiteralPath $sdk -PathType Container)) { $problems += 'Falta Android SDK. Instala los componentes para Godot y configura Android SDK Path en el editor.' }
            $java = Get-Command java.exe -ErrorAction SilentlyContinue
            if (-not $java -and -not ($env:JAVA_HOME -and (Test-Path -LiteralPath (Join-Path $env:JAVA_HOME 'bin\java.exe')))) {
                $problems += 'Falta Java. Instala un JDK compatible y configura JAVA_HOME y Java SDK Path en Godot.'
            }
        }
    }
    if ($problems.Count) { throw ($problems -join [Environment]::NewLine) }
    if ($Check) { Write-Host 'Comprobacion basica correcta. No se ha compilado ni conectado al visor.'; exit 0 }

    $state = Invoke-Adb -s $serial get-state
    if (($state -join '').Trim() -ne 'device') { throw 'Visor no disponible. Activa depuracion USB y acepta la autorizacion dentro del visor.' }
    if ($needsBuild) {
        $env:ANDROID_HOME = $sdk
        $env:ANDROID_SDK_ROOT = $sdk
        $log = $env:BUILD_LOG
        if (-not $log) { $log = Join-Path $env:TEMP "vr_objectgallery_$($Target.ToLowerInvariant())_build.log" }
        New-Item -ItemType Directory -Path (Split-Path $apkPath -Parent) -Force | Out-Null
        Write-Host "Exportando '$presetName'. Log: $log"
        $ErrorActionPreference = 'Continue'
        & $godot --headless --path $root --export-debug $presetName $apkPath 2>&1 | Tee-Object -FilePath $log
        $buildExit = $LASTEXITCODE
        $ErrorActionPreference = 'Stop'
        if ($buildExit -ne 0 -or -not (Test-Path -LiteralPath $apkPath -PathType Leaf)) { throw "La exportacion fallo. Revisa $log" }
    }
    Invoke-Adb -s $serial install -r $apkPath
    Invoke-Adb -s $serial shell monkey -p $packageName -c android.intent.category.LAUNCHER 1
    Write-Host 'Despliegue completado.'
    exit 0
} catch {
    [Console]::Error.WriteLine("ERROR: " + $_.Exception.Message)
    exit 1
}

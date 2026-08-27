param(
    [ValidateRange(1,4)][int]$Category,
    [ValidateRange(1,5)][int]$Slot,
    [string]$RoutePath = '',
    [Parameter(Mandatory = $true)][string]$ConfigPath,
    [Parameter(Mandatory = $true)][string]$ResultPath
)

$ErrorActionPreference = 'Stop'
$strictUtf8 = [Text.UTF8Encoding]::new($false, $true)
$utf8Bom = [Text.UTF8Encoding]::new($true)

function Write-Result([string]$Status, [string]$Detail = '') {
    $directory = [IO.Path]::GetDirectoryName($ResultPath)
    [IO.Directory]::CreateDirectory($directory) | Out-Null
    $safeDetail = ($Detail -replace '[\r\n]', ' ').Trim()
    $temporary = Join-Path $directory ('.launcher-run.' + [Guid]::NewGuid().ToString('N') + '.tmp')
    try {
        $payload = @('Version=1', "Status=$Status", "Category=$Category", "Slot=$Slot", "Detail=$safeDetail", '') -join [Environment]::NewLine
        [IO.File]::WriteAllText($temporary, $payload, $utf8Bom)
        if ([IO.File]::Exists($ResultPath)) {
            $rollback = Join-Path $directory ('.launcher-run.' + [Guid]::NewGuid().ToString('N') + '.rollback')
            try { [IO.File]::Replace($temporary, $ResultPath, $rollback, $true) }
            finally { if ([IO.File]::Exists($rollback)) { Remove-Item -LiteralPath $rollback -Force -ErrorAction SilentlyContinue } }
        }
        else { [IO.File]::Move($temporary, $ResultPath) }
    }
    finally { if ([IO.File]::Exists($temporary)) { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue } }
}

try {
    if (-not [string]::IsNullOrWhiteSpace($RoutePath)) {
        if (-not [IO.File]::Exists($RoutePath)) { Write-Result 'route_error'; exit 2 }
        $route = @{}
        foreach ($line in [IO.File]::ReadAllLines($RoutePath, [Text.Encoding]::UTF8)) {
            if ($line -match '^([^=]+)=(.*)$') { $route[$matches[1]] = $matches[2] }
        }
        $routeCategory = 0
        $routeSlot = 0
        if ($route['Version'] -ne '1' -or -not [int]::TryParse([string]$route['Category'], [ref]$routeCategory) -or -not [int]::TryParse([string]$route['Slot'], [ref]$routeSlot) -or $routeCategory -lt 1 -or $routeCategory -gt 4 -or $routeSlot -lt 1 -or $routeSlot -gt 5) {
            Write-Result 'route_error'
            exit 2
        }
        $Category = $routeCategory
        $Slot = $routeSlot
    }
    if (-not [IO.File]::Exists($ConfigPath)) { Write-Result 'config_error'; exit 2 }
    $map = @{}
    foreach ($line in [IO.File]::ReadAllLines($ConfigPath, [Text.Encoding]::UTF8)) {
        if ($line -match '^([^=]+)=(.*)$') { $map[$matches[1]] = $matches[2] }
    }
    $encoded = [string]$map["Slot${Category}_${Slot}Command"]
    if ([string]::IsNullOrWhiteSpace($encoded)) { Write-Result 'not_configured'; exit 3 }
    try { $command = $strictUtf8.GetString([Convert]::FromBase64String($encoded)) }
    catch { Write-Result 'config_error'; exit 2 }
    if ([string]::IsNullOrWhiteSpace($command)) { Write-Result 'not_configured'; exit 3 }
    $isUri = $command -match '^(?i:https?|mailto):'
    if (-not $isUri -and -not [IO.File]::Exists($command)) { Write-Result 'missing'; exit 4 }
    $startInfo = New-Object Diagnostics.ProcessStartInfo
    $startInfo.FileName = $command
    $startInfo.UseShellExecute = $true
    [void][Diagnostics.Process]::Start($startInfo)
    Write-Result 'ok'
}
catch {
    Write-Result 'error' $_.Exception.Message
    exit 1
}

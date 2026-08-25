param(
    [ValidateRange(1,4)][int]$Category,
    [ValidateRange(1,5)][int]$Slot,
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
        [IO.File]::WriteAllText($temporary, "Version=1`r`nStatus=$Status`r`nDetail=$safeDetail`r`n", $utf8Bom)
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
    Start-Process -FilePath $command | Out-Null
    Write-Result 'ok'
}
catch {
    Write-Result 'error' $_.Exception.Message
    exit 1
}

param(
    [string]$Server = 'http://localhost:5600',
    [string]$OutputInc = (Join-Path $PSScriptRoot '..\Data\activitywatch.inc'),
    [string]$CacheJson = (Join-Path $PSScriptRoot '..\Data\activitywatch_cache.json'),
    [int]$BarWidth = 110
)

$ErrorActionPreference = 'Stop'
$utf8NoBom = New-Object Text.UTF8Encoding($false)

function Get-FriendlyAppName {
    param([string]$Name)
    switch -Regex ($Name) {
        '^(msedge|chrome|firefox|brave|opera|vivaldi)(\.exe)?$' { return 'Browser' }
        '^(Code|Code - Insiders)(\.exe)?$' { return 'VS Code' }
        '^(Unity|Unity Hub)(\.exe)?$' { return 'Unity' }
        '^Discord(\.exe)?$' { return 'Discord' }
        '^explorer(\.exe)?$' { return 'Explorer' }
        '^WindowsTerminal(\.exe)?$' { return 'Terminal' }
        '^ApplicationFrameHost(\.exe)?$' { return 'Windows Apps' }
        '^Rainmeter(\.exe)?$' { return 'Rainmeter' }
        '^(wallpaper32|wallpaper64|wallpaperui|wallpaper)(\.exe)?$' { return 'Wallpaper Engine' }
        '^(LeagueClient|League of Legends)(\.exe)?$' { return 'League of Legends' }
        '^LeagueClientUx(Render)?(\.exe)?$' { return 'Riot Client' }
        '^steamwebhelper(\.exe)?$' { return 'Steam' }
        '^ChatGPT(\.exe)?$' { return 'ChatGPT' }
        default {
            $clean = [IO.Path]::GetFileNameWithoutExtension($Name)
            if ([string]::IsNullOrWhiteSpace($clean)) { return 'Unknown' }
            return $clean
        }
    }
}

function Format-Duration {
    param([double]$Seconds)
    $minutes = [Math]::Max(1, [Math]::Floor($Seconds / 60))
    if ($minutes -ge 60) { return ('{0}h {1}m' -f [Math]::Floor($minutes / 60), ($minutes % 60)) }
    return ('{0}m' -f $minutes)
}

function Write-AtomicText {
    param([string]$Path, [string]$Text, [Text.Encoding]$Encoding, [scriptblock]$Validator)
    $directory = Split-Path -Parent $Path
    [IO.Directory]::CreateDirectory($directory) | Out-Null
    $temporary = Join-Path $directory ('.' + [IO.Path]::GetFileName($Path) + '.' + [Guid]::NewGuid().ToString('N') + '.tmp')
    $backup = $Path + '.bak'
    try {
        [IO.File]::WriteAllText($temporary, $Text, $Encoding)
        $check = [IO.File]::ReadAllText($temporary, $Encoding)
        if (-not (& $Validator $check)) { throw ('Validation failed for ' + $Path) }
        if (Test-Path -LiteralPath $Path) {
            if (Test-Path -LiteralPath $backup) { Remove-Item -LiteralPath $backup -Force }
            [IO.File]::Replace($temporary, $Path, $backup)
            if (Test-Path -LiteralPath $backup) { Remove-Item -LiteralPath $backup -Force }
        }
        else { [IO.File]::Move($temporary, $Path) }
    }
    finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
    }
}

function Read-PreviousCache {
    $apps = @()
    $updatedEpoch = 0
    if (Test-Path -LiteralPath $CacheJson) {
        try {
            $json = Get-Content -LiteralPath $CacheJson -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($null -ne $json.apps) {
                $apps = @($json.apps)
                $updatedEpoch = [long]$json.updatedEpoch
            }
            else { $apps = @($json) }
        }
        catch {}
    }
    if ($updatedEpoch -le 0 -and (Test-Path -LiteralPath $OutputInc)) {
        $stamp = [DateTimeOffset](Get-Item -LiteralPath $OutputInc).LastWriteTime
        $updatedEpoch = $stamp.ToUnixTimeSeconds()
    }
    return [pscustomobject]@{ Apps = $apps; UpdatedEpoch = $updatedEpoch }
}

function Build-IncLines {
    param([object[]]$Apps, [int]$StateCode, [string]$Status, [long]$UpdatedEpoch, [long]$AttemptEpoch)
    $hasData = @($Apps).Count -gt 0
    $updatedText = if ($UpdatedEpoch -gt 0) { '最後更新 ' + [DateTimeOffset]::FromUnixTimeSeconds($UpdatedEpoch).LocalDateTime.ToString('HH:mm') } else { '尚未更新' }
    $lines = @(
        '[Variables]',
        ('UsageStateCode=' + $StateCode),
        ('UsageStatus=' + $Status),
        ('UsageHasData=' + [int]$hasData),
        ('UsageUpdatedEpoch=' + $UpdatedEpoch),
        ('UsageAttemptEpoch=' + $AttemptEpoch),
        ('UsageUpdated=' + $updatedText)
    )
    $maximum = if ($hasData) { [double]$Apps[0].seconds } else { 1.0 }
    for ($i = 1; $i -le 5; $i++) {
        if ($i -le @($Apps).Count) {
            $entry = $Apps[$i - 1]
            $name = ([string]$entry.app -replace '[\r\n=#;]', ' ').Trim()
            $seconds = [double]$entry.seconds
            $bar = [Math]::Round($BarWidth * ($seconds / [Math]::Max(1.0, $maximum)))
            $lines += "App$($i)Name=$name"
            $lines += "App$($i)Time=$(Format-Duration $seconds)"
            $lines += "App$($i)Bar=$bar"
        }
        else {
            $lines += "App$($i)Name=—"
            $lines += "App$($i)Time=0m"
            $lines += "App$($i)Bar=0"
        }
    }
    return $lines
}

function Commit-Cache {
    param([object[]]$Apps, [string]$State, [int]$StateCode, [string]$Status, [long]$UpdatedEpoch, [long]$AttemptEpoch)
    $inc = (Build-IncLines $Apps $StateCode $Status $UpdatedEpoch $AttemptEpoch) -join [Environment]::NewLine
    $inc += [Environment]::NewLine
    Write-AtomicText $OutputInc $inc ([Text.Encoding]::Unicode) {
        param($text)
        return $text.Contains('UsageStateCode=') -and $text.Contains('App1Name=') -and $text.Contains('UsageUpdatedEpoch=')
    }
    $cacheObject = [pscustomobject]@{ state = $State; updatedEpoch = $UpdatedEpoch; attemptEpoch = $AttemptEpoch; apps = @($Apps) }
    $json = $cacheObject | ConvertTo-Json -Depth 4
    Write-AtomicText $CacheJson $json $utf8NoBom {
        param($text)
        try { $null = $text | ConvertFrom-Json; return $true } catch { return $false }
    }
}

$previous = Read-PreviousCache
$attemptEpoch = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
try {
    $buckets = Invoke-RestMethod -Uri "$Server/api/0/buckets/" -TimeoutSec 5
    $windowBucket = $buckets.PSObject.Properties | Where-Object { $_.Value.type -eq 'currentwindow' } | Select-Object -First 1
    if (-not $windowBucket) { throw 'currentwindow bucket not found' }
    $start = (Get-Date).Date.ToUniversalTime().ToString('o')
    $end = (Get-Date).ToUniversalTime().ToString('o')
    $bucketId = [Uri]::EscapeDataString($windowBucket.Name)
    $requestUri = "$Server/api/0/buckets/$bucketId/events?start=$([Uri]::EscapeDataString($start))&end=$([Uri]::EscapeDataString($end))&limit=-1"
    $events = Invoke-RestMethod -Uri $requestUri -TimeoutSec 20
    $totals = @{}
    foreach ($event in $events) {
        if (-not $event.data.app) { continue }
        $friendly = Get-FriendlyAppName ([string]$event.data.app)
        if (-not $totals.ContainsKey($friendly)) { $totals[$friendly] = 0.0 }
        $totals[$friendly] += [double]$event.duration
    }
    $apps = @($totals.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 5 | ForEach-Object {
        [pscustomobject]@{ app = [string]$_.Key; seconds = [Math]::Round([double]$_.Value, 2) }
    })
    $status = if ($apps.Count -gt 0) { '已更新' } else { '今日尚無使用資料' }
    Commit-Cache $apps 'Fresh' 1 $status $attemptEpoch $attemptEpoch
    exit 0
}
catch {
    $apps = @($previous.Apps)
    if ($apps.Count -gt 0) {
        Commit-Cache $apps 'OfflineWithLastKnownGood' 2 'ActivityWatch 離線・顯示最後資料' ([long]$previous.UpdatedEpoch) $attemptEpoch
    }
    else {
        Commit-Cache @() 'OfflineWithNoPreviousData' 3 'ActivityWatch 離線・沒有可用資料' 0 $attemptEpoch
    }
    Write-Error $_.Exception.Message
    exit 1
}

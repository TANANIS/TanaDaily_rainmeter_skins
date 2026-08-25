param(
    [Parameter(Mandatory = $true)][string]$InputPath,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [Parameter(Mandatory = $true)][string]$RenderPath
)

$ErrorActionPreference = 'Stop'
$strictUtf8 = [Text.UTF8Encoding]::new($false, $true)
$utf8Bom = [Text.UTF8Encoding]::new($true, $true)
$utf8NoBom = [Text.UTF8Encoding]::new($false, $true)
$cp950 = [Text.Encoding]::GetEncoding(950, [Text.EncoderExceptionFallback]::ExceptionFallback, [Text.DecoderExceptionFallback]::ExceptionFallback)

function Get-Sha256Hex {
    param([byte[]]$Bytes)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '') }
    finally { $sha.Dispose() }
}

function Read-SourceFile {
    param([string]$Path)
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        return [pscustomobject]@{ Text = [Text.Encoding]::Unicode.GetString($bytes, 2, $bytes.Length - 2); Encoding = 'utf16le-bom'; Bytes = $bytes }
    }
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        return [pscustomobject]@{ Text = $strictUtf8.GetString($bytes, 3, $bytes.Length - 3); Encoding = 'utf8-bom'; Bytes = $bytes }
    }
    try {
        return [pscustomobject]@{ Text = $strictUtf8.GetString($bytes); Encoding = 'utf8'; Bytes = $bytes }
    }
    catch {
        return [pscustomobject]@{ Text = $cp950.GetString($bytes); Encoding = 'cp950'; Bytes = $bytes }
    }
}

function Write-ValidatedCache {
    param([string[]]$Lines)
    $directory = Split-Path -Parent $OutputPath
    [IO.Directory]::CreateDirectory($directory) | Out-Null
    $temporary = Join-Path $directory ('.tasks.cache.' + [Guid]::NewGuid().ToString('N') + '.tmp')
    try {
        $payload = ($Lines -join "`r`n") + "`r`n"
        [IO.File]::WriteAllText($temporary, $payload, $utf8Bom)
        $bytes = [IO.File]::ReadAllBytes($temporary)
        if ($bytes.Length -lt 3 -or $bytes[0] -ne 0xEF -or $bytes[1] -ne 0xBB -or $bytes[2] -ne 0xBF) { throw 'Cache BOM validation failed' }
        $check = $strictUtf8.GetString($bytes, 3, $bytes.Length - 3)
        if ($check -notmatch '^Version=2\r?\nStatus=(ok|partial|empty|missing|parse_error|bridge_error)\r?\n') { throw 'Cache validation failed' }
        if (Test-Path -LiteralPath $OutputPath) {
            $rollback = Join-Path $directory ('.tasks.cache.rollback.' + [Guid]::NewGuid().ToString('N') + '.tmp')
            try { [IO.File]::Replace($temporary, $OutputPath, $rollback) }
            finally { if (Test-Path -LiteralPath $rollback) { Remove-Item -LiteralPath $rollback -Force -ErrorAction SilentlyContinue } }
        }
        else { [IO.File]::Move($temporary, $OutputPath) }
    }
    finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
    }
}

function ConvertTo-RainmeterCharacterReferences {
    param([string]$Text)
    $builder = New-Object Text.StringBuilder
    foreach ($character in $Text.ToCharArray()) {
        [void]$builder.Append(('\u{0:X4}' -f [int]$character))
    }
    return $builder.ToString()
}

function Write-ValidatedRenderInclude {
    param([string]$SourceHash, [object[]]$Items)
    $directory = Split-Path -Parent $RenderPath
    [IO.Directory]::CreateDirectory($directory) | Out-Null
    $temporary = Join-Path $directory ('.tasks.render.' + [Guid]::NewGuid().ToString('N') + '.tmp')
    try {
        $lines = @($SourceHash)
        for ($i = 0; $i -lt 6; $i++) {
            $value = if ($i -lt $Items.Count) { ConvertTo-RainmeterCharacterReferences ([string]$Items[$i].Title) } else { '' }
            $lines += $value
        }
        $payload = ($lines -join "`r`n") + "`r`n"
        [IO.File]::WriteAllText($temporary, $payload, $utf8NoBom)
        $bytes = [IO.File]::ReadAllBytes($temporary)
        $check = $strictUtf8.GetString($bytes)
        if (($check -split "\r?\n").Count -lt 7) { throw 'Render cache validation failed' }
        if (Test-Path -LiteralPath $RenderPath) {
            $rollback = Join-Path $directory ('.tasks.render.rollback.' + [Guid]::NewGuid().ToString('N') + '.tmp')
            try { [IO.File]::Replace($temporary, $RenderPath, $rollback) }
            finally { if (Test-Path -LiteralPath $rollback) { Remove-Item -LiteralPath $rollback -Force -ErrorAction SilentlyContinue } }
        }
        else { [IO.File]::Move($temporary, $RenderPath) }
    }
    finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
    }
}

try {
    if (-not (Test-Path -LiteralPath $InputPath -PathType Leaf)) {
        Write-ValidatedCache @('Version=2', 'Status=missing', 'SourceHash=', 'SourceEncoding=', 'Count=0', 'Total=0')
        Write-ValidatedRenderInclude '' @()
        exit 0
    }

    $source = Read-SourceFile $InputPath
    $sourceHash = Get-Sha256Hex $source.Bytes
    $items = New-Object Collections.Generic.List[object]
    $malformed = 0
    $lineNumber = 0
    foreach ($rawLine in ($source.Text -split "\r\n|\n|\r", -1)) {
        $lineNumber++
        if ($rawLine -match '^\s*[-*+]\s*\\?\[([ xX])\\?\]\s*(.+?)\s*$') {
            $title = ($Matches[2] -replace '[\r\n\t]', ' ').Trim()
            if ($title) {
                $items.Add([pscustomobject]@{ Done = $Matches[1].ToLowerInvariant() -eq 'x'; Line = $lineNumber; Title = $title })
            }
        }
        elseif ($rawLine -match '^\s*[-*+]\s*') { $malformed++ }
    }

    if ($items.Count -eq 0) {
        $status = if ($malformed -gt 0) { 'parse_error' } else { 'empty' }
        Write-ValidatedCache @('Version=2', ('Status=' + $status), ('SourceHash=' + $sourceHash), ('SourceEncoding=' + $source.Encoding), 'Count=0', 'Total=0')
        Write-ValidatedRenderInclude $sourceHash @()
        exit 0
    }

    $status = if ($malformed -gt 0) { 'partial' } else { 'ok' }
    $visibleCount = [Math]::Min(6, $items.Count)
    $lines = @('Version=2', ('Status=' + $status), ('SourceHash=' + $sourceHash), ('SourceEncoding=' + $source.Encoding), ('Count=' + $visibleCount), ('Total=' + $items.Count))
    for ($i = 0; $i -lt $visibleCount; $i++) {
        $item = $items[$i]
        $lines += ('Item{0}={1}|{2}|{3}' -f ($i + 1), ([int]$item.Done), $item.Line, [string]$item.Title)
    }
    Write-ValidatedCache $lines
    Write-ValidatedRenderInclude $sourceHash @($items | Select-Object -First 6)
}
catch {
    try {
        Write-ValidatedCache @('Version=2', 'Status=bridge_error', 'SourceHash=', 'SourceEncoding=', 'Count=0', 'Total=0')
        Write-ValidatedRenderInclude '' @()
    } catch {}
    Write-Error $_.Exception.Message
    exit 1
}

param(
    [Parameter(Mandatory = $true)][string]$InputPath,
    [Parameter(Mandatory = $true)][string]$RequestPath,
    [Parameter(Mandatory = $true)][string]$ResultPath
)

$ErrorActionPreference = 'Stop'
$strictUtf8 = [Text.UTF8Encoding]::new($false, $true)
$utf8Bom = [Text.UTF8Encoding]::new($true, $true)
$temporarySource = $null
$replaceRollback = $null

function Get-Sha256Hex {
    param([byte[]]$Bytes)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '') }
    finally { $sha.Dispose() }
}

function Write-Result {
    param([string]$Status, [string]$Action = '', [string]$NewHash = '', [string]$Detail = '')
    $directory = Split-Path -Parent $ResultPath
    [IO.Directory]::CreateDirectory($directory) | Out-Null
    $temporary = Join-Path $directory ('.todo-result.' + [Guid]::NewGuid().ToString('N') + '.tmp')
    try {
        $safeDetail = ($Detail -replace '[\r\n]', ' ').Trim()
        $payload = @('Version=1', ('Status=' + $Status), ('Action=' + $Action), ('NewHash=' + $NewHash), ('Detail=' + $safeDetail)) -join "`r`n"
        [IO.File]::WriteAllText($temporary, $payload + "`r`n", $utf8Bom)
        if (Test-Path -LiteralPath $ResultPath) {
            $rollback = Join-Path $directory ('.todo-result.rollback.' + [Guid]::NewGuid().ToString('N') + '.tmp')
            try { [IO.File]::Replace($temporary, $ResultPath, $rollback) }
            finally { if (Test-Path -LiteralPath $rollback) { Remove-Item -LiteralPath $rollback -Force -ErrorAction SilentlyContinue } }
        }
        else { [IO.File]::Move($temporary, $ResultPath) }
    }
    finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue } }
}

function Read-KeyFile {
    param([string]$Path)
    $bytes = [IO.File]::ReadAllBytes($Path)
    $offset = if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { 3 } else { 0 }
    $text = $strictUtf8.GetString($bytes, $offset, $bytes.Length - $offset)
    $map = @{}
    foreach ($line in ($text -split "\r\n|\n|\r")) {
        if ($line -match '^([^=]+)=(.*)$') { $map[$Matches[1].Trim()] = $Matches[2] }
    }
    return $map
}

function Get-TaskRecords {
    param([string]$Text)
    $records = New-Object Collections.Generic.List[object]
    $number = 0
    foreach ($line in ($Text -split "\r\n|\n|\r", -1)) {
        $number++
        if ($line -match '^\s*[-*+]\s*\\?\[([ xX])\\?\]\s*(.+?)\s*$') {
            $records.Add([pscustomobject]@{ Line = $number; Done = $Matches[1].ToLowerInvariant() -eq 'x'; Title = $Matches[2] })
        }
    }
    return $records.ToArray()
}

function Insert-AfterLine {
    param([string]$Text, [int]$LineNumber, [string]$InsertedLine, [string]$LineBreak)
    $parts = [regex]::Split($Text, '(\r\n|\n|\r)')
    $lineIndex = ($LineNumber - 1) * 2
    if ($lineIndex -ge $parts.Count) { throw 'Insertion line is outside the document' }
    if (($lineIndex + 1) -lt $parts.Count -and $parts[$lineIndex + 1] -match '^(\r\n|\n|\r)$') {
        $head = ($parts[0..($lineIndex + 1)] -join '')
        $tail = if (($lineIndex + 2) -lt $parts.Count) { $parts[($lineIndex + 2)..($parts.Count - 1)] -join '' } else { '' }
        return $head + $InsertedLine + $LineBreak + $tail
    }
    return $Text + $LineBreak + $InsertedLine
}

function Toggle-Task {
    param([string]$Text, [int]$LineNumber)
    $parts = [regex]::Split($Text, '(\r\n|\n|\r)')
    $lineIndex = ($LineNumber - 1) * 2
    if ($lineIndex -ge $parts.Count) { throw 'invalid_task' }
    $line = $parts[$lineIndex]
    if ($line -notmatch '^(\s*[-*+]\s*\\?\[)([ xX])(\\?\]\s*.*)$') { throw 'invalid_task' }
    $newMarker = if ($Matches[2] -eq ' ') { 'x' } else { ' ' }
    $parts[$lineIndex] = $Matches[1] + $newMarker + $Matches[3]
    return ($parts -join '')
}

function Add-Task {
    param([string]$Text, [string]$Title)
    $newline = if ($Text.Contains("`r`n")) { "`r`n" } elseif ($Text.Contains("`n")) { "`n" } elseif ($Text.Contains("`r")) { "`r" } else { "`n" }
    $lines = $Text -split "\r\n|\n|\r", -1
    $todayLine = 0
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*#{1,6}\s+Today\s*$') { $todayLine = $i + 1; break }
    }

    if ($todayLine -eq 0) {
        $newTask = '- [ ] ' + $Title
        if ($Text.Length -eq 0) { return $newTask }
        if ($Text -match '(\r\n|\n|\r)$') { return $Text + $newTask + $newline }
        return $Text + $newline + $newTask
    }

    $sectionEnd = $lines.Count + 1
    for ($i = $todayLine; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*#{1,6}\s+') { $sectionEnd = $i + 1; break }
    }

    $lastTaskLine = 0
    $prefix = '- '
    $openEscape = ''
    $closeEscape = ''
    $spacing = ' '
    for ($lineNumber = $todayLine + 1; $lineNumber -lt $sectionEnd; $lineNumber++) {
        $line = $lines[$lineNumber - 1]
        if ($line -match '^(\s*[-*+]\s*)(\\?)\[([ xX])(\\?)\](\s*).*$') {
            $lastTaskLine = $lineNumber
            $prefix = $Matches[1]
            $openEscape = $Matches[2]
            $closeEscape = $Matches[4]
            $spacing = if ($Matches[5].Length -gt 0) { $Matches[5] } else { ' ' }
        }
    }

    $newTaskLine = $prefix + $openEscape + '[ ' + $closeEscape + ']' + $spacing + $Title
    $insertAfter = if ($lastTaskLine -gt 0) { $lastTaskLine } else { $todayLine }
    return Insert-AfterLine $Text $insertAfter $newTaskLine $newline
}

try {
    if (-not (Test-Path -LiteralPath $InputPath -PathType Leaf)) { Write-Result 'missing'; exit 2 }
    if (-not (Test-Path -LiteralPath $RequestPath -PathType Leaf)) { Write-Result 'invalid_request'; exit 2 }

    $request = Read-KeyFile $RequestPath
    if ($request['Version'] -ne '1') { Write-Result 'invalid_request'; exit 2 }
    $action = [string]$request['Action']
    if ($action -ne 'Toggle' -and $action -ne 'Add') { Write-Result 'invalid_request' $action; exit 2 }
    $expectedHash = ([string]$request['ExpectedHash']).ToUpperInvariant()

    $sourceBytes = [IO.File]::ReadAllBytes($InputPath)
    if ($sourceBytes.Length -lt 3 -or $sourceBytes[0] -ne 0xEF -or $sourceBytes[1] -ne 0xBB -or $sourceBytes[2] -ne 0xBF) { Write-Result 'encoding_error' $action; exit 3 }
    $sourceHash = Get-Sha256Hex $sourceBytes
    if ($sourceHash -ne $expectedHash) { Write-Result 'conflict' $action $sourceHash; exit 4 }
    $text = $strictUtf8.GetString($sourceBytes, 3, $sourceBytes.Length - 3)
    $beforeTasks = @(Get-TaskRecords $text)

    if ($action -eq 'Toggle') {
        $lineNumber = 0
        if (-not [int]::TryParse([string]$request['LineNumber'], [ref]$lineNumber) -or $lineNumber -lt 1) { Write-Result 'invalid_request' $action; exit 2 }
        try { $updatedText = Toggle-Task $text $lineNumber }
        catch { Write-Result 'invalid_task' $action; exit 5 }
        $afterTasks = @(Get-TaskRecords $updatedText)
        if ($afterTasks.Count -ne $beforeTasks.Count) { throw 'Toggle changed the task count' }
    }
    else {
        try { $titleBytes = [Convert]::FromBase64String([string]$request['TitleBase64']) }
        catch { Write-Result 'invalid_input' $action; exit 6 }
        try { $title = $strictUtf8.GetString($titleBytes).Trim() }
        catch { Write-Result 'invalid_input' $action; exit 6 }
        if ([string]::IsNullOrWhiteSpace($title) -or $title.Length -gt 200 -or $title -match '[\r\n\t\x00]') { Write-Result 'invalid_input' $action; exit 6 }
        $updatedText = Add-Task $text $title
        $afterTasks = @(Get-TaskRecords $updatedText)
        if ($afterTasks.Count -ne ($beforeTasks.Count + 1)) { throw 'Add validation did not produce exactly one task' }
        if ($afterTasks[-1].Title -ne $title -and -not ($afterTasks | Where-Object { $_.Title -eq $title })) { throw 'Added title validation failed' }
    }

    $directory = Split-Path -Parent $InputPath
    $temporarySource = Join-Path $directory ('.tasks.write.' + [Guid]::NewGuid().ToString('N') + '.tmp')
    [IO.File]::WriteAllText($temporarySource, $updatedText, $utf8Bom)
    $checkBytes = [IO.File]::ReadAllBytes($temporarySource)
    if ($checkBytes.Length -lt 3 -or $checkBytes[0] -ne 0xEF -or $checkBytes[1] -ne 0xBB -or $checkBytes[2] -ne 0xBF) { throw 'Temporary BOM validation failed' }
    $checkText = $strictUtf8.GetString($checkBytes, 3, $checkBytes.Length - 3)
    if ($checkText -ne $updatedText) { throw 'Temporary source validation failed' }

    $latestHash = Get-Sha256Hex ([IO.File]::ReadAllBytes($InputPath))
    if ($latestHash -ne $expectedHash) { Write-Result 'conflict' $action $latestHash; exit 4 }
    [IO.File]::Copy($InputPath, ($InputPath + '.bak'), $true)
    $replaceRollback = Join-Path $directory ('.tasks.rollback.' + [Guid]::NewGuid().ToString('N') + '.tmp')
    [IO.File]::Replace($temporarySource, $InputPath, $replaceRollback)
    $temporarySource = $null
    if (Test-Path -LiteralPath $replaceRollback) { Remove-Item -LiteralPath $replaceRollback -Force -ErrorAction SilentlyContinue }
    $replaceRollback = $null
    $finalBytes = [IO.File]::ReadAllBytes($InputPath)
    $finalHash = Get-Sha256Hex $finalBytes
    if ($finalHash -ne (Get-Sha256Hex $checkBytes)) { throw 'Post-replace hash validation failed' }
    Write-Result 'ok' $action $finalHash
    exit 0
}
catch {
    try { Write-Result 'write_error' '' '' $_.Exception.Message } catch {}
    Write-Error $_.Exception.Message
    exit 1
}
finally {
    if ($temporarySource -and (Test-Path -LiteralPath $temporarySource)) { Remove-Item -LiteralPath $temporarySource -Force -ErrorAction SilentlyContinue }
    if ($replaceRollback -and (Test-Path -LiteralPath $replaceRollback)) { Remove-Item -LiteralPath $replaceRollback -Force -ErrorAction SilentlyContinue }
}

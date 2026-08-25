param(
    [ValidateSet('slot','category')][string]$Mode = 'slot',
    [ValidateRange(1,4)][int]$Category = 1,
    [ValidateRange(0,5)][int]$Slot = 0,
    [Parameter(Mandatory = $true)][string]$ConfigPath,
    [Parameter(Mandatory = $true)][string]$ResultPath,
    [Parameter(Mandatory = $true)][string]$IconDirectory,
    [ValidateSet('','save','clear','cancel')][string]$TestAction = '',
    [string]$TestName = '',
    [string]$TestCommand = ''
)

$ErrorActionPreference = 'Stop'
$utf8Bom = New-Object Text.UTF8Encoding($true)

function Decode([string]$Value) {
    if ([string]::IsNullOrEmpty($Value)) { return '' }
    return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Value))
}
function Encode([string]$Value) { return [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes([string]$Value)) }

function Read-ConfigFile([string]$Path) {
    $map = [ordered]@{}
    foreach ($line in [IO.File]::ReadAllLines($Path, [Text.Encoding]::UTF8)) {
        if ($line -match '^([^=]+)=(.*)$') { $map[$matches[1]] = $matches[2] }
    }
    return $map
}

function Write-Result([string]$Status, [string]$Detail = '') {
    $directory = [IO.Path]::GetDirectoryName($ResultPath)
    [IO.Directory]::CreateDirectory($directory) | Out-Null
    $safeDetail = ($Detail -replace '[\r\n]', ' ').Trim()
    $payload = @('Version=1', "Status=$Status", "Mode=$Mode", "Category=$Category", "Slot=$Slot", "Detail=$safeDetail", '') -join "`r`n"
    $temporary = Join-Path $directory ('.launcher-result.' + [Guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [IO.File]::WriteAllText($temporary, $payload, $utf8Bom)
        if (Test-Path -LiteralPath $ResultPath) {
            $rollback = Join-Path $directory ('.launcher-result.' + [Guid]::NewGuid().ToString('N') + '.rollback')
            try { [IO.File]::Replace($temporary, $ResultPath, $rollback, $true) }
            finally { if (Test-Path -LiteralPath $rollback) { Remove-Item -LiteralPath $rollback -Force -ErrorAction SilentlyContinue } }
        }
        else { [IO.File]::Move($temporary, $ResultPath) }
    }
    finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue } }
}

function Save-Config($Map) {
    $directory = [IO.Path]::GetDirectoryName($ConfigPath)
    [IO.Directory]::CreateDirectory($directory) | Out-Null
    $lines = New-Object Collections.Generic.List[string]
    $lines.Add('[Launchers]')
    foreach ($key in $Map.Keys) { $lines.Add("$key=$($Map[$key])") }
    $temporary = Join-Path $directory ('.launchers.' + [Guid]::NewGuid().ToString('N') + '.tmp')
    $rollback = $null
    try {
        [IO.File]::WriteAllLines($temporary, $lines, $utf8Bom)
        $check = Read-ConfigFile $temporary
        if ($check['Version'] -ne '1') { throw 'Config version validation failed' }
        for ($i = 1; $i -le 4; $i++) { if (-not $check.Contains("Category$($i)Name")) { throw "Category $i is missing" } }
        if (Test-Path -LiteralPath $ConfigPath) {
            [IO.File]::Copy($ConfigPath, "$ConfigPath.bak", $true)
            $rollback = Join-Path $directory ('.launchers.' + [Guid]::NewGuid().ToString('N') + '.rollback')
            [IO.File]::Replace($temporary, $ConfigPath, $rollback, $true)
            if (Test-Path -LiteralPath $rollback) { Remove-Item -LiteralPath $rollback -Force }
            $rollback = $null
        }
        else { [IO.File]::Move($temporary, $ConfigPath) }
        $final = Read-ConfigFile $ConfigPath
        if ($final['Version'] -ne '1') { throw 'Post-write validation failed' }
    }
    finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
        if ($rollback -and (Test-Path -LiteralPath $rollback)) { Remove-Item -LiteralPath $rollback -Force -ErrorAction SilentlyContinue }
    }
}

function Apply-Theme([Windows.Forms.Control]$Root) {
    $Root.BackColor = [Drawing.Color]::FromArgb(38,38,42)
    $Root.ForeColor = [Drawing.Color]::FromArgb(232,232,236)
    foreach ($control in $Root.Controls) {
        if ($control -is [Windows.Forms.TextBox]) {
            $control.BackColor = [Drawing.Color]::FromArgb(25,25,29)
            $control.ForeColor = [Drawing.Color]::FromArgb(245,245,247)
            $control.BorderStyle = 'FixedSingle'
        }
        elseif ($control -is [Windows.Forms.Button]) {
            $control.FlatStyle = 'Flat'
            $control.FlatAppearance.BorderColor = [Drawing.Color]::FromArgb(92,92,102)
            $control.BackColor = [Drawing.Color]::FromArgb(52,52,59)
        }
        else { $control.BackColor = [Drawing.Color]::Transparent }
    }
}

function Set-CategoryName($Config, [string]$Value) {
    $name = $Value.Trim()
    if ([string]::IsNullOrWhiteSpace($name) -or $name.Length -gt 16) { throw [ArgumentException]::new('invalid_name') }
    $Config["Category$($Category)Name"] = Encode $name
    Save-Config $Config
}

function Set-LauncherSlot($Config, [string]$DisplayName, [string]$Command) {
    $name = $DisplayName.Trim()
    $cmd = $Command.Trim()
    if ([string]::IsNullOrWhiteSpace($name) -or $name.Length -gt 40 -or [string]::IsNullOrWhiteSpace($cmd)) { throw [ArgumentException]::new('invalid_input') }
    $kind = if ($cmd -match '^(https?|mailto):') { 'url' } else { 'file' }
    if ($kind -eq 'file' -and -not (Test-Path -LiteralPath $cmd -PathType Leaf)) { throw [IO.FileNotFoundException]::new('missing_file', $cmd) }

    $icon = ''
    if ($kind -eq 'file') {
        try {
            $source = $cmd
            if ([IO.Path]::GetExtension($cmd) -ieq '.lnk') {
                $shell = New-Object -ComObject WScript.Shell
                $target = $shell.CreateShortcut($cmd).TargetPath
                if (Test-Path -LiteralPath $target -PathType Leaf) { $source = $target }
            }
            $iconRoot = [IO.Path]::GetFullPath($IconDirectory)
            [IO.Directory]::CreateDirectory($iconRoot) | Out-Null
            $destination = Join-Path $iconRoot ("category$Category-slot$Slot.png")
            $associated = [Drawing.Icon]::ExtractAssociatedIcon($source)
            if ($associated) {
                $bitmap = $associated.ToBitmap()
                try { $bitmap.Save($destination, [Drawing.Imaging.ImageFormat]::Png) }
                finally { $bitmap.Dispose(); $associated.Dispose() }
                $icon = $destination
            }
        }
        catch { $icon = '' }
    }

    $key = "Slot$($Category)_$($Slot)"
    $Config["$($key)Name"] = Encode $name
    $Config["$($key)Command"] = Encode $cmd
    $Config["$($key)Icon"] = Encode $icon
    $Config["$($key)Kind"] = $kind
    Save-Config $Config
}

function Clear-LauncherSlot($Config) {
    $key = "Slot$($Category)_$($Slot)"
    $Config["$($key)Name"] = ''
    $Config["$($key)Command"] = ''
    $Config["$($key)Icon"] = ''
    $Config["$($key)Kind"] = 'empty'
    Save-Config $Config
}

try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) { throw [IO.FileNotFoundException]::new('config_missing', $ConfigPath) }
    $cfg = Read-ConfigFile $ConfigPath
    if ($cfg['Version'] -ne '1') { throw 'config_invalid' }

    if ($TestAction -ne '') {
        if ($TestAction -eq 'cancel') { Write-Result 'cancel'; exit 0 }
        if ($Mode -eq 'category') { Set-CategoryName $cfg $TestName; Write-Result 'ok'; exit 0 }
        if ($TestAction -eq 'clear') { Clear-LauncherSlot $cfg; Write-Result 'ok'; exit 0 }
        Set-LauncherSlot $cfg $TestName $TestCommand
        Write-Result 'ok'
        exit 0
    }

    $form = New-Object Windows.Forms.Form
    $form.Text = if ($Mode -eq 'category') { '重新命名分類' } else { '設定捷徑' }
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.ShowInTaskbar = $true
    $form.TopMost = $true
    $form.Width = 470
    $form.Height = if ($Mode -eq 'category') { 180 } else { 270 }

    $labelName = New-Object Windows.Forms.Label
    $labelName.Text = '顯示名稱'
    $labelName.SetBounds(18,18,110,22)
    $form.Controls.Add($labelName)
    $nameBox = New-Object Windows.Forms.TextBox
    $nameBox.SetBounds(130,16,300,25)
    $nameBox.MaxLength = if ($Mode -eq 'category') { 16 } else { 40 }
    $form.Controls.Add($nameBox)

    if ($Mode -eq 'category') {
        $nameBox.Text = Decode $cfg["Category$($Category)Name"]
        $save = New-Object Windows.Forms.Button; $save.Text = '儲存'; $save.SetBounds(250,75,85,30); $save.DialogResult = [Windows.Forms.DialogResult]::OK; $form.Controls.Add($save)
        $cancel = New-Object Windows.Forms.Button; $cancel.Text = '取消'; $cancel.SetBounds(345,75,85,30); $cancel.DialogResult = [Windows.Forms.DialogResult]::Cancel; $form.Controls.Add($cancel)
        $form.AcceptButton = $save; $form.CancelButton = $cancel; Apply-Theme $form
        $form.Add_Shown({ $form.Activate(); $form.BringToFront(); $nameBox.Select() })
        try { $dialog = $form.ShowDialog(); $enteredName = $nameBox.Text }
        finally { $form.Dispose() }
        if ($dialog -ne [Windows.Forms.DialogResult]::OK) { Write-Result 'cancel'; exit 0 }
        try { Set-CategoryName $cfg $enteredName }
        catch [ArgumentException] { Write-Result 'invalid_input'; exit 2 }
        Write-Result 'ok'; exit 0
    }

    $key = "Slot$($Category)_$($Slot)"
    $nameBox.Text = Decode $cfg["$($key)Name"]
    $labelCommand = New-Object Windows.Forms.Label; $labelCommand.Text = '程式、捷徑或 URL'; $labelCommand.SetBounds(18,63,110,22); $form.Controls.Add($labelCommand)
    $commandBox = New-Object Windows.Forms.TextBox; $commandBox.SetBounds(130,61,220,25); $commandBox.Text = Decode $cfg["$($key)Command"]; $form.Controls.Add($commandBox)
    $browse = New-Object Windows.Forms.Button; $browse.Text = '瀏覽'; $browse.SetBounds(360,59,70,29); $form.Controls.Add($browse)
    $browse.Add_Click({
        $picker = New-Object Windows.Forms.OpenFileDialog
        $picker.Filter = 'Programs and shortcuts (*.exe;*.lnk;*.url)|*.exe;*.lnk;*.url|All files (*.*)|*.*'
        if ($picker.ShowDialog() -eq [Windows.Forms.DialogResult]::OK) {
            $commandBox.Text = $picker.FileName
            if ([string]::IsNullOrWhiteSpace($nameBox.Text)) { $nameBox.Text = [IO.Path]::GetFileNameWithoutExtension($picker.FileName) }
        }
        $picker.Dispose()
    })
    $choose = New-Object Windows.Forms.Button; $choose.Text = '儲存'; $choose.SetBounds(155,145,85,30); $choose.DialogResult = [Windows.Forms.DialogResult]::OK; $form.Controls.Add($choose)
    $clear = New-Object Windows.Forms.Button; $clear.Text = '清除'; $clear.SetBounds(250,145,85,30); $clear.DialogResult = [Windows.Forms.DialogResult]::No; $form.Controls.Add($clear)
    $cancel = New-Object Windows.Forms.Button; $cancel.Text = '取消'; $cancel.SetBounds(345,145,85,30); $cancel.DialogResult = [Windows.Forms.DialogResult]::Cancel; $form.Controls.Add($cancel)
    $form.AcceptButton = $choose; $form.CancelButton = $cancel; Apply-Theme $form
    $form.Add_Shown({ $form.Activate(); $form.BringToFront(); $nameBox.Select() })
    try { $dialog = $form.ShowDialog(); $enteredName = $nameBox.Text; $enteredCommand = $commandBox.Text }
    finally { $form.Dispose() }

    if ($dialog -eq [Windows.Forms.DialogResult]::No) {
        if ([Windows.Forms.MessageBox]::Show('確定清除此捷徑？','Quick Launch','YesNo','Question') -eq [Windows.Forms.DialogResult]::Yes) { Clear-LauncherSlot $cfg; Write-Result 'ok' }
        else { Write-Result 'cancel' }
        exit 0
    }
    if ($dialog -ne [Windows.Forms.DialogResult]::OK) { Write-Result 'cancel'; exit 0 }
    try { Set-LauncherSlot $cfg $enteredName $enteredCommand }
    catch [ArgumentException] { [Windows.Forms.MessageBox]::Show('名稱與路徑不可空白。','Quick Launch','OK','Warning') | Out-Null; Write-Result 'invalid_input'; exit 2 }
    catch [IO.FileNotFoundException] { [Windows.Forms.MessageBox]::Show('找不到選取的檔案。','Quick Launch','OK','Warning') | Out-Null; Write-Result 'missing_file'; exit 3 }
    Write-Result 'ok'
}
catch [ArgumentException] {
    try { Write-Result 'invalid_input' $_.Exception.Message } catch { }
    exit 2
}
catch [IO.FileNotFoundException] {
    try { Write-Result 'missing_file' $_.Exception.Message } catch { }
    exit 3
}
catch {
    try { Write-Result 'error' ($_.Exception.GetType().Name + ': ' + $_.Exception.Message) } catch { }
    exit 1
}
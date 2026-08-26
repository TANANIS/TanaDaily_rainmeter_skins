param(
    [ValidateSet('slot','category')][string]$Mode = 'slot',
    [ValidateRange(1,4)][int]$Category = 1,
    [ValidateRange(0,5)][int]$Slot = 0,
    [string]$RoutePath = '',
    [Parameter(Mandatory = $true)][string]$ConfigPath,
    [Parameter(Mandatory = $true)][string]$ResultPath,
    [Parameter(Mandatory = $true)][string]$IconDirectory,
    [ValidateSet('','save','clear','cancel')][string]$TestAction = '',
    [string]$TestName = '',
    [string]$TestCommand = '',
    [switch]$InspectPanel,
    [string]$InspectImagePath = '',
    [switch]$InspectClearArmed
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

function Write-Result([string]$Status, [string]$Detail = '', [string]$Action = '') {
    $directory = [IO.Path]::GetDirectoryName($ResultPath)
    [IO.Directory]::CreateDirectory($directory) | Out-Null
    $safeDetail = ($Detail -replace '[\r\n]', ' ').Trim()
    $payload = @('Version=1', "Status=$Status", "Mode=$Mode", "Category=$Category", "Slot=$Slot", "Action=$Action", "Detail=$safeDetail", '') -join "`r`n"
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

function Save-PanelPreview([Windows.Forms.Form]$Panel) {
    if ([string]::IsNullOrWhiteSpace($InspectImagePath)) { return }
    $directory = [IO.Path]::GetDirectoryName($InspectImagePath)
    if (-not [string]::IsNullOrWhiteSpace($directory)) { [IO.Directory]::CreateDirectory($directory) | Out-Null }
    $Panel.CreateControl()
    $Panel.PerformLayout()
    $bitmap = New-Object Drawing.Bitmap($Panel.ClientSize.Width, $Panel.ClientSize.Height)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.Clear($Panel.BackColor)
        foreach ($control in $Panel.Controls) {
            $skipConfiguredOnly = $control.AccessibleName -like '清除此格*' -and -not [bool]$control.Tag
            if ($skipConfiguredOnly) { continue }
            $control.CreateControl()
            $control.DrawToBitmap($bitmap, $control.Bounds)
        }
        $bitmap.Save($InspectImagePath, [Drawing.Imaging.ImageFormat]::Png)
    }
    finally { $graphics.Dispose(); $bitmap.Dispose() }
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
    if ([string]::IsNullOrWhiteSpace($icon)) {
        $staleIcon = Join-Path ([IO.Path]::GetFullPath($IconDirectory)) ('category' + $Category + '-slot' + $Slot + '.png')
        if (Test-Path -LiteralPath $staleIcon -PathType Leaf) { Remove-Item -LiteralPath $staleIcon -Force -ErrorAction SilentlyContinue }
    }
}

function Clear-LauncherSlot($Config) {
    $key = "Slot$($Category)_$($Slot)"
    $Config["$($key)Name"] = ''
    $Config["$($key)Command"] = ''
    $Config["$($key)Icon"] = ''
    $Config["$($key)Kind"] = 'empty'
    Save-Config $Config
    $slotIcon = Join-Path ([IO.Path]::GetFullPath($IconDirectory)) ('category' + $Category + '-slot' + $Slot + '.png')
    if (Test-Path -LiteralPath $slotIcon -PathType Leaf) { Remove-Item -LiteralPath $slotIcon -Force -ErrorAction SilentlyContinue }
}

try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    if (-not [string]::IsNullOrWhiteSpace($RoutePath)) {
        if (-not (Test-Path -LiteralPath $RoutePath -PathType Leaf)) { throw [IO.FileNotFoundException]::new('route_missing', $RoutePath) }
        $route = Read-ConfigFile $RoutePath
        $routeCategory = 0
        $routeSlot = 0
        if ($route['Version'] -ne '1' -or $route['Mode'] -notin @('slot','category') -or -not [int]::TryParse([string]$route['Category'], [ref]$routeCategory) -or -not [int]::TryParse([string]$route['Slot'], [ref]$routeSlot)) { throw [ArgumentException]::new('route_invalid') }
        if ($routeCategory -lt 1 -or $routeCategory -gt 4 -or ($route['Mode'] -eq 'slot' -and ($routeSlot -lt 1 -or $routeSlot -gt 5)) -or ($route['Mode'] -eq 'category' -and $routeSlot -ne 0)) { throw [ArgumentException]::new('route_invalid') }
        $Mode = [string]$route['Mode']
        $Category = $routeCategory
        $Slot = $routeSlot
    }
    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) { throw [IO.FileNotFoundException]::new('config_missing', $ConfigPath) }
    $cfg = Read-ConfigFile $ConfigPath
    if ($cfg['Version'] -ne '1') { throw 'config_invalid' }

    if ($TestAction -ne '') {
        if ($TestAction -eq 'cancel') { Write-Result 'cancel'; exit 0 }
        if ($Mode -eq 'category') { Set-CategoryName $cfg $TestName; Write-Result 'ok' '' 'rename'; exit 0 }
        if ($TestAction -eq 'clear') { Clear-LauncherSlot $cfg; Write-Result 'ok' '' 'clear'; exit 0 }
        Set-LauncherSlot $cfg $TestName $TestCommand
        Write-Result 'ok' '' 'save'
        exit 0
    }

    $key = "Slot$($Category)_$($Slot)"
    $categoryName = Decode $cfg["Category$($Category)Name"]
    $currentName = if ($Mode -eq 'slot') { Decode $cfg["$($key)Name"] } else { Decode $cfg["Category$($Category)Name"] }
    $currentCommand = if ($Mode -eq 'slot') { Decode $cfg["$($key)Command"] } else { '' }
    $isConfigured = $Mode -eq 'slot' -and -not [string]::IsNullOrWhiteSpace($currentName) -and -not [string]::IsNullOrWhiteSpace($currentCommand)

    $form = New-Object Windows.Forms.Form
    $form.Text = if ($Mode -eq 'category') { '重新命名分類' } elseif ($isConfigured) { '編輯快速啟動' } else { '新增快速啟動' }
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.ShowInTaskbar = $false
    $form.TopMost = $true
    $form.Width = 540
    $form.Height = if ($Mode -eq 'category') { 245 } else { 355 }
    $form.Font = New-Object Drawing.Font('Segoe UI', 9)
    $form.Tag = 'cancel'

    $accent = [Drawing.Color]::FromArgb(126,131,224)
    $surface = [Drawing.Color]::FromArgb(43,43,48)
    $field = [Drawing.Color]::FromArgb(27,27,31)
    $textMain = [Drawing.Color]::FromArgb(244,244,246)
    $textMuted = [Drawing.Color]::FromArgb(180,180,188)
    $warning = [Drawing.Color]::FromArgb(226,177,105)

    $accentLine = New-Object Windows.Forms.Panel
    $accentLine.SetBounds(0,0,540,3)
    $accentLine.BackColor = $accent
    $form.Controls.Add($accentLine)

    $title = New-Object Windows.Forms.Label
    $title.Text = $form.Text
    $title.Font = New-Object Drawing.Font('Segoe UI Semibold', 15)
    $title.ForeColor = $textMain
    $title.SetBounds(24,20,470,32)
    $form.Controls.Add($title)

    $context = New-Object Windows.Forms.Label
    $context.Text = if ($Mode -eq 'category') { "分類 $Category" } else { "$categoryName  ·  位置 $Slot" }
    $context.ForeColor = $textMuted
    $context.SetBounds(26,54,460,22)
    $form.Controls.Add($context)

    $labelName = New-Object Windows.Forms.Label
    $labelName.Text = if ($Mode -eq 'category') { '分類名稱' } else { '顯示名稱' }
    $labelName.ForeColor = $textMuted
    $labelName.SetBounds(26,88,110,22)
    $form.Controls.Add($labelName)

    $nameBox = New-Object Windows.Forms.TextBox
    $nameBox.SetBounds(26,112,480,29)
    $nameBox.MaxLength = if ($Mode -eq 'category') { 16 } else { 40 }
    $nameBox.Text = $currentName
    $nameBox.AccessibleName = $labelName.Text
    $form.Controls.Add($nameBox)

    $errorY = if ($Mode -eq 'category') { 146 } else { 240 }
    $errorH = if ($Mode -eq 'category') { 22 } else { 28 }
    $buttonY = if ($Mode -eq 'category') { 171 } else { 274 }

    $errorLabel = New-Object Windows.Forms.Label
    $errorLabel.ForeColor = $warning
    $errorLabel.AutoEllipsis = $true
    $errorLabel.SetBounds(26,$errorY,480,$errorH)
    $form.Controls.Add($errorLabel)

    $cancel = New-Object Windows.Forms.Button
    $cancel.Text = '取消'
    $cancel.SetBounds(414,$buttonY,92,34)
    $cancel.AccessibleName = '取消，不儲存變更'
    $form.Controls.Add($cancel)

    $save = New-Object Windows.Forms.Button
    $save.Text = if ($Mode -eq 'category') { '儲存名稱' } elseif ($isConfigured) { '儲存變更' } else { '新增捷徑' }
    $save.SetBounds(306,$buttonY,98,34)
    $save.AccessibleName = $save.Text
    $form.Controls.Add($save)

    Apply-Theme $form
    $form.BackColor = $surface
    $nameBox.BackColor = $field
    $nameBox.ForeColor = $textMain
    $save.BackColor = $accent
    $save.ForeColor = [Drawing.Color]::White
    $save.FlatAppearance.BorderColor = $accent
    $cancel.BackColor = [Drawing.Color]::FromArgb(55,55,61)
    $accentLine.BackColor = $accent

    $cancel.Add_Click({ $form.Tag = 'cancel'; $form.Close() })
    $form.CancelButton = $cancel
    $form.AcceptButton = $save

    if ($Mode -eq 'category') {
        $save.Add_Click({
            try {
                Set-CategoryName $cfg $nameBox.Text
                $form.Tag = 'renamed'
                $form.Close()
            }
            catch [ArgumentException] { $errorLabel.Text = '請輸入 1–16 個字的分類名稱。'; $nameBox.Select() }
            catch { $errorLabel.Text = '無法儲存分類名稱，原設定未變更。' }
        })
        if ($InspectPanel) {
            if ($form.Text -ne '重新命名分類' -or $save.Text -ne '儲存名稱' -or $form.AcceptButton -ne $save -or $form.CancelButton -ne $cancel) { throw 'category_panel_invalid' }
            Save-PanelPreview $form; $form.Dispose(); Write-Result 'ok' 'panel=category;inlineValidation=1;messageBox=0'; exit 0
        }        $form.Add_Shown({ $form.Activate(); $form.BringToFront(); $nameBox.Select(); $nameBox.SelectAll() })
        try { [void]$form.ShowDialog(); $outcome = [string]$form.Tag }
        finally { $form.Dispose() }
        if ($outcome -eq 'renamed') { Write-Result 'ok' '' 'rename' } else { Write-Result 'cancel' }
        exit 0
    }

    $labelCommand = New-Object Windows.Forms.Label
    $labelCommand.Text = '程式、捷徑或網址'
    $labelCommand.ForeColor = $textMuted
    $labelCommand.SetBounds(26,154,170,22)
    $form.Controls.Add($labelCommand)

    $commandBox = New-Object Windows.Forms.TextBox
    $commandBox.SetBounds(26,178,384,29)
    $commandBox.Text = $currentCommand
    $commandBox.AccessibleName = '程式、捷徑或網址'
    $form.Controls.Add($commandBox)

    $browse = New-Object Windows.Forms.Button
    $browse.Text = '選擇檔案…'
    $browse.SetBounds(418,176,88,33)
    $browse.AccessibleName = '選擇 EXE LNK 或 URL 檔案'
    $form.Controls.Add($browse)

    $hint = New-Object Windows.Forms.Label
    $hint.Text = '支援 .exe、.lnk、.url，或直接貼上 https:// 網址'
    $hint.ForeColor = $textMuted
    $hint.SetBounds(28,211,470,20)
    $form.Controls.Add($hint)

    $clear = New-Object Windows.Forms.Button
    $clear.Text = '清除此格'
    $clear.SetBounds(26,274,96,34)
    $clear.Visible = $isConfigured
    $clear.Tag = [bool]$isConfigured
    $clear.AccessibleName = '清除此格，需要再次確認'
    $form.Controls.Add($clear)

    Apply-Theme $form
    $form.BackColor = $surface
    foreach ($box in @($nameBox,$commandBox)) { $box.BackColor = $field; $box.ForeColor = $textMain }
    $save.BackColor = $accent
    $save.ForeColor = [Drawing.Color]::White
    $save.FlatAppearance.BorderColor = $accent
    $cancel.BackColor = [Drawing.Color]::FromArgb(55,55,61)
    $accentLine.BackColor = $accent
    $browse.BackColor = [Drawing.Color]::FromArgb(55,55,61)
    $clear.BackColor = [Drawing.Color]::FromArgb(50,50,55)
    $clear.ForeColor = [Drawing.Color]::FromArgb(211,158,166)

    $resetClear = {
        if ([string]$form.Tag -eq 'clear-armed') {
            $form.Tag = 'cancel'
            $clear.Text = '清除此格'
            $clear.BackColor = [Drawing.Color]::FromArgb(50,50,55)
            $errorLabel.Text = ''
        }
    }
    $nameBox.Add_TextChanged($resetClear)
    $commandBox.Add_TextChanged($resetClear)

    $browse.Add_Click({
        & $resetClear
        $picker = New-Object Windows.Forms.OpenFileDialog
        try {
            $picker.Title = '選擇要加入的程式或捷徑'
            $picker.Filter = '程式與捷徑 (*.exe;*.lnk;*.url)|*.exe;*.lnk;*.url|所有檔案 (*.*)|*.*'
            $picker.CheckFileExists = $true
            if (-not [string]::IsNullOrWhiteSpace($commandBox.Text) -and (Test-Path -LiteralPath $commandBox.Text -PathType Leaf)) {
                $picker.InitialDirectory = [IO.Path]::GetDirectoryName($commandBox.Text)
                $picker.FileName = [IO.Path]::GetFileName($commandBox.Text)
            }
            if ($picker.ShowDialog($form) -eq [Windows.Forms.DialogResult]::OK) {
                $previousBase = if ([string]::IsNullOrWhiteSpace($currentCommand)) { '' } else { [IO.Path]::GetFileNameWithoutExtension($currentCommand) }
                $commandBox.Text = $picker.FileName
                if ([string]::IsNullOrWhiteSpace($nameBox.Text) -or $nameBox.Text -eq $previousBase) {
                    $nameBox.Text = [IO.Path]::GetFileNameWithoutExtension($picker.FileName)
                }
                $errorLabel.Text = ''
            }
        }
        finally { $picker.Dispose() }
    })

    $save.Add_Click({
        & $resetClear
        $name = $nameBox.Text.Trim()
        $command = $commandBox.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($name)) { $errorLabel.Text = '請輸入顯示名稱。'; $nameBox.Select(); return }
        if ([string]::IsNullOrWhiteSpace($command)) { $errorLabel.Text = '請選擇程式、捷徑，或貼上網址。'; $commandBox.Select(); return }
        if ($command -notmatch '^(?i:https?|mailto):' -and -not (Test-Path -LiteralPath $command -PathType Leaf)) {
            $errorLabel.Text = '找不到這個檔案，請重新選擇。'
            $commandBox.Select(); $commandBox.SelectAll(); return
        }
        try {
            Set-LauncherSlot $cfg $name $command
            $form.Tag = 'saved'
            $form.Close()
        }
        catch [ArgumentException] { $errorLabel.Text = '名稱需為 1–40 個字，且目標不可空白。' }
        catch [IO.FileNotFoundException] { $errorLabel.Text = '找不到這個檔案，請重新選擇。' }
        catch { $errorLabel.Text = '無法儲存；原捷徑設定保持不變。' }
    })

    $clear.Add_Click({
        if ([string]$form.Tag -ne 'clear-armed') {
            $form.Tag = 'clear-armed'
            $clear.Text = '確認清除'
            $clear.BackColor = [Drawing.Color]::FromArgb(125,67,75)
            $errorLabel.Text = '再次點擊「確認清除」才會移除此格；按取消可保留。'
            return
        }
        try {
            Clear-LauncherSlot $cfg
            $form.Tag = 'cleared'
            $form.Close()
        }
        catch { $form.Tag = 'cancel'; $errorLabel.Text = '無法清除；原捷徑設定保持不變。' }
    })

    if ($InspectClearArmed -and $isConfigured) {
        $form.Tag = 'clear-armed'
        $clear.Text = '確認清除'
        $clear.BackColor = [Drawing.Color]::FromArgb(125,67,75)
        $errorLabel.Text = '再次點擊「確認清除」才會移除此格；按取消可保留。'
    }
    if ($InspectPanel) {
        $expectedTitle = if ($isConfigured) { '編輯快速啟動' } else { '新增快速啟動' }
        $expectedSave = if ($isConfigured) { '儲存變更' } else { '新增捷徑' }
        if ($form.Text -ne $expectedTitle -or $save.Text -ne $expectedSave -or [bool]$clear.Tag -ne $isConfigured -or $form.AcceptButton -ne $save -or $form.CancelButton -ne $cancel) { throw 'slot_panel_invalid' }
        Save-PanelPreview $form; $form.Dispose(); Write-Result 'ok' ("panel=slot;configured=$isConfigured;inlineValidation=1;twoStepClear=1;messageBox=0"); exit 0
    }
    $form.Add_Shown({
        $form.Activate(); $form.BringToFront()
        if ($isConfigured) { $nameBox.Select(); $nameBox.SelectAll() } else { $browse.Select() }
    })
    try { [void]$form.ShowDialog(); $outcome = [string]$form.Tag }
    finally { $form.Dispose() }
    if ($outcome -eq 'saved') { Write-Result 'ok' '' 'save' } elseif ($outcome -eq 'cleared') { Write-Result 'ok' '' 'clear' } else { Write-Result 'cancel' }
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
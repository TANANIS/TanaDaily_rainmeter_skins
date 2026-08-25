param(
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [string]$TestTitle,
    [switch]$TestCancel
)

$ErrorActionPreference = 'Stop'
$utf8Bom = New-Object System.Text.UTF8Encoding($true)

function Write-Result {
    param([string]$Status, [string]$TitleBase64 = '', [string]$Detail = '')
    $directory = [IO.Path]::GetDirectoryName($OutputPath)
    if (-not [string]::IsNullOrWhiteSpace($directory)) { [IO.Directory]::CreateDirectory($directory) | Out-Null }
    $safeDetail = ($Detail -replace '[\r\n]', ' ').Trim()
    $content = @('Version=1', "Status=$Status", "TitleBase64=$TitleBase64", "Detail=$safeDetail", '') -join "`r`n"
    $temporary = Join-Path $directory ('.todo-input.' + [Guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [IO.File]::WriteAllText($temporary, $content, $utf8Bom)
        if ([IO.File]::Exists($OutputPath)) {
            $rollback = Join-Path $directory ('.todo-input.' + [Guid]::NewGuid().ToString('N') + '.rollback')
            try { [IO.File]::Replace($temporary, $OutputPath, $rollback, $true) }
            finally { if ([IO.File]::Exists($rollback)) { Remove-Item -LiteralPath $rollback -Force -ErrorAction SilentlyContinue } }
        }
        else { [IO.File]::Move($temporary, $OutputPath) }
    }
    finally { if ([IO.File]::Exists($temporary)) { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue } }
}

function Convert-TitleResult {
    param([string]$Value)
    $title = ([string]$Value).Trim()
    if ([string]::IsNullOrWhiteSpace($title) -or $title.Length -gt 200 -or $title.IndexOfAny(@([char]13, [char]10, [char]9, [char]0)) -ge 0) {
        Write-Result -Status 'invalid_input'
        return $false
    }
    Write-Result -Status 'ok' -TitleBase64 ([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($title)))
    return $true
}

try {
    if ($TestCancel) { Write-Result -Status 'cancel'; exit 0 }
    if ($PSBoundParameters.ContainsKey('TestTitle')) { if (Convert-TitleResult $TestTitle) { exit 0 } else { exit 2 } }

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $form = New-Object System.Windows.Forms.Form
    $form.Text = '新增任務'
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.ShowInTaskbar = $true
    $form.TopMost = $true
    $form.ClientSize = New-Object System.Drawing.Size(420, 126)
    $form.BackColor = [Drawing.Color]::FromArgb(43, 43, 43)
    $form.ForeColor = [Drawing.Color]::FromArgb(238, 238, 238)

    $label = New-Object System.Windows.Forms.Label
    $label.Text = '任務內容'
    $label.AutoSize = $true
    $label.Location = New-Object System.Drawing.Point(18, 16)
    $label.Font = New-Object System.Drawing.Font('Microsoft JhengHei UI', 9)
    $form.Controls.Add($label)

    $textBox = New-Object System.Windows.Forms.TextBox
    $textBox.Location = New-Object System.Drawing.Point(18, 42)
    $textBox.Size = New-Object System.Drawing.Size(384, 28)
    $textBox.Font = New-Object System.Drawing.Font('Microsoft JhengHei UI', 10)
    $textBox.MaxLength = 200
    $form.Controls.Add($textBox)

    $addButton = New-Object System.Windows.Forms.Button
    $addButton.Text = '新增'
    $addButton.DialogResult = [Windows.Forms.DialogResult]::OK
    $addButton.Location = New-Object System.Drawing.Point(246, 84)
    $addButton.Size = New-Object System.Drawing.Size(75, 28)
    $form.Controls.Add($addButton)

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Text = '取消'
    $cancelButton.DialogResult = [Windows.Forms.DialogResult]::Cancel
    $cancelButton.Location = New-Object System.Drawing.Point(327, 84)
    $cancelButton.Size = New-Object System.Drawing.Size(75, 28)
    $form.Controls.Add($cancelButton)

    $form.AcceptButton = $addButton
    $form.CancelButton = $cancelButton
    $form.Add_Shown({ $form.Activate(); $form.BringToFront(); $textBox.Select() })
    try { $dialogResult = $form.ShowDialog(); $enteredText = $textBox.Text }
    finally { $form.Dispose() }

    if ($dialogResult -ne [Windows.Forms.DialogResult]::OK) { Write-Result -Status 'cancel'; exit 0 }
    if (Convert-TitleResult $enteredText) { exit 0 } else { exit 2 }
}
catch {
    try { Write-Result -Status 'error' -Detail ($_.Exception.GetType().Name + ': ' + $_.Exception.Message) } catch { }
    exit 1
}
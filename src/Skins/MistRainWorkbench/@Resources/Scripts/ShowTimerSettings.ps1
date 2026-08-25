param(
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [Parameter(Mandatory = $true)][string]$DefaultNameBase64,
    [Parameter(Mandatory = $true)][int]$DefaultMinutes
)

$ErrorActionPreference = 'Stop'

function Write-Result {
    param([string]$Status, [string]$NameBase64 = '', [int]$Minutes = 0, [string]$Detail = '')
    $directory = [IO.Path]::GetDirectoryName($OutputPath)
    if ($directory) { [IO.Directory]::CreateDirectory($directory) | Out-Null }
    $content = @('Version=1', "Status=$Status", "NameBase64=$NameBase64", "Minutes=$Minutes", "Detail=$Detail", '') -join "`r`n"
    $encoding = New-Object Text.UTF8Encoding($true)
    $temporary = "$OutputPath.$([Guid]::NewGuid().ToString('N')).tmp"
    [IO.File]::WriteAllText($temporary, $content, $encoding)
    if ([IO.File]::Exists($OutputPath)) {
        $rollback = "$OutputPath.$([Guid]::NewGuid().ToString('N')).rollback"
        try { [IO.File]::Replace($temporary, $OutputPath, $rollback, $true) }
        finally { if ([IO.File]::Exists($rollback)) { Remove-Item -LiteralPath $rollback -Force } }
    }
    else { [IO.File]::Move($temporary, $OutputPath) }
}

try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $defaultName = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($DefaultNameBase64))

    $form = New-Object Windows.Forms.Form
    $form.Text = '計時器設定'
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.ShowInTaskbar = $false
    $form.TopMost = $true
    $form.ClientSize = New-Object Drawing.Size(390, 174)
    $form.BackColor = [Drawing.Color]::FromArgb(43, 43, 43)
    $form.ForeColor = [Drawing.Color]::FromArgb(238, 238, 238)

    $nameLabel = New-Object Windows.Forms.Label
    $nameLabel.Text = '名稱'
    $nameLabel.AutoSize = $true
    $nameLabel.Location = New-Object Drawing.Point(18, 18)
    $form.Controls.Add($nameLabel)
    $nameBox = New-Object Windows.Forms.TextBox
    $nameBox.Text = $defaultName
    $nameBox.MaxLength = 16
    $nameBox.Location = New-Object Drawing.Point(92, 15)
    $nameBox.Size = New-Object Drawing.Size(278, 28)
    $nameBox.Font = New-Object Drawing.Font('Microsoft JhengHei UI', 10)
    $form.Controls.Add($nameBox)

    $minutesLabel = New-Object Windows.Forms.Label
    $minutesLabel.Text = '分鐘'
    $minutesLabel.AutoSize = $true
    $minutesLabel.Location = New-Object Drawing.Point(18, 66)
    $form.Controls.Add($minutesLabel)
    $minutesBox = New-Object Windows.Forms.NumericUpDown
    $minutesBox.Minimum = 1
    $minutesBox.Maximum = 180
    $minutesBox.Value = [Math]::Max(1, [Math]::Min(180, $DefaultMinutes))
    $minutesBox.Location = New-Object Drawing.Point(92, 63)
    $minutesBox.Size = New-Object Drawing.Size(100, 28)
    $form.Controls.Add($minutesBox)

    $saveButton = New-Object Windows.Forms.Button
    $saveButton.Text = '儲存'
    $saveButton.DialogResult = [Windows.Forms.DialogResult]::OK
    $saveButton.Location = New-Object Drawing.Point(214, 126)
    $saveButton.Size = New-Object Drawing.Size(75, 28)
    $form.Controls.Add($saveButton)
    $cancelButton = New-Object Windows.Forms.Button
    $cancelButton.Text = '取消'
    $cancelButton.DialogResult = [Windows.Forms.DialogResult]::Cancel
    $cancelButton.Location = New-Object Drawing.Point(295, 126)
    $cancelButton.Size = New-Object Drawing.Size(75, 28)
    $form.Controls.Add($cancelButton)
    $form.AcceptButton = $saveButton
    $form.CancelButton = $cancelButton
    $form.Add_Shown({ $nameBox.SelectAll(); $nameBox.Focus() })

    if ($form.ShowDialog() -ne [Windows.Forms.DialogResult]::OK) { Write-Result -Status 'cancel'; exit 0 }
    $name = $nameBox.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($name) -or $name.Length -gt 16 -or $name.IndexOfAny(@([char]13,[char]10,[char]9,[char]0)) -ge 0) { Write-Result -Status 'invalid_input'; exit 0 }
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($name))
    Write-Result -Status 'ok' -NameBase64 $encoded -Minutes ([int]$minutesBox.Value)
}
catch {
    try { Write-Result -Status 'error' -Detail $_.Exception.GetType().Name } catch { }
    exit 1
}

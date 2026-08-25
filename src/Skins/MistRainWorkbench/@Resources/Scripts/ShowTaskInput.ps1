param(
    [Parameter(Mandatory = $true)]
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

function Write-Result {
    param(
        [Parameter(Mandatory = $true)][string]$Status,
        [string]$TitleBase64 = '',
        [string]$Detail = ''
    )

    $directory = [System.IO.Path]::GetDirectoryName($OutputPath)
    if (-not [string]::IsNullOrWhiteSpace($directory)) {
        [System.IO.Directory]::CreateDirectory($directory) | Out-Null
    }

    $content = @(
        'Version=1'
        "Status=$Status"
        "TitleBase64=$TitleBase64"
        "Detail=$Detail"
        ''
    ) -join "`r`n"

    $encoding = New-Object System.Text.UTF8Encoding($true)
    $temporary = "$OutputPath.$([Guid]::NewGuid().ToString('N')).tmp"
    [System.IO.File]::WriteAllText($temporary, $content, $encoding)
    if ([System.IO.File]::Exists($OutputPath)) {
        $rollback = "$OutputPath.$([Guid]::NewGuid().ToString('N')).rollback"
        try {
            [System.IO.File]::Replace($temporary, $OutputPath, $rollback, $true)
        }
        finally {
            if ([System.IO.File]::Exists($rollback)) { Remove-Item -LiteralPath $rollback -Force }
        }
    }
    else {
        [System.IO.File]::Move($temporary, $OutputPath)
    }
}

try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $form = New-Object System.Windows.Forms.Form
    $form.Text = '新增任務'
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.ShowInTaskbar = $false
    $form.TopMost = $true
    $form.ClientSize = New-Object System.Drawing.Size(420, 126)
    $form.BackColor = [System.Drawing.Color]::FromArgb(43, 43, 43)
    $form.ForeColor = [System.Drawing.Color]::FromArgb(238, 238, 238)

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
    $addButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $addButton.Location = New-Object System.Drawing.Point(246, 84)
    $addButton.Size = New-Object System.Drawing.Size(75, 28)
    $form.Controls.Add($addButton)

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Text = '取消'
    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $cancelButton.Location = New-Object System.Drawing.Point(327, 84)
    $cancelButton.Size = New-Object System.Drawing.Size(75, 28)
    $form.Controls.Add($cancelButton)

    $form.AcceptButton = $addButton
    $form.CancelButton = $cancelButton
    $form.Add_Shown({ $textBox.Focus() })

    $dialogResult = $form.ShowDialog()
    if ($dialogResult -ne [System.Windows.Forms.DialogResult]::OK) {
        Write-Result -Status 'cancel'
        exit 0
    }

    $title = $textBox.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($title) -or $title.Length -gt 200 -or $title.IndexOfAny(@([char]13, [char]10, [char]9, [char]0)) -ge 0) {
        Write-Result -Status 'invalid_input'
        exit 0
    }

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($title)
    Write-Result -Status 'ok' -TitleBase64 ([Convert]::ToBase64String($bytes))
}
catch {
    try { Write-Result -Status 'error' -Detail $_.Exception.GetType().Name } catch { }
    exit 1
}

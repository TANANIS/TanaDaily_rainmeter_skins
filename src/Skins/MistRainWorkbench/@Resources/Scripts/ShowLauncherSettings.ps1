param(
 [ValidateSet('slot','category')][string]$Mode='slot',
 [ValidateRange(1,4)][int]$Category=1,
 [ValidateRange(0,5)][int]$Slot=0,
 [Parameter(Mandatory=$true)][string]$ConfigPath,
 [Parameter(Mandatory=$true)][string]$ResultPath,
 [Parameter(Mandatory=$true)][string]$IconDirectory
)
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$utf8Bom=New-Object System.Text.UTF8Encoding($true)
function Apply-Theme([Windows.Forms.Control]$root){
 $root.BackColor=[Drawing.Color]::FromArgb(38,38,42)
 $root.ForeColor=[Drawing.Color]::FromArgb(232,232,236)
 foreach($control in $root.Controls){
  if($control -is [Windows.Forms.TextBox]){
   $control.BackColor=[Drawing.Color]::FromArgb(25,25,29)
   $control.ForeColor=[Drawing.Color]::FromArgb(245,245,247)
   $control.BorderStyle='FixedSingle'
  }elseif($control -is [Windows.Forms.Button]){
   $control.FlatStyle='Flat'
   $control.FlatAppearance.BorderColor=[Drawing.Color]::FromArgb(92,92,102)
   $control.BackColor=[Drawing.Color]::FromArgb(52,52,59)
  }else{$control.BackColor=[Drawing.Color]::Transparent}
 }
}
function Decode([string]$s){if([string]::IsNullOrEmpty($s)){return ''};[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($s))}
function Encode([string]$s){[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($s))}
function Read-Config{
 $map=[ordered]@{}
 foreach($line in [IO.File]::ReadAllLines($ConfigPath,[Text.Encoding]::UTF8)){if($line -match '^([^=]+)=(.*)$'){$map[$matches[1]]=$matches[2]}}
 return $map
}
function Save-Config($map){
 $lines=New-Object Collections.Generic.List[string]
 $lines.Add('[Launchers]'); foreach($key in $map.Keys){if($key -ne 'Launchers'){$lines.Add("$key=$($map[$key])")}}
 $temp=Join-Path ([IO.Path]::GetDirectoryName($ConfigPath)) ([IO.Path]::GetRandomFileName())
 [IO.File]::WriteAllLines($temp,$lines,$utf8Bom)
 $check=Read-ConfigFile $temp
 if($check['Version'] -ne '1'){Remove-Item -LiteralPath $temp -Force;throw 'Config validation failed'}
 [IO.File]::Replace($temp,$ConfigPath,"$ConfigPath.bak",$true)
}
function Read-ConfigFile([string]$path){
 $m=@{};foreach($line in [IO.File]::ReadAllLines($path,[Text.Encoding]::UTF8)){if($line -match '^([^=]+)=(.*)$'){$m[$matches[1]]=$matches[2]}};return $m
}
function Write-Result([string]$status){[IO.File]::WriteAllText($ResultPath,"Status=$status`r`n",$utf8Bom)}
$cfg=Read-Config
$form=New-Object Windows.Forms.Form
$form.Text=if($Mode -eq 'category'){'Rename category'}else{'Configure shortcut'}
$form.StartPosition='CenterScreen';$form.FormBorderStyle='FixedDialog';$form.MaximizeBox=$false;$form.MinimizeBox=$false;$form.TopMost=$true
$form.Width=470;$form.Height=if($Mode -eq 'category'){180}else{270}
$labelName=New-Object Windows.Forms.Label;$labelName.Text='Display name';$labelName.SetBounds(18,18,110,22);$form.Controls.Add($labelName)
$name=New-Object Windows.Forms.TextBox;$name.SetBounds(130,16,300,25);$form.Controls.Add($name)
if($Mode -eq 'category'){
 $key="Category$($Category)Name";$name.Text=Decode $cfg[$key]
 $save=New-Object Windows.Forms.Button;$save.Text='Save';$save.SetBounds(250,75,85,30);$save.DialogResult='OK';$form.Controls.Add($save)
 $cancel=New-Object Windows.Forms.Button;$cancel.Text='Cancel';$cancel.SetBounds(345,75,85,30);$cancel.DialogResult='Cancel';$form.Controls.Add($cancel)
 $form.AcceptButton=$save;$form.CancelButton=$cancel;Apply-Theme $form
 if($form.ShowDialog() -eq 'OK' -and -not [string]::IsNullOrWhiteSpace($name.Text)){$cfg[$key]=Encode $name.Text.Trim();Save-Config $cfg;Write-Result 'ok'}else{Write-Result 'cancel'}
 exit
}
$key="Slot$($Category)_$($Slot)";$name.Text=Decode $cfg["$($key)Name"]
$labelCommand=New-Object Windows.Forms.Label;$labelCommand.Text='Command / URL';$labelCommand.SetBounds(18,63,110,22);$form.Controls.Add($labelCommand)
$command=New-Object Windows.Forms.TextBox;$command.SetBounds(130,61,220,25);$command.Text=Decode $cfg["$($key)Command"];$form.Controls.Add($command)
$browse=New-Object Windows.Forms.Button;$browse.Text='Browse';$browse.SetBounds(360,59,70,29);$form.Controls.Add($browse)
$browse.Add_Click({
 $dlg=New-Object Windows.Forms.OpenFileDialog;$dlg.Filter='Programs and shortcuts (*.exe;*.lnk;*.url)|*.exe;*.lnk;*.url|All files (*.*)|*.*'
 if($dlg.ShowDialog() -eq 'OK'){$command.Text=$dlg.FileName;if([string]::IsNullOrWhiteSpace($name.Text)){$name.Text=[IO.Path]::GetFileNameWithoutExtension($dlg.FileName)}}
})
$save=New-Object Windows.Forms.Button;$save.Text='Choose';$save.SetBounds(155,145,85,30);$save.DialogResult='OK';$form.Controls.Add($save)
$clear=New-Object Windows.Forms.Button;$clear.Text='Clear';$clear.SetBounds(250,145,85,30);$clear.DialogResult='No';$form.Controls.Add($clear)
$cancel=New-Object Windows.Forms.Button;$cancel.Text='Cancel';$cancel.SetBounds(345,145,85,30);$cancel.DialogResult='Cancel';$form.Controls.Add($cancel)
$form.AcceptButton=$save;$form.CancelButton=$cancel;Apply-Theme $form
$result=$form.ShowDialog()
if($result -eq 'No'){
 if([Windows.Forms.MessageBox]::Show('Clear this shortcut?','Quick Launch','YesNo','Question') -eq 'Yes'){$cfg["$($key)Name"]='';$cfg["$($key)Command"]='';$cfg["$($key)Icon"]='';$cfg["$($key)Kind"]='empty';Save-Config $cfg;Write-Result 'ok'}else{Write-Result 'cancel'};exit
}
if($result -ne 'OK'){Write-Result 'cancel';exit}
$n=$name.Text.Trim();$cmd=$command.Text.Trim()
if([string]::IsNullOrWhiteSpace($n) -or [string]::IsNullOrWhiteSpace($cmd)){[Windows.Forms.MessageBox]::Show('Name and command are required.','Quick Launch','OK','Warning');Write-Result 'error';exit}
$kind=if($cmd -match '^(https?|mailto):'){'url'}else{'file'}
if($kind -eq 'file' -and -not (Test-Path -LiteralPath $cmd)){[Windows.Forms.MessageBox]::Show('The selected file does not exist.','Quick Launch','OK','Warning');Write-Result 'error';exit}
$icon=''
try{
 $source=$cmd
 if([IO.Path]::GetExtension($cmd) -ieq '.lnk'){$ws=New-Object -ComObject WScript.Shell;$target=$ws.CreateShortcut($cmd).TargetPath;if(Test-Path -LiteralPath $target){$source=$target}}
 if($kind -eq 'file'){$dir=[IO.Path]::GetFullPath($IconDirectory);[IO.Directory]::CreateDirectory($dir)|Out-Null;$dest=Join-Path $dir ("category$Category-slot$Slot.png");$ico=[Drawing.Icon]::ExtractAssociatedIcon($source);if($ico){$bmp=$ico.ToBitmap();$bmp.Save($dest,[Drawing.Imaging.ImageFormat]::Png);$bmp.Dispose();$ico.Dispose();$icon=$dest}}
}catch{}
$cfg["$($key)Name"]=Encode $n;$cfg["$($key)Command"]=Encode $cmd;$cfg["$($key)Icon"]=Encode $icon;$cfg["$($key)Kind"]=$kind
Save-Config $cfg;Write-Result 'ok'


# Setup.ps1 - one-click installer for the KenshiCoop co-op mod (this fork).
#
# Runs inside KenshiCoop-Setup.exe (built by installer/build_setup.ps1), next to
# payload.zip. Windows PowerShell 5.1 compatible: it must run on a stock Windows
# 10/11 PC with nothing else installed.
#
# Install:
#   1. find Steam's Kenshi (registry + libraryfolders.vdf), or let the player pick
#   2. refuse while Kenshi is running; check kenshi_x64.exe is Steam 1.0.65
#   3. back up saves, Plugins_x64.cfg, data\mods.cfg and any old mod folder
#   4. RE_Kenshi 0.3.5 if missing - the documented manual install: copy the
#      loose files, put Plugin=RE_Kenshi before the first Plugin= line
#   5. the mod into mods\KenshiCoop (an existing coop_config.json is kept)
#   6. KenshiCoop.mod into data\mods.cfg (other mods are untouched)
#   7. a fresh coop_config.json defaults to the Steam transport
# Uninstall reverses what this setup added (recorded in setup-record.json).
#
# Config files are read and written as Latin-1, a byte-for-byte round trip, so
# other mods' names survive whatever their encoding.
#
# Test hooks (not used by the .exe): -Unattended -Action install|uninstall
# -KenshiDir <folder> -SaveDir <folder> -BackupRoot <folder> -Payload <zip>.

[CmdletBinding()]
param(
    [switch]$Unattended,
    [ValidateSet('install', 'uninstall')][string]$Action = 'install',
    [string]$KenshiDir = '',
    [string]$SaveDir = '',
    [string]$BackupRoot = '',
    [string]$Payload = '',
    [switch]$SkipVersionCheck
)

$ErrorActionPreference = 'Stop'
$SetupVersion   = '0.1.32'
# kenshi_x64.exe of Steam Kenshi 1.0.65 (RE_Kenshi reports "Kenshi 1.0.65 / Steam / supported").
$KenshiExeSha256 = 'A596AB4E407C67B58599C54FFB32DC1BF2B64510CDEBD3FA9359EF05A576AEB1'
$KenshiAppId    = '233860'
$ModFiles       = @('KenshiCoop.dll', 'KenshiCoopUI.dll', 'KenshiCoop.mod', 'RE_Kenshi.json')
$ReKenshiFiles  = @('RE_Kenshi.dll', 'KenshiLib.dll', 'CompressToolsLib.dll')
$Latin1         = [Text.Encoding]::GetEncoding(28591)

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $Payload) { $Payload = Join-Path $here 'payload.zip' }
if (-not $SaveDir) { $SaveDir = Join-Path $env:LOCALAPPDATA 'kenshi\save' }
if (-not $BackupRoot) { $BackupRoot = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'KenshiCoop backups' }

# ---- output -----------------------------------------------------------------
$script:LogBox = $null
$script:LogLines = New-Object System.Collections.ArrayList
function Write-Log([string]$msg) {
    $line = '{0}  {1}' -f (Get-Date -Format 'HH:mm:ss'), $msg
    [void]$script:LogLines.Add($line)
    if ($script:LogBox) {
        $script:LogBox.AppendText($line + "`r`n")
        [System.Windows.Forms.Application]::DoEvents()
    } else {
        Write-Host $line
    }
}
function Show-Message([string]$text, [string]$title = 'KenshiCoop Setup', [string]$icon = 'Information') {
    if ($Unattended) { Write-Log "[$title] $text"; return }
    [void][System.Windows.Forms.MessageBox]::Show($text, $title, 'OK', $icon)
}
function Ask-YesNo([string]$text, [string]$title = 'KenshiCoop Setup') {
    if ($Unattended) { Write-Log "[$title] $text -> No (unattended)"; return $false }
    return ([System.Windows.Forms.MessageBox]::Show($text, $title, 'YesNo', 'Warning') -eq 'Yes')
}

# ---- text files, byte-exact -------------------------------------------------
function Read-Lines([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { return ,@() }
    $text = [IO.File]::ReadAllText($path, $Latin1)
    $lines = @($text -split "`r?`n")
    # Drop the empty element after a trailing newline. (Never slice 0..-1: in
    # PowerShell that range counts DOWN and would return two elements.)
    if ($lines.Count -gt 0 -and $lines[$lines.Count - 1] -eq '') {
        if ($lines.Count -eq 1) { $lines = @() } else { $lines = $lines[0..($lines.Count - 2)] }
    }
    return ,@($lines)
}
function Write-Lines([string]$path, [string[]]$lines) {
    # Keep the file's own line-ending style (Kenshi ships Plugins_x64.cfg with LF,
    # its launcher writes mods.cfg with CRLF); CRLF only for a brand-new file.
    $nl = "`r`n"
    if (Test-Path -LiteralPath $path) {
        $old = [IO.File]::ReadAllText($path, $Latin1)
        if ($old -notmatch "`r`n" -and $old -match "`n") { $nl = "`n" }
    }
    [IO.File]::WriteAllText($path, (($lines -join $nl) + $nl), $Latin1)
}

# ---- finding Kenshi ---------------------------------------------------------
function Find-SteamKenshi {
    $steam = $null
    try { $steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -Name SteamPath -ErrorAction Stop).SteamPath } catch { }
    if (-not $steam) { return $null }
    $steam = $steam -replace '/', '\'
    $libs = New-Object System.Collections.ArrayList
    [void]$libs.Add($steam)
    $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
    if (Test-Path -LiteralPath $vdf) {
        foreach ($m in [regex]::Matches([IO.File]::ReadAllText($vdf), '"path"\s+"([^"]+)"')) {
            [void]$libs.Add(($m.Groups[1].Value -replace '\\\\', '\'))
        }
    }
    foreach ($lib in $libs) {
        $acf = Join-Path $lib "steamapps\appmanifest_$KenshiAppId.acf"
        if (-not (Test-Path -LiteralPath $acf)) { continue }
        $dir = 'Kenshi'
        $m = [regex]::Match([IO.File]::ReadAllText($acf), '"installdir"\s+"([^"]+)"')
        if ($m.Success) { $dir = $m.Groups[1].Value }
        $path = Join-Path $lib "steamapps\common\$dir"
        if (Test-Path -LiteralPath (Join-Path $path 'kenshi_x64.exe')) { return $path }
    }
    return $null
}
function Test-KenshiFolder([string]$dir) {
    return ($dir -and (Test-Path -LiteralPath (Join-Path $dir 'kenshi_x64.exe')) -and
            (Test-Path -LiteralPath (Join-Path $dir 'Plugins_x64.cfg')))
}

# ---- checks -----------------------------------------------------------------
function Assert-KenshiClosed {
    while (Get-Process -Name 'kenshi_x64', 'kenshi' -ErrorAction SilentlyContinue) {
        if ($Unattended) { throw 'Kenshi is running.' }
        $r = [System.Windows.Forms.MessageBox]::Show(
            "Kenshi is running. Please close it completely, then click Retry.",
            'KenshiCoop Setup', 'RetryCancel', 'Warning')
        if ($r -ne 'Retry') { throw 'Cancelled: Kenshi is still running.' }
    }
}
function Assert-KenshiVersion([string]$dir) {
    if ($SkipVersionCheck) { Write-Log 'Version check skipped.'; return }
    $sha = (Get-FileHash -LiteralPath (Join-Path $dir 'kenshi_x64.exe') -Algorithm SHA256).Hash
    if ($sha -eq $KenshiExeSha256) { Write-Log 'Kenshi version: 1.0.65 (Steam) - supported.'; return }
    Write-Log "Kenshi version not recognised (kenshi_x64.exe sha256 $($sha.Substring(0,12))...)."
    $ok = Ask-YesNo ("This copy of Kenshi is not the Steam 1.0.65 version the co-op mod needs.`r`n`r`n" +
        "To fix it: in Steam, right-click Kenshi > Properties > Betas, choose 'None', let Steam " +
        "update, then run this setup again.`r`n`r`nContinue anyway? (The mod will probably not work.)")
    if (-not $ok) { throw 'Stopped: unsupported Kenshi version.' }
}

# ---- payload ----------------------------------------------------------------
function Expand-Payload {
    if (-not (Test-Path -LiteralPath $Payload)) { throw "Setup is incomplete: payload.zip not found next to Setup.ps1." }
    $dir = Join-Path ([IO.Path]::GetTempPath()) ('KenshiCoopSetup-' + [guid]::NewGuid().ToString('N'))
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::ExtractToDirectory($Payload, $dir)
    foreach ($f in $ModFiles) {
        if (-not (Test-Path -LiteralPath (Join-Path $dir "KenshiCoop\$f"))) { throw "Setup is incomplete: $f missing from payload." }
    }
    return $dir
}

# ---- backup -----------------------------------------------------------------
function New-Backup([string]$kenshi) {
    $stamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
    $dir = Join-Path $BackupRoot $stamp
    $n = 2
    while (Test-Path -LiteralPath $dir) { $dir = Join-Path $BackupRoot "$stamp-$n"; $n++ }   # never reuse a backup
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    foreach ($rel in @('Plugins_x64.cfg', 'data\mods.cfg')) {
        $src = Join-Path $kenshi $rel
        if (Test-Path -LiteralPath $src) { Copy-Item -LiteralPath $src -Destination (Join-Path $dir ($rel -replace '\\', '_')) }
    }
    $oldMod = Join-Path $kenshi 'mods\KenshiCoop'
    if (Test-Path -LiteralPath $oldMod) { Copy-Item -LiteralPath $oldMod -Destination (Join-Path $dir 'mods_KenshiCoop') -Recurse }
    if (Test-Path -LiteralPath $SaveDir) {
        Write-Log 'Backing up your saves (this can take a minute)...'
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [IO.Compression.ZipFile]::CreateFromDirectory($SaveDir, (Join-Path $dir 'saves.zip'))
    } else {
        Write-Log 'No Kenshi saves found to back up.'
    }
    Write-Log "Backup saved to: $dir"
    return $dir
}

# ---- install steps ----------------------------------------------------------
function Test-PluginLine([string[]]$lines) {
    foreach ($l in $lines) { if ($l -match '^\s*Plugin\s*=\s*RE_Kenshi\s*$') { return $true } }
    return $false
}
function Install-ReKenshi([string]$kenshi, [string]$stage) {
    $cfg = Join-Path $kenshi 'Plugins_x64.cfg'
    $lines = Read-Lines $cfg
    $haveDll = Test-Path -LiteralPath (Join-Path $kenshi 'RE_Kenshi.dll')
    $haveLine = Test-PluginLine $lines
    if ($haveDll -and $haveLine) { Write-Log 'RE_Kenshi is already installed - leaving it as it is.'; return $false }
    $copied = $false
    if (-not $haveDll) {
        Write-Log 'Installing RE_Kenshi 0.3.5...'
        $src = Join-Path $stage 'RE_Kenshi\install'
        foreach ($f in $ReKenshiFiles) { Copy-Item -LiteralPath (Join-Path $src $f) -Destination $kenshi -Force }
        Copy-Item -LiteralPath (Join-Path $src 'RE_Kenshi') -Destination $kenshi -Recurse -Force
        $copied = $true
    }
    if (-not $haveLine) {
        $out = New-Object System.Collections.ArrayList
        $done = $false
        foreach ($l in $lines) {
            if (-not $done -and $l -match '^\s*Plugin\s*=') { [void]$out.Add('Plugin=RE_Kenshi'); $done = $true }
            [void]$out.Add($l)
        }
        if (-not $done) { [void]$out.Add('Plugin=RE_Kenshi') }
        Write-Lines $cfg ([string[]]$out)
        Write-Log 'Registered RE_Kenshi in Plugins_x64.cfg.'
    }
    return $copied
}
function Install-Mod([string]$kenshi, [string]$stage) {
    $dest = Join-Path $kenshi 'mods\KenshiCoop'
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    foreach ($f in $ModFiles) { Copy-Item -LiteralPath (Join-Path $stage "KenshiCoop\$f") -Destination $dest -Force }
    $cfg = Join-Path $dest 'coop_config.json'
    if (-not (Test-Path -LiteralPath $cfg)) {
        [IO.File]::WriteAllText($cfg, "{`r`n  `"transport`": `"steam`"`r`n}`r`n", $Latin1)
        Write-Log 'Connection method set to Steam (no port forwarding needed).'
    } else {
        Write-Log 'Kept your existing co-op settings (coop_config.json).'
    }
    Write-Log "Installed KenshiCoop $SetupVersion into mods\KenshiCoop."
}
function Enable-Mod([string]$kenshi) {
    $data = Join-Path $kenshi 'data'
    New-Item -ItemType Directory -Force -Path $data | Out-Null
    $cfg = Join-Path $data 'mods.cfg'
    $lines = Read-Lines $cfg
    foreach ($l in $lines) { if ($l.Trim() -ieq 'KenshiCoop.mod') { Write-Log 'KenshiCoop was already enabled in the mod list.'; return } }
    Write-Lines $cfg ([string[]](@($lines) + 'KenshiCoop.mod'))
    Write-Log 'Enabled KenshiCoop in the mod list.'
}

# ---- record (for uninstall) ---------------------------------------------------
function Get-RecordPath([string]$kenshi) { return (Join-Path $kenshi 'mods\KenshiCoop\setup-record.json') }
function Save-Record([string]$kenshi, [bool]$installedReKenshi, [string]$backup) {
    $old = Read-Record $kenshi
    if ($old -and $old.installedReKenshi) { $installedReKenshi = $true }
    $rec = [ordered]@{ version = $SetupVersion; installedReKenshi = $installedReKenshi; backup = $backup;
                       installedAt = (Get-Date).ToString('s') }
    [IO.File]::WriteAllText((Get-RecordPath $kenshi), ($rec | ConvertTo-Json), $Latin1)
}
function Read-Record([string]$kenshi) {
    $p = Get-RecordPath $kenshi
    if (-not (Test-Path -LiteralPath $p)) { return $null }
    try { return ([IO.File]::ReadAllText($p, $Latin1) | ConvertFrom-Json) } catch { return $null }
}

# ---- actions ----------------------------------------------------------------
function Invoke-Install([string]$kenshi) {
    if (-not (Test-KenshiFolder $kenshi)) { throw "That folder is not a Kenshi installation: $kenshi" }
    Write-Log "Kenshi folder: $kenshi"
    Assert-KenshiClosed
    Assert-KenshiVersion $kenshi
    $stage = Expand-Payload
    try {
        $backup = New-Backup $kenshi
        $addedRe = Install-ReKenshi $kenshi $stage
        Install-Mod $kenshi $stage
        Enable-Mod $kenshi
        Save-Record $kenshi $addedRe $backup
        [IO.File]::WriteAllLines((Join-Path $backup 'setup-log.txt'), [string[]]$script:LogLines)
    } finally {
        Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Log 'All done!'
    Show-Message ("KenshiCoop is installed.`r`n`r`n" +
        "1. Start Kenshi from Steam as usual. The main menu should say 'RE_Kenshi v0.3.5'.`r`n" +
        "2. Load the same save as your friends, then press F2.`r`n" +
        "3. Host: choose Steam, click 'Copy Steam ID' and send it to your friends.`r`n" +
        "4. Friends: choose Steam, paste the host's Steam ID and connect.`r`n`r`n" +
        "Everyone needs this same setup. A backup of your saves is in:`r`n$BackupRoot")
}
function Invoke-Uninstall([string]$kenshi) {
    if (-not (Test-KenshiFolder $kenshi)) { throw "That folder is not a Kenshi installation: $kenshi" }
    Assert-KenshiClosed
    $rec = Read-Record $kenshi
    $mod = Join-Path $kenshi 'mods\KenshiCoop'
    if (Test-Path -LiteralPath $mod) { Remove-Item -LiteralPath $mod -Recurse -Force; Write-Log 'Removed mods\KenshiCoop.' }
    $cfg = Join-Path $kenshi 'data\mods.cfg'
    if (Test-Path -LiteralPath $cfg) {
        $lines = Read-Lines $cfg
        $kept = @($lines | Where-Object { $_.Trim() -ine 'KenshiCoop.mod' })
        if ($kept.Count -ne $lines.Count) { Write-Lines $cfg ([string[]]$kept); Write-Log 'Removed KenshiCoop from the mod list.' }
    }
    if ($rec -and $rec.installedReKenshi) {
        if ($Unattended -or (Ask-YesNo "This setup also installed RE_Kenshi. Remove RE_Kenshi too?`r`n(Choose No if other mods need it.)")) {
            $p = Join-Path $kenshi 'Plugins_x64.cfg'
            Write-Lines $p ([string[]]@((Read-Lines $p) | Where-Object { $_ -notmatch '^\s*Plugin\s*=\s*RE_Kenshi\s*$' }))
            foreach ($f in $ReKenshiFiles) { Remove-Item -LiteralPath (Join-Path $kenshi $f) -Force -ErrorAction SilentlyContinue }
            Remove-Item -LiteralPath (Join-Path $kenshi 'RE_Kenshi') -Recurse -Force -ErrorAction SilentlyContinue
            Write-Log 'Removed RE_Kenshi.'
        }
    }
    Write-Log 'Uninstall finished. Your saves and backups were not touched.'
    Show-Message 'KenshiCoop has been removed. Your saves and backups were not touched.'
}

# ---- entry ------------------------------------------------------------------
if (-not $KenshiDir) { $KenshiDir = Find-SteamKenshi }

if ($Unattended) {
    if (-not $KenshiDir) { throw 'Kenshi not found; pass -KenshiDir.' }
    if ($Action -eq 'install') { Invoke-Install $KenshiDir } else { Invoke-Uninstall $KenshiDir }
    return
}

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
$form = New-Object System.Windows.Forms.Form
$form.Text = "KenshiCoop Setup $SetupVersion"
$form.Size = New-Object System.Drawing.Size(600, 460)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false

$title = New-Object System.Windows.Forms.Label
$title.Text = 'KenshiCoop - play Kenshi together'
$title.Font = New-Object System.Drawing.Font('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)
$title.Location = New-Object System.Drawing.Point(16, 12); $title.AutoSize = $true
$form.Controls.Add($title)

$info = New-Object System.Windows.Forms.Label
$info.Text = 'Installs RE_Kenshi (if needed) and the co-op mod, and backs up your saves first. Close Kenshi before you start.'
$info.Location = New-Object System.Drawing.Point(18, 48); $info.Size = New-Object System.Drawing.Size(560, 36)
$form.Controls.Add($info)

$folder = New-Object System.Windows.Forms.Label
$folder.Location = New-Object System.Drawing.Point(18, 90); $folder.Size = New-Object System.Drawing.Size(450, 36)
$form.Controls.Add($folder)
function Update-FolderLabel {
    if ($script:KenshiDirUi) { $folder.Text = "Kenshi found:`r`n$script:KenshiDirUi" }
    else { $folder.Text = "Kenshi was not found automatically. Click 'Choose folder...' and pick your Kenshi folder." }
}
$script:KenshiDirUi = $KenshiDir
Update-FolderLabel

$browse = New-Object System.Windows.Forms.Button
$browse.Text = 'Choose folder...'; $browse.Location = New-Object System.Drawing.Point(474, 92); $browse.Size = New-Object System.Drawing.Size(100, 28)
$browse.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = 'Pick the Kenshi folder (the one that contains kenshi_x64.exe).'
    if ($dlg.ShowDialog() -eq 'OK') {
        if (Test-KenshiFolder $dlg.SelectedPath) { $script:KenshiDirUi = $dlg.SelectedPath; Update-FolderLabel }
        else { Show-Message 'That folder does not contain kenshi_x64.exe. Please pick the Kenshi folder.' 'KenshiCoop Setup' 'Warning' }
    }
})
$form.Controls.Add($browse)

$log = New-Object System.Windows.Forms.TextBox
$log.Multiline = $true; $log.ReadOnly = $true; $log.ScrollBars = 'Vertical'
$log.Location = New-Object System.Drawing.Point(18, 134); $log.Size = New-Object System.Drawing.Size(556, 230)
$form.Controls.Add($log)
$script:LogBox = $log

$install = New-Object System.Windows.Forms.Button
$install.Text = 'Install'; $install.Location = New-Object System.Drawing.Point(18, 376); $install.Size = New-Object System.Drawing.Size(140, 34)
$install.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
$uninstall = New-Object System.Windows.Forms.Button
$uninstall.Text = 'Uninstall'; $uninstall.Location = New-Object System.Drawing.Point(168, 376); $uninstall.Size = New-Object System.Drawing.Size(100, 34)
$close = New-Object System.Windows.Forms.Button
$close.Text = 'Close'; $close.Location = New-Object System.Drawing.Point(474, 376); $close.Size = New-Object System.Drawing.Size(100, 34)
$close.Add_Click({ $form.Close() })

function Invoke-Guarded([scriptblock]$work) {
    if (-not $script:KenshiDirUi) { Show-Message "Please choose your Kenshi folder first." 'KenshiCoop Setup' 'Warning'; return }
    $install.Enabled = $false; $uninstall.Enabled = $false; $browse.Enabled = $false
    try { & $work $script:KenshiDirUi }
    catch {
        Write-Log "ERROR: $($_.Exception.Message)"
        Show-Message ("Something went wrong:`r`n`r`n$($_.Exception.Message)`r`n`r`nNothing else was changed after this point. Your backups are in:`r`n$BackupRoot") 'KenshiCoop Setup' 'Error'
    }
    finally { $install.Enabled = $true; $uninstall.Enabled = $true; $browse.Enabled = $true }
}
$install.Add_Click({ Invoke-Guarded { param($d) Invoke-Install $d } })
$uninstall.Add_Click({
    if (Ask-YesNo 'Remove KenshiCoop from this Kenshi installation?') { Invoke-Guarded { param($d) Invoke-Uninstall $d } }
})
$form.Controls.AddRange(@($install, $uninstall, $close))
[void]$form.ShowDialog()

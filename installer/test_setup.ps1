# test_setup.ps1 - dry-run tests for installer/Setup.ps1 against a FAKE Kenshi folder
# (copies kenshi_x64.exe from the Steam install; never touches the real game).
# -Extract: a folder holding Setup.ps1 + payload.zip (installer\build\stage after a build).
#   powershell -ExecutionPolicy Bypass -File installer\test_setup.ps1 -Extract <folder>
param([string]$Extract)
$ErrorActionPreference = 'Stop'
$root  = Join-Path $env:LOCALAPPDATA ("Temp\kc-sdk\fake-kenshi-" + (Get-Date -Format 'HHmmss'))
$k     = Join-Path $root 'Kenshi'
$save  = Join-Path $root 'save'
$bk    = Join-Path $root 'backups'
$real  = 'C:\Program Files (x86)\Steam\steamapps\common\Kenshi'
New-Item -ItemType Directory -Force -Path "$k\data", "$save\MySave" | Out-Null
Copy-Item -LiteralPath "$real\kenshi_x64.exe" -Destination $k
$plug = [IO.File]::ReadAllText("$real\Plugins_x64.cfg") -replace "Plugin=RE_Kenshi\r?\n", ''
[IO.File]::WriteAllText("$k\Plugins_x64.cfg", $plug)
[IO.File]::WriteAllText("$k\data\mods.cfg", "SomeOtherMod.mod`r`n")
Set-Content -LiteralPath "$save\MySave\quick.save" -Value 'pretend save'
$setup = Join-Path $Extract 'Setup.ps1'
$common = @{ Unattended = $true; KenshiDir = $k; SaveDir = $save; BackupRoot = $bk }
function Check([string]$what, [bool]$ok) { "{0}  {1}" -f $(if ($ok) { 'PASS' } else { 'FAIL' }), $what }
function Plugins { [IO.File]::ReadAllText("$k\Plugins_x64.cfg") }
function Mods { [IO.File]::ReadAllText("$k\data\mods.cfg") }

"=== 1. fresh install (no RE_Kenshi)"
& $setup @common -Action install | Out-Host
Check 'RE_Kenshi DLLs copied' ((Test-Path "$k\RE_Kenshi.dll") -and (Test-Path "$k\KenshiLib.dll") -and (Test-Path "$k\CompressToolsLib.dll"))
Check 'RE_Kenshi folder copied (RVAs)' (Test-Path "$k\RE_Kenshi\RVAs\Steam_1.0.65.br")
Check 'Plugin=RE_Kenshi right before RenderSystem' ((Plugins) -match "Plugin=RE_Kenshi\r?\nPlugin=RenderSystem_Direct3D11_x64")
Check 'Plugin=RE_Kenshi exactly once' (([regex]::Matches((Plugins), 'Plugin=RE_Kenshi')).Count -eq 1)
Check 'four mod files present' (@('KenshiCoop.dll','KenshiCoopUI.dll','KenshiCoop.mod','RE_Kenshi.json' | Where-Object { Test-Path "$k\mods\KenshiCoop\$_" }).Count -eq 4)
Check 'mod DLL identical to built Release' ((Get-FileHash "$k\mods\KenshiCoop\KenshiCoop.dll").Hash -eq (Get-FileHash 'C:\dev\KenshiCoop\src\plugin\x64\Release\KenshiCoop.dll').Hash)
Check 'coop_config.json = steam' ((Get-Content -Raw "$k\mods\KenshiCoop\coop_config.json") -match '"transport": "steam"')
Check 'mods.cfg keeps other mod + adds ours (CRLF)' ((Mods) -eq "SomeOtherMod.mod`r`nKenshiCoop.mod`r`n")
$rec = Get-Content -Raw "$k\mods\KenshiCoop\setup-record.json" | ConvertFrom-Json
Check 'record: installedReKenshi=true' ($rec.installedReKenshi -eq $true)
$b = Get-ChildItem $bk -Directory | Select-Object -First 1
Check 'backup has saves.zip + both cfgs + log' ((Test-Path "$($b.FullName)\saves.zip") -and (Test-Path "$($b.FullName)\Plugins_x64.cfg") -and (Test-Path "$($b.FullName)\data_mods.cfg") -and (Test-Path "$($b.FullName)\setup-log.txt"))
Check 'backed-up mods.cfg is the ORIGINAL' ([IO.File]::ReadAllText("$($b.FullName)\data_mods.cfg") -eq "SomeOtherMod.mod`r`n")

"=== 2. second install (idempotent, keeps settings)"
[IO.File]::WriteAllText("$k\mods\KenshiCoop\coop_config.json", '{ "transport": "udp", "playerName": "Bro" }')
& $setup @common -Action install | Out-Host
Check 'still one Plugin=RE_Kenshi' (([regex]::Matches((Plugins), 'Plugin=RE_Kenshi')).Count -eq 1)
Check 'mods.cfg unchanged' ((Mods) -eq "SomeOtherMod.mod`r`nKenshiCoop.mod`r`n")
Check 'existing coop_config.json kept' ((Get-Content -Raw "$k\mods\KenshiCoop\coop_config.json") -match 'Bro')
$rec = Get-Content -Raw "$k\mods\KenshiCoop\setup-record.json" | ConvertFrom-Json
Check 'record still remembers RE_Kenshi was ours' ($rec.installedReKenshi -eq $true)

"=== 3. uninstall"
& $setup @common -Action uninstall | Out-Host
Check 'mod folder removed' (-not (Test-Path "$k\mods\KenshiCoop"))
Check 'mods.cfg back to other mod only' ((Mods) -eq "SomeOtherMod.mod`r`n")
Check 'RE_Kenshi removed (we installed it)' (-not (Test-Path "$k\RE_Kenshi.dll") -and -not (Test-Path "$k\RE_Kenshi"))
Check 'Plugins_x64.cfg back to original' ((Plugins) -eq $plug)
Check 'save untouched' (Test-Path "$save\MySave\quick.save")

"=== 4. RE_Kenshi already there (installed by someone else)"
Copy-Item -LiteralPath "$real\RE_Kenshi.dll" -Destination $k
[IO.File]::WriteAllText("$k\Plugins_x64.cfg", [IO.File]::ReadAllText("$real\Plugins_x64.cfg"))
& $setup @common -Action install | Out-Host
$rec = Get-Content -Raw "$k\mods\KenshiCoop\setup-record.json" | ConvertFrom-Json
Check 'record: installedReKenshi=false' ($rec.installedReKenshi -eq $false)
& $setup @common -Action uninstall | Out-Host
Check 'their RE_Kenshi left alone on uninstall' ((Test-Path "$k\RE_Kenshi.dll") -and ((Plugins) -match 'Plugin=RE_Kenshi'))

"=== 5. wrong Kenshi version"
[IO.File]::WriteAllText("$k\kenshi_x64.exe", 'not the real game')
$threw = $false
try { & $setup @common -Action install | Out-Host } catch { $threw = $true; "  (stopped: $($_.Exception.Message))" }
Check 'unsupported version stops before changing anything' ($threw -and -not (Test-Path "$k\mods\KenshiCoop"))
"fake folder: $root"



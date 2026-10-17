# test_setup.ps1 - dry-run tests for installer/Setup.ps1 against FAKE Kenshi folders.
# Copies kenshi_x64.exe (and RE_Kenshi's 1.0.65 copy, if present) from the Steam
# install as test inputs; never writes to the real game.
# -Extract: a folder holding Setup.ps1 + payload.zip (installer\build\stage after a build).
#   powershell -ExecutionPolicy Bypass -File installer\test_setup.ps1 -Extract <folder>
param([string]$Extract, [string]$Real = 'C:\Program Files (x86)\Steam\steamapps\common\Kenshi')
$ErrorActionPreference = 'Stop'
$Sha065 = '504B362CDE850D56AFB1CEA6F5B7B0EE014D9DD7B47E188599D91C804502CD3E'
$Sha068 = 'A596AB4E407C67B58599C54FFB32DC1BF2B64510CDEBD3FA9359EF05A576AEB1'
$base   = Join-Path $env:LOCALAPPDATA ("Temp\kc-sdk\fake-kenshi-" + (Get-Date -Format 'HHmmss'))
$setup  = Join-Path $Extract 'Setup.ps1'
$script:pass = 0; $script:fail = 0
function Check([string]$what, [bool]$ok) {
    if ($ok) { $script:pass++ } else { $script:fail++ }
    "{0}  {1}" -f $(if ($ok) { 'PASS' } else { 'FAIL' }), $what
}
function Sha([string]$p) { if (Test-Path -LiteralPath $p) { (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash } else { '' } }
$plugNoRe = [IO.File]::ReadAllText("$Real\Plugins_x64.cfg") -replace "Plugin=RE_Kenshi\r?\n", ''

# A fake Kenshi folder; $exe is the kenshi_x64.exe to put in it.
function New-Fake([string]$name, [string]$exe) {
    $root = Join-Path $base $name
    $k = Join-Path $root 'Kenshi'
    New-Item -ItemType Directory -Force -Path "$k\data", "$root\save\MySave" | Out-Null
    Copy-Item -LiteralPath $exe -Destination "$k\kenshi_x64.exe"
    [IO.File]::WriteAllText("$k\Plugins_x64.cfg", $plugNoRe)
    [IO.File]::WriteAllText("$k\data\mods.cfg", "SomeOtherMod.mod`r`n")
    Set-Content -LiteralPath "$root\save\MySave\quick.save" -Value 'pretend save'
    return @{ K = $k; Args = @{ Unattended = $true; KenshiDir = $k; SaveDir = "$root\save"; BackupRoot = "$root\backups" } }
}
function Run($f, [string]$action, [switch]$Skip) {
    $a = $f.Args.Clone(); $a.Action = $action; if ($Skip) { $a.SkipVersionCheck = $true }
    & $setup @a | Out-Null
}
function Rec($f) { Get-Content -Raw "$($f.K)\mods\KenshiCoop\setup-record.json" | ConvertFrom-Json }
function Plugins($f) { [IO.File]::ReadAllText("$($f.K)\Plugins_x64.cfg") }
function Mods($f) { [IO.File]::ReadAllText("$($f.K)\data\mods.cfg") }

"=== 1. fresh install, Steam 1.0.68 (no RE_Kenshi)"
$f = New-Fake 'fresh068' "$Real\kenshi_x64.exe"
Check 'input is Steam 1.0.68' ((Sha "$($f.K)\kenshi_x64.exe") -eq $Sha068)
Run $f install
$k = $f.K
Check 'RE_Kenshi DLLs copied' ((Test-Path "$k\RE_Kenshi.dll") -and (Test-Path "$k\KenshiLib.dll") -and (Test-Path "$k\CompressToolsLib.dll"))
Check 'RE_Kenshi folder copied (RVAs)' (Test-Path "$k\RE_Kenshi\RVAs\Steam_1.0.65.br")
Check '1.0.65 copy created and byte-exact' ((Sha "$k\RE_Kenshi\kenshi_x64.exe") -eq $Sha065)
Check 'original kenshi_x64.exe untouched' ((Sha "$k\kenshi_x64.exe") -eq $Sha068)
Check 'Plugin=RE_Kenshi right before RenderSystem' ((Plugins $f) -match "Plugin=RE_Kenshi\r?\nPlugin=RenderSystem_Direct3D11_x64")
Check 'Plugin=RE_Kenshi exactly once' (([regex]::Matches((Plugins $f), 'Plugin=RE_Kenshi')).Count -eq 1)
Check 'four mod files present' (@('KenshiCoop.dll','KenshiCoopUI.dll','KenshiCoop.mod','RE_Kenshi.json' | Where-Object { Test-Path "$k\mods\KenshiCoop\$_" }).Count -eq 4)
Check 'mod DLL identical to built Release' ((Sha "$k\mods\KenshiCoop\KenshiCoop.dll") -eq (Sha 'C:\dev\KenshiCoop\src\plugin\x64\Release\KenshiCoop.dll'))
Check 'coop_config.json = steam' ((Get-Content -Raw "$k\mods\KenshiCoop\coop_config.json") -match '"transport": "steam"')
Check 'mods.cfg keeps other mod + adds ours (CRLF)' ((Mods $f) -eq "SomeOtherMod.mod`r`nKenshiCoop.mod`r`n")
$r = Rec $f
Check 'record: installedReKenshi + createdCompat' ($r.installedReKenshi -eq $true -and $r.createdCompat -eq $true)
$b = Get-ChildItem "$k\..\backups" -Directory | Select-Object -First 1
Check 'backup has saves.zip + both cfgs + log' ((Test-Path "$($b.FullName)\saves.zip") -and (Test-Path "$($b.FullName)\Plugins_x64.cfg") -and (Test-Path "$($b.FullName)\data_mods.cfg") -and (Test-Path "$($b.FullName)\setup-log.txt"))
Check 'backed-up mods.cfg is the ORIGINAL' ([IO.File]::ReadAllText("$($b.FullName)\data_mods.cfg") -eq "SomeOtherMod.mod`r`n")

"=== 2. second install (idempotent, keeps settings)"
[IO.File]::WriteAllText("$k\mods\KenshiCoop\coop_config.json", '{ "transport": "udp", "playerName": "Bro" }')
$compatTime = (Get-Item "$k\RE_Kenshi\kenshi_x64.exe").LastWriteTimeUtc
Run $f install
Check 'still one Plugin=RE_Kenshi' (([regex]::Matches((Plugins $f), 'Plugin=RE_Kenshi')).Count -eq 1)
Check 'mods.cfg unchanged' ((Mods $f) -eq "SomeOtherMod.mod`r`nKenshiCoop.mod`r`n")
Check 'existing coop_config.json kept' ((Get-Content -Raw "$k\mods\KenshiCoop\coop_config.json") -match 'Bro')
Check '1.0.65 copy not rebuilt' ((Get-Item "$k\RE_Kenshi\kenshi_x64.exe").LastWriteTimeUtc -eq $compatTime)
$r = Rec $f
Check 'record still remembers what it added' ($r.installedReKenshi -eq $true -and $r.createdCompat -eq $true)

"=== 3. uninstall"
Run $f uninstall
Check 'mod folder removed' (-not (Test-Path "$k\mods\KenshiCoop"))
Check 'mods.cfg back to other mod only' ((Mods $f) -eq "SomeOtherMod.mod`r`n")
Check 'RE_Kenshi + its 1.0.65 copy removed (we installed them)' (-not (Test-Path "$k\RE_Kenshi.dll") -and -not (Test-Path "$k\RE_Kenshi"))
Check 'Plugins_x64.cfg back to original' ((Plugins $f) -eq $plugNoRe)
Check 'original kenshi_x64.exe still untouched' ((Sha "$k\kenshi_x64.exe") -eq $Sha068)
Check 'save untouched' (Test-Path "$k\..\save\MySave\quick.save")

"=== 4. RE_Kenshi already there but no 1.0.65 copy (Steam 1.0.68)"
$f = New-Fake 'reNoCompat' "$Real\kenshi_x64.exe"
$k = $f.K
Copy-Item -LiteralPath "$Real\RE_Kenshi.dll" -Destination $k
[IO.File]::WriteAllText("$k\Plugins_x64.cfg", [IO.File]::ReadAllText("$Real\Plugins_x64.cfg"))
$plugWithRe = Plugins $f
Run $f install
$r = Rec $f
Check '1.0.65 copy created for their RE_Kenshi' ((Sha "$k\RE_Kenshi\kenshi_x64.exe") -eq $Sha065)
Check 'record: not our RE_Kenshi, but our copy' ($r.installedReKenshi -eq $false -and $r.createdCompat -eq $true)
Check 'their Plugins_x64.cfg unchanged' ((Plugins $f) -eq $plugWithRe)
Run $f uninstall
Check 'their RE_Kenshi left alone on uninstall' ((Test-Path "$k\RE_Kenshi.dll") -and ((Plugins $f) -match 'Plugin=RE_Kenshi'))
Check '1.0.65 copy kept (their RE_Kenshi needs it)' ((Sha "$k\RE_Kenshi\kenshi_x64.exe") -eq $Sha065)

"=== 5. Steam 1.0.65 player (no copy needed)"
if (Test-Path "$Real\RE_Kenshi\kenshi_x64.exe") {
    $f = New-Fake 'fresh065' "$Real\RE_Kenshi\kenshi_x64.exe"
    $k = $f.K
    Check 'input is Steam 1.0.65' ((Sha "$k\kenshi_x64.exe") -eq $Sha065)
    Run $f install
    $r = Rec $f
    Check 'RE_Kenshi installed' ((Test-Path "$k\RE_Kenshi.dll") -and ((Plugins $f) -match 'Plugin=RE_Kenshi'))
    Check 'no 1.0.65 copy created' (-not (Test-Path "$k\RE_Kenshi\kenshi_x64.exe"))
    Check 'record: createdCompat=false' ($r.installedReKenshi -eq $true -and $r.createdCompat -eq $false)
} else { 'SKIP  (no Steam 1.0.65 executable available as test input)' }

"=== 6. patch fails (stops before changing anything)"
$f = New-Fake 'badPatch' "$Real\kenshi_x64.exe"
$k = $f.K
[IO.File]::WriteAllText("$k\kenshi_x64.exe", 'not the real game')
$threw = $false
try { Run $f install -Skip } catch { $threw = $true; "  (stopped: $($_.Exception.Message))" }
Check 'setup stopped' $threw
Check 'no RE_Kenshi files, no mod, configs untouched' (-not (Test-Path "$k\RE_Kenshi.dll") -and -not (Test-Path "$k\RE_Kenshi") -and
    -not (Test-Path "$k\mods\KenshiCoop") -and ((Plugins $f) -eq $plugNoRe) -and ((Mods $f) -eq "SomeOtherMod.mod`r`n"))

"=== 7. unsupported Kenshi version"
$f = New-Fake 'wrongVer' "$Real\kenshi_x64.exe"
$k = $f.K
[IO.File]::WriteAllText("$k\kenshi_x64.exe", 'not the real game')
$threw = $false
try { Run $f install } catch { $threw = $true; "  (stopped: $($_.Exception.Message))" }
Check 'unsupported version stops before changing anything' ($threw -and -not (Test-Path "$k\mods\KenshiCoop") -and ((Plugins $f) -eq $plugNoRe))

"PASSED $script:pass, FAILED $script:fail  (fake folders: $base)"
if ($script:fail -gt 0) { exit 1 }

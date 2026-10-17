# build_setup.ps1 - build dist\KenshiCoop-Setup.exe, the one-file installer for
# players (see installer/Setup.ps1 for what it does on their PC).
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File installer\build_setup.ps1 [-SkipBuild]
#
# Steps: build the Release DLL pair (unless -SkipBuild), check it carries this
# version, fetch RE_Kenshi 0.3.5's loose release (SHA-256 pinned, cached),
# stage payload.zip (mod files + RE_Kenshi install files, licenses, NOTICE),
# and pack Setup.ps1 + launch.cmd + payload.zip with Windows' own IExpress.

[CmdletBinding()]
param(
    [switch]$SkipBuild,
    [string]$Out = ''
)
$ErrorActionPreference = 'Stop'
$Repo = Split-Path $PSScriptRoot -Parent
if (-not $Out) { $Out = Join-Path $Repo 'dist\KenshiCoop-Setup.exe' }

$ReKenshiUrl    = 'https://github.com/BFrizzleFoShizzle/RE_Kenshi/releases/download/v0.3.5/RE_Kenshi_v0.3.5_loose.zip'
$ReKenshiSha256 = '02245EC39C3A33872579E5D48067619223DFAA63D12B5329AA92D97532A46D6B'
$Cache          = Join-Path $env:LOCALAPPDATA 'KenshiCoop\setup-cache'

# ---- version + Release DLLs -------------------------------------------------
$wire = Get-Content -Raw (Join-Path $Repo 'src\netproto\Wire.h')
if ($wire -notmatch 'COOP_BUILD_VERSION\s*=\s*"([^"]+)"') { throw 'COOP_BUILD_VERSION not found in Wire.h' }
$Version = $Matches[1]
$setupPs = Get-Content -Raw (Join-Path $PSScriptRoot 'Setup.ps1')
if ($setupPs -notmatch "\`$SetupVersion\s*=\s*'([^']+)'" -or $Matches[1] -ne $Version) {
    throw "installer\Setup.ps1 `$SetupVersion does not match COOP_BUILD_VERSION $Version"
}

if (-not $SkipBuild) {
    & cmd.exe /c "`"$Repo\scripts\build_plugin.cmd`" Release"
    if ($LASTEXITCODE -ne 0) { throw "Release build failed ($LASTEXITCODE)" }
}
$dll   = Join-Path $Repo 'src\plugin\x64\Release\KenshiCoop.dll'
$uiDll = Join-Path $Repo 'src\ui\x64\Release\KenshiCoopUI.dll'
foreach ($f in @($dll, $uiDll)) { if (-not (Test-Path -LiteralPath $f)) { throw "Missing $f - build Release first" } }
# The DLL must carry this version string, or the stub would ship a stale build.
$bytes = [IO.File]::ReadAllBytes($dll)
$needle = [Text.Encoding]::ASCII.GetBytes($Version)
$found = $false
for ($i = 0; $i -le $bytes.Length - $needle.Length -and -not $found; $i++) {
    if ($bytes[$i] -ne $needle[0]) { continue }
    $match = $true
    for ($j = 1; $j -lt $needle.Length; $j++) { if ($bytes[$i + $j] -ne $needle[$j]) { $match = $false; break } }
    if ($match -and $bytes[$i + $needle.Length] -eq 0) { $found = $true }
}
if (-not $found) { throw "$dll does not contain version $Version - rebuild Release" }

# ---- RE_Kenshi (pinned) -------------------------------------------------------
New-Item -ItemType Directory -Force -Path $Cache | Out-Null
$reZip = Join-Path $Cache 'RE_Kenshi_v0.3.5_loose.zip'
if (-not (Test-Path -LiteralPath $reZip)) {
    Write-Host "Downloading RE_Kenshi 0.3.5 (loose) ..."
    Invoke-WebRequest -Uri $ReKenshiUrl -OutFile "$reZip.part" -UseBasicParsing
    Move-Item -LiteralPath "$reZip.part" -Destination $reZip
}
$got = (Get-FileHash -LiteralPath $reZip -Algorithm SHA256).Hash
if ($got -ne $ReKenshiSha256) { throw "RE_Kenshi archive hash mismatch: $got (expected $ReKenshiSha256)" }

# ---- stage --------------------------------------------------------------------
$build   = Join-Path $PSScriptRoot 'build'
$payload = Join-Path $build 'payload'
$stage   = Join-Path $build 'stage'
if (Test-Path -LiteralPath $build) { Remove-Item -LiteralPath $build -Recurse -Force }
New-Item -ItemType Directory -Force -Path "$payload\KenshiCoop", "$payload\RE_Kenshi", $stage | Out-Null

Copy-Item -LiteralPath $dll, $uiDll -Destination "$payload\KenshiCoop"
Copy-Item -LiteralPath (Join-Path $Repo 'dist\mods\KenshiCoop\KenshiCoop.mod'), (Join-Path $Repo 'dist\mods\KenshiCoop\RE_Kenshi.json') -Destination "$payload\KenshiCoop"

Add-Type -AssemblyName System.IO.Compression.FileSystem
$reTmp = Join-Path $build 're'
[IO.Compression.ZipFile]::ExtractToDirectory($reZip, $reTmp)
Copy-Item -LiteralPath (Join-Path $reTmp 'install') -Destination "$payload\RE_Kenshi" -Recurse
Copy-Item -LiteralPath (Join-Path $reTmp 'Licenses') -Destination "$payload\RE_Kenshi" -Recurse
Copy-Item -LiteralPath (Join-Path $Repo 'LICENSE') -Destination "$payload\KenshiCoop\LICENSE.txt"

@"
KenshiCoop $Version - co-op mod for Kenshi (this fork)
  License: GNU AGPL-3.0 (KenshiCoop\LICENSE.txt)
  Source:  https://github.com/Brandon-Ferguson/KenshiCoop

RE_Kenshi 0.3.5 by BFrizzleFoShizzle - redistributed unmodified
  License: GNU GPL-3.0 and bundled third-party licenses (RE_Kenshi\Licenses)
  Source:  https://github.com/BFrizzleFoShizzle/RE_Kenshi/tree/v0.3.5
  Release: $ReKenshiUrl
"@ | Set-Content -LiteralPath (Join-Path $payload 'NOTICE.txt') -Encoding ASCII

[IO.Compression.ZipFile]::CreateFromDirectory($payload, (Join-Path $stage 'payload.zip'))
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Setup.ps1'), (Join-Path $PSScriptRoot 'launch.cmd') -Destination $stage

# ---- IExpress -----------------------------------------------------------------
New-Item -ItemType Directory -Force -Path (Split-Path $Out -Parent) | Out-Null
if (Test-Path -LiteralPath $Out) { Remove-Item -LiteralPath $Out -Force }
$sed = Join-Path $build 'setup.sed'
@"
[Version]
Class=IEXPRESS
SEDVersion=3
[Options]
PackagePurpose=InstallApp
ShowInstallProgramWindow=1
HideExtractAnimation=1
UseLongFileName=1
InsideCompressed=0
CAB_FixedSize=0
CAB_ResvCodeSigning=0
RebootMode=N
InstallPrompt=%InstallPrompt%
DisplayLicense=%DisplayLicense%
FinishMessage=%FinishMessage%
TargetName=%TargetName%
FriendlyName=%FriendlyName%
AppLaunched=%AppLaunched%
PostInstallCmd=%PostInstallCmd%
AdminQuietInstCmd=%AdminQuietInstCmd%
UserQuietInstCmd=%UserQuietInstCmd%
SourceFiles=SourceFiles
[Strings]
InstallPrompt=
DisplayLicense=
FinishMessage=
TargetName=$Out
FriendlyName=KenshiCoop Setup $Version
AppLaunched=cmd.exe /c launch.cmd
PostInstallCmd=<None>
AdminQuietInstCmd=
UserQuietInstCmd=
FILE0="launch.cmd"
FILE1="Setup.ps1"
FILE2="payload.zip"
[SourceFiles]
SourceFiles0=$stage\
[SourceFiles0]
%FILE0%=
%FILE1%=
%FILE2%=
"@ | Set-Content -LiteralPath $sed -Encoding ASCII

# IExpress cannot open a QUOTED directive path ("Error opening the IExpress Self
# Extraction Directive file"), so run it from the build folder with a bare name.
$p = Start-Process -FilePath "$env:windir\System32\iexpress.exe" -ArgumentList '/N', '/Q', 'setup.sed' `
                   -WorkingDirectory $build -Wait -PassThru
if (-not (Test-Path -LiteralPath $Out)) { throw "IExpress did not produce $Out (exit $($p.ExitCode))" }
$o = Get-Item -LiteralPath $Out
Write-Host ("Built {0}  {1:N0} bytes  sha256={2}" -f $o.FullName, $o.Length, (Get-FileHash -LiteralPath $Out -Algorithm SHA256).Hash)
Write-Host "Version $Version, protocol from Wire.h, RE_Kenshi 0.3.5 bundled."

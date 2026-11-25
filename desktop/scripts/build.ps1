# Builds Practice for Windows end to end, on the mini PC:
#   powershell -NoProfile -File desktop\scripts\build.ps1            build, test, screenshots, installer, publish
#   ... -NoPublish                                                     everything but copying the installer out
# 1. CMake + Visual Studio 2022 Build Tools: Practice.exe and PracticeTests.exe (Release).
# 2. Tests: the desktop tests (scoring parity with shared/scoring-vectors.json, the detector, device picks under
#    stress, sync with a scratch drill server) and npm test (the server and the shared vectors). Any failure stops it.
# 3. Screenshots of every screen, dark and light, at two sizes, into logs\desktop-screens-<version> (not in git).
# 4. The installer (NSIS, the copy electron-builder keeps in %LOCALAPPDATA%\electron-builder\Cache): staged files are
#    Practice.exe and resources\ (the catalog, the voice and the guide guitar, the same files the phone carries).
# 5. Publish: desktop\release\ (what the drill server serves to the updater: latest.json and the newest installer)
#    and Dropbox\Apps\Practice\ (the newest installer only, as for every app).
param([switch]$NoPublish)
$ErrorActionPreference = 'Stop'
$repo = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$desktop = Join-Path $repo 'desktop'
$build = Join-Path $desktop 'build'
$version = (Get-Content (Join-Path $desktop 'VERSION') -TotalCount 1).Trim()
Write-Host "Practice for Windows $version"

# The drill server's address comes from config.local.json at the repo root (not in git); without it, 127.0.0.1.
$server = 'http://127.0.0.1:4700'
$localConfig = Join-Path $repo 'config.local.json'
if (Test-Path $localConfig) { $c = Get-Content $localConfig -Raw | ConvertFrom-Json; if ($c.serverUrl) { $server = $c.serverUrl.TrimEnd('/') } }
cmake -S $desktop -B $build -G "Visual Studio 17 2022" -A x64 -DPRACTICE_TESTS_ONLY=OFF "-DPRACTICE_DEFAULT_SERVER=$server" | Out-Null
if ($LASTEXITCODE) { throw 'cmake configure failed' }
cmake --build $build --config Release -- /m /v:minimal
if ($LASTEXITCODE) { throw 'build failed' }
$exe = Join-Path $build 'Practice_artefacts\Release\Practice.exe'
$tests = Join-Path $build 'PracticeTests_artefacts\Release\PracticeTests.exe'

& $tests
if ($LASTEXITCODE) { throw 'desktop tests failed' }
Push-Location $repo
npm test --silent
$npm = $LASTEXITCODE
Pop-Location
if ($npm) { throw 'npm test failed' }

$shots = Join-Path $repo "logs\desktop-screens-$version"
$scratch = Join-Path $env:TEMP "practice-screens-data"
if (Test-Path $scratch) { Remove-Item -Recurse -Force $scratch }
& $exe --screens $shots --data $scratch | Out-Null
Start-Sleep -Seconds 1
for ($i = 0; $i -lt 60 -and (Get-Process Practice -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $exe }); $i++) { Start-Sleep -Milliseconds 500 }
Write-Host "screens: $shots ($((Get-ChildItem $shots -Filter *.png).Count) pictures)"

$stage = Join-Path $build 'stage'
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
New-Item -ItemType Directory -Force (Join-Path $stage 'resources') | Out-Null
Copy-Item $exe $stage
Copy-Item -Recurse (Join-Path $repo 'catalog') (Join-Path $stage 'resources\catalog')
Copy-Item -Recurse (Join-Path $repo 'voice') (Join-Path $stage 'resources\voice')
Copy-Item -Recurse (Join-Path $repo 'ios\Practice\Resources\Guitar') (Join-Path $stage 'resources\guitar')
python (Join-Path $PSScriptRoot 'make-ico.py') (Join-Path $desktop 'assets\icon.png') (Join-Path $stage 'icon.ico')
if ($LASTEXITCODE) { throw 'icon failed' }

$nsis = Get-ChildItem (Join-Path $env:LOCALAPPDATA 'electron-builder\Cache') -Recurse -Filter makensis.exe | Where-Object { $_.FullName -notmatch 'linux|mac' } | Select-Object -First 1
if (-not $nsis) { throw 'makensis not found (electron-builder cache)' }
$out = Join-Path $build "Practice-Setup-$version.exe"
& $nsis.FullName /V2 "/DVERSION=$version" "/DSTAGE=$stage" "/DOUT=$out" (Join-Path $desktop 'installer\Practice.nsi')
if ($LASTEXITCODE) { throw 'makensis failed' }
Write-Host "installer: $out ($([math]::Round((Get-Item $out).Length / 1MB, 1)) MB)"

if ($NoPublish) { return }
$release = Join-Path $desktop 'release'
New-Item -ItemType Directory -Force $release | Out-Null
Get-ChildItem $release -Filter 'Practice-Setup-*.exe' | Remove-Item -Force
Copy-Item $out $release
$sha = (Get-FileHash $out -Algorithm SHA256).Hash.ToLower()
$json = @{ version = $version; file = "Practice-Setup-$version.exe"; sha256 = $sha; date = (Get-Date).ToString('s') } | ConvertTo-Json
[IO.File]::WriteAllText((Join-Path $release 'latest.json'), $json)   # no byte-order mark
$apps = 'C:\Users\Joe\Dropbox\Apps\Practice'
New-Item -ItemType Directory -Force $apps | Out-Null
Get-ChildItem $apps -Filter 'Practice-Setup-*.exe' | Remove-Item -Force
Copy-Item $out $apps
Write-Host "published: $release and $apps"

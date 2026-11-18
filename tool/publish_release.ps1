# Publishes one tAsikaso release on GitHub, nothing else.
#
#   & tool\publish_release.ps1 -Version 0.5.1
#
# Needs: the tag v<Version> already pushed, and Downloads\tAsikaso-<Version>\
# holding tAsikaso.apk (signed with the upload key) and release-notes.md.
# Creates the release (or reuses it) and attaches the APK. Uses the GitHub
# login git keeps on this PC; the token is never printed or saved.
param(
  [Parameter(Mandatory)]
  [ValidatePattern('^\d+\.\d+\.\d+$')]
  [string]$Version
)
$ErrorActionPreference = 'Stop'
$repo = 'yumemicutiee/tAsikaso'
$tag = "v$Version"
$dir = Join-Path $env:USERPROFILE "Downloads\tAsikaso-$Version"
$apk = Join-Path $dir 'tAsikaso.apk'
$notesFile = Join-Path $dir 'release-notes.md'
if (-not (Test-Path $apk) -or -not (Test-Path $notesFile)) { throw "Missing $apk or $notesFile" }
if (-not (git ls-remote --tags origin "refs/tags/$tag")) { throw "Tag $tag isn't on GitHub yet; push it first." }

$req = Join-Path $env:TEMP 'credreq.txt'
[IO.File]::WriteAllText($req, "protocol=https`nhost=github.com`n`n")
try { $out = cmd /c "git credential fill < `"$req`"" } finally { Remove-Item $req -ErrorAction SilentlyContinue }
$tok = ($out | Where-Object { $_ -like 'password=*' }) -replace '^password=', ''
if (-not $tok) { throw 'No GitHub login stored for git on this PC.' }
$h = @{ 'User-Agent' = 'tasikaso-release'; Authorization = "Bearer $tok"; Accept = 'application/vnd.github+json' }

try {
  $rel = Invoke-RestMethod "https://api.github.com/repos/$repo/releases/tags/$tag" -Headers $h
} catch {
  # Plain UTF-8 string (Get-Content -Raw in PowerShell 5.1 carries file
  # properties that ConvertTo-Json would send too, and misreads UTF-8).
  $notes = [IO.File]::ReadAllText($notesFile, [Text.Encoding]::UTF8)
  $body = @{ tag_name = $tag; name = "tAsikaso $Version"; body = $notes; draft = $false; prerelease = $false } | ConvertTo-Json
  $rel = Invoke-RestMethod "https://api.github.com/repos/$repo/releases" -Method Post -Headers $h -ContentType 'application/json' -Body ([Text.Encoding]::UTF8.GetBytes($body))
}
"release: $($rel.html_url)"

if ($rel.assets | Where-Object name -eq 'tAsikaso.apk') {
  'tAsikaso.apk is already attached.'
} else {
  $up = $rel.upload_url -replace '\{.*\}', '?name=tAsikaso.apk'
  $asset = Invoke-RestMethod $up -Method Post -Headers $h -ContentType 'application/vnd.android.package-archive' -InFile $apk -TimeoutSec 1800
  "attached: $($asset.name) $([math]::Round($asset.size / 1MB, 1)) MB  $($asset.browser_download_url)"
}

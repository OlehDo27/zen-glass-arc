# Glass Arc for Zen Browser (Windows): installs Zen if it is missing, then puts
# the Glass Arc mod, its settings and the Edit Theme style switch into your
# Zen profile. Run in PowerShell:
#
#   irm https://raw.githubusercontent.com/OlehDo27/zen-glass-arc/main/install.ps1 | iex
#
# Remove:  & ([scriptblock]::Create((irm https://raw.githubusercontent.com/OlehDo27/zen-glass-arc/main/install.ps1))) -Uninstall
# Options: -Uninstall, -Yes (no questions), -ProfileDir DIR, -NoLoader
param(
  [switch]$Uninstall,
  [switch]$Yes,
  [string]$ProfileDir = "",
  [switch]$NoLoader
)

$ErrorActionPreference = "Stop"
$Repo = if ($env:GLASSARC_REPO) { $env:GLASSARC_REPO } else { "OlehDo27/zen-glass-arc" }
$Branch = if ($env:GLASSARC_BRANCH) { $env:GLASSARC_BRANCH } else { "main" }
$ModId = "local-glass-arc"
$MarkStart = "/* >>> Glass Arc >>> */"
$MarkEnd = "/* <<< Glass Arc <<< */"
$PrefRe = '^user_pref\("([^"]+)",\s*(.*)\);\s*$'
$Utf8 = New-Object System.Text.UTF8Encoding $false

function Say($text) { Write-Host ":: $text" -ForegroundColor Magenta }
function Warn($text) { Write-Host "!! $text" -ForegroundColor Yellow }
function Die($text) { Write-Host "!! $text" -ForegroundColor Red; throw "Glass Arc: установка остановлена" }
function Ask($question) {
  if ($Yes) { return $true }
  $answer = Read-Host "$question [Y/n]"
  return ($answer -eq "" -or $answer -match '^[yYдД]')
}
function ReadText($path) { [System.IO.File]::ReadAllText($path, $Utf8) }
function WriteText($path, $text) { [System.IO.File]::WriteAllText($path, $text, $Utf8) }

# ---- repo files: next to this script, or downloaded --------------------------
$Src = $PSScriptRoot
if (-not $Src -or -not (Test-Path (Join-Path $Src "mod\$ModId\chrome.css"))) {
  Say "Скачиваю Glass Arc ($Repo)"
  $tmp = Join-Path $env:TEMP ("glass-arc-" + [guid]::NewGuid())
  New-Item -ItemType Directory $tmp | Out-Null
  $zip = Join-Path $tmp "repo.zip"
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  Invoke-WebRequest "https://github.com/$Repo/archive/refs/heads/$Branch.zip" -OutFile $zip -UseBasicParsing
  Expand-Archive $zip -DestinationPath $tmp
  $Src = (Get-ChildItem $tmp -Directory | Select-Object -First 1).FullName
}

# ---- Zen itself --------------------------------------------------------------
function Find-Zen {
  $candidates = @(
    "$env:ProgramFiles\Zen Browser\zen.exe",
    "$env:LOCALAPPDATA\Programs\Zen Browser\zen.exe",
    "$env:LOCALAPPDATA\Zen Browser\zen.exe"
  )
  foreach ($key in "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\zen.exe",
                   "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\zen.exe") {
    $value = (Get-ItemProperty $key -ErrorAction SilentlyContinue).'(default)'
    if ($value) { $candidates = @($value.Trim('"')) + $candidates }
  }
  foreach ($exe in $candidates) {
    if ($exe -and (Test-Path $exe)) { return $exe }
  }
  return $null
}

$ZenExe = Find-Zen
if (-not $ZenExe -and -not $Uninstall -and -not $ProfileDir) {
  Say "Zen Browser не установлен"
  if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Die "Сначала установите Zen Browser: https://zen-browser.app/download"
  }
  if (-not (Ask "Установить Zen через winget?")) { Die "Сначала установите Zen Browser" }
  winget install --id Zen-Team.Zen-Browser -e --accept-source-agreements --accept-package-agreements
  $ZenExe = Find-Zen
  if (-not $ZenExe) { Die "Zen так и не найден" }
}

# ---- the profile -------------------------------------------------------------
$ZenHome = Join-Path $env:APPDATA "zen"

function Get-DefaultProfile {
  $ini = Join-Path $ZenHome "profiles.ini"
  if (-not (Test-Path $ini)) { return $null }
  $sections = @{}
  $current = $null
  foreach ($line in (ReadText $ini) -split "`r?`n") {
    if ($line -match '^\[(.+)\]$') { $current = $Matches[1]; $sections[$current] = @{} }
    elseif ($current -and $line -match '^([^=]+)=(.*)$') { $sections[$current][$Matches[1]] = $Matches[2] }
  }
  $path = $null
  foreach ($name in $sections.Keys) {  # the profile Zen actually opens
    if ($name -like "Install*" -and $sections[$name]["Default"]) { $path = $sections[$name]["Default"] }
  }
  if (-not $path) {
    foreach ($name in $sections.Keys) {
      if ($sections[$name]["Path"] -and $sections[$name]["Default"] -eq "1") { $path = $sections[$name]["Path"] }
    }
  }
  if (-not $path) { return $null }
  $path = $path -replace '/', '\'
  if ([System.IO.Path]::IsPathRooted($path)) { return $path }
  return (Join-Path $ZenHome $path)
}

if (-not $ProfileDir) {
  $ProfileDir = Get-DefaultProfile
  if (-not $ProfileDir -and $ZenExe) {
    Say "Создаю профиль Zen (Zen откроется в фоне на несколько секунд)"
    $shot = Join-Path $env:TEMP "glass-arc-first-run.png"
    $proc = Start-Process $ZenExe -ArgumentList "--headless", "--no-remote", "--screenshot", "`"$shot`"", "about:blank" -PassThru
    if (-not $proc.WaitForExit(90000)) { $proc.Kill() }
    Remove-Item $shot -ErrorAction SilentlyContinue
    $ProfileDir = Get-DefaultProfile
  }
  if (-not $ProfileDir) { Die "Профиль Zen не найден в $ZenHome" }
}
if (-not (Test-Path $ProfileDir)) { Die "Папка профиля не найдена: $ProfileDir" }
Say "Профиль: $ProfileDir"

# ---- Zen has to be closed: it rewrites prefs.js when it quits -----------------
if (Get-Process zen -ErrorAction SilentlyContinue) {
  Warn "Закройте Zen Browser (Ctrl+Q), жду..."
  while (Get-Process zen -ErrorAction SilentlyContinue) { Start-Sleep 1 }
  Start-Sleep 1
}

# ---- profile changes (same steps as tools/setup_profile.py) --------------------
$Chrome = Join-Path $ProfileDir "chrome"
$ThemesJson = Join-Path $ProfileDir "zen-themes.json"
$PrefsJs = Join-Path $ProfileDir "prefs.js"

function Backup-Profile {
  $stamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
  $dest = Join-Path $ProfileDir "glass-arc-backup\$stamp"
  $n = 1
  while (Test-Path $dest) { $n++; $dest = Join-Path $ProfileDir "glass-arc-backup\${stamp}_$n" }
  New-Item -ItemType Directory $dest -Force | Out-Null
  foreach ($rel in "prefs.js", "zen-themes.json", "chrome\userChrome.css", "chrome\zen-themes.css") {
    $file = Join-Path $ProfileDir $rel
    if (Test-Path $file) {
      $target = Join-Path $dest $rel
      New-Item -ItemType Directory (Split-Path $target) -Force | Out-Null
      Copy-Item $file $target
    }
  }
  Write-Host "   резервная копия: $dest"
}

function Read-Mods {
  if (Test-Path $ThemesJson) {
    try { return (ReadText $ThemesJson | ConvertFrom-Json) } catch { }
  }
  return New-Object PSObject
}

function Write-ModsCss($mods) {
  # chrome/zen-themes.css the way Zen Mods writes it, with every enabled mod
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.Append("/* Zen Mods - Generated by ZenMods.`n")
  [void]$sb.Append("* FILE GENERATED AT: " + (Get-Date -Format "dddd, MMMM d, yyyy 'at' h:mm:ss tt") + "`n")
  [void]$sb.Append("* DO NOT EDIT THIS FILE DIRECTLY!`n* Your changes will be overwritten.`n* Instead, go to the preferences and edit the mods there.`n*/`n")
  foreach ($prop in $mods.PSObject.Properties) {
    $mod = $prop.Value
    if ($mod.enabled -eq $false) { continue }
    $css = Join-Path $Chrome ("zen-themes\" + $mod.id + "\chrome.css")
    if (-not (Test-Path $css)) { continue }
    [void]$sb.Append("`n/* Name: $($mod.name) */`n/* Description: $($mod.description) */`n/* Author: @$($mod.author) */`n")
    [void]$sb.Append((ReadText $css))
  }
  [void]$sb.Append("`n/* End of Zen Mods */`n")
  WriteText (Join-Path $Chrome "zen-themes.css") $sb.ToString()
}

function Set-UserChromeBlock($block) {
  $path = Join-Path $Chrome "userChrome.css"
  $text = ""
  if (Test-Path $path) { $text = ReadText $path }
  $text = [regex]::Replace($text, [regex]::Escape($MarkStart) + '.*?' + [regex]::Escape($MarkEnd) + '\r?\n?', '', 'Singleline')
  if ($block) {
    $text = $text.TrimEnd("`r", "`n")
    if ($text.Trim()) { $text += "`n`n" }
    $text += "$MarkStart`n$($block.TrimEnd())`n$MarkEnd`n"
  }
  if ($text.Trim() -or (Test-Path $path)) { WriteText $path $text }
}

function Get-PrefLines($file) {
  @((ReadText $file) -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -match $PrefRe })
}

function Write-Prefs($forced, $defaults) {
  # forced lines replace existing values; defaults only fill in missing ones
  $lines = @()
  if (Test-Path $PrefsJs) { $lines = @((ReadText $PrefsJs) -split "`r?`n" | Where-Object { $_ -ne "" }) }
  $existing = @{}
  foreach ($line in $lines) { if ($line -match $PrefRe) { $existing[$Matches[1]] = $true } }
  $forcedKeys = @{}
  foreach ($line in $forced) { if ($line -match $PrefRe) { $forcedKeys[$Matches[1]] = $true } }
  $kept = @($lines | Where-Object { -not ($_ -match $PrefRe -and $forcedKeys.ContainsKey($Matches[1])) })
  $added = @($forced) + @($defaults | Where-Object { $_ -match $PrefRe -and -not $existing.ContainsKey($Matches[1]) })
  WriteText $PrefsJs (((@($kept) + $added) -join "`n") + "`n")
}

function Get-ModDefaultPrefs {
  $out = @()
  foreach ($p in (ReadText (Join-Path $Src "mod\$ModId\preferences.json") | ConvertFrom-Json)) {
    if ($p.defaultValue -is [bool]) { $value = $p.defaultValue.ToString().ToLower() }
    else { $value = ConvertTo-Json ([string]$p.defaultValue) }
    $out += "user_pref(`"$($p.property)`", $value);"
  }
  return $out
}

Backup-Profile
$mods = Read-Mods

if ($Uninstall) {
  Remove-Item (Join-Path $Chrome "zen-themes\$ModId") -Recurse -Force -ErrorAction SilentlyContinue
  if ($mods.PSObject.Properties[$ModId]) {
    $mods.PSObject.Properties.Remove($ModId)
    WriteText $ThemesJson ($mods | ConvertTo-Json -Depth 10)
    Write-ModsCss $mods
  }
  Set-UserChromeBlock $null
  Remove-Item (Join-Path $Chrome "JS\glassarc-style.uc.js") -ErrorAction SilentlyContinue
} else {
  $modDir = Join-Path $Chrome "zen-themes\$ModId"
  New-Item -ItemType Directory $modDir -Force | Out-Null
  Copy-Item (Join-Path $Src "mod\$ModId\*") $modDir -Recurse -Force

  $today = Get-Date -Format "yyyy-MM-dd"
  $created = $today
  if ($mods.PSObject.Properties[$ModId] -and $mods.$ModId.createdAt) { $created = $mods.$ModId.createdAt }
  $entry = [ordered]@{
    id = $ModId; name = "Glass Arc"
    description = "Frosted glass sidebar with gradient tint, Nova-style buttons, glass AI panel"
    homepage = ""; style = "https://localhost.invalid/$ModId/chrome.css"
    readme = "https://localhost.invalid/$ModId/readme.md"
    preferences = "https://localhost.invalid/$ModId/preferences.json"
    image = ""; author = "local"; version = "1.1.0"; tags = @("glass", "arc", "local")
    createdAt = $created; updatedAt = $today; enabled = $true
  }
  if ($mods.PSObject.Properties[$ModId]) { $mods.PSObject.Properties.Remove($ModId) }
  $mods | Add-Member -NotePropertyName $ModId -NotePropertyValue ([pscustomobject]$entry)
  WriteText $ThemesJson ($mods | ConvertTo-Json -Depth 10)
  Write-ModsCss $mods

  Set-UserChromeBlock (ReadText (Join-Path $Src "profile\userChrome.css"))

  $jsDir = Join-Path $Chrome "JS"
  New-Item -ItemType Directory $jsDir -Force | Out-Null
  Copy-Item (Join-Path $Src "profile\JS\*.uc.js") $jsDir -Force

  # Downloads in place of Library is done by glassarc-style.uc.js on first start
  $forced = @(Get-PrefLines (Join-Path $Src "prefs\common.prefs")) + @(Get-PrefLines (Join-Path $Src "prefs\windows.prefs"))
  Write-Prefs $forced (Get-ModDefaultPrefs)
}

# ---- loader for the style switch in Edit Theme (a file in Zen's folder) --------
function Invoke-Elevated($code) {
  # The file contents travel inside the command, so the admin window needs
  # no access to this user's temp folder and no quoting of paths.
  $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
  if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    & ([scriptblock]::Create($code))
    return
  }
  $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code))
  Start-Process powershell -Verb RunAs -Wait -WindowStyle Hidden `
    -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-EncodedCommand", $encoded
}

function Quote($path) { "'" + ($path -replace "'", "''") + "'" }

function Get-Base64($path) { [Convert]::ToBase64String([IO.File]::ReadAllBytes($path)) }

if (-not $NoLoader -and $ZenExe) {
  $zenDir = Split-Path $ZenExe
  $prefDir = Join-Path $zenDir "defaults\pref"
  $configJs = Join-Path $zenDir "config.js"
  $configPrefs = Join-Path $prefDir "config-prefs.js"
  if ($Uninstall) {
    if ((Test-Path $configJs) -and (Select-String -Path $configJs -Pattern "Glass Arc loader" -Quiet)) {
      try { Invoke-Elevated "Remove-Item -LiteralPath $(Quote $configJs), $(Quote $configPrefs) -Force -ErrorAction SilentlyContinue" } catch { }
    }
  } elseif (Ask "Добавить переключатель стиля в Edit Theme? Windows спросит права администратора, чтобы положить config.js в $zenDir") {
    $code = @"
New-Item -ItemType Directory -Force -Path $(Quote $prefDir) | Out-Null
[IO.File]::WriteAllBytes($(Quote $configJs), [Convert]::FromBase64String('$(Get-Base64 (Join-Path $Src "loader\config.js"))'))
[IO.File]::WriteAllBytes($(Quote $configPrefs), [Convert]::FromBase64String('$(Get-Base64 (Join-Path $Src "loader\defaults\pref\config-prefs.js"))'))
"@
    try { Invoke-Elevated $code } catch { Warn "Права администратора не получены: $($_.Exception.Message)" }
    if ((Test-Path $configJs) -and (Test-Path $configPrefs)) {
      Say "Переключатель стиля добавлен в Edit Theme ($zenDir)"
    } else {
      Warn "Не удалось положить config.js в $zenDir — переключателя в Edit Theme не будет."
      Warn "Стиль можно выбрать в Настройки -> Zen Mods -> Glass Arc, или запустите установщик снова."
    }
  }
}

if ($Uninstall) {
  Say "Glass Arc удалён. Настройки Zen остались как есть (старый prefs.js лежит в резервной копии выше)."
} else {
  Say "Готово. Запустите Zen. Стиль стекла: правый клик по боковой панели -> Edit Theme."
}

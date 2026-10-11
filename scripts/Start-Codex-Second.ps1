[CmdletBinding()]
param(
    [ValidatePattern('^[A-Za-z][A-Za-z0-9_-]{0,31}$')]
    [string]$InstanceName = 'Second',
    [ValidateNotNullOrEmpty()]
    [string]$ShortcutName = 'Codex 2',
    [switch]$CreateShortcutOnly,
    [switch]$CheckOnly,
    [switch]$Sequential
)

$ErrorActionPreference = 'Stop'
# Community workaround for one installed OpenAI.Codex package, not a second installation.
# The internal profile switch can change. The package's fixed tray GUID can still conflict.
# This script does not patch the package or establish that both windows are isolated.
# New profiles use their own file credential store; no primary credentials are copied.

function Get-NormalPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    $expanded = [Environment]::ExpandEnvironmentVariables($Path)
    if ($expanded.StartsWith('~\') -or $expanded.StartsWith('~/')) {
        $expanded = Join-Path $env:USERPROFILE $expanded.Substring(2)
    }
    if ($expanded.StartsWith('\\?\')) { $expanded = $expanded.Substring(4) }
    if ($expanded.StartsWith('\??\')) { $expanded = $expanded.Substring(4) }
    $full = [IO.Path]::GetFullPath($expanded)
    if ($full -eq [IO.Path]::GetPathRoot($full)) { return $full }
    return $full.TrimEnd('\', '/')
}

function Get-PathItems {
    param([Parameter(Mandatory = $true)][string]$Path)
    $full = Get-NormalPath $Path
    $root = [IO.Path]::GetPathRoot($full)
    $current = $root
    $paths = @($root)
    foreach ($part in $full.Substring($root.Length).Split('\', [StringSplitOptions]::RemoveEmptyEntries)) {
        $current = Join-Path $current $part
        $paths += $current
    }
    foreach ($candidate in $paths) {
        try { Get-Item -LiteralPath $candidate -Force -ErrorAction Stop }
        catch { if ($_.CategoryInfo.Category -ne 'ObjectNotFound') { throw } }
    }
}

function Assert-NoReparsePath {
    param([Parameter(Mandatory = $true)][string]$Path)
    foreach ($item in @(Get-PathItems $Path)) {
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "独立实例路径包含目录链接或重解析点，无法确认隔离：$($item.FullName)"
        }
    }
}

function Resolve-MainPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    $current = Get-NormalPath $Path
    for ($depth = 0; $depth -lt 16; $depth++) {
        $link = @(Get-PathItems $current | Where-Object { ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 } | Select-Object -First 1)
        if ($link.Count -eq 0) { return $current }
        $targets = @($link[0].Target)
        if ($targets.Count -ne 1 -or [string]::IsNullOrWhiteSpace([string]$targets[0])) {
            throw "无法确定主账号目录链接的目标，暂不创建独立实例：$($link[0].FullName)"
        }
        $target = [string]$targets[0]
        if (-not [IO.Path]::IsPathRooted($target)) { $target = Join-Path $link[0].Parent.FullName $target }
        $tail = $current.Substring((Get-NormalPath $link[0].FullName).Length).TrimStart('\')
        $current = Get-NormalPath $(if ($tail) { Join-Path $target $tail } else { $target })
    }
    throw '主账号目录链接层数过多，无法确认独立实例路径。'
}

function Test-PathOverlap {
    param([string]$First, [string]$Second)
    $a = (Get-NormalPath $First).TrimEnd('\')
    $b = (Get-NormalPath $Second).TrimEnd('\')
    return $a -ieq $b -or $a.StartsWith($b + '\', [StringComparison]::OrdinalIgnoreCase) -or $b.StartsWith($a + '\', [StringComparison]::OrdinalIgnoreCase)
}

function Get-MainHomes {
    $values = @((Join-Path $env:USERPROFILE '.codex'))
    foreach ($scope in @([EnvironmentVariableTarget]::Process, [EnvironmentVariableTarget]::User)) {
        $value = [Environment]::GetEnvironmentVariable('CODEX_HOME', $scope)
        if (-not [string]::IsNullOrWhiteSpace($value)) { $values += $value }
    }
    @($values | ForEach-Object { Resolve-MainPath $_ } | Select-Object -Unique)
}

function Get-PrimaryDataPaths {
    $values = @(Get-MainHomes)
    foreach ($scope in @([EnvironmentVariableTarget]::Process, [EnvironmentVariableTarget]::User)) {
        $value = [Environment]::GetEnvironmentVariable('CODEX_ELECTRON_USER_DATA_PATH', $scope)
        if (-not [string]::IsNullOrWhiteSpace($value)) { $values += Resolve-MainPath $value }
    }
    @($values | Select-Object -Unique)
}

function Get-CredentialConfigStatus {
    param([Parameter(Mandatory = $true)][string]$ConfigPath)
    Assert-NoReparsePath $ConfigPath
    if (-not (Test-Path -LiteralPath $ConfigPath)) { return 'new-file-config' }
    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) { throw '独立实例 config.toml 不是文件。' }
    $rootSection = $true
    $rootModes = @()
    foreach ($line in [IO.File]::ReadAllLines($ConfigPath, [Text.Encoding]::UTF8)) {
        $text = $line.Trim()
        if (-not $text -or $text.StartsWith('#')) { continue }
        if ($text -match '(?i)\bsqlite_home\b\s*["'']?\s*=') {
            throw '已有配置包含 sqlite_home，SQLite 隔离未确认；请核对该配置，脚本保留原文件。'
        }
        if ($text -match '(?i)^\s*(?:["'']?(?:profile|include|includes)["'']?\s*=|\[\s*["'']?profiles?\b)') {
            throw '已有配置使用 profile/include 特殊设置，脚本无法完整确认隔离；请核对配置，原文件不会被覆盖。'
        }
        if ($text.StartsWith('[')) { $rootSection = $false }
        if ($text -match '\bcli_auth_credentials_store\b\s*["'']?\s*=') {
            if ($text -notmatch '^(?:cli_auth_credentials_store|"cli_auth_credentials_store"|''cli_auth_credentials_store'')\s*=\s*(?:"(?<mode>[^"\r\n]*)"|''(?<mode>[^''\r\n]*)'')\s*(?:#.*)?$') {
                throw '无法确认已有配置的凭据存储语法，请使用明确的根级 cli_auth_credentials_store = "file"；原文件保留。'
            }
            $mode = $Matches['mode']
            if ($mode -cne 'file') {
                throw '已有配置未使用独立 file 凭据存储（keyring/auto 等可能共享系统凭据）；请核对配置，原文件保留。'
            }
            if ($rootSection) { $rootModes += $mode }
        }
    }
    if ($rootModes.Count -ne 1) {
        throw '已有配置缺少唯一、明确的根级 cli_auth_credentials_store = "file"，隔离未确认；脚本不会覆盖它。'
    }
    return 'existing-file-config'
}

function Find-CodexPackage {
    if ($PSVersionTable.PSVersion.Major -ne 5 -or $PSVersionTable.PSVersion.Minor -ne 1) {
        throw '请用 Windows PowerShell 5.1 通过 -File 运行已保存的脚本。'
    }
    foreach ($name in @('Get-AppxPackage', 'Invoke-CommandInDesktopPackage')) {
        if (-not (Get-Command $name -ErrorAction SilentlyContinue)) { throw "缺少 Windows Appx 命令：$name" }
    }
    $pkg = Get-AppxPackage -Name 'OpenAI.Codex' -ErrorAction Stop | Sort-Object Version -Descending | Select-Object -First 1
    if ($null -eq $pkg) { throw '未找到当前 Windows 用户安装的官方 OpenAI.Codex 应用。' }
    $manifest = Join-Path $pkg.InstallLocation 'AppxManifest.xml'
    $prefix = '/*[local-name()="Package"]/*[local-name()="Applications"]/*[local-name()="Application"]'
    $app = Select-Xml -LiteralPath $manifest -XPath ($prefix + '[@Id="App"]') | Select-Object -First 1
    if ($null -eq $app) { $app = Select-Xml -LiteralPath $manifest -XPath $prefix | Select-Object -First 1 }
    if ($null -eq $app -or [string]::IsNullOrWhiteSpace([string]$app.Node.Executable)) { throw '无法确定安装包中的应用入口。' }
    $exe = Get-NormalPath (Join-Path $pkg.InstallLocation ([string]$app.Node.Executable))
    if (-not $exe.StartsWith((Get-NormalPath $pkg.InstallLocation) + '\', [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $exe -PathType Leaf)) {
        throw '安装包中的可执行文件路径无效。'
    }
    [pscustomobject]@{ FamilyName = $pkg.PackageFamilyName; AppId = [string]$app.Node.Id; Exe = $exe }
}

function Get-PackageProcesses {
    param([string]$AppExe)
    foreach ($process in @(Get-Process -Name ([IO.Path]::GetFileNameWithoutExtension($AppExe)) -ErrorAction SilentlyContinue)) {
        $path = $null
        try { $path = $process.Path } catch { $path = $null }
        if (-not $path -or $path -ieq $AppExe -or $path -like '*\OpenAI.Codex_*\*') { $process.Id }
    }
}

function Get-DesktopPath { [Environment]::GetFolderPath('Desktop') }
function New-ShortcutShell { New-Object -ComObject WScript.Shell }

function Get-LauncherPlan {
    param([string]$ScriptPath, [string]$Name, [string]$LinkName, [switch]$SequentialMode)
    if ([string]::IsNullOrWhiteSpace($ScriptPath) -or -not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
        throw '请保存完整脚本并用 -File 运行；不要将脚本内容逐行粘贴到 PowerShell。'
    }
    if ($Name -notmatch '^[A-Za-z][A-Za-z0-9_-]{0,31}$' -or $Name -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$') { throw 'InstanceName 必须是非保留的简单英文标识符。' }
    if ([string]::IsNullOrWhiteSpace($LinkName) -or $LinkName.Length -gt 80 -or $LinkName.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0 -or $LinkName -ne $LinkName.Trim().TrimEnd('.') -or $LinkName -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)' -or $LinkName.EndsWith('.lnk', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'ShortcutName 请填写合法的桌面名称，不含路径、保留名称或 .lnk 后缀。'
    }
    if (-not $env:LOCALAPPDATA -or -not $env:USERPROFILE -or -not $env:SystemRoot) { throw '无法确定当前用户的 Windows 目录。' }
    $base = Get-NormalPath (Join-Path $env:LOCALAPPDATA ('OpenAI-Codex\Profiles\' + $Name))
    $secondHome = Join-Path $base 'codex-home'; $userData = Join-Path $base 'user-data'
    foreach ($path in @($base, $secondHome, $userData)) {
        Assert-NoReparsePath $path
        if ((Test-Path -LiteralPath $path) -and -not (Test-Path -LiteralPath $path -PathType Container)) { throw "独立目录路径被现有文件占用：$path" }
        foreach ($main in @(Get-PrimaryDataPaths)) {
            if (Test-PathOverlap $path $main) { throw '独立实例目录与主账号数据或桌面缓存目录相同或互相包含，拒绝创建或启动。' }
        }
    }
    Assert-NoReparsePath (Join-Path $secondHome 'auth.json')
    $config = Join-Path $secondHome 'config.toml'
    $configStatus = Get-CredentialConfigStatus $config
    $desktop = Get-DesktopPath
    if ([string]::IsNullOrWhiteSpace($desktop) -or -not (Test-Path -LiteralPath $desktop -PathType Container)) { throw '无法确定现有桌面目录。' }
    $shortcut = Join-Path $desktop ($LinkName + '.lnk')
    if (Test-Path -LiteralPath $shortcut) {
        $item = Get-Item -LiteralPath $shortcut -Force
        if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw '现有快捷方式路径是目录或链接，拒绝覆盖，请换一个 ShortcutName。' }
    }
    $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path -LiteralPath $psExe -PathType Leaf)) { throw '找不到 Windows PowerShell 5.1。' }
    $package = Find-CodexPackage
    if ($SequentialMode -and @(Get-PackageProcesses $package.Exe).Count -gt 0) {
        throw 'Sequential 模式要求先完全退出现有 Codex；脚本未创建目录或终止进程。'
    }
    $plan = [pscustomobject]@{ ScriptPath = (Get-Item -LiteralPath $ScriptPath).FullName; InstanceName = $Name; ShortcutName = $LinkName;
        Base = $base; Home = $secondHome; UserData = $userData; Config = $config; ConfigStatus = $configStatus;
        Shortcut = $shortcut; PowerShell = $psExe; Package = $package; Sequential = [bool]$SequentialMode }
    Assert-ShortcutAvailable $plan
    return $plan
}

function Prepare-SecondProfile {
    param($Plan)
    foreach ($path in @($Plan.Base, $Plan.Home, $Plan.UserData)) {
        Assert-NoReparsePath $path
        [void][IO.Directory]::CreateDirectory($path)
    }
    Assert-NoReparsePath $Plan.Config
    if (-not (Test-Path -LiteralPath $Plan.Config)) {
        $bytes = (New-Object Text.UTF8Encoding($true)).GetPreamble() + [Text.Encoding]::UTF8.GetBytes('cli_auth_credentials_store = "file"' + [Environment]::NewLine)
        $stream = New-Object IO.FileStream($Plan.Config, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try { $stream.Write($bytes, 0, $bytes.Length) } finally { $stream.Dispose() }
    }
    [void](Get-CredentialConfigStatus $Plan.Config)
}

function Get-ShortcutArguments {
    param($Plan)
    $shortcutArguments = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $Plan.ScriptPath + '" -InstanceName "' + $Plan.InstanceName + '" -ShortcutName "' + $Plan.ShortcutName + '"'
    if ($Plan.Sequential) { $shortcutArguments += ' -Sequential' }
    return $shortcutArguments
}

function Assert-ShortcutAvailable {
    param($Plan)
    if (-not (Test-Path -LiteralPath $Plan.Shortcut)) { return }
    $shell = $null; $shortcut = $null
    try {
        $shell = New-ShortcutShell; $shortcut = $shell.CreateShortcut($Plan.Shortcut)
        $expected = (Get-ShortcutArguments $Plan) -replace ' -Sequential$', ''
        $actual = ([string]$shortcut.Arguments) -replace ' -Sequential$', ''
        if ($shortcut.TargetPath -ine $Plan.PowerShell -or $actual -cne $expected -or
            $shortcut.WorkingDirectory -ine $Plan.Base -or $shortcut.Description -cne ('Codex separate profile: ' + $Plan.InstanceName)) {
            throw '同名桌面入口属于其他脚本或实例，拒绝覆盖。请指定另一个 -ShortcutName，例如 "Codex 2 New"。'
        }
    } finally {
        foreach ($item in @($shortcut, $shell)) {
            if ($null -ne $item -and [Runtime.InteropServices.Marshal]::IsComObject($item)) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($item) }
        }
    }
}

function Update-SecondShortcut {
    param($Plan)
    Assert-ShortcutAvailable $Plan
    $shell = $null; $shortcut = $null
    try {
        $shell = New-ShortcutShell
        $shortcut = $shell.CreateShortcut($Plan.Shortcut)
        $shortcut.TargetPath = $Plan.PowerShell; $shortcut.Arguments = Get-ShortcutArguments $Plan
        $shortcut.WorkingDirectory = $Plan.Base
        $shortcut.Description = 'Codex separate profile: ' + $Plan.InstanceName
        $shortcut.IconLocation = $Plan.Package.Exe + ',0'
        $shortcut.Save()
    } finally {
        foreach ($item in @($shortcut, $shell)) {
            if ($null -ne $item -and [Runtime.InteropServices.Marshal]::IsComObject($item)) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($item) }
        }
    }
}

function ConvertTo-PowerShellLiteral {
    param([string]$Value)
    return "'" + $Value.Replace("'", "''") + "'"
}

function Get-ClearedEnvironmentNames {
    $names = @('CODEX_SQLITE_HOME', 'OPENAI_API_KEY', 'CODEX_API_KEY', 'CODEX_ACCESS_TOKEN', 'OPENAI_ACCESS_TOKEN', 'OPENAI_ADMIN_KEY', 'OPENAI_IDENTITY_TOKEN_FILE', 'OPENAI_CUSTOM_HEADERS')
    foreach ($key in [Environment]::GetEnvironmentVariables([EnvironmentVariableTarget]::Process).Keys) {
        if ([string]$key -match '^(?i:OPENAI|CODEX)_.*(?:API_KEY|TOKEN|CREDENTIAL|IDENTITY_PROVIDER)') { $names += [string]$key }
    }
    @($names | Select-Object -Unique)
}

function New-LaunchHelper {
    param($Plan, [string[]]$RemoveNames)
    $code = @'
$ErrorActionPreference = 'Stop'
$launchInfo = New-Object Diagnostics.ProcessStartInfo
$launchInfo.FileName = __EXE__
$launchInfo.Arguments = '--user-data-dir="' + __USER_DATA__ + '"'
$launchInfo.WorkingDirectory = __BASE__
$launchInfo.UseShellExecute = $false
$launchInfo.CreateNoWindow = $true
# .NET Framework can see duplicate Path/PATH keys. Retry, then rebuild by assignment.
try { $launchVariables = $launchInfo.get_Environment() }
catch {
    if ($_.Exception -is [ArgumentException] -or $_.Exception.InnerException -is [ArgumentException]) { $launchVariables = $launchInfo.get_Environment() }
    else { throw }
}
$launchVariables.Clear()
$parentVariables = [Environment]::GetEnvironmentVariables([EnvironmentVariableTarget]::Process)
foreach ($entry in $parentVariables.GetEnumerator()) { $launchVariables[[string]$entry.Key] = [string]$entry.Value }
foreach ($entry in $parentVariables.GetEnumerator()) { if ([string]$entry.Key -ceq 'PATH') { $launchVariables['PATH'] = [string]$entry.Value } }
foreach ($name in __REMOVE__) { [void]$launchVariables.Remove($name) }
$launchVariables['CODEX_HOME'] = __HOME__
$launchVariables['CODEX_ELECTRON_USER_DATA_PATH'] = __USER_DATA__
$launched = [Diagnostics.Process]::Start($launchInfo)
if ($null -ne $launched) { $launched.Dispose() }
'@
    foreach ($pair in @(@('__EXE__', $Plan.Package.Exe), @('__USER_DATA__', $Plan.UserData), @('__BASE__', $Plan.Base), @('__HOME__', $Plan.Home))) {
        $code = $code.Replace($pair[0], (ConvertTo-PowerShellLiteral $pair[1]))
    }
    $literals = @($RemoveNames | ForEach-Object { ConvertTo-PowerShellLiteral $_ })
    return $code.Replace('__REMOVE__', ('@(' + ($literals -join ',') + ')'))
}

function Send-SecondLaunchRequest {
    param($Plan)
    $removeNames = @(Get-ClearedEnvironmentNames)
    $helper = New-LaunchHelper $Plan $removeNames
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($helper))
    $saved = @{}
    $names = @('CODEX_HOME', 'CODEX_ELECTRON_USER_DATA_PATH') + $removeNames
    foreach ($name in $names) { $saved[$name] = [Environment]::GetEnvironmentVariable($name, [EnvironmentVariableTarget]::Process) }
    try {
        foreach ($name in $removeNames) { [Environment]::SetEnvironmentVariable($name, $null, [EnvironmentVariableTarget]::Process) }
        [Environment]::SetEnvironmentVariable('CODEX_HOME', $Plan.Home, [EnvironmentVariableTarget]::Process)
        [Environment]::SetEnvironmentVariable('CODEX_ELECTRON_USER_DATA_PATH', $Plan.UserData, [EnvironmentVariableTarget]::Process)
        Invoke-CommandInDesktopPackage -PackageFamilyName $Plan.Package.FamilyName -AppId $Plan.Package.AppId -Command $Plan.PowerShell `
            -Args ('-NoProfile -NonInteractive -WindowStyle Hidden -EncodedCommand ' + $encoded) -PreventBreakaway -ErrorAction Stop | Out-Null
    } finally {
        foreach ($name in $names) { [Environment]::SetEnvironmentVariable($name, $saved[$name], [EnvironmentVariableTarget]::Process) }
    }
}

function Invoke-SecondLauncher {
    param([string]$ScriptPath, [string]$Name, [string]$LinkName, [switch]$OnlyShortcut, [switch]$OnlyCheck, [switch]$SequentialMode)
    $plan = Get-LauncherPlan -ScriptPath $ScriptPath -Name $Name -LinkName $LinkName -SequentialMode:$SequentialMode
    Write-Host "第二实例后端目录：$($plan.Home)"
    Write-Host "第二实例桌面目录：$($plan.UserData)"
    Write-Host "桌面入口：$($plan.Shortcut)"
    if ($OnlyCheck) {
        Write-Host "只读检查通过；配置状态：$($plan.ConfigStatus)。未创建目录、写入文件或启动应用。"
        return $plan
    }
    Prepare-SecondProfile $plan
    Update-SecondShortcut $plan
    if ($OnlyShortcut) { Write-Host '已准备独立目录与快捷方式，未提交应用启动请求。'; return }
    Send-SecondLaunchRequest $plan
    Write-Host '已提交第二实例启动请求；实际隔离尚未验证。请在新窗口登录第二账号并核对账号名称。'
    Write-Host '保留原窗口；若版本限制导致无法同时打开，可先退出 Codex，再使用 -Sequential。'
}

if ([string]::IsNullOrWhiteSpace($PSCommandPath)) { throw '请将脚本保存为文件，再通过 Windows PowerShell 5.1 的 -File 运行。' }
Invoke-SecondLauncher -ScriptPath $PSCommandPath -Name $InstanceName -LinkName $ShortcutName `
    -OnlyShortcut:$CreateShortcutOnly -OnlyCheck:$CheckOnly -SequentialMode:$Sequential

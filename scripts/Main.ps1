<#
博途工具箱 v1.5.2
主脚本：安装过程监控
- 外置监控窗口（当前窗口切换）
- 实时读取博途安装日志
- 日志中文翻译
- 卡住判断
- 挂起标记自动清理
- 系统状态显示
#>

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Continue'
# ============================================================
# 全局状态追踪
# ============================================================
$script:CurrentState = "Init"
$script:StateHistory = New-Object System.Collections.ArrayList

function Set-State {
    param([string]$State)
    $script:CurrentState = $State
    [void]$script:StateHistory.Add([PSCustomObject]@{
            Time  = Get-Date
            State = $State
        })
    if ($script:StateHistory.Count -gt 50) {
        $script:StateHistory.RemoveAt(0)
    }
}

# ============================================================
# 联系方式（老板自己改）
# ============================================================
$script:ContactInfo = @"

  微信 / QQ：17789514767/527269661
  邮箱：527269661@qq.com

  请把反馈包发到上面任一渠道。
  我会尽快帮你看，也会持续改进工具。

"@
# ===== 全局路径 =====
$script:SiemensLogDir = "C:\ProgramData\Siemens\Automation\Logfiles\Setup"
$script:SiemensLogDirFallback = "C:\ProgramData\Siemens\Automation\Logfiles"
$script:LogDir = "$env:LOCALAPPDATA\TIAHelper\logs"
if (-not (Test-Path $script:LogDir)) { New-Item -ItemType Directory -Path $script:LogDir -Force | Out-Null }
$script:logFile = "$($script:LogDir)\main_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

# ===== 日志翻译字典 =====
$script:Translations = @(
    # ===== 组件安装 =====
    @{ Pattern = 'Installing component[:：]?\s*(.+)'; Replace = '正在安装组件：$1' }
    @{ Pattern = 'Registering service[:：]?\s*(.+)'; Replace = '正在注册服务：$1' }
    @{ Pattern = 'Starting service[:：]?\s*(.+)'; Replace = '正在启动服务：$1' }
    @{ Pattern = 'Stopping service[:：]?\s*(.+)'; Replace = '正在停止服务：$1' }

    # ===== 文件操作 =====
    @{ Pattern = 'Copying files to (.+)'; Replace = '正在复制文件到 $1' }
    @{ Pattern = 'Copying files'; Replace = '正在复制文件' }
    @{ Pattern = 'Extracting file[:：]?\s*(.+)'; Replace = '正在解压文件：$1' }
    @{ Pattern = 'Extracting'; Replace = '正在解压' }

    # ===== 检查与等待 =====
    @{ Pattern = 'Checking license prerequisites'; Replace = '正在检查许可证前置条件' }
    @{ Pattern = 'Checking (.+)'; Replace = '正在检查 $1' }
    @{ Pattern = 'Waiting for user input'; Replace = '等待用户输入' }

    # ===== 完成状态 =====
    @{ Pattern = 'Installation completed'; Replace = '安装已完成' }
    @{ Pattern = 'Setup completed'; Replace = '安装程序已完成' }

    # ===== 错误码 =====
    @{ Pattern = 'Error 1332'; Replace = '错误 1332：账户名与安全ID无映射（可能是中文用户名导致）' }
    @{ Pattern = 'Error 1603'; Replace = '错误 1603：安装致命错误（可能是权限或磁盘问题）' }
    @{ Pattern = 'Error 2503'; Replace = '错误 2503：安装程序权限问题（需要管理员权限）' }

    # ===== 重启相关 =====
    @{ Pattern = 'Reboot required'; Replace = '需要重启' }
    @{ Pattern = 'Reboot pending'; Replace = '有待处理的重启任务' }

    # ===== 通用动作 =====
    @{ Pattern = 'Launching (.+)'; Replace = '正在启动：$1' }
    @{ Pattern = 'Success'; Replace = '成功' }
    @{ Pattern = 'Failed'; Replace = '失败' }
    @{ Pattern = 'Retry'; Replace = '重试' }
    @{ Pattern = 'Finished'; Replace = '已完成' }
)
# ============================================================
# 反馈收集
# ============================================================
function Show-FeedbackDialog {
    Clear-Host
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "  问题反馈" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  你当前卡在：$($script:CurrentState)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  这个功能会把以下信息打包：" -ForegroundColor White
    Write-Host "    - 你遇到的问题描述（下面让你输入）" -ForegroundColor Gray
    Write-Host "    - 你操作到哪一步了（自动记录）" -ForegroundColor Gray
    Write-Host "    - 系统信息、挂起标记" -ForegroundColor Gray
    Write-Host "    - Siemens 服务、进程状态" -ForegroundColor Gray
    Write-Host "    - 博途安装日志" -ForegroundColor Gray
    Write-Host "    - 工具箱运行日志" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  ──────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host "  联系方式" -ForegroundColor Cyan
    Write-Host "  ──────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host $script:ContactInfo -ForegroundColor Green
    Write-Host "  ──────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  先简单描述一下你遇到的问题（一句话就行）：" -ForegroundColor White
    Write-Host "  （直接回车跳过）" -ForegroundColor DarkGray
    Write-Host ""
    $userMsg = Read-Host "  问题描述"

    Write-Host ""
    Write-Host "  正在收集现场信息..." -ForegroundColor Cyan
    Write-Host ""

    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $tempDir = "$env:TEMP\TIAHelper_Feedback_$timestamp"
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    # ---- 0. 用户描述 + 状态历史 ----
    $info = @()
    $info += "===== 用户反馈 ====="
    $info += "生成时间：$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $info += ""
    $info += "当前状态：$($script:CurrentState)"
    $info += ""
    $info += "用户描述："
    if ($userMsg) { $info += $userMsg } else { $info += "（用户未填写）" }
    $info += ""
    $info += "===== 状态历史（最近 50 次）====="
    foreach ($h in $script:StateHistory) {
        $info += "[$($h.Time.ToString('HH:mm:ss'))] $($h.State)"
    }
    $info -join "`r`n" | Out-File "$tempDir\00_反馈说明.txt" -Encoding UTF8

    # ---- 1. 系统信息 ----
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        $cs = Get-CimInstance Win32_ComputerSystem
        $s = @()
        $s += "计算机名：$($cs.Name)"
        $s += "操作系统：$($os.Caption) ($($os.Version))"
        $s += "物理内存：$([math]::Round($cs.TotalPhysicalMemory/1GB,1)) GB"
        $s += "可用内存：$([math]::Round($os.FreePhysicalMemory/1MB,1)) GB"
        $s += "当前用户：$env:USERNAME"
        Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue |
        Where-Object { $_.Free -ne $null -and $_.Root -match '^[A-Z]:\\$' } |
        ForEach-Object {
            $s += "$($_.Name)盘：已用 $([math]::Round($_.Used/1GB,1)) GB，剩余 $([math]::Round($_.Free/1GB,1)) GB"
        }
        $s -join "`r`n" | Out-File "$tempDir\01_系统信息.txt" -Encoding UTF8
    }
    catch { }

    # ---- 2. 挂起标记 ----
    try {
        $s = @()
        $pfro = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' `
            -Name PendingFileRenameOperations -ErrorAction SilentlyContinue
        if ($pfro -and $pfro.PendingFileRenameOperations) {
            $s += "PendingFileRenameOperations ($($pfro.PendingFileRenameOperations.Count) 条)"
            $pfro.PendingFileRenameOperations | ForEach-Object { $s += "  $_" }
        }
        if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') {
            $s += "CBS RebootPending：存在"
        }
        if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') {
            $s += "WindowsUpdate RebootRequired：存在"
        }
        if ($s.Count -eq 0) { $s += "无挂起标记" }
        $s -join "`r`n" | Out-File "$tempDir\02_挂起标记.txt" -Encoding UTF8
    }
    catch { }

    # ---- 3. Siemens 服务状态 ----
    try {
        $allSvc = Get-CimInstance Win32_Service -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -match 'Siemens|SIMATIC|S7|ALM|TIA|WinCC' -or
            $_.DisplayName -match 'Siemens|SIMATIC|S7|ALM|TIA|WinCC'
        }
        $s = @("===== Siemens 服务 =====")
        foreach ($svc in $allSvc) {
            $s += "$($svc.Name) | $($svc.DisplayName) | 状态：$($svc.State) | 启动：$($svc.StartMode)"
        }
        $s -join "`r`n" | Out-File "$tempDir\03_Siemens服务.txt" -Encoding UTF8
    }
    catch { }

    # ---- 4. Siemens 进程 ----
    try {
        $procs = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match 'Siemens|SIMATIC|s7o|S7Trace|TIA|WinCC|Portal|ALM|alm' -or
            ($_.ExecutablePath -and $_.ExecutablePath -match 'Siemens') }
        $s = @("===== Siemens 进程 =====")
        foreach ($p in $procs) {
            $memMB = 0
            try {
                $psP = Get-Process -Id $p.ProcessId -ErrorAction SilentlyContinue
                if ($psP) { $memMB = [math]::Round($psP.WorkingSet64 / 1MB, 1) }
            }
            catch { }
            $s += "$($p.Name) (PID $($p.ProcessId)) 内存 $memMB MB"
            if ($p.ExecutablePath) { $s += "  路径：$($p.ExecutablePath)" }
        }
        $s -join "`r`n" | Out-File "$tempDir\04_Siemens进程.txt" -Encoding UTF8
    }
    catch { }

    # ---- 5. 博途安装日志 ----
    try {
        $logDest = "$tempDir\05_博途日志"
        New-Item -ItemType Directory -Path $logDest -Force | Out-Null
        $logDirs = @(
            "C:\ProgramData\Siemens\Automation\Logfiles\Setup",
            "C:\ProgramData\Siemens\Automation\Logfiles"
        )
        foreach ($dir in $logDirs) {
            if (-not (Test-Path $dir)) { continue }
            Get-ChildItem $dir -Filter "*.log" -File -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -gt (Get-Date).AddDays(-7) } |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 20 |
            ForEach-Object { Copy-Item $_.FullName -Destination $logDest -Force -ErrorAction SilentlyContinue }
        }
    }
    catch { }

    # ---- 6. 工具箱自身日志 ----
    try {
        $toolLogDir = "$env:LOCALAPPDATA\TIAHelper\logs"
        $toolDest = "$tempDir\06_工具箱日志"
        New-Item -ItemType Directory -Path $toolDest -Force | Out-Null
        if (Test-Path $toolLogDir) {
            Get-ChildItem $toolLogDir -Filter "*.log" -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 10 |
            ForEach-Object { Copy-Item $_.FullName -Destination $toolDest -Force -ErrorAction SilentlyContinue }
        }
    }
    catch { }

    # ---- 打包 ----
    $zipName = "工控工具箱问题反馈_$timestamp.zip"
    $zipPath = "$env:USERPROFILE\Desktop\$zipName"
    try {
        Compress-Archive -Path "$tempDir\*" -DestinationPath $zipPath -Force
        Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    catch {
        Write-Host "  [XX] 打包失败：$($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  按 [Enter] 返回..." -ForegroundColor White
        $null = [Console]::ReadKey($true)
        return
    }

    # ---- 结束 ----
    Clear-Host
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "  ✅ 反馈包已生成" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  文件位置：桌面" -ForegroundColor White
    Write-Host "  文件名：$zipName" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  ──────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host "  联系方式" -ForegroundColor Cyan
    Write-Host "  ──────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host $script:ContactInfo -ForegroundColor Green
    Write-Host "  ──────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  接下来交给你：" -ForegroundColor White
    Write-Host "    1. 打开桌面上的 zip" -ForegroundColor Gray
    Write-Host "    2. 检查里面有没有隐私信息" -ForegroundColor Gray
    Write-Host "    3. 确认后发给我" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  不想发也没关系，放在那儿就行。" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  [1] 继续当前操作"
    Write-Host "  [2] 退出工具箱"
    Write-Host ""
    Write-Host "  按数字键选择：" -ForegroundColor White

    $k = Read-MenuChoice -ValidKeys @('1', '2')
    if ($k -eq '2') {
        Write-Host ""
        Write-Host "  感谢反馈，再见。" -ForegroundColor Cyan
        Write-Host ""
        exit
    }
}
function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = "[$(Get-Date -Format 'HH:mm:ss')] [$Level] $Message"
    Add-Content -Path $script:logFile -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
}

function Translate-LogLine {
    param([string]$Line)
    $result = $Line
    foreach ($t in $script:Translations) {
        if ($result -match $t.Pattern) {
            $result = $result -replace $t.Pattern, $t.Replace
        }
    }
    return $result
}

# ===== 结果收集 =====
$script:results = @()
$script:net35 = $null
$script:msmq = $null
$script:recommendedDrive = $null

function Add-Result {
    param([string]$Item, [string]$Status, [string]$Detail)
    $script:results += [PSCustomObject]@{Item = $Item; Status = $Status; Detail = $Detail }
}

# ===== 按键提示 =====
function Show-KeyHints {
    param([switch]$ShowEsc, [switch]$ShowEnter)
    Write-Host ""
    Write-Host "  ┌────────────────────────────────────────────┐" -ForegroundColor DarkGray
    if ($ShowEnter) {
        Write-Host "  │  [Enter] 下一步                            │" -ForegroundColor DarkGray
        Write-Host "  │         （你平常登录的那个键）              │" -ForegroundColor DarkGray
    }
    if ($ShowEsc) {
        Write-Host "  │  [Esc] 上一步                              │" -ForegroundColor DarkGray
        Write-Host "  │       （键盘左上角那个键）                  │" -ForegroundColor DarkGray
    }
    Write-Host "  │  [Ctrl+C] 随时退出                          │" -ForegroundColor DarkGray
    Write-Host "  │          （键盘左下角两个键一起按）          │" -ForegroundColor DarkGray
    Write-Host "  └────────────────────────────────────────────┘" -ForegroundColor DarkGray
    Write-Host ""
}

# ===== 菜单选择 =====
function Read-MenuChoice {
    param([string[]]$ValidKeys, [switch]$AllowEsc)
    while ($true) {
        $key = [Console]::ReadKey($true)
        if ($key.Key -eq [ConsoleKey]::Escape -and $AllowEsc) { return 'ESC' }
        if ($key.KeyChar -ne [char]0) {
            $char = $key.KeyChar.ToString()
            # F 键 = 反馈
            if ($char -match '^[Ff]$') {
                Show-FeedbackDialog
                Clear-Host
                continue
            }
            if ($ValidKeys -contains $char) {
                Write-Host "  > $char" -ForegroundColor Cyan
                return $char
            }
        }
    }
}
# ============================================================
# 1.5.3 确认输入（支持 Esc 返回 + 手动输入）
# ============================================================
function Read-ConfirmInput {
    $buffer = ""
    while ($true) {
        $key = [Console]::ReadKey($true)

        # Esc 取消
        if ($key.Key -eq [ConsoleKey]::Escape) {
            Write-Host ""
            return $null
        }

        # Enter 提交
        if ($key.Key -eq [ConsoleKey]::Enter) {
            Write-Host ""
            return $buffer
        }

        # Backspace 删除
        if ($key.Key -eq [ConsoleKey]::Backspace) {
            if ($buffer.Length -gt 0) {
                $buffer = $buffer.Substring(0, $buffer.Length - 1)
                Write-Host "`b `b" -NoNewline
            }
            continue
        }

        # 可打印字符
        if ($key.KeyChar -ne [char]0 -and -not [char]::IsControl($key.KeyChar)) {
            $buffer += $key.KeyChar
            Write-Host $key.KeyChar -NoNewline -ForegroundColor White
        }
    }
}
# ===== 搜索安装包 =====
function Scan-OneLevel {
    param([string]$Path, $Results)
    if (-not (Test-Path $Path)) { return }
    Get-ChildItem $Path -Filter "*.iso" -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match 'TIA|Portal|博途|V1[5-9]|V20' -and $_.Length -gt 1GB } |
    ForEach-Object { [void]$Results.Add($_.FullName) }
    Get-ChildItem $Path -Directory -ErrorAction SilentlyContinue |
    Where-Object { Test-Path (Join-Path $_.FullName "Start.exe") } |
    ForEach-Object { [void]$Results.Add($_.FullName) }
}

function Search-TiaPackage {
    $found = New-Object System.Collections.ArrayList
    $roots = @(
        "$env:USERPROFILE\Desktop",
        "$env:USERPROFILE\Downloads",
        "$env:USERPROFILE\Documents"
    )
    Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue |
    Where-Object { $_.Root -match '^[A-Z]:\\$' } |
    ForEach-Object { $roots += $_.Root }

    foreach ($root in $roots) {
        if (-not (Test-Path $root)) { continue }
        Write-Host "  搜索：$root" -ForegroundColor DarkGray
        Scan-OneLevel -Path $root -Results $found
        Get-ChildItem $root -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            Scan-OneLevel -Path $_.FullName -Results $found
        }
    }
    return @($found | Select-Object -Unique)
}

# ===== 环境自检 =====
function Invoke-EnvironmentCheck {
    $script:results = @()
    Write-Host ""
    Write-Host "  正在检测环境..." -ForegroundColor Cyan

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Add-Result "管理员权限" "PASS" "已提权"
    }
    else {
        Add-Result "管理员权限" "WARN" "未提权"
    }

    $os = Get-CimInstance Win32_OperatingSystem
    if ([version]$os.Version -ge [version]"10.0.17763") {
        Add-Result "操作系统" "PASS" "$($os.Caption) ($($os.Version))"
    }
    else {
        Add-Result "操作系统" "FAIL" "$($os.Caption) 版本过低"
    }

    $cs = Get-CimInstance Win32_ComputerSystem
    $memGB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
    if ($memGB -ge 16) {
        Add-Result "内存" "PASS" "${memGB} GB"
    }
    elseif ($memGB -ge 6.5) {
        Add-Result "内存" "WARN" "${memGB} GB（8GB内存条），勉强够用"
    }
    else {
        Add-Result "内存" "FAIL" "${memGB} GB，低于最低要求"
    }

    $allDrives = Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue | Where-Object {
        $_.Free -ne $null -and $_.Used -ne $null -and $_.Root -match '^[A-Z]:\\$'
    }
    $script:recommendedDrive = $null
    $maxFree = 0
    foreach ($drive in $allDrives) {
        $freeGB = [math]::Round($drive.Free / 1GB, 1)
        $driveName = "$($drive.Name)盘"
        if ($freeGB -ge 50) {
            Add-Result $driveName "PASS" "剩余 ${freeGB} GB"
            if ($freeGB -gt $maxFree) { $maxFree = $freeGB; $script:recommendedDrive = $drive.Name }
        }
        elseif ($freeGB -ge 30) {
            Add-Result $driveName "WARN" "剩余 ${freeGB} GB，偏紧"
        }
        else {
            Add-Result $driveName "WARN" "剩余 ${freeGB} GB，不建议"
        }
    }
    if ($script:recommendedDrive) {
        Add-Result "推荐安装盘" "PASS" "建议装在 $($script:recommendedDrive) 盘"
    }
    else {
        Add-Result "推荐安装盘" "FAIL" "无合适盘"
    }

    try {
        $script:net35 = Get-WindowsOptionalFeature -Online -FeatureName "NetFx3" -ErrorAction Stop
        if ($script:net35.State -eq "Enabled") {
            Add-Result ".NET 3.5" "PASS" "已启用"
        }
        else {
            Add-Result ".NET 3.5" "WARN" "未启用"
        }
    }
    catch {
        Add-Result ".NET 3.5" "WARN" "无法检测"
    }

    $net4 = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full" -ErrorAction SilentlyContinue
    if ($net4.Release -ge 528040) {
        Add-Result ".NET 4.x" "PASS" "4.8+"
    }
    elseif ($net4.Release) {
        Add-Result ".NET 4.x" "WARN" "版本偏低"
    }
    else {
        Add-Result ".NET 4.x" "FAIL" "未检测到"
    }

    try {
        $script:msmq = Get-WindowsOptionalFeature -Online -FeatureName "MSMQ-Server" -ErrorAction Stop
        if ($script:msmq.State -eq "Enabled") {
            Add-Result "MSMQ" "PASS" "已启用"
        }
        else {
            Add-Result "MSMQ" "WARN" "未启用"
        }
    }
    catch {
        Add-Result "MSMQ" "WARN" "无法检测"
    }

    if ($env:USERNAME -match '[\u4e00-\u9fa5]') {
        Add-Result "用户名" "FAIL" "含中文（$env:USERNAME）"
    }
    else {
        Add-Result "用户名" "PASS" "$env:USERNAME"
    }

    $avProcesses = Get-Process | Where-Object {
        $_.ProcessName -match '360|huorong|McAfee|Symantec|Kaspersky|Norton|Avast|AVG|Bitdefender'
    }
    if ($avProcesses) {
        $avNames = ($avProcesses.ProcessName | Select-Object -Unique) -join ', '
        Add-Result "杀毒软件" "WARN" "检测到 $avNames"
    }
    else {
        Add-Result "杀毒软件" "PASS" "未检测到"
    }
}

function Show-EnvironmentReport {
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "  环境自检报告" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""

    $passCount = @($script:results | Where-Object Status -eq 'PASS').Count
    $warnCount = @($script:results | Where-Object Status -eq 'WARN').Count
    $failCount = @($script:results | Where-Object Status -eq 'FAIL').Count

    foreach ($r in $script:results) {
        $icon = switch ($r.Status) { 'PASS' { "[OK]  " }; 'WARN' { "[!!]  " }; 'FAIL' { "[XX]  " } }
        $color = switch ($r.Status) { 'PASS' { 'Green' }; 'WARN' { 'Yellow' }; 'FAIL' { 'Red' } }
        Write-Host ("  $icon{0,-16} {1}" -f $r.Item, $r.Detail) -ForegroundColor $color
    }
    Write-Host ""
    Write-Host "  通过: $passCount   警告: $warnCount   失败: $failCount" -ForegroundColor White
    Write-Host ""
}

# ===== 自动修复 =====
function Invoke-AutoFix {
    function Test-Online {
        try {
            return Test-NetConnection -ComputerName "www.microsoft.com" -Port 443 `
                -InformationLevel Quiet -WarningAction SilentlyContinue -ErrorAction Stop
        }
        catch { return $false }
    }

    $fixable = @()
    if ($script:net35 -and $script:net35.State -ne "Enabled") {
        $fixable += [PSCustomObject]@{Name = ".NET Framework 3.5"; Feature = "NetFx3"; NeedNet = $true }
    }
    if ($script:msmq -and $script:msmq.State -ne "Enabled") {
        $fixable += [PSCustomObject]@{Name = "MSMQ 服务"; Feature = "MSMQ-Server"; NeedNet = $false }
    }

    if ($fixable.Count -eq 0) {
        Write-Host "  无需修复，环境已就绪。" -ForegroundColor Green
        return
    }

    $online = Test-Online
    if (-not $online) { Write-Host "  网络：未连通，部分项将跳过" -ForegroundColor Yellow }

    $needRestart = $false
    foreach ($f in $fixable) {
        if ($f.NeedNet -and -not $online) {
            Write-Host "  [--] $($f.Name)：跳过（需联网）" -ForegroundColor DarkGray
            continue
        }
        try {
            $result = Enable-WindowsOptionalFeature -Online -FeatureName $f.Feature `
                -All -NoRestart -WarningAction SilentlyContinue -ErrorAction Stop
            if ($result.RestartNeeded) { $needRestart = $true }
            Write-Host "  [OK] $($f.Name) 已启用" -ForegroundColor Green
        }
        catch {
            Write-Host "  [XX] $($f.Name) 修复失败" -ForegroundColor Red
        }
    }
    if ($needRestart) {
        Write-Host "  部分修复项需重启后生效。" -ForegroundColor Cyan
    }
}

# ===== 推荐方案 =====
function Show-Recommendation {
    param([string]$Purpose)

    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "  推荐安装方案" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""

    $recommend = @(); $avoid = @()
    switch ($Purpose) {
        "PLC" {
            $recommend += "TIA Portal 主程序（必装）"
            $recommend += "S7-PLCSIM（推荐）"
            $avoid += "WinCC（暂时不需要）"
            $avoid += "Startdrive（暂时不需要）"
        }
        "WinCC" {
            $recommend += "TIA Portal 主程序（必装）"
            $recommend += "WinCC（必装）"
            $recommend += "S7-PLCSIM（推荐）"
            $avoid += "Startdrive（暂时不需要）"
        }
        "Motion" {
            $recommend += "TIA Portal 主程序（必装）"
            $recommend += "Startdrive（必装）"
            $recommend += "S7-PLCSIM（推荐）"
            $avoid += "WinCC（暂时不需要）"
        }
    }

    Write-Host "  [需要安装]" -ForegroundColor Green
    foreach ($item in $recommend) { Write-Host "    ✓ $item" }
    if ($avoid.Count -gt 0) {
        Write-Host ""
        Write-Host "  [暂时不用装]" -ForegroundColor DarkGray
        foreach ($item in $avoid) { Write-Host "    ✗ $item" }
    }
    if ($script:recommendedDrive) {
        Write-Host ""
        Write-Host "  [安装位置] 建议装在 $($script:recommendedDrive) 盘" -ForegroundColor Cyan
    }
    Write-Host ""
}

# ============================================================
# 威胁分类
# ============================================================
function Get-ThreatClassification {
    param([string]$ThreatName)
    if ([string]::IsNullOrWhiteSpace($ThreatName)) { return 'UNKNOWN' }
    if ($ThreatName -match 'HackTool|Keygen|Crack|Patch|Generic|PUA|UnwantedSoftware') { return 'POTENTIALLY_UNWANTED' }
    if ($ThreatName -match 'Trojan|Worm|Ransom|Backdoor|Spyware|Rootkit|Virus|Dropper|Downloader|Miner|Stealer') { return 'MALWARE' }
    return 'UNKNOWN'
}

# ============================================================
# 查找注册机
# ============================================================
function Find-Keygen {
    param([string]$PackagePath)
    if ($PackagePath -match '\.iso$') { return @() }
    if (-not (Test-Path $PackagePath)) { return @() }
    $patterns = @('*EKB*', '*Keygen*', '*注册机*', '*授权*', '*Crack*', '*Patch*', '*Sim_EKB*')
    $found = @()
    foreach ($p in $patterns) {
        Get-ChildItem $PackagePath -Recurse -Filter $p -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -match '\.(exe|bat|cmd)$' -or $_.PSIsContainer } |
        ForEach-Object { $found += $_.FullName }
    }
    return @($found | Select-Object -Unique -First 5)
}
# ============================================================
# 1.5 安全退出：残留检测
# ============================================================
function Test-Residuals {
    Write-Host ""
    Write-Host "  正在检测残留..." -ForegroundColor Cyan
    Write-Host ""

    $residuals = [PSCustomObject]@{
        Services       = @()
        StartupItems   = @()
        ScheduledTasks = @()
        RegistryKeys   = @()
        RebootPending  = @()
    }

    
    $allServices = Get-CimInstance Win32_Service -ErrorAction SilentlyContinue
    $tiaServicePattern = '^(S7TraceService|s7oiehsx|s7oiehsx64|SIMATIC|S7DOS|ALM|almservice)$'
    $tiaDisplayPattern = 'Siemens|SIMATIC|Automation License Manager'
    $matchedServices = $allServices | Where-Object {
        $_.Name -match $tiaServicePattern -or
        $_.DisplayName -match $tiaDisplayPattern
    }
    foreach ($svc in $matchedServices) {
        $path = $svc.PathName
        $exePath = ''
        if ($path) {
            if ($path -match '^"([^"]+\.exe)"') { $exePath = $Matches[1] }
            elseif ($path -match '^([^\s]+\.exe)') { $exePath = $Matches[1] }
        }
        $exeExists = if ($exePath -and (Test-Path $exePath -ErrorAction SilentlyContinue)) { $true } else { $false }
        $isProtected = ($svc.Name -match '^(ALM|almservice)$') -or ($svc.DisplayName -match 'Automation License Manager')
        if ($isProtected) { $exeExists = $true }
        $residuals.Services += [PSCustomObject]@{
            Name        = $svc.Name
            DisplayName = $svc.DisplayName
            Status      = $svc.State
            Path        = $path
            ExeExists   = $exeExists
            IsProtected = $isProtected
        }
    }
    

    
    $startupItems = Get-CimInstance Win32_StartupCommand -ErrorAction SilentlyContinue |
    Where-Object { $_.Command -match 'Siemens|TIA|SIMATIC' }
    foreach ($item in $startupItems) {
        $cmd = $item.Command
        $exePath = ''
        if ($cmd -match '^"([^"]+\.exe)"') { $exePath = $Matches[1] }
        elseif ($cmd -match '^([^\s]+\.exe)') { $exePath = $Matches[1] }
        $exeExists = if ($exePath -and (Test-Path $exePath -ErrorAction SilentlyContinue)) { $true } else { $false }
        $residuals.StartupItems += [PSCustomObject]@{
            Name      = $item.Name
            Command   = $cmd
            ExeExists = $exeExists
        }
    }
    

    
    $tasks = Get-ScheduledTask -ErrorAction SilentlyContinue |
    Where-Object {
        $_.TaskName -match 'Siemens|TIA|SIMATIC' -and
        $_.TaskPath -notmatch '^\\Microsoft\\Windows\\'
    }
    foreach ($task in $tasks) {
        $residuals.ScheduledTasks += [PSCustomObject]@{
            Name  = $task.TaskName
            Path  = $task.TaskPath
            State = $task.State
        }
    }
    

    
    $regPaths = @(
        'HKLM:\SOFTWARE\Siemens',
        'HKLM:\SOFTWARE\WOW6432Node\Siemens',
        'HKCU:\SOFTWARE\Siemens'
    )
    foreach ($path in $regPaths) {
        if (Test-Path $path) {
            $residuals.RegistryKeys += $path
        }
    }
    
    
    $pfro = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' `
        -Name PendingFileRenameOperations -ErrorAction SilentlyContinue
    if ($pfro -and $pfro.PendingFileRenameOperations) {
        $residuals.RebootPending += "PendingFileRenameOperations ($($pfro.PendingFileRenameOperations.Count) 条)"
    }
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') {
        $residuals.RebootPending += 'CBS RebootPending'
    }
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') {
        $residuals.RebootPending += 'WindowsUpdate RebootRequired'
    }
    

    return $residuals
}
function Show-ResidualReport {
    param($Residuals)

    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "  残留检测报告" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""

    # 用 @() 强制转数组，避免 .Count 返回 $null
    $badServices = @($Residuals.Services | Where-Object { -not $_.ExeExists -and -not $_.IsProtected })
    $protectedServices = @($Residuals.Services | Where-Object { $_.IsProtected })
    $badStartup = @($Residuals.StartupItems | Where-Object { -not $_.ExeExists })
    $rebootPending = @($Residuals.RebootPending)
    $scheduledTasks = @($Residuals.ScheduledTasks)
    $registryKeys = @($Residuals.RegistryKeys)
    $allServices = @($Residuals.Services)

    # 挂起重启
    if ($rebootPending.Count -gt 0) {
        Write-Host "  [挂起重启标记]" -ForegroundColor Yellow
        foreach ($r in $rebootPending) {
            Write-Host "    - $r" -ForegroundColor Yellow
        }
        Write-Host ""
    }

    # 残留服务
    if ($badServices.Count -gt 0) {
        Write-Host "  [残留服务 - 文件缺失，可清理]" -ForegroundColor Red
        foreach ($s in $badServices) {
            $label = if ($s.DisplayName) { $s.DisplayName } else { $s.Name }
            Write-Host "    - $label [$($s.Status)]" -ForegroundColor Red
        }
        Write-Host ""
    }

    # 核心服务
    if ($protectedServices.Count -gt 0) {
        Write-Host "  [核心服务 - 勿动]" -ForegroundColor DarkGray
        foreach ($s in $protectedServices) {
            $label = if ($s.DisplayName) { $s.DisplayName } else { $s.Name }
            Write-Host "    - $label [$($s.Status)]" -ForegroundColor DarkGray
        }
        Write-Host ""
    }

    # 正常服务
    $normalCount = $allServices.Count - $badServices.Count - $protectedServices.Count
    if ($normalCount -gt 0) {
        Write-Host "  [正常服务] $normalCount 个 Siemens 相关服务运行正常，无需处理。" -ForegroundColor Gray
        Write-Host ""
    }

    # 无效启动项
    if ($badStartup.Count -gt 0) {
        Write-Host "  [无效启动项 - 文件缺失，可清理]" -ForegroundColor Red
        foreach ($item in $badStartup) {
            Write-Host "    - $($item.Name)" -ForegroundColor Red
        }
        Write-Host ""
    }

    # 计划任务
    if ($scheduledTasks.Count -gt 0) {
        Write-Host "  [计划任务]" -ForegroundColor Yellow
        foreach ($t in $scheduledTasks) {
            Write-Host "    - $($t.Path)$($t.Name) [$($t.State)]" -ForegroundColor Gray
        }
        Write-Host ""
    }

    # 注册表
    if ($registryKeys.Count -gt 0) {
        Write-Host "  [注册表项] 检测到 $($registryKeys.Count) 个 Siemens 相关项（正常）。" -ForegroundColor Gray
        Write-Host ""
    }

    # 总结
    $totalIssues = $badServices.Count + $badStartup.Count + $rebootPending.Count
    if ($totalIssues -eq 0) {
        Write-Host "  ✅ 未检测到明显的残留问题。" -ForegroundColor Green
        Write-Host "     系统状态看起来是干净的。" -ForegroundColor Gray
    }
    else {
        Write-Host "  ⚠️ 发现 $totalIssues 个需要处理的问题。" -ForegroundColor Yellow
        Write-Host "     建议选 [1] 修复挂起重启问题。" -ForegroundColor White
    }
    Write-Host ""
}

# ============================================================
# 1.5 安全退出：挂起重启修复（复用 1.0 逻辑）
# ============================================================
function Clear-RebootPending {
    Write-Host ""
    Write-Host "  正在清理挂起重启标记..." -ForegroundColor Cyan
    Write-Host ""

    $cleaned = 0

    # PendingFileRenameOperations
    $pfro = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' `
        -Name PendingFileRenameOperations -ErrorAction SilentlyContinue
    if ($pfro -and $pfro.PendingFileRenameOperations) {
        try {
            Remove-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' `
                -Name PendingFileRenameOperations -Force -ErrorAction Stop
            Write-Host "  [OK] 已清理 PendingFileRenameOperations" -ForegroundColor Green
            $cleaned++
        }
        catch {
            Write-Host "  [XX] 清理失败：$($_.Exception.Message)" -ForegroundColor Red
        }
    }

    # CBS
    $cbsPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
    if (Test-Path $cbsPath) {
        try {
            Remove-Item $cbsPath -Recurse -Force -ErrorAction Stop
            Write-Host "  [OK] 已清理 CBS RebootPending" -ForegroundColor Green
            $cleaned++
        }
        catch {
            Write-Host "  [XX] CBS 清理失败（可能需要手动处理）" -ForegroundColor Yellow
        }
    }

    # WindowsUpdate
    $wuPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    if (Test-Path $wuPath) {
        try {
            Remove-Item $wuPath -Recurse -Force -ErrorAction Stop
            Write-Host "  [OK] 已清理 WindowsUpdate RebootRequired" -ForegroundColor Green
            $cleaned++
        }
        catch {
            Write-Host "  [XX] WindowsUpdate 清理失败" -ForegroundColor Yellow
        }
    }

    if ($cleaned -eq 0) {
        Write-Host "  没有需要清理的挂起标记。" -ForegroundColor Gray
    }
    else {
        Write-Host ""
        Write-Host "  ✅ 清理完成（$cleaned 项）。" -ForegroundColor Green
        Write-Host "  提示：清理后不要重启，直接重新运行博途安装程序。" -ForegroundColor Cyan
    }
    Write-Host ""
}
# ============================================================
# 1.5.2 系统还原点
# ============================================================
function New-RestorePoint {
    Write-Host ""
    Write-Host "  正在创建系统还原点..." -ForegroundColor Cyan

    # 检查系统保护是否开启
    try {
        $srEnabled = Get-CimInstance -Namespace root/default -ClassName SystemRestore -ErrorAction Stop
    }
    catch {
        $srEnabled = $null
    }

    # 直接尝试创建
    try {
        # 关闭频率限制（Windows 默认 24 小时内只能建一个）
        New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore" `
            -Name "SystemRestorePointCreationFrequency" -Value 0 -PropertyType DWord -Force `
            -ErrorAction SilentlyContinue | Out-Null

        Checkpoint-Computer -Description "TIAHelper Before Cleanup" `
            -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop

        Write-Host "  [OK] 系统还原点已创建。" -ForegroundColor Green
        Write-Host "       描述：TIAHelper Before Cleanup" -ForegroundColor Gray
        return $true
    }
    catch {
        Write-Host "  [!!] 无法创建系统还原点。" -ForegroundColor Yellow
        Write-Host "       原因：$($_.Exception.Message)" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "       可能原因：" -ForegroundColor Gray
        Write-Host "       1. 系统保护未开启（Win11 家庭版默认关闭）" -ForegroundColor Gray
        Write-Host "       2. 磁盘空间不足" -ForegroundColor Gray
        Write-Host ""
        Write-Host "       你可以手动开启：设置 → 系统 → 系统保护 → 配置 → 启用" -ForegroundColor DarkGray
        Write-Host ""
        return $false
    }
}

# ============================================================
# 1.5.2 备份注册表
# ============================================================
function Backup-RegistryKey {
    param([string]$RegPath, [string]$OutputFile)

    try {
        # 转换 PowerShell 路径格式为 reg.exe 格式
        $regExePath = $RegPath -replace '^HKLM:', 'HKLM' -replace '^HKCU:', 'HKCU'
        & reg export $regExePath $OutputFile /y 2>$null | Out-Null
        return (Test-Path $OutputFile)
    }
    catch {
        return $false
    }
}
# ============================================================
# 1.5.3 注册表扫描与分类
# ============================================================
function Scan-SiemensRegistry {
    param([string]$RootPath)

    $result = [PSCustomObject]@{
        RootPath = $RootPath
        Safe     = @()   # 安全清理
        Cautious = @()   # 谨慎清理
        Keep     = @()   # 保留
    }

    if (-not (Test-Path $RootPath)) { return $result }

    # 已知：安全清理的子项/键（缓存、日志、更新器临时数据）
    $safePatterns = @(
        'Cache',
        'Temp',
        'Log',
        'Logfiles',
        'Update',
        'Updater',
        'Downloads',
        'WebCache',
        'CrashDumps'
    )

    # 已知：必须保留的子项（授权、系统服务）
    $keepPatterns = @(
        'Automation License Manager',
        'Licenses',
        'License',
        'ALM',
        'Security',
        'DotNet',
        'Installer',
        'Shared'
    )

    try {
        $subKeys = Get-ChildItem -Path $RootPath -ErrorAction Stop
    }
    catch {
        return $result
    }

    foreach ($key in $subKeys) {
        $name = $key.PSChildName
        $matched = 'Cautious'  # 默认谨慎

        foreach ($p in $safePatterns) {
            if ($name -match $p) { $matched = 'Safe'; break }
        }
        if ($matched -ne 'Safe') {
            foreach ($p in $keepPatterns) {
                if ($name -match $p) { $matched = 'Keep'; break }
            }
        }

        $item = [PSCustomObject]@{
            Name = $name
            Path = $key.PSPath
        }

        switch ($matched) {
            'Safe' { $result.Safe += $item }
            'Cautious' { $result.Cautious += $item }
            'Keep' { $result.Keep += $item }
        }
    }

    return $result
}

function Show-SiemensRegistryReport {
    param($ScanResult)

    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "  注册表扫描报告" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  扫描路径：$($ScanResult.RootPath)" -ForegroundColor Gray
    Write-Host ""

    if ($ScanResult.Safe.Count -gt 0) {
        Write-Host "  [安全清理 - 缓存、日志、临时数据]" -ForegroundColor Green
        foreach ($item in $ScanResult.Safe) {
            Write-Host "    - $($item.Name)" -ForegroundColor Green
        }
        Write-Host "      删除后：无影响，下次使用会重建。" -ForegroundColor DarkGray
        Write-Host ""
    }

    if ($ScanResult.Cautious.Count -gt 0) {
        Write-Host "  [谨慎清理 - 组件配置]" -ForegroundColor Yellow
        foreach ($item in $ScanResult.Cautious) {
            Write-Host "    - $($item.Name)" -ForegroundColor Yellow
        }
        Write-Host "      删除后：当前博途可能失效，需要重新配置。" -ForegroundColor DarkGray
        Write-Host "      适用场景：你想彻底重装博途。" -ForegroundColor DarkGray
        Write-Host ""
    }

    if ($ScanResult.Keep.Count -gt 0) {
        Write-Host "  [禁止清理 - 授权、系统服务]" -ForegroundColor DarkGray
        foreach ($item in $ScanResult.Keep) {
            Write-Host "    - $($item.Name)" -ForegroundColor DarkGray
        }
        Write-Host ""
    }

    Write-Host "  ──────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host "  安全：$($ScanResult.Safe.Count)   谨慎：$($ScanResult.Cautious.Count)   保留：$($ScanResult.Keep.Count)" -ForegroundColor White
    Write-Host "  ──────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""
}

function Invoke-SiemensRegistryCleanup {
    param($ScanResult)

    # 没有可清理的
    if ($ScanResult.Safe.Count -eq 0 -and $ScanResult.Cautious.Count -eq 0) {
        Write-Host "  ✅ 没有可清理的注册表项。" -ForegroundColor Green
        Write-Host ""
        Write-Host "  按 [Enter] 返回..." -ForegroundColor White
        $null = [Console]::ReadKey($true)
        return
    }

    Write-Host "  请选择清理范围：" -ForegroundColor White
    Write-Host ""
    Write-Host "  [1] 只清理【安全】层级（推荐）"
    Write-Host "  [2] 清理【安全 + 谨慎】层级（彻底重置）"
    Write-Host "  [3] 取消"
    Write-Host ""

    $choice = Read-MenuChoice -ValidKeys @('1', '2', '3')

    $toDelete = @()
    switch ($choice) {
        '1' { $toDelete = $ScanResult.Safe }
        '2' { $toDelete = $ScanResult.Safe + $ScanResult.Cautious }
        '3' {
            Write-Host "  已取消。" -ForegroundColor Yellow
            Write-Host "  按 [Enter] 返回..." -ForegroundColor White
            $null = [Console]::ReadKey($true)
            return
        }
    }

    # 创建还原点
    Write-Host ""
    $restoreOk = New-RestorePoint

    if (-not $restoreOk) {
        Write-Host "  [!!] 无还原点保护，继续有风险。" -ForegroundColor Yellow
        Write-Host "  按 [Enter] 继续，或按 [Q] 取消..." -ForegroundColor White
        $k = [Console]::ReadKey($true)
        
        if ($k.KeyChar -match '^[Qq]$') {
            Write-Host "  已取消。" -ForegroundColor Yellow
            return
        }
    }

    # 备份整个 Siemens 键
    $backupDir = "$env:LOCALAPPDATA\TIAHelper\backup"
    if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $backupFile = "$backupDir\Siemens_$timestamp.reg"

    Write-Host ""
    Write-Host "  正在备份整个 Siemens 注册表键..." -ForegroundColor Cyan
    $backupOk = Backup-RegistryKey -RegPath $ScanResult.RootPath -OutputFile $backupFile
    if ($backupOk) {
        Write-Host "  [OK] 备份成功：$backupFile" -ForegroundColor Green
    }
    else {
        Write-Host "  [XX] 备份失败，中止清理。" -ForegroundColor Red
        Write-Host "  按 [Enter] 返回..." -ForegroundColor White
        $null = [Console]::ReadKey($true)
        return
    }

    # ============================================================
    # 第一层确认
    # ============================================================
    Clear-Host
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "  ⚠️  危险操作确认" -ForegroundColor Red
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  即将删除 $($toDelete.Count) 个 Siemens 注册表子项。" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  如果选的是【安全 + 谨慎】层级，" -ForegroundColor Yellow
    Write-Host "  博途将无法使用，必须重新安装。" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  备份文件：$backupFile" -ForegroundColor DarkGray
    Write-Host "  如需恢复，双击备份文件即可。" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  ──────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host "  第一层确认" -ForegroundColor Yellow
    Write-Host "  ──────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  请输入 clean 继续（按 Esc 取消）：" -ForegroundColor White
    Write-Host ""
    Write-Host "  > " -NoNewline -ForegroundColor Cyan

    $c1 = Read-ConfirmInput
    if ($null -eq $c1 -or $c1 -ne 'clean') {
        Write-Host ""
        Write-Host "  已取消。" -ForegroundColor Yellow
        Write-Host "  按 [Enter] 返回..." -ForegroundColor White
        $null = [Console]::ReadKey($true)
        return
    }

    # ============================================================
    # 第二层确认
    # ============================================================
    Clear-Host
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "  ⚠️  最终确认" -ForegroundColor Red
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  这是最后一步。" -ForegroundColor Red
    Write-Host "  一旦确认，将无法在本次会话中撤销。" -ForegroundColor Red
    Write-Host ""
    Write-Host "  如果你不确定，请按 Esc 取消。" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  ──────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host "  第二层确认" -ForegroundColor Red
    Write-Host "  ──────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  请再次输入 clean 确认（按 Esc 取消）：" -ForegroundColor White
    Write-Host ""
    Write-Host "  > " -NoNewline -ForegroundColor Cyan

    $c2 = Read-ConfirmInput
    if ($null -eq $c2 -or $c2 -ne 'clean') {
        Write-Host ""
        Write-Host "  已取消。" -ForegroundColor Yellow
        Write-Host "  按 [Enter] 返回..." -ForegroundColor White
        $null = [Console]::ReadKey($true)
        return
    }

    # ============================================================
    # 两层通过，开始清理
    # ============================================================
    Write-Host ""
    Write-Host "  ✅ 两层验证通过。" -ForegroundColor Green
    Write-Host "  开始清理..." -ForegroundColor Cyan
    Write-Host ""

    # 执行删除
    Write-Host ""
    Write-Host "  开始清理..." -ForegroundColor Cyan
    Write-Host ""

    $deleted = 0
    $failed = 0

    foreach ($item in $toDelete) {
        try {
            Remove-Item -Path $item.Path -Recurse -Force -ErrorAction Stop
            Write-Host "  [OK] 已删除：$($item.Name)" -ForegroundColor Green
            $deleted++
        }
        catch {
            Write-Host "  [XX] 删除失败：$($item.Name) — $($_.Exception.Message)" -ForegroundColor Red
            $failed++
        }
    }

    Write-Host ""
    Write-Host "  ──────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host "  清理完成" -ForegroundColor Green
    Write-Host "  成功：$deleted   失败：$failed" -ForegroundColor White
    Write-Host "  备份：$backupFile" -ForegroundColor DarkGray
    Write-Host "  ──────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  按 [Enter] 返回..." -ForegroundColor White
    $null = [Console]::ReadKey($true)
}
# ============================================================
# 1.5.2 残留清理
# ============================================================
function Invoke-ResidualCleanup {
    param($Residuals)

    Clear-Host
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "  残留清理" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""

    # 收集可清理项
    $badServices = @($Residuals.Services | Where-Object { -not $_.ExeExists -and -not $_.IsProtected })
    $badStartup = @($Residuals.StartupItems | Where-Object { -not $_.ExeExists })

    $totalCleanable = $badServices.Count + $badStartup.Count

    if ($totalCleanable -eq 0) {
        Write-Host "  ✅ 没有可清理的残留。" -ForegroundColor Green
        Write-Host "     当前系统状态是干净的。" -ForegroundColor Gray
        Write-Host ""
        Write-Host "  按 [Enter] 返回..." -ForegroundColor White
        $null = [Console]::ReadKey($true)
        return
    }

    Write-Host "  检测到以下可清理项：" -ForegroundColor Yellow
    Write-Host ""

    if ($badServices.Count -gt 0) {
        Write-Host "  [无效服务 - 文件缺失]" -ForegroundColor Red
        foreach ($s in $badServices) {
            $label = if ($s.DisplayName) { $s.DisplayName } else { $s.Name }
            Write-Host "    - $label [$($s.Status)]" -ForegroundColor Red
        }
        Write-Host ""
    }

    if ($badStartup.Count -gt 0) {
        Write-Host "  [无效启动项 - 文件缺失]" -ForegroundColor Red
        foreach ($item in $badStartup) {
            Write-Host "    - $($item.Name)" -ForegroundColor Red
        }
        Write-Host ""
    }

    # 创建还原点
    Write-Host "  ──────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host "  清理前会创建系统还原点（如果系统保护已开启）" -ForegroundColor Gray
    Write-Host "  ──────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""

    $restoreOk = New-RestorePoint

    if (-not $restoreOk) {
        Write-Host "  [!!] 无法创建还原点。" -ForegroundColor Yellow
        Write-Host "       没有还原点保护，清理风险较高。" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  [1] 我明白风险，继续清理"
        Write-Host "  [2] 取消，先开启系统保护"
        Write-Host ""
        $choice = Read-MenuChoice -ValidKeys @('1', '2')
        if ($choice -ne '1') {
            Write-Host "  已取消。" -ForegroundColor Yellow
            Write-Host "  按 [Enter] 返回..." -ForegroundColor White
            $null = [Console]::ReadKey($true)
            return
        }
    }

    # 备份注册表
    $backupDir = "$env:LOCALAPPDATA\TIAHelper\backup"
    if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'

    # 二次确认
    Write-Host ""
    Write-Host "  ──────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host "  ⚠️  即将清理 $totalCleanable 项残留。" -ForegroundColor Yellow
    Write-Host "  ──────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  如果你确认清理，请输入：clean"
    Write-Host "  （其他任何输入都会取消）"
    Write-Host ""
    $confirm = Read-Host "  确认"

    if ($confirm -ne 'clean') {
        Write-Host ""
        Write-Host "  已取消。" -ForegroundColor Yellow
        Write-Host "  按 [Enter] 返回..." -ForegroundColor White
        $null = [Console]::ReadKey($true)
        return
    }

    # 执行清理
    Write-Host ""
    Write-Host "  开始清理..." -ForegroundColor Cyan
    Write-Host ""

    $cleanedServices = 0
    $cleanedStartup = 0

    # 清理服务
    foreach ($s in $badServices) {
        Write-Host "  正在删除服务：$($s.Name)..." -ForegroundColor Gray
        try {
            & sc.exe delete $s.Name 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "    [OK] 已删除" -ForegroundColor Green
                $cleanedServices++
            }
            else {
                Write-Host "    [XX] 删除失败（错误码 $LASTEXITCODE）" -ForegroundColor Red
            }
        }
        catch {
            Write-Host "    [XX] $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    # 清理启动项
    foreach ($item in $badStartup) {
        Write-Host "  正在删除启动项：$($item.Name)..." -ForegroundColor Gray
        try {
            # 备份启动项所在注册表
            $backupFile = "$backupDir\startup_$($timestamp)_$($cleanedStartup).reg"
            # 尝试从常见位置删除
            $startupKeys = @(
                'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
                'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
                'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
            )
            $deleted = $false
            foreach ($key in $startupKeys) {
                $value = Get-ItemProperty -Path $key -Name $item.Name -ErrorAction SilentlyContinue
                if ($value) {
                    Backup-RegistryKey -RegPath $key -OutputFile $backupFile | Out-Null
                    Remove-ItemProperty -Path $key -Name $item.Name -Force -ErrorAction Stop
                    $deleted = $true
                    break
                }
            }
            if ($deleted) {
                Write-Host "    [OK] 已删除（备份：$backupFile）" -ForegroundColor Green
                $cleanedStartup++
            }
            else {
                Write-Host "    [!!] 未找到对应注册表项" -ForegroundColor Yellow
            }
        }
        catch {
            Write-Host "    [XX] $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    Write-Host ""
    Write-Host "  ──────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host "  清理完成" -ForegroundColor Green
    Write-Host "  服务：$cleanedServices / $($badServices.Count)" -ForegroundColor White
    Write-Host "  启动项：$cleanedStartup / $($badStartup.Count)" -ForegroundColor White
    Write-Host "  ──────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  备份目录：$backupDir" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  按 [Enter] 返回..." -ForegroundColor White
    $null = [Console]::ReadKey($true)
}
# ============================================================
# 1.7 授权引导
# ============================================================
function Get-ALMStatus {
    # 查找 ALM 服务
    $almService = Get-Service -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '^(ALM|almservice)$' -or $_.DisplayName -match 'Automation License Manager' } |
    Select-Object -First 1

    if (-not $almService) {
        return [PSCustomObject]@{
            Found     = $false
            Name      = ''
            Display   = ''
            Status    = ''
            StartType = ''
        }
    }

    return [PSCustomObject]@{
        Found     = $true
        Name      = $almService.Name
        Display   = $almService.DisplayName
        Status    = $almService.Status
        StartType = $almService.StartType
    }
}

function Get-ALMPath {
    # ============================================================
    # 方法1：从开始菜单快捷方式反查（最可靠，不依赖安装盘符）
    # ============================================================
    try {
        $sh = New-Object -ComObject WScript.Shell
        $startMenus = @(
            "$env:ProgramData\Microsoft\Windows\Start Menu\Programs",
            "$env:APPDATA\Microsoft\Windows\Start Menu\Programs"
        )
        foreach ($menu in $startMenus) {
            if (-not (Test-Path $menu)) { continue }
            $lnks = Get-ChildItem $menu -Recurse -Filter "*.lnk" -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match 'Automation License Manager|ALM' }
            foreach ($lnk in $lnks) {
                $target = $sh.CreateShortcut($lnk.FullName).TargetPath
                if ($target -and (Test-Path $target)) {
                    return $target
                }
            }
        }
    }
    catch { }

    # ============================================================
    # 方法2：从运行中的进程反查
    # ============================================================
    $guiProc = Get-Process -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowTitle -match 'Automation License Manager' } |
    Select-Object -First 1
    if ($guiProc) {
        $p = $guiProc.Path
        if ($p -and (Test-Path $p)) { return $p }
        try {
            $wmiProc = Get-CimInstance Win32_Process -Filter "Name='$($guiProc.ProcessName).exe'" -ErrorAction Stop |
            Select-Object -First 1
            if ($wmiProc -and $wmiProc.ExecutablePath) { return $wmiProc.ExecutablePath }
        }
        catch { }
    }

    # ============================================================
    # 方法3：在所有盘搜索 alm 相关目录
    # ============================================================
    $guiNames = @('almgui64x.exe', 'almgui.exe', 'almgui32x.exe')

    # 遍历所有盘，找 Siemens 目录
    $allRoots = @()
    Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue |
    Where-Object { $_.Root -match '^[A-Z]:\\$' } |
    ForEach-Object { $allRoots += "$($_.Root)Siemens" }

    # 加上常见路径（C 盘）
    $allRoots += @(
        "C:\Program Files\Siemens",
        "C:\Program Files (x86)\Siemens",
        "C:\Program Files\Common Files\Siemens",
        "C:\Program Files (x86)\Common Files\Siemens"
    )

    foreach ($root in $allRoots) {
        if (-not (Test-Path $root)) { continue }
        foreach ($name in $guiNames) {
            $found = Get-ChildItem $root -Recurse -Filter $name -ErrorAction SilentlyContinue |
            Select-Object -First 1
            if ($found) { return $found.FullName }
        }
    }

    # ============================================================
    # 方法4：兜底递归搜所有盘
    # ============================================================
    Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue |
    Where-Object { $_.Root -match '^[A-Z]:\\$' } |
    ForEach-Object {
        $root = $_.Root
        if (-not (Test-Path $root)) { return }
        $found = Get-ChildItem $root -Recurse -Filter "almgui*.exe" -ErrorAction SilentlyContinue -Depth 5 |
        Select-Object -First 1
        if ($found) { return $found.FullName }
    }

    return $null
}

function Find-LicenseFiles {
    $searchPaths = @(
        "C:\Program Files (x86)\Siemens\Automation\WinCC\flexible\License",
        "C:\ProgramData\Siemens\Automation\License",
        "C:\ProgramData\Siemens\Automation\Logfiles",
        "$env:USERPROFILE\Documents\Siemens\Automation"
    )
    $found = @()
    foreach ($p in $searchPaths) {
        if (-not (Test-Path $p)) { continue }
        $files = Get-ChildItem $p -Recurse -Include *.lic, *.awl -ErrorAction SilentlyContinue
        if ($files) {
            $found += $files
        }
    }
    return $found
}

function Show-ALMStatus {
    param($AlmStatus)

    Write-Host "  [1] Automation License Manager 服务" -ForegroundColor Cyan
    Write-Host "  ──────────────────────────────────────────" -ForegroundColor DarkGray

    if (-not $AlmStatus.Found) {
        Write-Host "    [XX] 未找到 ALM 服务。" -ForegroundColor Red
        Write-Host "         你可能还没装博途，或者安装没完成。" -ForegroundColor DarkGray
        Write-Host "         建议先完成博途安装。" -ForegroundColor DarkGray
        Write-Host ""
        return $false
    }

    $statusColor = if ($AlmStatus.Status -eq 'Running') { 'Green' } else { 'Red' }
    Write-Host "    - 服务名：$($AlmStatus.Name)" -ForegroundColor Gray
    Write-Host "    - 显示名：$($AlmStatus.Display)" -ForegroundColor Gray
    Write-Host "    - 状态：$($AlmStatus.Status)" -ForegroundColor $statusColor
    Write-Host "    - 启动类型：$($AlmStatus.StartType)" -ForegroundColor Gray
    Write-Host ""

    if ($AlmStatus.Status -ne 'Running') {
        Write-Host "    ⚠️ 服务未运行，博途会提示『找不到许可证』。" -ForegroundColor Yellow
        Write-Host "       建议：现在启动 ALM 服务。" -ForegroundColor Yellow
        return $false
    }
    return $true
}

function Test-TrialLicense {
    param($AlmPath)
    # 试用期信息在 ALM 内部，PowerShell 只能给出间接判断
    # 通过查看 ALM 日志（如果存在）判断是否用过试用
    $trialLogPaths = @(
        "C:\ProgramData\Siemens\Automation\Automation License Manager\logging",
        "C:\Program Files (x86)\Siemens\Automation License Manager\Logging"
    )
    $found = @()
    foreach ($p in $trialLogPaths) {
        if (-not (Test-Path $p)) { continue }
        $files = Get-ChildItem $p -Filter "*.log" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 3
        foreach ($f in $files) {
            try {
                $content = Get-Content $f.FullName -Tail 100 -ErrorAction SilentlyContinue
                $trialLines = $content | Where-Object { $_ -match 'Trial|trial|Rental|Demo' }
                if ($trialLines) {
                    $found += [PSCustomObject]@{
                        File  = $f.FullName
                        Lines = $trialLines
                    }
                }
            }
            catch { }
        }
    }
    return $found
}

function Show-LicenseErrorCodes {
    Write-Host ""
    Write-Host "  [常见授权错误码]" -ForegroundColor Cyan
    Write-Host "  ──────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  0xC0000005  | 访问冲突" -ForegroundColor White
    Write-Host "              原因：许可证服务未运行，或权限不足。" -ForegroundColor DarkGray
    Write-Host "              解决：以管理员身份运行博途；确认 ALM 服务已启动。" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  1067        | 进程意外终止" -ForegroundColor White
    Write-Host "              原因：ALM 服务依赖缺失，或端口被占用。" -ForegroundColor DarkGray
    Write-Host "              解决：重启 ALM 服务；检查 27000-27009 端口占用。" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  1068        | 依赖服务启动失败" -ForegroundColor White
    Write-Host "              原因：ALM 依赖的其他系统服务未启动。" -ForegroundColor DarkGray
    Write-Host "              解决：手动启动依赖服务；重启电脑。" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  -1          | 授权未找到" -ForegroundColor White
    Write-Host "              原因：许可证文件丢失、损坏，或未导入。" -ForegroundColor DarkGray
    Write-Host "              解决：运行 Sim_EKB_Install 重新激活；检查 ALM 界面是否显示许可证。" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  试用期已过  | 试用许可证已用完" -ForegroundColor White
    Write-Host "              原因：14/21 天试用期到期，或卸载后重装（试用期不重置）。" -ForegroundColor DarkGray
    Write-Host "              解决：购买正式授权，或用 Sim_EKB_Install。" -ForegroundColor DarkGray
    Write-Host ""
}
# ============================================================
# 1.8 日常使用
# ============================================================

# 保护名单：这些进程绝不清理
$script:ProtectedProcesses = @(
    # ALM 授权
    'almservice', 'almsrv64x', 'almsrvbubble64x',
    # SQL Server
    'sqlservr', 'sqlceip', 'SQLAGENT',
    # WinCC
    'CCProjectMgr', 'CCAgent',
    # S7 通信
    'S7O.TunnelServiceHost', 's7oiehsx64', 's7oiehsx', 's7oPNDiscoveryx64',
    # 跟踪
    'S7TraceService64X', 'S7TraceServiceX',
    # TIA 管理
    'node',
    # 授权服务器
    'lmgrd', 'ugslmd',
    # Siemens 系统服务
    'Siemens.Automation.Tracing.ETW.EventCollector.ServiceHost',
    'Siemens.Simatic.TelemetryConnector.WindowsService'
)

# Siemens 特征：进程名或路径匹配
$script:SiemensPattern = 'Siemens|SIMATIC|s7o|S7Trace|CCProject|CCAlg|CCDelta|CCLicense|CCNSInfo|CCPackage|CCProfile|CCRts|CCSystem|CCText|CCTlg|CCTM|CCUsr|TIA|WinCC|Portal|PLM'

function Get-SiemensProcesses {
    $procs = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue
    $result = @()
    foreach ($p in $procs) {
        $isSiemens = ($p.Name -match $script:SiemensPattern) -or ($p.ExecutablePath -and $p.ExecutablePath -match 'Siemens')
        if (-not $isSiemens) { continue }

        $isProtected = $false
        foreach ($protected in $script:ProtectedProcesses) {
            if ($p.Name -match [regex]::Escape($protected)) { $isProtected = $true; break }
        }

        # 判断有无可见窗口
        $hasWindow = $false
        try {
            $psProc = Get-Process -Id $p.ProcessId -ErrorAction SilentlyContinue
            if ($psProc -and $psProc.MainWindowHandle -ne 0) { $hasWindow = $true }
        }
        catch { }

        $memMB = 0
        $cpu = 0
        try {
            $psProc = Get-Process -Id $p.ProcessId -ErrorAction SilentlyContinue
            if ($psProc) {
                $memMB = [math]::Round($psProc.WorkingSet64 / 1MB, 1)
                $cpu = [math]::Round($psProc.CPU, 1)
            }
        }
        catch { }

        $result += [PSCustomObject]@{
            Name        = $p.Name
            PID         = $p.ProcessId
            MemoryMB    = $memMB
            CPU         = $cpu
            HasWindow   = $hasWindow
            IsProtected = $isProtected
            Path        = $p.ExecutablePath
        }
    }
    return $result
}

function Show-ProcessList {
    Clear-Host
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "  Siemens 相关进程" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""

    $procs = Get-SiemensProcesses

    if ($procs.Count -eq 0) {
        Write-Host "  未检测到 Siemens 相关进程。" -ForegroundColor Gray
        Write-Host ""
        Write-Host "  按 [Enter] 返回..." -ForegroundColor White
        $null = [Console]::ReadKey($true)
        return
    }

    $totalMem = [math]::Round(($procs | Measure-Object MemoryMB -Sum).Sum, 1)

    Write-Host "  共 $($procs.Count) 个进程，占用内存 $totalMem MB" -ForegroundColor White
    Write-Host ""
    Write-Host "  ------------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "   进程名                       PID      内存MB   CPU秒    状态" -ForegroundColor DarkGray
    Write-Host "  ------------------------------------------------------------------" -ForegroundColor DarkGray

    foreach ($p in ($procs | Sort-Object MemoryMB -Descending)) {
        $name = if ($p.Name.Length -gt 26) { $p.Name.Substring(0, 26) } else { $p.Name.PadRight(26) }
        $pidStr = $p.PID.ToString().PadRight(8)
        $mem = $p.MemoryMB.ToString().PadRight(8)
        $cpu = $p.CPU.ToString().PadRight(8)

        $status = if ($p.IsProtected) { "保护" }
        elseif ($p.HasWindow) { "有窗口" }
        else { "空闲" }
        $status = $status.PadRight(6)

        $color = if ($p.IsProtected) { 'DarkGray' }
        elseif ($p.HasWindow) { 'Yellow' }
        else { 'Green' }

        Write-Host "   $name $pidStr $mem $cpu $status" -ForegroundColor $color
    }
    Write-Host "  ------------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  图例：" -ForegroundColor White
    Write-Host "    保护   = 不能关（关了博途会崩）" -ForegroundColor DarkGray
    Write-Host "    有窗口 = 你正在用，不要关" -ForegroundColor DarkGray
    Write-Host "    空闲   = 后台残留，可以关" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  按 [Enter] 返回..." -ForegroundColor White
    $null = [Console]::ReadKey($true)
}

function Invoke-CleanIdleProcesses {
    Clear-Host
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "  一键清理空闲进程" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""

    $procs = Get-SiemensProcesses
    $cleanable = @($procs | Where-Object { -not $_.IsProtected -and -not $_.HasWindow })

    if ($cleanable.Count -eq 0) {
        Write-Host "  ✅ 没有可清理的空闲进程。" -ForegroundColor Green
        Write-Host "     所有 Siemens 进程要么在用，要么是核心服务。" -ForegroundColor Gray
        Write-Host ""
        Write-Host "  按 [Enter] 返回..." -ForegroundColor White
        $null = [Console]::ReadKey($true)
        return
    }

    Write-Host "  以下进程可以安全关闭：" -ForegroundColor Yellow
    Write-Host ""
    $totalMem = 0
    foreach ($p in $cleanable) {
        Write-Host "    - $($p.Name) (PID $($p.PID)) 内存 $($p.MemoryMB) MB" -ForegroundColor Gray
        $totalMem += $p.MemoryMB
    }
    Write-Host ""
    Write-Host "  预计释放内存：约 $([math]::Round($totalMem, 1)) MB" -ForegroundColor Green
    Write-Host ""
    Write-Host "  ⚠️  关闭后，如果博途正在用这些组件，可能会短暂卡顿。" -ForegroundColor Yellow
    Write-Host "     建议：先关掉博途，再跑这个功能。" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  [1] 清理（逐条确认）"
    Write-Host "  [2] 全部清理（不逐条问）"
    Write-Host "  [3] 取消"
    Write-Host ""
    Write-Host "  按数字键选择：" -ForegroundColor White

    $choice = Read-MenuChoice -ValidKeys @('1', '2', '3')
    if ($choice -eq '3') { return }

    $killed = 0
    $failed = 0

    if ($choice -eq '1') {
        # 逐条确认
        foreach ($p in $cleanable) {
            Write-Host ""
            Write-Host "  关闭 $($p.Name) (PID $($p.PID))？" -ForegroundColor Yellow
            Write-Host "    [Y] 关闭  [N] 跳过  [A] 全部关闭  [Q] 退出" -ForegroundColor White
            $k = [Console]::ReadKey($true).KeyChar.ToString().ToUpper()
            if ($k -eq 'Q') { break }
            if ($k -eq 'N') { continue }
            if ($k -eq 'A') { $choice = '2' }
            if ($k -eq 'Y' -or $k -eq 'A') {
                try {
                    Stop-Process -Id $p.PID -Force -ErrorAction Stop
                    Write-Host "    [OK] 已关闭 $($p.Name)" -ForegroundColor Green
                    $killed++
                }
                catch {
                    Write-Host "    [XX] 失败：$($_.Exception.Message)" -ForegroundColor Red
                    $failed++
                }
                if ($k -eq 'A') { $choice = '2'; break }
            }
        }
    }

    if ($choice -eq '2') {
        foreach ($p in $cleanable) {
            try {
                Stop-Process -Id $p.PID -Force -ErrorAction Stop
                Write-Host "  [OK] 已关闭 $($p.Name)" -ForegroundColor Green
                $killed++
            }
            catch {
                Write-Host "  [XX] $($p.Name) 失败" -ForegroundColor Red
                $failed++
            }
        }
    }

    Write-Host ""
    Write-Host "  ──────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host "  清理完成：成功 $killed，失败 $failed" -ForegroundColor Green
    Write-Host "  ──────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  按 [Enter] 返回..." -ForegroundColor White
    $null = [Console]::ReadKey($true)
}

function Show-StartupItems {
    Clear-Host
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "  Siemens 相关启动项" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""

    $items = Get-CimInstance Win32_StartupCommand -ErrorAction SilentlyContinue |
    Where-Object { $_.Command -match 'Siemens|SIMATIC|TIA|s7o|WinCC' }

    if ($items.Count -eq 0) {
        Write-Host "  未检测到 Siemens 相关启动项。" -ForegroundColor Gray
        Write-Host ""
        Write-Host "  按 [Enter] 返回..." -ForegroundColor White
        $null = [Console]::ReadKey($true)
        return
    }

    Write-Host "  共 $($items.Count) 项：" -ForegroundColor White
    Write-Host ""

    foreach ($item in $items) {
        # 判断路径是否存在
        $exePath = ''
        if ($item.Command -match '^"([^"]+\.exe)"') { $exePath = $Matches[1] }
        elseif ($item.Command -match '^([^\s]+\.exe)') { $exePath = $Matches[1] }
        $exeExists = if ($exePath -and (Test-Path $exePath -ErrorAction SilentlyContinue)) { $true } else { $false }

        $status = if ($exeExists) { "正常" } else { "文件缺失" }
        $color = if ($exeExists) { 'Gray' } else { 'Red' }
        Write-Host "  - $($item.Name) [$status]" -ForegroundColor $color
        Write-Host "    位置：$($item.Location)" -ForegroundColor DarkGray
        Write-Host "    命令：$($item.Command)" -ForegroundColor DarkGray
        Write-Host ""
    }

    Write-Host "  ──────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host "  建议：" -ForegroundColor White
    Write-Host "    - 文件缺失的启动项：可以清理（1.5.2 已支持）" -ForegroundColor Gray
    Write-Host "    - 正常启动项：如果不需要开机自启，可以在任务管理器里禁用" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  按 [Enter] 返回..." -ForegroundColor White
    $null = [Console]::ReadKey($true)
}

function Show-ErrorCodeLookup {
    Clear-Host
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "  错误码查询" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""

    $codes = @{
        '1332'       = @("账户名与安全ID无映射", "系统用户名含中文导致", "新建英文用户，用新用户安装")
        '1603'       = @("安装致命错误", "权限不足 / 磁盘空间不足 / 杀毒拦截", "以管理员运行，关杀毒，检查磁盘")
        '2503'       = @("安装程序权限问题", "需要管理员权限", "右键安装程序 → 以管理员身份运行")
        '2502'       = @("安装程序启动失败", "MSI 服务异常", "重启 MSI 服务：net start msiserver")
        '1067'       = @("进程意外终止", "服务依赖缺失或端口占用", "重启服务，检查端口占用")
        '1068'       = @("依赖服务启动失败", "依赖的系统服务未启动", "手动启动依赖服务，重启电脑")
        '0xc0000005' = @("访问冲突", "内存访问非法 / 权限不足", "管理员运行，检查杀软")
        '0x80004005' = @("未指定错误", "通用错误码，多种原因", "查看详细日志，重新安装对应组件")
        '0x80070643' = @("安装失败", ".NET 安装失败 / MSI 异常", "修复 .NET，重装 MSI")
        '0x80070005' = @("拒绝访问", "权限不足", "管理员权限运行，检查文件夹权限")
        '0x8007000e' = @("内存不足", "系统内存不够", "关闭其他程序，或加内存")
        '0x800f081f' = @(".NET 源文件缺失", "本地无 .NET 3.5 源", "联网后重试，或挂载系统 ISO")
        '3'          = @("系统找不到指定路径", "安装包路径被移动/删除", "重新解压安装包，用纯英文路径")
        '5'          = @("访问被拒绝", "权限问题", "以管理员运行")
        '-1'         = @("通用错误", "多种原因，看日志", "查看安装日志具体信息")
        '试用期已过'      = @("试用许可证用完", "14/21 天试用到期，卸载重装也不重置", "购买正式授权，或用注册机")
    }

    Write-Host "  常用错误码：" -ForegroundColor White
    Write-Host ""
    $i = 0
    $keys = @($codes.Keys | Sort-Object)
    foreach ($code in $keys) {
        $i++
        Write-Host "    [$i] $code — $($codes[$code][0])" -ForegroundColor Gray
    }
    Write-Host ""
    Write-Host "  输入错误码查询，或输入编号查看，直接回车退出：" -ForegroundColor White
    Write-Host "  （错误码可以带或不带 0x 前缀，大小写不限）"
    Write-Host ""

    $input = Read-Host "  查询"

    if ([string]::IsNullOrWhiteSpace($input)) { return }

    # 数字编号
    if ($input -match '^\d+$' -and [int]$input -ge 1 -and [int]$input -le $keys.Count) {
        $code = $keys[[int]$input - 1]
    }
    else {
        $code = $input.Trim().ToLower()
    }

    # 精确匹配
    $found = $null
    if ($codes.ContainsKey($code)) {
        $found = $codes[$code]
    }
    else {
        # 模糊匹配
        foreach ($k in $codes.Keys) {
            if ($k.ToLower() -eq $code -or $k.ToLower().Contains($code)) {
                $found = $codes[$k]
                $code = $k
                break
            }
        }
    }

    Write-Host ""
    if ($found) {
        Write-Host "  ══════════════════════════════════════════" -ForegroundColor Cyan
        Write-Host "  错误码：$code" -ForegroundColor Cyan
        Write-Host "  ══════════════════════════════════════════" -ForegroundColor Cyan
        Write-Host "  含义：$($found[0])" -ForegroundColor White
        Write-Host "  原因：$($found[1])" -ForegroundColor Yellow
        Write-Host "  解决：$($found[2])" -ForegroundColor Green
        Write-Host ""
    }
    else {
        Write-Host "  未在知识库找到这个错误码。" -ForegroundColor Yellow
        Write-Host "  建议：" -ForegroundColor White
        Write-Host "    1. 把错误码发给我（工具开发者）" -ForegroundColor Gray
        Write-Host "    2. 或者用 1.6 日志收集功能，打包日志后找人看" -ForegroundColor Gray
        Write-Host ""
    }

    Write-Host "  按 [Enter] 返回..." -ForegroundColor White
    $null = [Console]::ReadKey($true)
}
# ============================================================
# 1.9 卸载/重装
# ============================================================

function Get-InstalledSiemensComponents {
    $components = @()
    $regPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($rp in $regPaths) {
        try {
            $items = Get-ItemProperty $rp -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -match 'Siemens|SIMATIC|TIA|WinCC|STEP 7|Automation License' }
            foreach ($item in $items) {
                $components += [PSCustomObject]@{
                    Name            = $item.DisplayName
                    Version         = $item.DisplayVersion
                    Publisher       = $item.Publisher
                    InstallLocation = $item.InstallLocation
                    UninstallString = $item.UninstallString
                }
            }
        }
        catch { }
    }
    return $components
}

function Show-InstalledComponents {
    Clear-Host
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "  已安装的 Siemens 组件" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""

    $components = Get-InstalledSiemensComponents

    if ($components.Count -eq 0) {
        Write-Host "  未检测到 Siemens 组件。" -ForegroundColor Gray
        Write-Host "  可能是：还没装博途，或已完全卸载。" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  按 [Enter] 返回..." -ForegroundColor White
        $null = [Console]::ReadKey($true)
        return
    }

    Write-Host "  共 $($components.Count) 个组件：" -ForegroundColor White
    Write-Host ""
    foreach ($c in ($components | Sort-Object Name)) {
        Write-Host "  - $($c.Name)" -ForegroundColor Green
        if ($c.Version) { Write-Host "      版本：$($c.Version)" -ForegroundColor Gray }
        if ($c.InstallLocation) { Write-Host "      路径：$($c.InstallLocation)" -ForegroundColor DarkGray }
    }
    Write-Host ""
    Write-Host "  按 [Enter] 返回..." -ForegroundColor White
    $null = [Console]::ReadKey($true)
}

function Backup-AlmLicenses {
    Clear-Host
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "  备份 ALM 许可证" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""

    # ALM 许可证存储位置（隐藏目录）
    $licenseDirs = @(
        "C:\AX NF ZZ",
        "C:\ProgramData\Siemens\Automation\License",
        "C:\ProgramData\Siemens\Automation\Automation License Manager"
    )

    $found = @()
    foreach ($dir in $licenseDirs) {
        if (Test-Path $dir) {
            $found += $dir
        }
    }

    if ($found.Count -eq 0) {
        Write-Host "  未找到 ALM 许可证存储目录。" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  可能原因：" -ForegroundColor Gray
        Write-Host "    1. 你的许可证是通过注册机激活的（在别处）" -ForegroundColor DarkGray
        Write-Host "    2. 或者根本没有许可证" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  按 [Enter] 返回..." -ForegroundColor White
        $null = [Console]::ReadKey($true)
        return
    }

    Write-Host "  找到以下许可证目录：" -ForegroundColor Green
    foreach ($d in $found) {
        Write-Host "    - $d" -ForegroundColor Gray
    }
    Write-Host ""

    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $backupDir = "$env:USERPROFILE\Desktop\ALM_License_Backup_$timestamp"
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null

    Write-Host "  正在备份到：$backupDir" -ForegroundColor Cyan
    Write-Host ""

    $totalFiles = 0
    foreach ($d in $found) {
        try {
            $subDir = Join-Path $backupDir (Split-Path $d -Leaf)
            New-Item -ItemType Directory -Path $subDir -Force | Out-Null
            # 用 robocopy 复制（保留隐藏属性）
            $robolog = "$env:TEMP\robocopy_$timestamp.log"
            robocopy $d $subDir /E /COPYALL /R:1 /W:1 /NFL /NDL /NJH /NJS /LOG:$robolog | Out-Null
            $count = (Get-ChildItem $subDir -Recurse -File -Force -ErrorAction SilentlyContinue).Count
            $totalFiles += $count
            Write-Host "  [OK] $d → $subDir （$count 个文件）" -ForegroundColor Green
        }
        catch {
            Write-Host "  [XX] 备份 $d 失败：$($_.Exception.Message)" -ForegroundColor Red
        }
    }

    Write-Host ""
    Write-Host "  ──────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host "  备份完成：共 $totalFiles 个文件" -ForegroundColor Green
    Write-Host "  位置：$backupDir" -ForegroundColor Cyan
    Write-Host "  ──────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  ⚠️  重装博途后，把备份的文件恢复到原位置即可。" -ForegroundColor Yellow
    Write-Host "     或者用 ALM 界面里的""传送许可证""功能恢复。" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  按 [Enter] 返回..." -ForegroundColor White
    $null = [Console]::ReadKey($true)
}
function Show-DownloadGuide {
    Clear-Host
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "  下载官方卸载工具" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  西门子官方卸载工具不在博途安装包里，" -ForegroundColor White
    Write-Host "  需要从西门子官网单独下载。" -ForegroundColor White
    Write-Host ""
    Write-Host "  ══════════════════════════════════════════" -ForegroundColor DarkGray
    Write-Host "  工具名称" -ForegroundColor Cyan
    Write-Host "  ══════════════════════════════════════════" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "    SIMATIC_Cleanup_Tool.exe" -ForegroundColor Green
    Write-Host "    （也叫 CleanUp_TIA_Vxx.exe，xx = 版本号）" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  ══════════════════════════════════════════" -ForegroundColor DarkGray
    Write-Host "  下载地址" -ForegroundColor Cyan
    Write-Host "  ══════════════════════════════════════════" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "    西门子工业在线支持（SIOS）：" -ForegroundColor White
    Write-Host "    https://support.industry.siemens.com" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "    搜索关键词（任选一个）：" -ForegroundColor White
    Write-Host "      · SIMATIC Cleanup Tool" -ForegroundColor Gray
    Write-Host "      · TIA Portal Complete Uninstall Tool" -ForegroundColor Gray
    Write-Host "      · CleanUp_TIA" -ForegroundColor Gray
    Write-Host ""
    Write-Host "    对应的文章 ID：" -ForegroundColor White
    Write-Host "      · 189025      — 完整卸载 STEP 7 / TIA 的官方步骤" -ForegroundColor Gray
    Write-Host "      · 109750668   — 如何完全卸载 TIA Portal" -ForegroundColor Gray
    Write-Host "      · 109776066   — SIMATIC CleanUp 工具说明" -ForegroundColor Gray
    Write-Host "      · 109482460   — CleanUp_TIA 脚本" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  ══════════════════════════════════════════" -ForegroundColor DarkGray
    Write-Host "  下载步骤" -ForegroundColor Cyan
    Write-Host "  ══════════════════════════════════════════" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "    1. 打开 https://support.industry.siemens.com" -ForegroundColor White
    Write-Host "    2. 注册/登录西门子账号（免费）" -ForegroundColor White
    Write-Host "    3. 在搜索框输入上方任一关键词" -ForegroundColor White
    Write-Host "    4. 找到对应的下载链接" -ForegroundColor White
    Write-Host "    5. 下载到本地（比如 D 盘或桌面）" -ForegroundColor White
    Write-Host ""
    Write-Host "  ⚠️  下载后，回到本工具，选 [3] → [2] 手动指定路径。" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  按 [Enter] 返回..." -ForegroundColor White
    $null = [Console]::ReadKey($true)
}
function Find-OfficialCleanTool {
    # 排除名单
    $excludePatterns = 'Sangfor|aTrust|深信服|360|Tencent|Baidu|Aliyun|WeChat|QQ'

    # 官方清理工具的已知名称（只搜这些，不再搜 Sim_EKB）
    $officialNames = @(
        'SIMATIC_Cleanup*.exe',
        'SIMATIC Cleanup*.exe',
        'CleanUp_TIA_*.exe',
        'CleanUp_TIA*.exe',
        'TIA_Portal_Uninstall*.exe',
        'SIMATIC_Clean_Uninstall*.exe',
        'SIMATIC Clean Uninstall*.exe'
    )

    # 方法1：从开始菜单快捷方式反查
    try {
        $sh = New-Object -ComObject WScript.Shell
        $menus = @(
            "$env:ProgramData\Microsoft\Windows\Start Menu\Programs",
            "$env:APPDATA\Microsoft\Windows\Start Menu\Programs"
        )
        foreach ($menu in $menus) {
            if (-not (Test-Path $menu)) { continue }
            $lnks = Get-ChildItem $menu -Recurse -Filter "*.lnk" -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match 'SIMATIC.*Clean|Clean.*Uninstall|CleanUp_TIA|TIA.*Uninstall' }
            foreach ($lnk in $lnks) {
                $target = $sh.CreateShortcut($lnk.FullName).TargetPath
                if ($target -and (Test-Path $target) -and ($target -notmatch $excludePatterns)) {
                    return $target
                }
            }
        }
    }
    catch { }

    # 方法2：遍历所有盘，搜官方工具名称
    $drives = Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue |
    Where-Object { $_.Root -match '^[A-Z]:\\$' }

    foreach ($drive in $drives) {
        $root = $drive.Root
        if (-not (Test-Path $root)) { continue }
        foreach ($name in $officialNames) {
            $found = Get-ChildItem $root -Recurse -Filter $name -ErrorAction SilentlyContinue -Depth 6 |
            Where-Object { $_.FullName -notmatch $excludePatterns } |
            Select-Object -First 1
            if ($found) { return $found.FullName }
        }
    }

    # 方法3：在 Siemens 安装包目录下搜
    $siemensDirs = @(
        "C:\Program Files (x86)\Siemens",
        "C:\Program Files\Siemens",
        "D:\Program Files (x86)\Siemens",
        "D:\Program Files\Siemens"
    )
    foreach ($dir in $siemensDirs) {
        if (-not (Test-Path $dir)) { continue }
        $found = Get-ChildItem $dir -Recurse -Filter "*.exe" -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match 'Clean.*Uninstall|CleanUninstall|CleanUp' } |
        Select-Object -First 1
        if ($found) { return $found.FullName }
    }

    return $null
}

function Start-OfficialCleanTool {
    while ($true) {
        Clear-Host
        Write-Host "==========================================" -ForegroundColor Cyan
        Write-Host "  官方卸载工具" -ForegroundColor Cyan
        Write-Host "==========================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  正在搜索官方卸载工具..." -ForegroundColor Cyan
        Write-Host ""

        $tool = Find-OfficialCleanTool

        if (-not $tool) {
            # 自动找不到，显示下载指引
            Write-Host "  [!!] 未自动找到官方卸载工具。" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "  这是正常现象——官方卸载工具不在博途安装包里，" -ForegroundColor Gray
            Write-Host "  需要从西门子官网单独下载。" -ForegroundColor Gray
            Write-Host ""
            Write-Host "  [1] 查看下载指引（推荐）"
            Write-Host "  [2] 我已有工具，手动指定路径"
            Write-Host "  [3] 取消"
            Write-Host ""
            Write-Host "  按数字键选择：" -ForegroundColor White

            $manual = Read-MenuChoice -ValidKeys @('1', '2', '3')
            if ($manual -eq '3') { return }

            if ($manual -eq '1') {
                Show-DownloadGuide
                continue
            }

            if ($manual -eq '2') {
                Write-Host ""
                Write-Host "  请把卸载工具拖进来，或粘贴路径：" -ForegroundColor White
                $rawPath = Read-Host "  路径"
                $tool = $rawPath.Trim('"').Trim("'").Trim()

                if (-not (Test-Path $tool)) {
                    Write-Host "  [XX] 路径不存在。" -ForegroundColor Red
                    Write-Host "  按 [Enter] 返回..." -ForegroundColor White
                    $null = [Console]::ReadKey($true)
                    continue
                }

                # 二次校验：确认是 exe
                if ($tool -notmatch '\.exe$') {
                    Write-Host "  [XX] 这不是一个 .exe 文件。" -ForegroundColor Red
                    Write-Host "  按 [Enter] 返回..." -ForegroundColor White
                    $null = [Console]::ReadKey($true)
                    continue
                }
            }
        }

        # 找到了（自动或手动）
        Clear-Host
        Write-Host "==========================================" -ForegroundColor Cyan
        Write-Host "  官方卸载工具" -ForegroundColor Cyan
        Write-Host "==========================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  找到：$tool" -ForegroundColor Green
        Write-Host ""
        Write-Host "  ⚠️  官方卸载工具会删除所有 Siemens 组件。" -ForegroundColor Yellow
        Write-Host "     建议先做：备份许可证（[2]）。" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  [1] 启动卸载工具"
        Write-Host "  [2] 重新搜索"
        Write-Host "  [3] 取消"
        Write-Host ""
        Write-Host "  按数字键选择：" -ForegroundColor White

        $choice = Read-MenuChoice -ValidKeys @('1', '2', '3')
        if ($choice -eq '3') { return }
        if ($choice -eq '2') { continue }

        Write-Host ""
        Write-Host "  正在启动..." -ForegroundColor Cyan
        try {
            Start-Process -FilePath $tool -Verb RunAs
            Write-Host "  [OK] 已启动。" -ForegroundColor Green
            Write-Host ""
            Write-Host "  请在卸载工具窗口里完成卸载。" -ForegroundColor White
            Write-Host "  卸载完成后，回到本工具，选 [4] 清理残留。" -ForegroundColor White
        }
        catch {
            Write-Host "  [XX] 启动失败：$($_.Exception.Message)" -ForegroundColor Red
        }
        Write-Host ""
        Write-Host "  按 [Enter] 返回..." -ForegroundColor White
        $null = [Console]::ReadKey($true)
        return
    }
}

function Invoke-PreinstallCheck {
    Clear-Host
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "  重装前环境检查" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""

    # 检查残留
    Write-Host "  [1] 残留检查" -ForegroundColor Cyan
    $residuals = Test-Residuals
    Show-ResidualReport -Residuals $residuals

    # 检查环境
    Write-Host ""
    Write-Host "  [2] 环境检查" -ForegroundColor Cyan
    Invoke-EnvironmentCheck
    Show-EnvironmentReport

    # 给出结论
    $badServices = @($residuals.Services | Where-Object { -not $_.ExeExists -and -not $_.IsProtected })
    $badStartup = @($residuals.StartupItems | Where-Object { -not $_.ExeExists })
    $hasReboot = $residuals.RebootPending.Count -gt 0

    Write-Host ""
    Write-Host "  ══════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  重装前结论" -ForegroundColor Cyan
    Write-Host "  ══════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""

    if ($badServices.Count -gt 0 -or $badStartup.Count -gt 0 -or $hasReboot) {
        Write-Host "  ⚠️  还有残留，建议先清理：" -ForegroundColor Yellow
        if ($hasReboot) { Write-Host "    - 挂起重启标记" -ForegroundColor Yellow }
        if ($badServices.Count -gt 0) { Write-Host "    - $($badServices.Count) 个无效服务" -ForegroundColor Yellow }
        if ($badStartup.Count -gt 0) { Write-Host "    - $($badStartup.Count) 个无效启动项" -ForegroundColor Yellow }
        Write-Host ""
        Write-Host "  返回上一级，选 [4] 清理残留。" -ForegroundColor White
    }
    else {
        Write-Host "  ✅ 环境干净，可以开始重装了。" -ForegroundColor Green
        Write-Host ""
        Write-Host "  下一步：重新运行博途安装程序 Start.exe。" -ForegroundColor White
    }
    Write-Host ""
    Write-Host "  按 [Enter] 返回..." -ForegroundColor White
    $null = [Console]::ReadKey($true)
}

function Invoke-UninstallReinstall {
    while ($true) {
        Clear-Host
        Write-Host "==========================================" -ForegroundColor Cyan
        Write-Host "  卸载/重装" -ForegroundColor Cyan
        Write-Host "==========================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  [1] 检测已安装的 Siemens 组件"
        Write-Host "  [2] 备份许可证（卸载前必做）"
        Write-Host "  [3] 启动官方卸载工具"
        Write-Host "  [4] 清理卸载残留"
        Write-Host "  [5] 重装前环境检查"
        Write-Host "  [6] 返回主菜单"
        Write-Host ""
        Write-Host "  按数字键选择：" -ForegroundColor White

        $choice = Read-MenuChoice -ValidKeys @('1', '2', '3', '4', '5', '6')
        switch ($choice) {
            '1' { Show-InstalledComponents }
            '2' { Backup-AlmLicenses }
            '3' { Start-OfficialCleanTool }
            '4' {
                Clear-Host
                Write-Host "==========================================" -ForegroundColor Cyan
                Write-Host "  清理卸载残留" -ForegroundColor Cyan
                Write-Host "==========================================" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "  [1] 清理挂起重启标记"
                Write-Host "  [2] 清理无效服务/启动项"
                Write-Host "  [3] 清理 Siemens 注册表配置"
                Write-Host "  [4] 全部清理（1+2+3）"
                Write-Host "  [5] 返回"
                Write-Host ""
                Write-Host "  按数字键选择：" -ForegroundColor White
                $c2 = Read-MenuChoice -ValidKeys @('1', '2', '3', '4', '5')
                switch ($c2) {
                    '1' { Clear-RebootPending }
                    '2' {
                        $residuals = Test-Residuals
                        Invoke-ResidualCleanup -Residuals $residuals
                    }
                    '3' {
                        $regRoot = 'HKLM:\SOFTWARE\Siemens'
                        $scan = Scan-SiemensRegistry -RootPath $regRoot
                        Show-SiemensRegistryReport -ScanResult $scan
                        Invoke-SiemensRegistryCleanup -ScanResult $scan
                    }
                    '4' {
                        Clear-RebootPending
                        $residuals = Test-Residuals
                        Invoke-ResidualCleanup -Residuals $residuals
                        $regRoot = 'HKLM:\SOFTWARE\Siemens'
                        $scan = Scan-SiemensRegistry -RootPath $regRoot
                        Show-SiemensRegistryReport -ScanResult $scan
                        Invoke-SiemensRegistryCleanup -ScanResult $scan
                    }
                    '5' { }
                }
            }
            '5' { Invoke-PreinstallCheck }
            '6' { return }
        }
    }
}
function Invoke-DailyUse {
    while ($true) {
        Clear-Host
        Write-Host "==========================================" -ForegroundColor Cyan
        Write-Host "  日常使用" -ForegroundColor Cyan
        Write-Host "==========================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  [1] 查看 Siemens 进程"
        Write-Host "  [2] 一键清理空闲进程"
        Write-Host "  [3] 检查启动项"
        Write-Host "  [4] 错误码查询"
        Write-Host "  [5] 返回主菜单"
        Write-Host ""
        Write-Host "  按数字键选择：" -ForegroundColor White

        $choice = Read-MenuChoice -ValidKeys @('1', '2', '3', '4', '5')
        switch ($choice) {
            '1' { Show-ProcessList }
            '2' { Invoke-CleanIdleProcesses }
            '3' { Show-StartupItems }
            '4' { Show-ErrorCodeLookup }
            '5' { return }
        }
    }
}
function Invoke-LicenseGuide {
    Clear-Host
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "  授权引导" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  正在检测许可证环境..." -ForegroundColor Cyan
    Write-Host ""

    # 检测 ALM 服务
    $almStatus = Get-ALMStatus
    $serviceOK = Show-ALMStatus -AlmStatus $almStatus

    # 查找 ALM 程序路径
    $almPath = Get-ALMPath

    Write-Host "  [2] ALM 图形界面" -ForegroundColor Cyan
    Write-Host "  ──────────────────────────────────────────" -ForegroundColor DarkGray
    if ($almPath) {
        Write-Host "    找到：$almPath" -ForegroundColor Green
    }
    else {
        Write-Host "    未找到 alm gui 程序" -ForegroundColor Yellow
        Write-Host "    可在开始菜单搜索 'Automation License Manager' 打开" -ForegroundColor DarkGray
    }
    Write-Host ""
    # 查找许可证文件
    Write-Host "  [3] 许可证文件" -ForegroundColor Cyan
    Write-Host "  ──────────────────────────────────────────" -ForegroundColor DarkGray
    $licFiles = Find-LicenseFiles
    if ($licFiles.Count -eq 0) {
        Write-Host "    未在常见路径找到 .lic / .awl 文件。" -ForegroundColor Yellow
        Write-Host "    这不代表你没有许可证——许可证存在 ALM 内部数据库中。" -ForegroundColor DarkGray
        Write-Host "    打开 ALM 界面才能看到真实情况。" -ForegroundColor DarkGray
    }
    else {
        Write-Host "    找到 $($licFiles.Count) 个文件：" -ForegroundColor Green
        foreach ($f in $licFiles | Select-Object -First 10) {
            Write-Host "      - $($f.FullName)" -ForegroundColor Gray
        }
    }
    Write-Host ""

    # 下一步菜单
    Write-Host "  ──────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host "  接下来你可以：" -ForegroundColor White
    Write-Host ""
    Write-Host "  [1] 一键打开 ALM 界面（推荐）"
    Write-Host "  [2] 启动 ALM 服务（如果未运行）"
    Write-Host "  [3] 查看常见授权错误码"
    Write-Host "  [4] 返回主菜单"
    Write-Host ""
    Write-Host "  按数字键选择：" -ForegroundColor White

    $choice = Read-MenuChoice -ValidKeys @('1', '2', '3', '4')

    switch ($choice) {
        '1' {
            if (-not $almPath) {
                Write-Host ""
                Write-Host "  [XX] 未找到 ALM 图形界面程序。" -ForegroundColor Red
                Write-Host ""
                Write-Host "  替代方法：" -ForegroundColor White
                Write-Host "    1. 点开始菜单 → 搜索 'Automation License Manager'" -ForegroundColor White
                Write-Host "    2. 或者 Win+R → 输入 'almgui64x' → 回车" -ForegroundColor White
                Write-Host "    3. 或者右键任务栏 ALM 图标 → 打开文件所在位置" -ForegroundColor White
                Write-Host ""
                Write-Host "  按 [Enter] 返回..." -ForegroundColor White
                $null = [Console]::ReadKey($true)
                return
            }
            Write-Host ""
            Write-Host "  正在打开 ALM 界面：$almPath" -ForegroundColor Cyan
            try {
                Start-Process -FilePath $almPath -Verb RunAs
                Write-Host "  [OK] 已启动。" -ForegroundColor Green
                Write-Host ""
                Write-Host "  【ALM 使用提示】" -ForegroundColor Cyan
                Write-Host "  1. 左侧选择计算机名（本机）" -ForegroundColor White
                Write-Host "  2. 右侧会显示已安装的许可证列表" -ForegroundColor White
                Write-Host "  3. 如果列表为空，说明没有许可证" -ForegroundColor White
                Write-Host "  4. 双击许可证可以看到类型和有效期" -ForegroundColor White
                Write-Host ""
            }
            catch {
                Write-Host "  [XX] 启动失败：$($_.Exception.Message)" -ForegroundColor Red
            }
            Write-Host "  按 [Enter] 返回..." -ForegroundColor White
            $null = [Console]::ReadKey($true)
            return
        }
        '2' {
            Write-Host ""
            if ($almStatus.Status -eq 'Running') {
                Write-Host "  ALM 服务已经在运行，无需启动。" -ForegroundColor Green
            }
            else {
                Write-Host "  正在启动 ALM 服务..." -ForegroundColor Cyan
                try {
                    Start-Service -Name $almStatus.Name -ErrorAction Stop
                    Write-Host "  [OK] 已启动。" -ForegroundColor Green
                }
                catch {
                    Write-Host "  [XX] 启动失败：$($_.Exception.Message)" -ForegroundColor Red
                    Write-Host "       请右键以管理员身份运行本工具。" -ForegroundColor DarkGray
                }
            }
            Write-Host ""
            Write-Host "  按 [Enter] 返回..." -ForegroundColor White
            $null = [Console]::ReadKey($true)
            return
        }
        '3' {
            Clear-Host
            Write-Host "==========================================" -ForegroundColor Cyan
            Write-Host "  常见授权错误码" -ForegroundColor Cyan
            Write-Host "==========================================" -ForegroundColor Cyan
            Show-LicenseErrorCodes
            Write-Host "  按 [Enter] 返回..." -ForegroundColor White
            $null = [Console]::ReadKey($true)
            return
        }
        '4' { return }
    }
}
# ============================================================
# 1.6 日志收集
# ============================================================
function Invoke-LogCollector {
    Clear-Host
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "  日志收集" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  正在收集诊断信息，稍等..." -ForegroundColor Cyan
    Write-Host ""

    # 创建临时目录
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $tempDir = "$env:TEMP\TIAHelper_Collect_$timestamp"
    if (-not (Test-Path $tempDir)) { New-Item -ItemType Directory -Path $tempDir -Force | Out-Null }

    $collected = @()

    # ---------- 1. 系统信息 ----------
    Write-Host "  [1/7] 系统信息..." -ForegroundColor Gray
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        $cs = Get-CimInstance Win32_ComputerSystem
        $info = @()
        $info += "===== 系统信息 ====="
        $info += "生成时间：$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        $info += ""
        $info += "计算机名：$($cs.Name)"
        $info += "操作系统：$($os.Caption) ($($os.Version))"
        $info += "系统架构：$($os.OSArchitecture)"
        $info += "物理内存：$([math]::Round($cs.TotalPhysicalMemory/1GB,1)) GB"
        $info += "可用内存：$([math]::Round($os.FreePhysicalMemory/1MB,1)) GB"
        $info += "当前用户：$env:USERNAME"
        $info += "系统语言：$((Get-Culture).DisplayName)"
        $info += ""
        $info += "===== 磁盘 ====="
        Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue |
        Where-Object { $_.Free -ne $null -and $_.Root -match '^[A-Z]:\\$' } |
        ForEach-Object {
            $freeGB = [math]::Round($_.Free / 1GB, 1)
            $usedGB = [math]::Round($_.Used / 1GB, 1)
            $info += "$($_.Name)盘：已用 $usedGB GB，剩余 $freeGB GB"
        }
        $info += ""
        $info += "===== 环境依赖 ====="
        try {
            $net35 = Get-WindowsOptionalFeature -Online -FeatureName "NetFx3" -ErrorAction Stop
            $info += ".NET 3.5：$($net35.State)"
        }
        catch { $info += ".NET 3.5：无法检测" }
        $net4 = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full" -ErrorAction SilentlyContinue
        $info += ".NET 4.x Release：$($net4.Release)"
        try {
            $msmq = Get-WindowsOptionalFeature -Online -FeatureName "MSMQ-Server" -ErrorAction Stop
            $info += "MSMQ：$($msmq.State)"
        }
        catch { $info += "MSMQ：无法检测" }

        $info -join "`r`n" | Out-File -FilePath "$tempDir\01_系统信息.txt" -Encoding UTF8
        $collected += "系统信息"
    }
    catch {
        Write-Host "    [XX] 系统信息收集失败" -ForegroundColor Red
    }

    # ---------- 2. 挂起重启标记 ----------
    Write-Host "  [2/7] 挂起重启标记..." -ForegroundColor Gray
    try {
        $pending = @()
        $pfro = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' `
            -Name PendingFileRenameOperations -ErrorAction SilentlyContinue
        if ($pfro -and $pfro.PendingFileRenameOperations) {
            $pending += "PendingFileRenameOperations ($($pfro.PendingFileRenameOperations.Count) 条)"
            $pending += ""
            $pending += "详细内容："
            $pfro.PendingFileRenameOperations | ForEach-Object { $pending += "  $_" }
        }
        if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') {
            $pending += "CBS RebootPending：存在"
        }
        if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') {
            $pending += "WindowsUpdate RebootRequired：存在"
        }
        if ($pending.Count -eq 0) { $pending += "无挂起重启标记" }
        $pending -join "`r`n" | Out-File -FilePath "$tempDir\02_挂起标记.txt" -Encoding UTF8
        $collected += "挂起标记"
    }
    catch {
        Write-Host "    [XX] 挂起标记收集失败" -ForegroundColor Red
    }

    # ---------- 3. Siemens 服务状态 ----------
    Write-Host "  [3/7] Siemens 服务状态..." -ForegroundColor Gray
    try {
        $allServices = Get-CimInstance Win32_Service -ErrorAction SilentlyContinue
        $matched = $allServices | Where-Object {
            $_.Name -match 'Siemens|SIMATIC|S7|ALM|TIA|WinCC' -or
            $_.DisplayName -match 'Siemens|SIMATIC|S7|ALM|TIA|WinCC'
        }
        $lines = @("===== Siemens 相关服务 =====")
        foreach ($s in $matched) {
            $lines += "$($s.Name) | $($s.DisplayName) | 状态：$($s.State) | 启动：$($s.StartMode)"
            $lines += "  路径：$($s.PathName)"
        }
        $lines -join "`r`n" | Out-File -FilePath "$tempDir\03_Siemens服务.txt" -Encoding UTF8
        $collected += "Siemens 服务"
    }
    catch {
        Write-Host "    [XX] 服务状态收集失败" -ForegroundColor Red
    }

    # ---------- 4. 系统事件日志（最近3天错误） ----------
    Write-Host "  [4/7] 系统事件日志..." -ForegroundColor Gray
    try {
        $lines = @("===== 最近 3 天系统错误（前 50 条）=====")
        try {
            $events = Get-WinEvent -FilterHashtable @{
                LogName = 'System'; Level = 1, 2
                StartTime = (Get-Date).AddDays(-3)
            } -MaxEvents 50 -ErrorAction Stop
            foreach ($e in $events) {
                $lines += "[$($e.TimeCreated.ToString('MM-dd HH:mm'))] [$($e.LevelDisplayName)] $($e.ProviderName): $($e.Message.Split("`n")[0])"
            }
        }
        catch {
            $lines += "（无事件或读取失败）"
        }
        $lines += ""
        $lines += "===== 最近 3 天应用错误（前 50 条）====="
        try {
            $events = Get-WinEvent -FilterHashtable @{
                LogName = 'Application'; Level = 1, 2
                StartTime = (Get-Date).AddDays(-3)
            } -MaxEvents 50 -ErrorAction Stop
            foreach ($e in $events) {
                $lines += "[$($e.TimeCreated.ToString('MM-dd HH:mm'))] [$($e.LevelDisplayName)] $($e.ProviderName): $($e.Message.Split("`n")[0])"
            }
        }
        catch {
            $lines += "（无事件或读取失败）"
        }
        $lines -join "`r`n" | Out-File -FilePath "$tempDir\04_事件日志.txt" -Encoding UTF8
        $collected += "事件日志"
    }
    catch {
        Write-Host "    [XX] 事件日志收集失败" -ForegroundColor Red
    }

    # ---------- 5. 博途安装日志 ----------
    Write-Host "  [5/7] 博途安装日志..." -ForegroundColor Gray
    try {
        $logDirs = @(
            "C:\ProgramData\Siemens\Automation\Logfiles\Setup",
            "C:\ProgramData\Siemens\Automation\Logfiles"
        )
        $logDest = "$tempDir\05_博途日志"
        if (-not (Test-Path $logDest)) { New-Item -ItemType Directory -Path $logDest -Force | Out-Null }

        $logCount = 0
        foreach ($dir in $logDirs) {
            if (-not (Test-Path $dir)) { continue }
            $files = Get-ChildItem $dir -Filter "*.log" -File -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -gt (Get-Date).AddDays(-7) } |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 20
            foreach ($f in $files) {
                Copy-Item $f.FullName -Destination $logDest -Force -ErrorAction SilentlyContinue
                $logCount++
            }
        }
        $collected += "博途日志（$logCount 个文件）"
    }
    catch {
        Write-Host "    [XX] 博途日志收集失败" -ForegroundColor Red
    }

    # ---------- 6. 工具箱自身日志 ----------
    Write-Host "  [6/7] 工具箱日志..." -ForegroundColor Gray
    try {
        $toolLogDir = "$env:LOCALAPPDATA\TIAHelper\logs"
        $toolDest = "$tempDir\06_工具箱日志"
        if (-not (Test-Path $toolDest)) { New-Item -ItemType Directory -Path $toolDest -Force | Out-Null }
        if (Test-Path $toolLogDir) {
            Get-ChildItem $toolLogDir -Filter "*.log" -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 10 |
            ForEach-Object { Copy-Item $_.FullName -Destination $toolDest -Force -ErrorAction SilentlyContinue }
        }
        $collected += "工具箱日志"
    }
    catch {
        Write-Host "    [XX] 工具箱日志收集失败" -ForegroundColor Red
    }

    # ---------- 7. 运行环境自检 ----------
    Write-Host "  [7/7] 运行环境自检..." -ForegroundColor Gray
    try {
        Invoke-EnvironmentCheck
        $reportPath = "$tempDir\07_环境自检报告.txt"
        $lines = @("===== 环境自检报告 =====")
        foreach ($r in $script:results) {
            $lines += "[$($r.Status)] $($r.Item)：$($r.Detail)"
        }
        $lines -join "`r`n" | Out-File -FilePath $reportPath -Encoding UTF8
        $collected += "环境自检"
    }
    catch {
        Write-Host "    [XX] 环境自检失败" -ForegroundColor Red
    }

    # ---------- 打包 ----------
    Write-Host ""
    Write-Host "  正在打包..." -ForegroundColor Cyan
    $zipPath = "$env:USERPROFILE\Desktop\TIAHelper_Diagnostic_$timestamp.zip"
    try {
        Compress-Archive -Path "$tempDir\*" -DestinationPath $zipPath -Force
        Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    catch {
        Write-Host "  [XX] 打包失败：$($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  按 [Enter] 返回..." -ForegroundColor White
        $null = [Console]::ReadKey($true)
        return
    }

    # ---------- 完成 ----------
    Clear-Host
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "  ✅ 收集完成" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  已收集内容：" -ForegroundColor White
    foreach ($item in $collected) {
        Write-Host "    ✓ $item" -ForegroundColor Green
    }
    Write-Host ""
    Write-Host "  ──────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host "  文件位置：" -ForegroundColor White
    Write-Host "  $zipPath" -ForegroundColor Cyan
    Write-Host "  ──────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  ⚠️  这个压缩包包含你的系统信息，请只发给你信任的人。" -ForegroundColor Yellow
    Write-Host "     比如：老师、学长、实验室管理员。" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  按 [Enter] 返回..." -ForegroundColor White
    $null = [Console]::ReadKey($true)
}
# ============================================================
# 1.5 安全退出：主流程
# ============================================================
function Invoke-SafeExit {
    Clear-Host
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "  安装失败安全退出" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  正在检测系统残留..." -ForegroundColor Cyan

    $residuals = Test-Residuals
    Show-ResidualReport -Residuals $residuals

    Write-Host "  [1] 修复挂起重启问题（推荐先做这个）"
    Write-Host "  [2] 残留清理（删除无效服务/启动项，需要管理员权限）"
    Write-Host "  [3] 注册表深度清理（重置 Siemens 配置）"
    Write-Host "  [4] 生成诊断报告（发给别人排查）"
    Write-Host "  [5] 返回主菜单"
    Write-Host ""
    Write-Host "  按数字键选择：" -ForegroundColor White

    $choice = Read-MenuChoice -ValidKeys @('1', '2', '3', '4')
    switch ($choice) {
        '1' {
            Clear-RebootPending
            Write-Host "  按 [Enter] 返回..." -ForegroundColor White
            $null = [Console]::ReadKey($true)
            return
        }
        '2' {
            Invoke-ResidualCleanup -Residuals $residuals
            return
        }
        '3' {
            Clear-Host
            Write-Host "==========================================" -ForegroundColor Cyan
            Write-Host "  注册表深度清理" -ForegroundColor Cyan
            Write-Host "==========================================" -ForegroundColor Cyan
            Write-Host ""
            Write-Host "  正在扫描 Siemens 注册表..." -ForegroundColor Cyan

            $regRoot = 'HKLM:\SOFTWARE\Siemens'
            $scan = Scan-SiemensRegistry -RootPath $regRoot
            Show-SiemensRegistryReport -ScanResult $scan
            Invoke-SiemensRegistryCleanup -ScanResult $scan
            return
        }
        '4' {
            $reportPath = "$env:USERPROFILE\Desktop\TIAHelper_Diagnostic_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
            try {
                $content = @()
                $content += "博途工具箱诊断报告"
                $content += "生成时间：$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
                $content += ""
                $content += "=== 挂起重启标记 ==="
                if ($residuals.RebootPending.Count -eq 0) { $content += "无" }
                else { $residuals.RebootPending | ForEach-Object { $content += "- $_" } }
                $content += ""
                $content += "=== 残留服务 ==="
                if ($residuals.Services.Count -eq 0) { $content += "无" }
                else {
                    $residuals.Services | ForEach-Object {
                        $content += "- $($_.Name) [$($_.Status)] 文件存在：$($_.ExeExists)"
                    }
                }
                $content += ""
                $content += "=== 启动项 ==="
                if ($residuals.StartupItems.Count -eq 0) { $content += "无" }
                else {
                    $residuals.StartupItems | ForEach-Object {
                        $content += "- $($_.Name) 文件存在：$($_.ExeExists)"
                    }
                }
                $content += ""
                $content += "=== 计划任务 ==="
                if ($residuals.ScheduledTasks.Count -eq 0) { $content += "无" }
                else {
                    $residuals.ScheduledTasks | ForEach-Object {
                        $content += "- $($_.Path)$($_.Name) [$($_.State)]"
                    }
                }
                $content += ""
                $content += "=== 注册表项 ==="
                if ($residuals.RegistryKeys.Count -eq 0) { $content += "无" }
                else { $residuals.RegistryKeys | ForEach-Object { $content += "- $_" } }

                $content -join "`r`n" | Out-File -FilePath $reportPath -Encoding UTF8
                Write-Host ""
                Write-Host "  ✅ 诊断报告已生成：" -ForegroundColor Green
                Write-Host "  $reportPath" -ForegroundColor Cyan
            }
            catch {
                Write-Host "  [XX] 生成失败：$($_.Exception.Message)" -ForegroundColor Red
            }
            Write-Host ""
            Write-Host "  按 [Enter] 返回..." -ForegroundColor White
            $null = [Console]::ReadKey($true)
            return
        }
        '4' { return }
    }
}
# ============================================================
# 安装包检测
# ============================================================
function Test-Package {
    param([string]$Path)

    Write-Host ""
    Write-Host "  正在检测安装包..." -ForegroundColor Cyan
    Write-Host ""

    $result = [PSCustomObject]@{
        Path           = $Path
        HasChinese     = $false
        SignatureValid = $false
        IsSiemens      = $false
        ScanResult     = 'clean'
        ThreatName     = ''
        KeygenPaths    = @()
    }

    if ($Path -match '[\u4e00-\u9fa5]') {
        Write-Host "  [!!] 路径含中文，可能导致安装失败" -ForegroundColor Yellow
        $result.HasChinese = $true
    }
    else {
        Write-Host "  [OK] 路径无中文" -ForegroundColor Green
    }

    $isIso = $Path -match '\.iso$'
    if ($isIso) {
        Write-Host "  [--] ISO 文件，需挂载后检查内部签名" -ForegroundColor Gray
    }
    else {
        $startExe = Join-Path $Path "Start.exe"
        if (Test-Path $startExe) {
            $sig = Get-AuthenticodeSignature $startExe -ErrorAction SilentlyContinue
            if ($sig.Status -eq 'Valid') {
                if ($sig.SignerCertificate.Subject -match 'Siemens') {
                    Write-Host "  [OK] 数字签名有效（Siemens AG）" -ForegroundColor Green
                    $result.SignatureValid = $true
                    $result.IsSiemens = $true
                }
                else {
                    Write-Host "  [!!] 签名有效，但不是西门子签的" -ForegroundColor Yellow
                    $result.SignatureValid = $true
                }
            }
            else {
                Write-Host "  [!!] 无有效数字签名" -ForegroundColor Yellow
            }
        }
        else {
            Write-Host "  [!!] 未找到 Start.exe" -ForegroundColor Yellow
        }
    }

    Write-Host ""
    Write-Host "  正在调用 Windows Defender 扫描..." -ForegroundColor Cyan

    $defenderPath = Get-ChildItem "C:\ProgramData\Microsoft\Windows Defender\Platform" -Directory -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending | Select-Object -First 1 |
    ForEach-Object { Join-Path $_.FullName "MpCmdRun.exe" }

    if ($defenderPath -and (Test-Path $defenderPath)) {
        try {
            $scanOutput = & $defenderPath -Scan -ScanType 3 -File $Path -DisableRemediation 2>&1 | Out-String
            $scanCode = $LASTEXITCODE

            if ($scanCode -eq 0) {
                Write-Host "  [OK] 未发现威胁" -ForegroundColor Green
                $result.ScanResult = 'clean'
            }
            elseif ($scanCode -eq 2) {
                $threatName = ''
                if ($scanOutput -match '(HackTool|Keygen|Crack|Trojan|Worm|Ransom|Backdoor|Spyware|Rootkit|Virus|Dropper|Downloader|Miner|Stealer)[:\w/\.\-]+') {
                    $threatName = $Matches[0]
                }
                else {
                    $recent = Get-MpThreatDetection -ErrorAction SilentlyContinue |
                    Sort-Object InitialDetectionTime -Descending | Select-Object -First 1
                    if ($recent) { $threatName = $recent.ThreatName }
                }

                if ([string]::IsNullOrWhiteSpace($threatName)) {
                    $threatName = "不明风险（可能是注册机，也可能是误报）"
                    $result.ThreatName = $threatName
                    Write-Host "  [!!] 检测到潜在风险：$threatName" -ForegroundColor Yellow
                    $result.ScanResult = 'unknown'
                }
                else {
                    $result.ThreatName = $threatName
                    $class = Get-ThreatClassification -ThreatName $threatName
                    if ($class -eq 'POTENTIALLY_UNWANTED') {
                        Write-Host "  [!!] 检测到破解/授权工具：$threatName" -ForegroundColor Yellow
                        $result.ScanResult = 'hacktool'
                    }
                    elseif ($class -eq 'MALWARE') {
                        Write-Host "  [XX] 检测到恶意软件：$threatName" -ForegroundColor Red
                        $result.ScanResult = 'malware'
                    }
                    else {
                        Write-Host "  [!!] 检测到未知风险：$threatName" -ForegroundColor Yellow
                        $result.ScanResult = 'unknown'
                    }
                }
            }
            else {
                Write-Host "  [!!] 扫描返回码：$scanCode" -ForegroundColor Yellow
                $result.ScanResult = 'unknown'
            }
        }
        catch {
            Write-Host "  [!!] 扫描失败" -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "  [--] 未找到 Windows Defender，跳过扫描" -ForegroundColor Gray
    }

    if ($result.ScanResult -eq 'hacktool' -or $result.ScanResult -eq 'clean' -or $result.ScanResult -eq 'unknown') {
        $result.KeygenPaths = Find-Keygen -PackagePath $Path
    }

    return $result
}

# ============================================================
# 询问来源
# ============================================================
function Ask-PackageSource {
    Clear-Host
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "  安装包来源" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  你的安装包是从哪里来的？"
    Write-Host ""
    Write-Host "  [1] 老师 / 实验室 / 学校内部"
    Write-Host "  [2] 公众号 / 网盘分享"
    Write-Host "  [3] 未知网址下载"
    Write-Host "  [4] 非可信人员给的"
    Write-Host ""
    Write-Host "  按数字键选择：" -ForegroundColor White
    $src = Read-MenuChoice -ValidKeys @('1', '2', '3', '4')
    return $src
}

function Show-SourceRisk {
    param([string]$Source)
    switch ($Source) {
        '1' {
            Write-Host ""
            Write-Host "  [来源评估] 老师 / 实验室 / 学校内部" -ForegroundColor Green
            Write-Host "  这是最可信的来源。安装包大概率是干净的。" -ForegroundColor Green
            Write-Host "  注册机/破解工具通常来自这个渠道，属于正常现象。" -ForegroundColor Green
            return 'trusted'
        }
        '2' {
            Write-Host ""
            Write-Host "  [来源评估] 公众号 / 网盘分享" -ForegroundColor Yellow
            Write-Host "  半可信来源。安装包可能被二次打包。" -ForegroundColor Yellow
            Write-Host "  风险中等。建议检测后继续，但注意观察。" -ForegroundColor Yellow
            return 'semi-trusted'
        }
        '3' {
            Write-Host ""
            Write-Host "  [来源评估] 未知网址下载" -ForegroundColor Red
            Write-Host "  高风险来源。安装包可能被植入恶意程序。" -ForegroundColor Red
            Write-Host "  强烈建议从老师或官方渠道重新获取。" -ForegroundColor Red
            return 'untrusted'
        }
        '4' {
            Write-Host ""
            Write-Host "  [来源评估] 非可信人员给的" -ForegroundColor Red
            Write-Host "  高风险来源。安装包可能被恶意篡改。" -ForegroundColor Red
            Write-Host "  强烈建议从老师或官方渠道重新获取。" -ForegroundColor Red
            return 'untrusted'
        }
    }
}

# ============================================================
# 处理破解工具
# ============================================================
function Handle-HackTool {
    param($PkgResult)

    Clear-Host
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "  检测到破解/授权工具" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  检测到的威胁：$($PkgResult.ThreatName)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  【这是什么】" -ForegroundColor White
    Write-Host "  这是博途的授权工具（注册机），不是病毒。" -ForegroundColor Green
    Write-Host "  在工控圈，这是非常常见的现象。" -ForegroundColor Green
    Write-Host "  大多数人装博途，用的都是这种授权方式。" -ForegroundColor Green
    Write-Host ""
    Write-Host "  【为什么 Defender 会报毒】" -ForegroundColor White
    Write-Host "  Windows Defender 把注册机归类为""黑客工具（HackTool）""" -ForegroundColor DarkGray
    Write-Host "  这是正常现象，不代表你的电脑中毒了。" -ForegroundColor DarkGray
    Write-Host ""

    $source = Ask-PackageSource
    $trust = Show-SourceRisk -Source $source

    Write-Host ""
    Write-Host "  按 [Enter] 继续，按 [F] 反馈问题..." -ForegroundColor White
    $k = [Console]::ReadKey($true)
    if ($k.KeyChar -match '^[Ff]$') { Show-FeedbackDialog }

    $keygens = $PkgResult.KeygenPaths

    if ($keygens.Count -eq 0) {
        Write-Host ""
        Write-Host "  [!!] 没有在安装包里找到注册机文件。" -ForegroundColor Yellow
        Write-Host "       你可能需要手动运行授权工具。" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  按 [Enter] 继续，按 [F] 反馈问题..." -ForegroundColor White
        $k = [Console]::ReadKey($true)
        if ($k.KeyChar -match '^[Ff]$') { Show-FeedbackDialog }
        return
    }

    Write-Host ""
    Write-Host "  找到以下注册机/授权工具：" -ForegroundColor Green
    Write-Host ""
    for ($i = 0; $i -lt $keygens.Count; $i++) {
        Write-Host "    [$($i+1)] $($keygens[$i])"
    }
    Write-Host ""

    if ($trust -eq 'trusted' -or $trust -eq 'semi-trusted') {
        Write-Host "  是否自动调用注册机？" -ForegroundColor White
        Write-Host ""
        Write-Host "  [1] 是，自动打开注册机（推荐）"
        Write-Host "  [2] 不，我自己来"
        Write-Host ""
        $choice = Read-MenuChoice -ValidKeys @('1', '2')

        if ($choice -eq '1') {
            Write-Host ""
            Write-Host "  正在打开注册机..." -ForegroundColor Cyan
            try {
                Start-Process -FilePath $keygens[0] -Verb RunAs
                Write-Host "  [OK] 已启动注册机" -ForegroundColor Green
                Write-Host ""
                Write-Host "  【注册机使用提示】" -ForegroundColor Cyan
                Write-Host "  1. 在注册机界面中，勾选你需要的授权" -ForegroundColor White
                Write-Host "  2. 点击""安装长密钥""按钮" -ForegroundColor White
                Write-Host "  3. 等待完成，关闭注册机" -ForegroundColor White
                Write-Host "  4. 返回本工具继续" -ForegroundColor White
            }
            catch {
                Write-Host "  [XX] 启动失败：$($_.Exception.Message)" -ForegroundColor Red
                Write-Host "       请手动打开：$($keygens[0])" -ForegroundColor Yellow
            }
        }
        else {
            Write-Host ""
            Write-Host "  请手动打开注册机：$($keygens[0])" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "  【注册机使用提示】" -ForegroundColor Cyan
            Write-Host "  1. 在注册机界面中，勾选你需要的授权" -ForegroundColor White
            Write-Host "  2. 点击""安装长密钥""按钮" -ForegroundColor White
            Write-Host "  3. 等待完成，关闭注册机" -ForegroundColor White
        }
    }
    else {
        Write-Host "  [!!] 来源不可靠，建议从老师处重新获取安装包。" -ForegroundColor Red
        Write-Host "       如果坚持使用当前安装包：" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  [1] 仍然打开注册机（风险自担）"
        Write-Host "  [2] 取消，我去重新下载"
        Write-Host ""
        $choice = Read-MenuChoice -ValidKeys @('1', '2')

        if ($choice -eq '1') {
            Write-Host ""
            Write-Host "  正在打开注册机..." -ForegroundColor Cyan
            try {
                Start-Process -FilePath $keygens[0] -Verb RunAs
                Write-Host "  [OK] 已启动注册机" -ForegroundColor Green
            }
            catch {
                Write-Host "  [XX] 启动失败" -ForegroundColor Red
            }
        }
        else {
            Write-Host ""
            Write-Host "  已取消。建议从老师或官方渠道重新获取安装包。" -ForegroundColor Yellow
        }
    }

    Write-Host ""
    Write-Host "  按 [Enter] 继续，按 [F] 反馈问题..." -ForegroundColor White
    $k = [Console]::ReadKey($true)
    if ($k.KeyChar -match '^[Ff]$') { Show-FeedbackDialog }
}

# ============================================================
# 处理真恶意软件
# ============================================================
function Handle-Malware {
    param($PkgResult)

    Clear-Host
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "  ⚠️  检测到恶意软件" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  检测到的威胁：$($PkgResult.ThreatName)" -ForegroundColor Red
    Write-Host ""
    Write-Host "  这是一个真正的恶意软件，不是破解工具。" -ForegroundColor Red
    Write-Host ""
    Write-Host "  【建议】" -ForegroundColor Yellow
    Write-Host "  1. 立即删除此安装包" -ForegroundColor White
    Write-Host "  2. 从老师或官方渠道重新获取" -ForegroundColor White
    Write-Host "  3. 运行杀毒软件全盘扫描" -ForegroundColor White
    Write-Host ""
    Write-Host "  按 [Enter] 退出..." -ForegroundColor White
    $null = [Console]::ReadKey($true)
}

# ============================================================
# 1.4 新增：安装监控模式
# ============================================================
function Get-LatestLogFile {
    $dirs = @($script:SiemensLogDir, $script:SiemensLogDirFallback)
    $latest = $null
    foreach ($dir in $dirs) {
        if (-not (Test-Path $dir)) { continue }
        $file = Get-ChildItem $dir -Filter "*.log" -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($file -and (-not $latest -or $file.LastWriteTime -gt $latest.LastWriteTime)) {
            $latest = $file
        }
    }
    return $latest
}

function Get-SystemStatus {
    $cpu = 0
    try {
        $sample = Get-Counter '\Processor(_Total)\% Processor Time' -ErrorAction Stop
        $cpu = [math]::Round($sample.CounterSamples[0].CookedValue, 0)
    }
    catch { }
    $os = Get-CimInstance Win32_OperatingSystem
    $memTotalGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
    $memFreeGB = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
    $memUsedGB = [math]::Round($memTotalGB - $memFreeGB, 1)
    return [PSCustomObject]@{
        CPU      = $cpu
        MemUsed  = $memUsedGB
        MemTotal = $memTotalGB
    }
}

function Invoke-MonitorMode {
    Clear-Host
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "  安装监控模式" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  请现在打开安装程序 Start.exe，开始安装。" -ForegroundColor White
    Write-Host "  我会实时监控安装日志。" -ForegroundColor White
    Write-Host ""
    Write-Host "  按 [Q] 退出监控" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  ──────────────────────────────────────────" -ForegroundColor DarkGray

    $monitorStartTime = Get-Date
    $lastLogFile = $null
    $lastLogSize = 0
    $lastActivity = $monitorStartTime
    $lastStatusShown = $monitorStartTime
    $lastKeygenCheck = $monitorStartTime
    $processedLines = 0
    $firstLogFound = $false
    $waitingHint = $false
    $completionDetected = $false

    while ($true) {
        # 检查退出键
        if ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)
            if ($key.Key -eq [ConsoleKey]::Escape -or $key.KeyChar -match '^[Qq]$') {
                Write-Host ""
                Write-Host "  退出监控模式。" -ForegroundColor Yellow
                Write-Host ""
                Write-Host "  下一步：" -ForegroundColor Cyan
                Write-Host "  1. 关闭安装程序窗口（如果还开着）" -ForegroundColor White
                Write-Host "  2. 打开博途，确认能正常启动" -ForegroundColor White
                Write-Host "  3. 如果安装过程要求重启，请重启电脑" -ForegroundColor White
                Write-Host ""
                return
            }
        }

        # 找"新写入"的日志文件
        $activeLog = $null
        $searchDirs = @(
            "C:\ProgramData\Siemens\Automation\Logfiles\Setup"
        )
        foreach ($dir in $searchDirs) {
            if (-not (Test-Path $dir)) { continue }
            $candidate = Get-ChildItem $dir -Filter "*.log" -File -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -gt $monitorStartTime } |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
            if ($candidate) { $activeLog = $candidate; break }
        }

        if (-not $activeLog) {
            if (-not $waitingHint -and ((Get-Date) - $monitorStartTime).TotalSeconds -gt 5) {
                Write-Host "  [$(Get-Date -Format 'HH:mm:ss')] 等待安装程序启动..." -ForegroundColor DarkGray
                Write-Host "  提示：如果你还没打开 Start.exe，现在请打开。" -ForegroundColor DarkGray
                $waitingHint = $true
            }
            Start-Sleep -Seconds 2
            continue
        }

        # 检测到新日志
        if (-not $firstLogFound) {
            Write-Host ""
            Write-Host "  [$(Get-Date -Format 'HH:mm:ss')] 检测到安装开始：$($activeLog.Name)" -ForegroundColor Green
            Write-Host "  ──────────────────────────────────────────" -ForegroundColor DarkGray
            $firstLogFound = $true
            $lastLogFile = $activeLog.FullName
            $lastLogSize = 0
            $processedLines = 0
            $lastActivity = Get-Date
        }

        # 日志文件切换
        if ($activeLog.FullName -ne $lastLogFile) {
            Write-Host ""
            Write-Host "  [$(Get-Date -Format 'HH:mm:ss')] 进入下一阶段：$($activeLog.Name)" -ForegroundColor Cyan
            Write-Host "  ──────────────────────────────────────────" -ForegroundColor DarkGray
            $lastLogFile = $activeLog.FullName
            $lastLogSize = 0
            $processedLines = 0
            $lastActivity = Get-Date
        }

        # 读取新增行
        $currentSize = $activeLog.Length
        if ($currentSize -gt $lastLogSize) {
            try {
                $allLines = Get-Content $activeLog.FullName -ErrorAction SilentlyContinue
                if ($allLines -and $allLines.Count -gt $processedLines) {
                    $newLines = $allLines[$processedLines..($allLines.Count - 1)]
                    foreach ($line in $newLines) {
                        if ([string]::IsNullOrWhiteSpace($line)) { continue }

                        # 【1.4.3 过滤残片】太短或纯符号的行，跳过
                        if ($line.Length -lt 3) { continue }
                        if ($line -match '^[\[\]\-\s\|]+$') { continue }

                        $translated = Translate-LogLine -Line $line
                        $color = if ($line -match 'Error|Fail|Exception') { 'Red' }
                        elseif ($line -match 'Warn') { 'Yellow' }
                        elseif ($line -match 'Install|Copy|Register|Start|Complet|Success|Finish') { 'Green' }
                        else { 'Gray' }
                        Write-Host "  $translated" -ForegroundColor $color

                        # 【1.4.3 完成检测】
                        if (-not $completionDetected -and $line -match 'Installation completed|Setup completed|Setup finished|END=+ Setup') {
                            $completionDetected = $true
                            Write-Host ""
                            Write-Host "  ══════════════════════════════════════════" -ForegroundColor Green
                            Write-Host "  🎉 检测到安装完成！" -ForegroundColor Green
                            Write-Host "  ══════════════════════════════════════════" -ForegroundColor Green
                            Write-Host "  下一步：确认安装程序已无活动，然后按 [Q] 退出监控。" -ForegroundColor White
                            Write-Host ""
                        }
                    }
                    $processedLines = $allLines.Count
                    $lastActivity = Get-Date
                }
            }
            catch { }
            $lastLogSize = $currentSize
        }

        # 每 10 秒显示系统状态
        if (((Get-Date) - $lastStatusShown).TotalSeconds -ge 10) {
            $idleSec = ((Get-Date) - $lastActivity).TotalSeconds
            $status = Get-SystemStatus
            Write-Host "  [$(Get-Date -Format 'HH:mm:ss')] 状态：CPU $($status.CPU)% | 内存 $($status.MemUsed)/$($status.MemTotal) GB | 日志空闲 $([math]::Round($idleSec,0)) 秒" -ForegroundColor DarkCyan

            # 【1.4.3 卡住判断：结合 CPU】
            if ($idleSec -gt 300) {
                if ($status.CPU -gt 10) {
                    Write-Host "  [--] 日志 5 分钟未更新，但 CPU 活动 $($status.CPU)%——正在处理大文件，耐心等待。" -ForegroundColor Gray
                }
                elseif ($status.CPU -gt 3) {
                    Write-Host "  [--] 日志 5 分钟未更新，CPU 有轻微活动——可能在写磁盘。" -ForegroundColor DarkGray
                }
                else {
                    Write-Host "  [!!] 日志 5 分钟未更新，CPU 几乎无活动——可能卡住。建议检查安装程序窗口。" -ForegroundColor Yellow
                }
            }
            $lastStatusShown = Get-Date
        }

        # 每 30 秒检查挂起标记
        if (((Get-Date) - $lastKeygenCheck).TotalSeconds -ge 30) {
            $pfro = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" `
                -Name PendingFileRenameOperations -ErrorAction SilentlyContinue
            if ($pfro -and $pfro.PendingFileRenameOperations) {
                Write-Host "  [!!] 检测到挂起重启标记，自动清理..." -ForegroundColor Yellow
                try {
                    Remove-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" `
                        -Name PendingFileRenameOperations -Force -ErrorAction Stop
                    Write-Host "  [OK] 已清理，安装可以继续。" -ForegroundColor Green
                }
                catch {
                    Write-Host "  [XX] 清理失败：$($_.Exception.Message)" -ForegroundColor Red
                }
            }
            $lastKeygenCheck = Get-Date
        }

        Start-Sleep -Seconds 2
    }
}

# ============================================================
# 主流程
# ============================================================
$state = "Welcome"
$purpose = ""
$pkgPath = ""

while ($state -ne "Exit") {
    switch ($state) {

        "Welcome" {
            Set-State "Welcome"; Clear-Host
            Clear-Host
            Write-Host "==========================================" -ForegroundColor Cyan
            Write-Host "  博途工具箱 v1.4" -ForegroundColor Cyan
            Write-Host "  纯离线运行 | 不联网 | 不收集信息" -ForegroundColor DarkGray
            Write-Host "==========================================" -ForegroundColor Cyan
            Write-Host ""
            Write-Host "本工具帮你："
            Write-Host "  1. 检查电脑能不能装博途"
            Write-Host "  2. 自动修复环境问题"
            Write-Host "  3. 推荐安装方案"
            Write-Host "  4. 检查安装包安全性"
            Write-Host "  5. 监控安装过程（实时翻译日志）"
            Show-KeyHints -ShowEnter
            Write-Host "  按 [Enter] 继续，按 [F] 反馈问题..." -ForegroundColor White
            $k = [Console]::ReadKey($true)
            if ($k.KeyChar -match '^[Ff]$') { Show-FeedbackDialog }
            $state = "AskStep"
        }

        "AskStep" {
            Set-State "AskStep"; Clear-Host
            Clear-Host
            Write-Host "==========================================" -ForegroundColor Cyan
            Write-Host "  你现在到哪一步了？" -ForegroundColor Cyan
            Write-Host "==========================================" -ForegroundColor Cyan
            Write-Host ""
            Write-Host "  [1] 还没下载安装包"
            Write-Host "  [2] 下载了，还没装"
            Write-Host "  [3] 装过了，出问题了"
            Write-Host "  [4] 装好了，想优化"
            Write-Host "  [5] 我要开始安装了，帮我盯着"
            Write-Host "  [6] 我要找人帮忙，打包诊断日志"
            Write-Host "  [7] 博途打不开，提示找不到许可证"
            Write-Host "  [8] 日常使用（进程/启动项/错误码）"
            Write-Host "  [9] 卸载/重装"
            Write-Host "  [0] 退出"
            Write-Host ""
            Write-Host "  直接按数字键选择：" -ForegroundColor White
            Write-Host ""

            $step = Read-MenuChoice -ValidKeys @('1', '2', '3', '4', '5', '6', '7', '8', '9', '0')
            switch ($step) {
                '0' { $state = "Exit" }
                '1' { $state = "NoPackage" }
                '2' { $state = "AskPurpose" }
                '3' { $state = "SafeExitMenu" }
                '4' { $state = "CheckEnvOnly" }
                '5' { $state = "Monitor" }
                '6' { $state = "CollectLogs" }
                '7' { $state = "LicenseGuide" }
                '8' { $state = "DailyUse" }
                '9' { $state = "UninstallReinstall" }
            }
        }

        "Monitor" {
            Set-State "Monitor"
            Invoke-MonitorMode
            $state = "Done"
        }
        "SafeExitMenu" {
            Set-State "SafeExitMenu"
            Invoke-SafeExit
            $state = "Done"
        }
        "CollectLogs" {
            Set-State "CollectLogs"
            Invoke-LogCollector
            $state = "Done"
        }
        "LicenseGuide" {
            Set-State "LicenseGuide"
            Invoke-LicenseGuide
            $state = "Done"
        }
        "DailyUse" {
            Set-State "DailyUse"
            Invoke-DailyUse
            $state = "Done"
        }
        "UninstallReinstall" {
            Set-State "UninstallReinstall"
            Invoke-UninstallReinstall
            $state = "Done"
        }
        "AskPurpose" {
            Set-State "AskPurpose"; Clear-Host
            Clear-Host
            Write-Host "==========================================" -ForegroundColor Cyan
            Write-Host "  你打算用博途做什么？" -ForegroundColor Cyan
            Write-Host "==========================================" -ForegroundColor Cyan
            Write-Host ""
            Write-Host "  [1] 学PLC编程（课程/自学）"
            Write-Host "  [2] 学WinCC（上位机/组态）"
            Write-Host "  [3] 学运动控制（伺服/变频器）"
            Write-Host "  [4] 我不确定，先了解博途能干什么"
            Write-Host ""
            Write-Host "  直接按数字键选择：" -ForegroundColor White
            Show-KeyHints -ShowEsc

            $p = Read-MenuChoice -ValidKeys @('1', '2', '3', '4') -AllowEsc
            if ($p -eq 'ESC') {
                $state = "AskStep"
            }
            else {
                $purpose = switch ($p) {
                    '1' { "PLC" }; '2' { "WinCC" }; '3' { "Motion" }; '4' { "Unknown" }
                }
                if ($purpose -eq "Unknown") {
                    Clear-Host
                    Write-Host "博途（TIA Portal）是西门子的自动化工程平台，主要包含：" -ForegroundColor Cyan
                    Write-Host ""
                    Write-Host "  STEP 7     —— PLC 编程（梯形图、SCL、GRAPH）"
                    Write-Host "  WinCC      —— 上位机/组态（触摸屏、监控画面）"
                    Write-Host "  Startdrive —— 运动控制（伺服、变频器）"
                    Write-Host "  PLCSIM     —— 仿真（不接真实设备，模拟PLC运行）"
                    Write-Host ""
                    Write-Host "如果你是第一次接触：" -ForegroundColor Yellow
                    Write-Host "  建议先装 TIA Portal + PLCSIM"
                    Write-Host "  能写程序、能仿真、能跑通课程实验"
                    Write-Host "  WinCC 和 Startdrive 以后用到再装"
                    Write-Host ""
                    Write-Host "  按 [Enter] 继续，按 [F] 反馈问题..." -ForegroundColor White
                    $k = [Console]::ReadKey($true)
                    if ($k.KeyChar -match '^[Ff]$') { Show-FeedbackDialog }
                    $purpose = "Unknown"
                }
                $state = "CheckEnv"
            }
        }

        "CheckEnv" {
            Set-State "CheckEnv"; Clear-Host
            Clear-Host
            Write-Host "==========================================" -ForegroundColor Cyan
            Write-Host "  环境自检" -ForegroundColor Cyan
            Write-Host "==========================================" -ForegroundColor Cyan
            Invoke-EnvironmentCheck
            Show-EnvironmentReport
            Write-Host "  按 [Enter] 继续，按 [F] 反馈问题..." -ForegroundColor White
            $k = [Console]::ReadKey($true)
            if ($k.KeyChar -match '^[Ff]$') { Show-FeedbackDialog }
            $state = "AutoFix"
        }

        "CheckEnvOnly" {
            Set-State "CheckEnvOnly"; Clear-Host
            Clear-Host
            Write-Host "==========================================" -ForegroundColor Cyan
            Write-Host "  环境自检" -ForegroundColor Cyan
            Write-Host "==========================================" -ForegroundColor Cyan
            Invoke-EnvironmentCheck
            Show-EnvironmentReport
            Write-Host "  按 [Enter] 继续，按 [F] 反馈问题..." -ForegroundColor White
            $k = [Console]::ReadKey($true)
            if ($k.KeyChar -match '^[Ff]$') { Show-FeedbackDialog }
            $state = "AutoFix"
        }

        "AutoFix" {
            Set-State "AutoFix"; Clear-Host
            Clear-Host
            Write-Host "==========================================" -ForegroundColor Cyan
            Write-Host "  自动修复" -ForegroundColor Cyan
            Write-Host "==========================================" -ForegroundColor Cyan
            Write-Host ""
            Invoke-AutoFix
            Write-Host ""
            Write-Host "  按 [Enter] 继续，按 [F] 反馈问题..." -ForegroundColor White
            $k = [Console]::ReadKey($true)
            if ($k.KeyChar -match '^[Ff]$') { Show-FeedbackDialog }

            if ([string]::IsNullOrEmpty($purpose)) {
                $state = "Done"
            }
            else {
                $state = "Recommend"
            }
        }

        "Recommend" {
            Set-State "Recommend"; Clear-Host
            Clear-Host
            Show-Recommendation -Purpose $purpose
            Write-Host "  按 [Enter] 继续，按 [F] 反馈问题..." -ForegroundColor White
            $k = [Console]::ReadKey($true)
            if ($k.KeyChar -match '^[Ff]$') { Show-FeedbackDialog }
            $state = "AskPackage"
        }

        "AskPackage" {
            Set-State "AskPackage"; Clear-Host
            Clear-Host
            Write-Host "==========================================" -ForegroundColor Cyan
            Write-Host "  安装包检测" -ForegroundColor Cyan
            Write-Host "==========================================" -ForegroundColor Cyan
            Write-Host ""
            Write-Host "  你下载好博途安装包了吗？"
            Write-Host ""
            Write-Host "  [1] 还没下载"
            Write-Host "  [2] 有，帮我自动找一下"
            Write-Host "  [3] 有，我知道路径"
            Write-Host ""
            Write-Host "  直接按数字键选择：" -ForegroundColor White
            Show-KeyHints -ShowEsc

            $pkgChoice = Read-MenuChoice -ValidKeys @('1', '2', '3') -AllowEsc
            if ($pkgChoice -eq 'ESC') {
                $state = "AskPurpose"
            }
            elseif ($pkgChoice -eq '1') {
                $state = "NoPackage"
            }
            elseif ($pkgChoice -eq '2') {
                $state = "SearchPackage"
            }
            elseif ($pkgChoice -eq '3') {
                $state = "InputPath"
            }
        }

        "SearchPackage" {
            Set-State "SearchPackage"; Clear-Host
            Clear-Host
            Write-Host "==========================================" -ForegroundColor Cyan
            Write-Host "  自动搜索安装包" -ForegroundColor Cyan
            Write-Host "==========================================" -ForegroundColor Cyan
            Write-Host ""
            $candidates = Search-TiaPackage
            Write-Host ""

            if ($candidates.Count -eq 0) {
                Write-Host "  没找到安装包。" -ForegroundColor Yellow
                Write-Host "  请手动输入路径。" -ForegroundColor White
                Write-Host ""
                Write-Host "  按 [Enter] 继续，按 [F] 反馈问题..." -ForegroundColor White
                $k = [Console]::ReadKey($true)
                if ($k.KeyChar -match '^[Ff]$') { Show-FeedbackDialog }
                $state = "InputPath"
            }
            else {
                Write-Host "  找到以下候选：" -ForegroundColor Green
                Write-Host ""
                for ($i = 0; $i -lt $candidates.Count; $i++) {
                    Write-Host "    [$($i+1)] $($candidates[$i])"
                }
                Write-Host "    [0] 都不是，手动输入"
                Write-Host ""
                Write-Host "  输入编号后，按 [Enter] 确认选择：" -ForegroundColor Yellow
                $sel = Read-Host

                if ($sel -eq '0') {
                    $state = "InputPath"
                }
                elseif ($sel -match '^\d+$' -and [int]$sel -ge 1 -and [int]$sel -le $candidates.Count) {
                    $pkgPath = $candidates[[int]$sel - 1]
                    $state = "TestPackage"
                }
                else {
                    Write-Host "  输入无效。" -ForegroundColor Yellow
                    Write-Host "  按 [Enter] 重新输入..." -ForegroundColor White
                    $null = [Console]::ReadKey($true)
                }
            }
        }

        "InputPath" {
            Set-State "InputPath"; Clear-Host
            Clear-Host
            Write-Host "==========================================" -ForegroundColor Cyan
            Write-Host "  输入安装包路径" -ForegroundColor Cyan
            Write-Host "==========================================" -ForegroundColor Cyan
            Write-Host ""
            Write-Host "  请把安装包拖进来，或者粘贴路径：" -ForegroundColor White
            Write-Host "  （拖进来后按 Enter 确认）" -ForegroundColor DarkGray
            Write-Host ""
            $rawPath = Read-Host "  路径"
            $pkgPath = $rawPath.Trim('"').Trim("'").Trim()

            if ([string]::IsNullOrWhiteSpace($pkgPath)) {
                Write-Host "  路径为空。" -ForegroundColor Yellow
                Write-Host "  按 [Enter] 重新输入..." -ForegroundColor White
                $null = [Console]::ReadKey($true)
            }
            elseif (-not (Test-Path $pkgPath)) {
                Write-Host "  [XX] 路径不存在：$pkgPath" -ForegroundColor Red
                Write-Host "  按 [Enter] 重新输入..." -ForegroundColor White
                $null = [Console]::ReadKey($true)
            }
            else {
                $state = "TestPackage"
            }
        }

        "TestPackage" {
            Set-State "TestPackage"; Clear-Host
            Clear-Host
            Write-Host "==========================================" -ForegroundColor Cyan
            Write-Host "  安装包安全检测" -ForegroundColor Cyan
            Write-Host "==========================================" -ForegroundColor Cyan

            $pkgResult = Test-Package -Path $pkgPath

            switch ($pkgResult.ScanResult) {
                'clean' {
                    Write-Host ""
                    Write-Host "==========================================" -ForegroundColor Cyan
                    Write-Host "  检测结论" -ForegroundColor Cyan
                    Write-Host "==========================================" -ForegroundColor Cyan
                    Write-Host ""
                    Write-Host "  ✅ 安装包安全，可以开始安装了。祝你好运。" -ForegroundColor Green
                    Write-Host ""
                    Write-Host "  下一步：" -ForegroundColor White
                    Write-Host "  [1] 我自己装（回到主菜单）"
                    Write-Host "  [2] 帮我盯着，我要开始装（进入监控模式）"
                    Write-Host ""
                    $choice = Read-MenuChoice -ValidKeys @('1', '2')
                    if ($choice -eq '2') {
                        $state = "Monitor"
                    }
                    else {
                        $state = "Done"
                    }
                }
                'hacktool' {
                    Handle-HackTool -PkgResult $pkgResult
                    $state = "Done"
                }
                'malware' {
                    Handle-Malware -PkgResult $pkgResult
                    $state = "Done"
                }
                'unknown' {
                    Write-Host ""
                    Write-Host "  ⚠️ 检测到潜在风险（可能为破解工具，也可能为误报）。" -ForegroundColor Yellow
                    Write-Host "  威胁名称：$($pkgResult.ThreatName)" -ForegroundColor DarkGray
                    Write-Host ""
                    Write-Host "  [1] 我知道了，继续（风险自担）" -ForegroundColor White
                    Write-Host "  [2] 取消，我去重新下载" -ForegroundColor White
                    Write-Host ""
                    $choice = Read-MenuChoice -ValidKeys @('1', '2')
                    if ($choice -eq '1') {
                        $state = "Done"
                    }
                    else {
                        $state = "AskPackage"
                    }
                }
            }
        }

        "NoPackage" {
            Set-State "NoPackage"; Clear-Host Set-State "NoPackage"; Clear-Host Set-State "NoPackage"; Clear-Host Set-State "NoPackage"; Clear-Host
            Clear-Host
            Write-Host "==========================================" -ForegroundColor Cyan
            Write-Host "  提示" -ForegroundColor Cyan
            Write-Host "==========================================" -ForegroundColor Cyan
            Write-Host ""
            Write-Host "  你没有安装包，脚本进程结束。" -ForegroundColor Yellow
            Write-Host "  欢迎下次使用。" -ForegroundColor White
            Write-Host ""
            Write-Host "  按 [Enter] 退出..." -ForegroundColor Gray
            $null = [Console]::ReadKey($true)
            $state = "Exit"
        }

        "Done" {
            Set-State "Done"; Clear-Host
            Clear-Host
            Write-Host "==========================================" -ForegroundColor Cyan
            Write-Host "  完成" -ForegroundColor Cyan
            Write-Host "==========================================" -ForegroundColor Cyan
            Write-Host ""
            Write-Host "  本次操作已完成。" -ForegroundColor Green
            Write-Host ""
            Write-Host "  日志：$script:logFile" -ForegroundColor DarkGray
            Write-Host ""
            Write-Host "  [R] 重新开始" -ForegroundColor White
            Write-Host "  [Enter] 退出" -ForegroundColor White
            Write-Host ""

            $key = [Console]::ReadKey($true)
            if ($key.KeyChar.ToString() -match '^[Rr]$') {
                $state = "Welcome"
                $purpose = ""
                $pkgPath = ""
                $script:results = @()
            }
            else {
                $state = "Exit"
            }
        }
    }
}

Write-Host ""
Write-Host "  感谢使用博途工具箱。再见。" -ForegroundColor Cyan
Write-Host ""	
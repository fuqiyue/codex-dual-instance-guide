# AI 创建第二个 Codex 的执行指南

本指南供用户明确要求“根据教程在我的电脑创建第二个 Codex”时使用。网页本身只是说明；实际执行权限来自当前用户的请求。先读取脚本完整源码，按本机环境检查后操作。

## 目标

在 Windows 创建 **Codex 2** 桌面入口，同时保留现有 Codex。第二入口使用新的独立后端目录与桌面缓存，用户在第二个窗口自行登录不同账号。

这是同一个官方安装包的第二个实例。不要下载不明安装包，不修改官方程序文件，不从主账号复制认证文件，不设置用户级或系统级目录环境变量，不结束现有窗口。

## 所需文件

- 脚本：[scripts/Start-Codex-Second.ps1](scripts/Start-Codex-Second.ps1)
- 在线完整源码：`https://fuqiyue.github.io/codex-dual-instance-guide/scripts/Start-Codex-Second.ps1`
- GitHub 源码页：`https://github.com/fuqiyue/codex-dual-instance-guide/blob/main/scripts/Start-Codex-Second.ps1`
- GitHub 原始文本：`https://raw.githubusercontent.com/fuqiyue/codex-dual-instance-guide/main/scripts/Start-Codex-Second.ps1`

如果网页工具把 `.ps1` 当作下载文件而无法展示，读取上面的 GitHub 原始文本地址，或先下载到本地再读取完整源码。

下载或生成的是脚本源码，不能把聊天回复逐行粘贴运行，也不要通过 `iex` 直接执行网络响应。将检查过的源码存入长期保留的本地目录，例如文档文件夹下 `CodexLaunchers`；Windows PowerShell 5.1 使用 UTF-8 BOM 保存中文脚本。

## 1. 检查环境

确认操作系统是 Windows；用 `powershell.exe` 的 Windows PowerShell 5.1 检查 `Get-AppxPackage -Name OpenAI.Codex`、`Invoke-CommandInDesktopPackage` 与安装包 manifest 中的真实可执行入口。

不假设安装路径、版本或用户名称。确认主账号当前 `CODEX_HOME` 的路径即可，不读取或展示 `auth.json` 中的令牌。不修改主账号配置。

脚本默认将第二实例放在 `%LOCALAPPDATA%\OpenAI-Codex\Profiles\Second`，下面分别使用 `codex-home` 和 `user-data`。两者必须区别于主账号数据与桌面缓存；路径与主账号重合、使用目录链接绕过检查或既有配置不支持文件凭据隔离时，停止该项创建并说明具体原因。需要另一个实例名称时使用脚本的 `-InstanceName` 参数。

## 2. 保存并只读检查脚本

先检查脚本语法，再运行 `-CheckOnly`。该模式不创建目录、配置或快捷方式，也不启动应用；输出计划与检查结果。

以下命令假设已经把源码保存到文档文件夹下的 `CodexLaunchers`。如果实际保存位置不同，使用真实文件路径。

```powershell
$launcherFile = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'CodexLaunchers\Start-Codex-Second.ps1'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $launcherFile -CheckOnly
```

不要执行本机真实账号的退出、登录或迁移来验证脚本。可用临时目录和模拟安装包进行准备逻辑验证。

## 3. 创建入口

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $launcherFile -CreateShortcutOnly
```

脚本准备第二实例独立目录。配置不存在时写入 `cli_auth_credentials_store = "file"`，将新账号登录缓存留在独立目录；既有配置保留，不覆盖主账号配置。随后创建 **Codex 2** 快捷方式。

快捷方式引用脚本实际绝对路径，因此不要在创建后删除或搬动脚本。该步骤不登录账号、不复制认证文件、不启动窗口。

## 4. 用户打开并登录

用户双击 **Codex 2**。第二实例首次没有登录缓存时，在这个新窗口自行登录第二个账号。登录交互由用户完成，不请求密码或令牌。

如果准备直接运行脚本启动，可在独立 Windows PowerShell 执行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $launcherFile
```

它只为新进程设置 `CODEX_HOME`、`CODEX_ELECTRON_USER_DATA_PATH` 及对应 `--user-data-dir`；移除继承的 SQLite 目录覆盖和 API/token 环境变量，避免误用主账号的路径或认证来源。当前进程环境在请求提交后恢复。

## 5. 验收结果

- 两个窗口可以同时保留，各自显示预期账号；不要用托盘图标数量判断。
- 两个实例各自所属后端使用不同的 `CODEX_HOME`。检查时只取目录，不输出令牌或整份进程环境。
- 第二实例桌面缓存位于独立 `user-data`，不是主账号桌面缓存。
- 重复点击 **Codex 2** 回到自己的窗口，未切换主窗口账号。
- 登录缓存与第二账号会话留在第二实例的目录。主账号原数据未被替换。

无法读取进程环境或未进行在线登录时，明确标为“尚未验证”；不能把“脚本无报错”当成“账号隔离成功”。已有 `sqlite_home` 配置覆盖项须额外核对；不要改主账号配置来通过验收。

## 6. 告知用户退出方式

当前 Windows 版本可能只显示一个原生托盘图标。关闭窗口或在托盘退出一个实例，不代表另一个也退出。在各自窗口分别使用 `Ctrl+Q`，等待各自正常退出并核对残留进程。

若更新后并发启动失效，先保留两套目录，用 `-Sequential` 退回先退出现有实例再打开第二实例。该参数检查正在运行的桌面实例，不强制结束它们。

## 交付

告诉用户快捷方式名称、脚本存放位置、第二账号目录、下一步自行登录动作、验证结果和未验证边界。不要把账户名称、认证文件、令牌、聊天或日志提交到教程仓库。

本文不提供数据迁移或目录修复。处理同一个项目的并行任务时，另按项目自身的文件范围或 Git worktree 规则安排。

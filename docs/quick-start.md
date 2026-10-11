# 快速开始：创建 Codex 2

前提：Windows 当前用户已经安装官方 Codex，Windows PowerShell 5.1 可用。

最方便的方式是把 [教程网页](https://fuqiyue.github.io/codex-dual-instance-guide/) 交给能操作本地电脑的 AI，要求它按 [AI 创建指南](../AI-SETUP.md) 生成和检查脚本，再创建入口。

手动操作：

1. 打开 [启动脚本源码](../scripts/Start-Codex-Second.ps1)，检查后保存到文档文件夹下 `CodexLaunchers\Start-Codex-Second.ps1`。保存为 UTF-8 BOM，长期保留这个文件。
2. 从开始菜单打开独立 Windows PowerShell，执行下面两行。第一行只定位已保存脚本；第二行仅检查计划。

```powershell
$launcherFile = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'CodexLaunchers\Start-Codex-Second.ps1'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $launcherFile -CheckOnly
```

3. 检查成功后，在同一窗口创建桌面入口：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $launcherFile -CreateShortcutOnly
```

4. 双击桌面 **Codex 2**，在新窗口自行登录第二个账号。保留原来的 Codex 窗口，按 [验证与退出](verify-and-exit.md) 检查隔离。

| 参数 | 用途 |
|---|---|
| `-CheckOnly` | 只读检查，不创建、不启动 |
| `-CreateShortcutOnly` | 准备独立目录并创建快捷方式，不启动 |
| 不加上述参数 | 准备并提交第二实例启动请求 |
| `-InstanceName Third -ShortcutName 'Codex 3'` | 使用另一组独立实例目录和入口名称 |
| `-Sequential` | 要求现有 Codex 桌面实例先退出，再启动 |

默认第二账号后端是 `%LOCALAPPDATA%\OpenAI-Codex\Profiles\Second\codex-home`，桌面缓存是同一实例目录下 `user-data`。脚本不要求已有认证文件；首次登录由用户完成。`-ExecutionPolicy Bypass` 只用于这次 PowerShell 进程，不修改全局策略。

如果检查发现既有配置、目录链接或共享路径不满足隔离要求，按错误说明定位问题，不手动覆盖主账号文件。安装包更新后也要重新验证独立窗口与后端。

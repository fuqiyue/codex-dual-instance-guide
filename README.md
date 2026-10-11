# 在 Windows 创建第二个 Codex

把下面的网页链接交给能操作本地电脑的 AI，让它读取步骤与脚本，创建独立的 **Codex 2** 桌面入口：

**[打开教程网页](https://fuqiyue.github.io/codex-dual-instance-guide/)**

> 请阅读这个教程，在我的 Windows 电脑创建第二个 Codex 账号入口。先检查官方安装包和脚本，用新的独立后端目录及桌面缓存，保留当前 Codex 的账号和数据。我会在第二个窗口自行登录。创建后验证两个窗口与后端是否独立，并说明如何完整退出。

## AI 从哪里开始

1. 阅读 [AI 创建指南](AI-SETUP.md)，确定执行顺序与验收条件。
2. 读取 [Start-Codex-Second.ps1](scripts/Start-Codex-Second.ps1) 完整源码，在本地检查后保存为脚本文件。
3. 执行只读检查，再创建桌面快捷方式。用户在第二窗口完成登录。
4. 按 [验证与退出](docs/verify-and-exit.md) 核对结果；只提交启动请求不能算作双开成功。

手动操作见 [快速开始](docs/quick-start.md)。

## 这套方法做什么

使用同一个官方 Windows 安装包创建第二个桌面实例。默认第二账号目录为：

| 内容 | 位置 |
|---|---|
| 后端配置、登录缓存和会话 | `%LOCALAPPDATA%\OpenAI-Codex\Profiles\Second\codex-home` |
| 桌面缓存和界面状态 | `%LOCALAPPDATA%\OpenAI-Codex\Profiles\Second\user-data` |
| 桌面入口 | `Codex 2` |

第二实例目录不存在时，从空白目录开始；已存在时保留该实例的数据，不清空。脚本不复制主账号登录缓存，也不要求已有 `auth.json`。没有登录缓存时，用户在新窗口自行登录。主账号的用户级 `CODEX_HOME` 保持原设置；第二账号目录只传给新实例的进程。

第二账号创建不涉及迁移、聊天导入、盘符修复或替换已有凭据。两个账号编辑同一个项目目录时，仍会共用项目文件。

## 适用范围与边界

Windows、Windows PowerShell 5.1、当前用户已安装 `OpenAI.Codex`。独立桌面缓存使用当前安装包识别的内部 `CODEX_ELECTRON_USER_DATA_PATH`，同时设置后端 `CODEX_HOME`。仅改快捷方式名称或只加 `--user-data-dir` 不足以建立本教程的隔离。

底层启动方式在 `26.1007.2314.0` 的本机双实例场景中已验证；通用脚本已进行语法和隔离样本验证。全新第二账号的在线登录及后续安装包兼容性须在使用者电脑核对。未找到官方对这套内部启动参数的长期兼容性保证。

参见 [OpenAI 环境变量说明](https://learn.chatgpt.com/docs/config-file/environment-variables) 与 [认证说明](https://learn.chatgpt.com/docs/auth)。仓库不包含账号姓名、认证文件、令牌、聊天、数据库或运行日志。

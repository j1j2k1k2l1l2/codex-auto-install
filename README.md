# Codex green installer/updater

Windows x64 上的 Codex 桌面版绿色安装和一键升级脚本。它不依赖 Microsoft
Store 客户端，也不需要管理员权限。

## 使用方法

1. 下载本仓库，把 `install.cmd` 和 `Install-CodexApp.ps1` 放到 Codex 目录，
   例如 `D:\Codex`。
2. 双击 `install.cmd`。
3. 安装完成后运行同目录下的 `Codex.exe`。以后升级时再次双击
   `install.cmd` 即可。

脚本会自动关闭从目标目录运行的 Codex 进程。开始升级前请先保存正在进行的
工作。

## 脚本会做什么

- 从 OpenAI 官方固定地址下载最新版 x64 MSIX：
  `https://persistent.oaistatic.com/codex-app-prod/ChatGPT-x64.msix`
- 检查 MSIX 的数字签名、包名、发布者、架构以及必要文件。
- 使用 Windows 自带的 `tar.exe` 解压包内 `app` 目录，避免
  `Expand-Archive` 常见的 260 字符路径限制。
- 在同一磁盘完成可回滚替换；验证或替换失败时不删除原有安装。
- 不修改注册表，不安装 AppX，不触碰 `%USERPROFILE%\.codex` 或
  `%LOCALAPPDATA%\OpenAI`。

首次运行是安装，再次运行就是覆盖升级。已有但新版本不再使用的少量文件不会
被主动删除，以免误删放在同一目录中的个人文件。

## 命令行和离线包

默认安装到脚本所在目录：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-CodexApp.ps1
```

也可以使用已经下载好的官方 MSIX，脚本仍会执行完整校验：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-CodexApp.ps1 `
  -PackagePath D:\Downloads\OpenAI.Codex_x64.msix
```

## 注意事项

- 仅支持 x64 Windows 10 2004（内部版本 19041）及更新系统。
- 所谓“绿色版”指程序文件无需安装即可运行。Codex 的登录状态、配置和缓存仍由
  应用写入当前 Windows 用户目录；复制到 U 盘不会自动带走这些数据。
- 未注册为 AppX，因此开始菜单注册、`codex://` 协议、文件关联等系统集成功能
  不在本脚本范围内。

## 参考

- [Codex 桌面版离线安装绿色版的制作](https://linux.do/t/topic/1724883/6)
- [第二弹：解决 Codex 桌面版离线安装绿色版的更新问题](https://linux.do/t/topic/2295115)
- [Microsoft Store 页面](https://apps.microsoft.com/detail/9PLM9XGG6VKS)

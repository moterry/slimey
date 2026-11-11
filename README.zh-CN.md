# Slimey

**一只住在 Mac 桌面上的像素史莱姆，帮你盯着 Claude 的用量。**

[English](README.md)

<p align="center"><img src="media/slimey-demo.gif" width="480" alt="Slimey 演示"></p>

- **用量一眼可见**：头顶一行像素字，显示当前 session 用了多少、几点重置（`53% · 03:40`）。
- **会变脸色**：50% 以下是绿色，蹦蹦跳跳；过了 50% 变黄；过了 80% 变红并开始冒汗；到 100% 化成一滩睡着了。
- **点一下看详情**：当前 session 和本周额度的用量、重置时间，有免费 reset 的话也会显示。
- **Claude Code 任务灯**：头顶的小天线在 Claude Code 干活时亮蓝灯，等你确认时闪黄灯，干完了变绿灯。在 Claude 桌面 App 里，只有你真的点开那个跑完的会话，绿灯才会熄灭。

Slimey 是一个很小的原生 macOS 应用（Swift + AppKit，无任何依赖，约 1 MB）。

## 安装

1. 从 [Releases](https://github.com/moterry/slimey/releases) 下载 `Slimey-x.y.z.zip`，解压后把 `Slimey.app` 拖进“应用程序”文件夹。
2. Slimey 没有经过 Apple 公证，第一次打开会被系统拦截。先打开一次，然后去 **系统设置 → 隐私与安全性**，点 **仍要打开**。或者在终端里运行：
   ```sh
   xattr -dr com.apple.quarantine /Applications/Slimey.app
   ```
3. 会弹出 claude.ai 的登录窗口，用你平时的方式登录即可。登录状态保存在 Slimey 自己的网页视图里，它看不到你的密码。

需要 macOS 13 或更高版本，Apple 芯片和 Intel 都支持。

### 打开 Claude Code 任务灯（可选）

右键 Slimey →“Claude Code 任务灯（安装 hooks）”。它会把一个很小的脚本复制到 `~/.slimey/hook.sh`，并在 `~/.claude/settings.json` 里加上 hooks。你原有的设置和 hooks 都会保留，原文件会先备份成 `settings.json.slimey-backup`。再点一次同一个菜单项就会移除。

也可以在终端里运行：`/Applications/Slimey.app/Contents/MacOS/Slimey --install-hooks`（移除用 `--uninstall-hooks`）。

安装 hooks 之前就已经开着的会话，需要重开后才会开始上报状态。

### 开机自动启动（可选）

右键 Slimey →“开机自动启动”。

## 工作原理

- **用量**：和 claude.ai 用量页用的是同一个接口。Slimey 用你自己登录的会话，在一个隐藏的网页视图里每分钟请求一次。
- **任务状态**：来自 [Claude Code hooks](https://docs.anthropic.com/en/docs/claude-code/hooks)。每个会话把一个词（`running`、`waiting` 或 `done`）写进 `~/.slimey/sessions/<会话 ID>`，Slimey 读取这些文件。
- **是否已读**：来自 Claude 桌面 App 在本地保存的会话记录，里面有你最后一次点开每个会话的时间。终端里开的会话没有这个记录，所以点一下 Slimey 就会熄灭绿灯。

## 隐私

Slimey **只连接 claude.ai**，用你自己登录的会话读取用量。没有服务器，没有统计，也不上报任何数据。其他所有数据都只存在你 Mac 上的本地文件里。

## 免责声明

Slimey 是一个非官方的粉丝项目，**与 Anthropic 没有任何关联，也未获其认可**。“Claude”是 Anthropic 的商标。

它依赖 claude.ai **未公开的**接口，以及 Claude 桌面 App 的内部文件，两者都可能随时变化，导致 Slimey 失效。用程序定时访问 claude.ai 也可能不符合 Anthropic 的条款，请阅读 [Anthropic 消费者条款](https://www.anthropic.com/legal/consumer-terms) 后自行判断。使用风险自负。

## 从源码构建

只需要 Xcode 或 Command Line Tools，不需要 Xcode 工程，也不需要包管理器：

```sh
./test.sh                 # 运行测试
./build.sh                # 构建 Slimey.app（通用版）
open Slimey.app
SLIMEY_LANG=zh open Slimey.app   # 强制使用中文（或 en）
./Slimey.app/Contents/MacOS/Slimey --demo 85   # 使用假数据，无需登录
```

`tools/make-video.sh` 会用 App 自己的绘制代码，在 `media/` 里生成演示视频和 GIF。

## 卸载

1. 右键 Slimey，取消勾选任务灯（会移除 hooks），然后点“退出”。
2. 删除 `Slimey.app` 和 `~/.slimey` 文件夹。

## 许可证

[MIT](LICENSE)

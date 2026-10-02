# Factorio × LLM 共同工厂

目标：后台留着一个**不会被重置的小工厂**。AI 从最简单的生产任务开始建设；你可以随时用正常游戏窗口连进去巡视，兴致来了就自己摆几台机器。

当前状态：**阶段 1 已通过（2026-10-03）。** 本机 Factorio `2.0.73` 服务器可保存并重新加载 `world/shared-world.zip`；Windows 客户端重连后，测试石炉仍在。尚未进入阶段 2。完整依据见 [实现调查.md](实现调查.md)。项目规则见 [AGENTS.md](AGENTS.md)。

## 现在就能确定的事

这件事能做，而且很适合你想要的玩法。但 **不能把 FLE（Factorio Learning Environment）原样接进 OpenCode 就当成品。**

FLE 提供了很有用的积木：Docker 里跑 Factorio 服务器、用 RCON 让 AI 用 Python 放机器。它首先是评测框架。默认连接会重建 AI 角色、清空玩家阵营建筑；会话结束还会再 reset 一次。这些行为会毁掉共同世界。

因此实现方式是：

1. 用 Factorio 自己的联机服务器保存世界（原生 `.zip`）。
2. 只用 FLE 的建造接口，并改掉会清场的初始化。
3. 另写一层循环，让模型持续决策、把经验写进这个文件夹。

## 本机盘点（2026-10-02）

| 项 | 状态 |
|---|---|
| 本目录 | 已建，目前只有文档 |
| Docker 客户端 / Compose | 已装（Docker 29.7.2，Compose v5.5.1） |
| Docker 引擎 | **没在跑**，连不上 `dockerDesktopLinuxEngine` |
| Factorio 客户端 | **未找到**（常见 Steam / 独立安装路径都没有） |
| conda Python | `F:\vscode\minicode` 为 3.13.12，满足 FLE 的 `>=3.10` |
| OpenCode | 1.18.18，可作交互会话；不能单靠当前聊天在回复后继续玩 |

## 开干前还缺的东西

- 买并安装 **Factorio 本体**（闭源付费；官方有 [Demo](https://www.factorio.com/download)）。不需要先买 Space Age。
- 启动 Docker Desktop。
- 第一阶段主动统一钉在 Factorio `2.0.73`，以减少变量。这不是“FLE 只能使用 2.0.73”；其他版本仍待实测。
- 确认后台调用模型走哪条通道、怎么限量。OpenCode 订阅不自动覆盖 FLE 评测脚本自己的 API 调用。

真正动手会超过半小时。我说开干之后，按 [实现调查.md](实现调查.md) 的阶段 0→1 做：**先证明世界能存、你能进去，再接 AI。**

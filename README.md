# Factorio × LLM 共同工厂

目标：后台留着一个**不会被重置的小工厂**。AI 从最简单的生产任务开始建设；你可以随时用正常游戏窗口连进去巡视，兴致来了就自己摆几台机器。

当前状态：**阶段 3C 已通过；阶段 4AB 未通过（2026-10-03）。** Mira 曾自主放置燃油采矿机和石炉，炉 31 产出 33 块 iron plate，但测试服重启后机器所有权全部丢失。正式 `world/shared-world.zip` 未修改。完整依据见 [实现调查.md](实现调查.md)。项目规则见 [AGENTS.md](AGENTS.md)。

## 当前实现

当前链路是 **OpenCode 的 Mira agent → `adapter/mira_mcp.py` 受限 MCP → `adapter/bridge_probe.py` 本机 RCON → 自建 `save-safe-bridge` mod → 测试世界**。bridge 版本为 `0.7.0`，数据 schema 为 `7`。`adapter/mira_runner.py` 是有硬时间上限的前台 runner，不是后台常驻服务。

**不使用 FLE 运行时、官方 MCP、`FactorioInstance` 或 FLE 建造接口。** FLE 只作为早期调查参考，它的默认初始化与退出 reset 会破坏共同世界。`实现调查.md` 第 1–15 节是原始方案，第 16–24 节是逐步实测；旧阶段的文件名和能力描述不能当作当前操作说明。

Mira 已能观察、步行、采矿、查询配方、制作、放置自己库存中的石炉，以及向石炉放料和取回产物。采矿是按距离、时间、资源消耗和库存变化实现的语义模拟，用户尚未看到可辨认的挖掘动画。查询会更新 bridge 诊断计数，角色定位还会维护头顶字和地图标记、揭示标记区域，不能称为完全无副作用。

目前按明确任务启动会话，完成后停止。**服务器持续模拟不等于 AI 持续决策；后台自主循环、多 agent、消息总线都未实现。** 未来角色身份应独立于模型供应商；供应商故障时角色应安全闲置，而不是静默换人格。

## 每个文件夹做什么

| 路径 | 用途 | 维护边界 |
|---|---|---|
| `.git/` | Git 的版本历史与仓库元数据 | 不手动整理内部文件；Git 不备份被忽略的游戏和存档 |
| `.opencode/` | 本项目的 OpenCode agent 定义 | `agent/mira.md` 管理 Mira 模型、28 步上限、工具权限和任务结束规则；不是聊天记录 |
| `adapter/` | 把 OpenCode 的工具请求接到测试服 | 日常代码仅保留 RCON 封装、受限 MCP 和离线自检；不放临时改世界的探针 |
| `mods/` | 自建 mod 的源码 | `save-safe-bridge/control.lua` 是游戏内逻辑，`info.json` 是 mod 元数据；这是唯一编辑真源 |
| `server/` | 正式世界的 Docker 部署 | `docker-compose.yml` 管服务；`config/` 放设置及本机凭据；`mods/` 放正式服启用列表，目前无 bridge |
| `server-test/` | AI 测试世界的独立 Docker 部署 | `config/` 与正式服独立；`mods/mod-list.json` 启用 bridge，`mods/save-safe-bridge/` 是部署副本，不在这里开发 |
| `world/` | 正式 Factorio 原生存档 | `shared-world.zip` 是正式命名存档，`_autosave*.zip` 是正式服轮换自动保存；AI 实验不得改动或清理 |
| `world-test/` | Mira 活动的测试原生存档 | `bridge-test.zip` 是测试命名存档，`_autosave*.zip` 是测试自动保存；不是可随便删的缓存 |
| `memory/` | Mira 跨会话的事实与任务状态 | 不是游戏存档；`long_term.md` 是长期事实，`current.md` 是整份重写的当前状态，`log/` 是按日期追加的冷日志，不默认注入上下文 |
| `Factorio.v2.0.73-P2P/` | 本机 Factorio 游戏客户端 | 内部有三层同名目录，是现有安装结构，不为美观重排；实际读写数据在 `%APPDATA%\Factorio` |

根目录文件：`README.md` 是入口，`AGENTS.md` 是工程安全规则，`实现调查.md` 是历史调查与验收证据，`opencode.json` 是 MCP 启动配置，`.gitignore` 区分源码与本机运行数据。

### adapter 中保留的文件

| 文件 | 做什么 | 能否直接运行 |
|---|---|---|
| `mira_mcp.py` | 只向 Mira 暴露 19 个受限工具，含固定范围的记忆操作 | 由 OpenCode 通过 `opencode.json` 拉起，不是人工交互脚本 |
| `bridge_probe.py` | 实际的 RCON 连接与 remote 调用封装，虽然名字含 probe，但仍是核心依赖 | 默认查询测试服；`--save` 会保存，`--ensure-agent` 可能创建角色，不能当离线检查 |
| `mcp_self_check.py` | 检查 MCP 握手与 19 个工具的注册 | 可离线运行，不调用游戏工具、不启动模型、不读 RCON 密码 |

MCP 默认不写调试日志。如需定位协议问题，只在临时调试时设置 `MIRA_MCP_DEBUG=1`；`adapter/mcp-debug.log` 可能包含任务文字、记忆和坐标，不提交，也不作为长期记忆。

## 连接与存档

| 项目 | 正式服 | 测试服（Mira 所在） |
|---|---|---|
| 容器 | `factorio-with-llm` | `factorio-bridge-test` |
| 游戏直连 | `127.0.0.1:34197` | `127.0.0.1:34297` |
| RCON | `127.0.0.1:27015` | `127.0.0.1:27115` |
| 挂载存档目录 | `world/` | `world-test/` |
| 启动命名存档 | `shared-world.zip` | `bridge-test.zip` |
| bridge mod | 未启用 | `save-safe-bridge 0.6.0` |

2026-10-03 整理时两台容器均在运行。正式服也会写自己的自动保存，因此“正式命名存档未修改”不表示 `world/` 整个目录静止。两个 compose 都设置 `LOAD_LATEST_SAVE=false`，不会自动选择最新 autosave；重要任务后应明确保存命名存档，不能假定重启会恢复最近的自动保存。

当前 AI character 为 `15`，人类 character 为 `1`，`game.speed=1`。Mira 的坐标与库存以 observation 为准，不把 README 当实时定位。

RCON 密码在各自的 `config/rconpw`，服务器身份在 `config/server-id.json`，均不提交、不显示。游戏和 RCON 端口都只映射 `127.0.0.1`，本轮没有公网入口。

## 修改与部署

修改 mod 时只改 `mods/save-safe-bridge/`。测试服运行副本是 `server-test/mods/save-safe-bridge/`；客户端实际使用 `%APPDATA%\Factorio\mods\save-safe-bridge_0.6.0.zip`，**不在便携游戏安装目录里**。测试服不再同时保留相同 mod 的文件夹和 zip，避免改错副本。

部署必须同步源码、测试服副本与客户端包，保持版本及文件内容一致。客户端 zip 内部必须以 `save-safe-bridge/` 为前缀，包含 `save-safe-bridge/info.json` 和 `save-safe-bridge/control.lua`，不能直接把两个文件放在 zip 根部，也不能多套一层 `modpack/`。

`info.json` 的 `description` 仍沿用初版的“只读查询”说明，不代表当前能力；实际接口以 `control.lua` 和 MCP 工具表为准。本轮不重写正在使用的 mod 包，这个元数据说明留到下次同步部署时一起更新。

更新客户端包前等 Factorio 完全退出；测试服重启会踢人，先通知并等用户确认。当前没有自动部署脚本，也不默认部署到正式服。只改 Python MCP 或 Mira 配置无需重启游戏服务器，但需要退出并重新启动相关 OpenCode 进程才能加载新版本。

`world/`、`world-test/`、客户端、凭据、日志、Python 缓存和测试服 mod 部署副本都被 Git 忽略。**Git 历史只保护已提交的源码与说明，不保护世界进度。** 备份原生存档时需单独保留 `.zip`，不要拿 AI 记忆或 FLE 快照代替。

## 本机依赖与自检

当前使用 Factorio `2.0.73 (build 84377)`、Docker `29.7.2` / Compose `v5.5.1`、OpenCode `1.18.18`。Python 为 `F:\vscode\minicode\python.exe`（3.13.12），RCON 库为 `factorio-rcon-py==1.2.1`。不需要安装 FLE 包。模型配置在 `.opencode/agent/mira.md`，provider 凭据由 OpenCode 全局配置管理，不复制到仓库。

在本目录打开 PowerShell，离线自检命令为：

```powershell
& "F:\vscode\minicode\python.exe" "adapter\mcp_self_check.py"
```

此自检只证明本地 MCP 握手和工具列表正常，不证明游戏连接、动作或模型调用成功。修改游戏逻辑后仍需另做对应测试世界验收。

## 本次整理（2026-10-03）

删除已完成阶段的一次性脚本：`attach_probe.py`、`action_probe.py`、`debug_walk.py`、`distance_probe.py`、`mine_once.py`、`prepare_chunks.py`、`resource_probe.py`、`survival_probe.py`。其中有指向正式服、免费发炉、清库存和强制扩图的历史入口，不应继续留作日常工具。已提交脚本可从 Git 历史查阅，其验收事实保留在 `实现调查.md`，不会因删除脚本而重跑实验。

修复离线自检中失效的 Stella 文件名及旧协议解析方式，更新 RCON 诊断中早于独立 AI 角色的检查条件；Mira 权限改为默认拒绝、只允许 `factorio-mira_*`，防止以后继承无关全局 MCP；补齐缓存与部署副本的忽略规则。核对源码、测试服文件夹与客户端包一致后，移除测试服重复的 mod zip 及 Python 缓存。未改游戏逻辑、客户端安装、任何存档或服务器运行状态，也没有开启下一阶段。

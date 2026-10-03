# Factorio_withLLM

这是「保留存档的小工厂 + 人机同世界」项目，不是 FLE 官方评测任务。全局交流与批准规则仍以 `C:\Users\ATRI\.config\opencode\AGENTS.md` 为准。

当前路线是自建 `save-safe-bridge` mod + 受限 MCP，不接入 FLE 运行时。阶段 3C 已完成。阶段 4AB 的有界 runner 已实现但原验收未通过。4AB-R Gate A 已修复所有权持久化；留言板和固定记忆注入尚未实现，完成前不要重跑自主验收。当前入口与目录说明以 `README.md` 为准；`实现调查.md` 的旧阶段是历史证据，不是可直接重跑的操作手册。

## 硬约束

- **共享世界禁止评测式清场。** 不要对正在给人玩的实例调用 FLE 的 `reset()`、`clear_entities`、默认 `FactorioInstance(...)` 初始化，也不要让 MCP 会话结束时的 `shutdown_session()` 跑起来。那些调用会删建筑，并毁掉所有 `character` 实体（包括人类角色）。
- **世界只认 Factorio 原生 `.zip`。** FLE 的 `GameState` / MCP `undo` / `restore` 是有损研究快照，不能当共同存档。
- **客户端、服务器、mods 必须同版本且 mod 内容一致。** 本项目镜像是 `factoriotools/factorio:2.0.73`，不能想当然拿当前 Steam 版去连。
- **不要把仓库或聊天里的 Factorio.com token 复制进本项目配置。** FLE 自带的 `server-settings.json` 含 token 字段；本地副本留空，或只用你自己的账号。
- **RCON 与游戏端口只绑本机。** 正式服使用 `34197/udp`、`27015/tcp`，测试服使用 `34297/udp`、`27115/tcp`。密码分别由 `server/config/rconpw` 与 `server-test/config/rconpw` 管理，禁止读取后输出或提交。
- **当前 AI 实验只在测试世界。** 不修改、覆盖或删除 `world/shared-world.zip`，不操作人类角色、库存或建筑。Mira 完成指定任务后停止，不自行进入下一阶段。
- **源码与部署副本分开。** mod 只在 `mods/save-safe-bridge/` 修改；测试服与客户端的副本必须同步。部署前先通知用户会不会踢人；不要在客户端运行时重写它的 zip。
- **观察不是零副作用。** 查询会更新诊断计数；角色状态查询还可能确保头顶字、揭示定位区域并维护地图标记，不把它们说成完全无写入。

## 文件放哪

| 路径 | 用途 |
|---|---|
| `README.md` | 项目入口与当前状态 |
| `实现调查.md` | 已核实的实现方式、阶段、探针 |
| `.opencode/agent/mira.md` | Mira 的模型、权限和任务停止规则 |
| `opencode.json` | 本项目受限 MCP 的启动配置 |
| `world/` | 正式原生存档与正式服自动保存，禁止在 AI 测试中改动 |
| `world-test/` | AI 唯一允许活动的测试原生存档与自动保存 |
| `memory/` | AI 的技能与事件，不是游戏存档 |
| `adapter/` | 测试服 RCON 封装、受限 MCP 与离线协议自检 |
| `mods/save-safe-bridge/` | mod 源码真源 |
| `server/`、`server-test/` | 独立部署配置、运行时凭据与 mod 副本 |
| `Factorio.v2.0.73-P2P/` | 游戏客户端，不重排或修改游戏安装文件 |

未确认的个人事实与尚未实测的连通性，写进调查文档的「待实测」，不要写成已验证能力。

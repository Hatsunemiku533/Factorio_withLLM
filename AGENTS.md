# Factorio_withLLM

这是「保留存档的小工厂 + 人机同世界」项目，不是 FLE 官方评测任务。全局交流与批准规则仍以 `C:\Users\ATRI\.config\opencode\AGENTS.md` 为准。

## 硬约束

- **共享世界禁止评测式清场。** 不要对正在给人玩的实例调用 FLE 的 `reset()`、`clear_entities`、默认 `FactorioInstance(...)` 初始化，也不要让 MCP 会话结束时的 `shutdown_session()` 跑起来。那些调用会删建筑，并毁掉所有 `character` 实体（包括人类角色）。
- **世界只认 Factorio 原生 `.zip`。** FLE 的 `GameState` / MCP `undo` / `restore` 是有损研究快照，不能当共同存档。
- **客户端、服务器、mods 必须同版本。** FLE 默认镜像是 `factoriotools/factorio:2.0.73`，不能想当然拿当前 Steam 版去连。
- **不要把仓库或聊天里的 Factorio.com token 复制进本项目配置。** FLE 自带的 `server-settings.json` 含 token 字段；本地副本留空，或只用你自己的账号。
- **RCON 只绑本机。** 默认密码见 FLE 源码，不要对公网暴露 34197/udp 或 27000/tcp。

## 文件放哪

| 路径 | 用途 |
|---|---|
| `README.md` | 项目入口与当前状态 |
| `实现调查.md` | 已核实的实现方式、阶段、探针 |
| `world/` | 原生存档（以后才有） |
| `memory/` | AI 的技能与事件，不是游戏存档 |
| `adapter/` | 以后放「连接已有世界且不清场」的代码 |

未确认的个人事实与尚未实测的连通性，写进调查文档的「待实测」，不要写成已验证能力。

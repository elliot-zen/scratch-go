---
name: scratch-go
description: 按工程手册初始化 Go + Gin 后端服务，创建 ping 接口、结构化日志、错误处理、优雅关闭、自动化测试和 Makefile，并将工程约定接入项目 AGENTS.md。用于新建 Go/Gin 项目或补齐服务骨架；已有工程优先遵守其约定。
---

# Go + Gin 工程初始化手册

按第 1、2 章创建工程，按第 3 章实现代码，按第 4 章验收。第 3、4 章也适用于后续开发；后续变更不重新执行初始化。

## 1. 初始化工程

### 1.1 确认输入与版本

先读目标目录的 `AGENTS.md`、源码和配置，保留已有文件及用户修改。已有 Module、入口或 Makefile 时合并所需能力，不重复创建。

Module 路径依次取用户指定值、仓库地址、`example.com/<规范化的项目目录名>`。使用默认路径时在交付中说明。

无已有版本约束时使用以下基线：

| 项目 | 固定版本 |
| --- | --- |
| Go | `1.27.3` |
| Gin | `v1.12.0` |
| Staticcheck | `v0.8.2` |
| govulncheck | `v1.9.0` |

使用 GNU Make 和 POSIX shell；竞态检测需要支持的平台及 C 编译器。检查 Go 是否可用，不擅自更换系统工具链。用户或已有项目指定其他版本时，核实兼容性并同步修改 Makefile、go.mod 和 README；依赖与工具必须固定具体版本，不使用 `@latest`。

### 1.2 创建文件与划分职责

| 路径 | 职责 |
| --- | --- |
| `cmd/api/main.go` | 配置读取、依赖组装、启动与关闭 |
| `cmd/api/main_test.go` | 监听与关闭行为测试 |
| `internal/httpapi/` | Gin 路由、HTTP 适配、中间件及其测试 |
| `go.mod`、`go.sum` | 单 Module 及固定依赖 |
| `Makefile` | 复制本技能同目录模板，作为工程执行入口 |
| `.agents/skills/scratch-go/` | 保存本手册及 Makefile 模板，供项目内持续引用 |
| `AGENTS.md` | 后续开发约束入口 |
| `README.md` | 环境、版本、配置、接口与 Makefile 目标说明 |
| `.gitignore` | 忽略 `/bin/`、`/.tools/`、`/coverage.out`、本地秘密文件；保留 `go.sum` |

在 `internal/httpapi` 中按实际职责拆分文件，不预建空业务层、Repository、数据库或部署配置。已有项目的路径可以保留，同时调整 Makefile 中对应的构建入口。

从全局技能初始化时，将当前 `SKILL.md` 和 `Makefile` 复制到项目的技能目录；已在目标目录时不重复复制。工程根 Makefile 是实际配置，技能内的 Makefile 只作模板，后续不自动覆盖根文件。

在根 `AGENTS.md` 中加入以下内容；已有文件只合并该约定，不重写其他指令：

```markdown
## Go 开发约定

修改 Go 代码前，阅读 `.agents/skills/scratch-go/SKILL.md` 第 3、4 章并遵守其中约定。
仅在初始化工程时执行第 1、2 章。检查命令以工程根目录 Makefile 为准。
```

README 不重复工程规范，引用本手册即可。

## 2. 建立服务与接口

### 2.1 HTTP 契约

注册 `GET /api/v1/ping`，成功返回 HTTP 200：

```json
{"message":"pong","request_id":"<请求标识>"}
```

错误响应统一为两个字段，不包含内部错误详情：

```json
{"error":"internal_error","request_id":"<请求标识>"}
```

| 场景 | HTTP 状态 | `error` |
| --- | --- | --- |
| 路由不存在 | 404 | `not_found` |
| 方法不支持 | 405 | `method_not_allowed` |
| 非预期失败或响应前 panic | 500 | `internal_error` |
| 服务端操作或依赖超时 | 503 | `service_unavailable` |

JSON 响应使用 `application/json`，允许 charset。响应头 `X-Request-ID` 与正文的 `request_id` 一致。已写响应及客户端断连按第 3.2 节处理，不强行补写错误 JSON。

请求 ID 接受 1–128 位 `[A-Za-z0-9._-]`；缺失或非法时使用 `crypto/rand.Read` 生成 16 字节、编码为 32 位十六进制。按所选 Go API 的实际语义处理，不另造随机源失败恢复机制。请求 ID 只用于关联，不用于认证或幂等判断。

正式路由只包含实际功能，不暴露故障、panic 或延时调试接口。

### 2.2 Gin 与中间件

使用 `gin.New()`，显式安装请求 ID、结果记录和 Recovery；生产使用 release 模式。禁用默认可信代理，检查 `SetTrustedProxies(nil)` 的返回错误；有反向代理要求时再配置可信网段。

中间件应保证：请求 ID 在处理前可用，Recovery 捕获处理器 panic，统一结果边界记录最终失败。不要叠加多套同责日志或 Recovery。边界应在异常退出时也能完成必要记录，保留 `http.ErrAbortHandler` 的中断语义。

### 2.3 启动与关闭

由 `http.Server` 承载 Gin，默认 `HTTP_ADDR=:8080`，支持环境覆盖。初始超时：读请求头 5 秒、读请求 15 秒、写响应 15 秒、空闲连接 60 秒；流式业务按需调整。

采用 `main → run → error`：`run` 负责运行与清理，`main` 负责最终失败日志和退出码。监听失败立即返回；不要用 `router.Run()` 代替生命周期管理。

收到 SIGINT/SIGTERM 后，使用独立、限时 10 秒的 Context 执行 Shutdown，允许在途请求完成。超时则 Close 并返回关闭失败；等待 Serve goroutine 退出。不要将已取消的信号 Context 用于 Shutdown。正常 `http.ErrServerClosed` 不记 ERROR。

## 3. 持续遵守的工程规范

### 3.1 组织、依赖与表达

按职责和内聚性组织 Package；入口在 `cmd/`，内部实现在 `internal/`。业务规则不依赖 Gin Context 或数据库驱动细节，不强制固定分层架构。

显式构造依赖，避免可变全局状态和万能 `common/utils/base` 包。默认使用具体类型；真实调用方需要隔离或替换行为时，在使用方声明最小接口。只导出实际需要的标识符。

遵循 Go 命名与格式惯例，保持函数职责清晰，不采用机械行数门槛。人工编写的源码注释使用英文，仅说明必要的公开契约、设计原因、不变量及关键限制。

### 3.2 错误传播与最终结果

常规失败返回 `error`，不使用 panic；不无理由忽略错误。需要调用方分支处理时才定义稳定错误语义，用 `errors.Is/As` 判断，不比较错误字符串。

在提供新诊断信息的边界补充操作上下文；需要保留原因时使用 `%w`。适配层转换对外语义时保留内部诊断能力。仅返回错误的函数不同时记录 ERROR，由 HTTP、任务或启动的最终处理边界记录一次。

HTTP 处理按以下规则区分结果，不能见到 `context.Canceled` 就吞错：

| 情形 | 处理与记录 |
| --- | --- |
| 客户端取消原始请求，当前错误确由该取消引起 | 停止工作，不补写成功响应；记录 `outcome=canceled`，取消本身不记 ERROR |
| 内部子操作取消，原始请求仍有效 | 返回 500 与 `internal_error`，记录一次 ERROR |
| 服务端操作期限或依赖超时 | 响应未写时返回 503 与 `service_unavailable`，记录一次 ERROR |
| 预期业务拒绝或 404/405 | 返回约定结果，不自动记 ERROR |
| 非预期失败或 panic | 记录一次 ERROR；未写响应时返回 500；已提交响应时中断尚未完成的连接或流，不追加 JSON；已发出的响应无法撤回 |

判断客户端取消时使用传输层原始请求 Context，不能拿内部派生 Context 的取消替代。客户端取消同时出现独立故障时，仍需保留该故障记录。访问日志分别记录 `status` 与 `outcome`，不能将取消或中途失败记为成功。

后续引入重试或降级时，中间失败由决策方处理；最终成功不记整体失败 ERROR，耗尽后记录最终错误及尝试次数。不为初始化演示增加重试器或 Worker。

### 3.3 日志与故障定位

使用 `slog.JSONHandler` 输出到 stdout，一条事件一行 JSON；关闭 Gin 调试输出，将 HTTP Server 内部日志接入结构化输出。

| 信息 | 要求 |
| --- | --- |
| 服务身份 | 基础 logger 附 `service`、`version`；`cmd/api` 定义构建可赋值的 `version`，开发允许 `dev`，发布使用可追溯标识 |
| 失败事件 | `time`、`level`、`msg`、稳定的 `operation`、可诊断的 `error` |
| HTTP 关联 | 显式附 `request_id`、`method`、路由模板 `route`；未匹配路由用固定值，不记录带查询参数的原始 URL |
| 依赖与分类 | 已知依赖提供 `dependency`，可可靠分类时提供 `error_kind`；任务按需附 `job_id` |
| panic 定位 | 记录安全的 panic 类型和恢复点捕获的 `stack`：包含实际处理器函数、源码文件及行号，不包含请求、参数值或局部变量 |

普通错误以操作级诊断为基线，无需全量堆栈；panic 不能只剩 `panic of type string`。`slog.*Context` 不会自动附加请求 ID，`AddSource` 也不代表原始故障位置。

禁止直接记录凭证、Authorization、Cookie、原始请求体、带秘密的 DSN 或不可信 panic 文本。外部错误按依赖提供安全诊断字段或明确过滤，既不能泄密，也不能一律抹成 `internal error`。访问日志不重复附带终结失败详情。

### 3.4 Context、并发与资源

可取消操作以 `ctx context.Context` 为首参并沿调用链传递；业务层使用标准 Context，不接收 `*gin.Context`，不跨请求保留 Gin Context。不随意替换为 Background，不将 Context 当业务参数容器或长期保存请求 Context。

释放创建的取消函数；每个 goroutine 都有所有者、退出条件和等待机制；共享状态正确同步。明确文件、响应体、连接和事务的清理责任，覆盖成功、失败与取消路径，检查有意义的 Close/Commit 错误。

## 4. 验收与交付

### 4.1 测试真实行为

测试使用实际路由构造器、中间件和错误出口，只在底层依赖或叶子处理器处注入行为。不要另写一套测试中间件，也不要用测试中自行包装错误的断言代替生产错误链验证。没有业务传播链时仅验证现有边界，待实际引入调用链后补测。

| 必测行为 | 断言 |
| --- | --- |
| ping 与请求 ID | 状态、完整 JSON 结构、Content-Type、头/体 ID；合法 ID 保留，非法或缺失 ID 替换 |
| 404/405 | 精确错误结构，不产生故障 ERROR |
| 非预期错误 | 生产边界只记一次终结 ERROR；保留注入的安全原因和关联信息，客户端不泄漏原因 |
| 取消与超时 | 分别覆盖客户端取消、请求有效但内部子操作取消、服务端超时；核对响应及日志，内部失败不得得到默认 200 |
| panic | 响应前返回 500；日志含路由和实际处理器的堆栈位置且无测试秘密；后续请求仍可处理 |
| 响应后的 panic | 在响应头已发送、正文未完成时注入 panic，通过真实本地 HTTP 连接确认中断；不追加 JSON、不误记成功，不能只用 ResponseRecorder 证明连接行为 |
| 生命周期 | 调用生产运行逻辑：监听失败返回、正常关闭无 ERROR、在途请求可完成、超时强制退出并回收资源 |

使用 `httptest` 和本地临时监听地址 `127.0.0.1:0`，测试自行启动和关闭服务，不依赖外部运行实例。通过可注入停止信号测试生命周期，使用同步条件和有界超时，不用 sleep 猜测时序。上述测试纳入普通测试集，不因缺少外部 URL 而跳过。

### 4.2 执行检查

从工程根目录运行 Makefile；命令实现只维护在 Makefile 中。

| 目标 | 用途 |
| --- | --- |
| `make fmt` | 修复格式 |
| `make tools` | 安装固定版本检查工具到项目 `.tools` |
| `make check` | 格式、Module、编译、vet、Staticcheck 和行为测试 |
| `make race` | 竞态检测，包括服务生命周期测试 |
| `make build` / `make run` | 构建 / 前台运行 |
| `make env` | 记录源码状态、工具链、平台、已安装工具及依赖信息 |
| `make vuln` / `make release-check` | 漏洞扫描 / 发布检查 |

初始化必须通过 `check`、`race`、`build` 并保存 `env` 输出。后续变更执行相关检查；修改错误、日志或并发行为时补充对应反例测试。发布执行 `release-check`，记录漏洞库及检查时间；不同日期的漏洞结果可能变化。

工具或环境缺失记为未执行，不绕过检查。交付说明生成位置、运行入口、实际结果及必要偏离；人工复核职责边界、抽象必要性和故障日志是否足以定位问题。


# PromptPolish

macOS 菜单栏 Prompt 优化工具，SwiftUI + AppKit，macOS 14+。本地构建、不自动发送消息。

## 运行

```sh
cd /Users/kker/jqh/PromptPolish
bash scripts/build-app.sh
open dist/PromptPolish.app
```

首次打开会展示设置页：

1. 在「权限与兼容性」中打开系统设置，手动允许 **PromptPolish** 的辅助功能权限。
2. 在「AI 服务」填写 API Key、Base URL、模型 ID 和 API 协议，测试连接后保存。已保存密钥留空不会清除。
3. 回到第三方应用，点击输入框，输入 Prompt；点输入框外侧的星光按钮，或按 **⌘ ⇧ E**。
4. 输入框附近立即打开原文对比浮窗，加载完成后可编辑优化结果或重新优化。点击「替换原文」或 **⌘ Return** 写回；成功后自动收起预览与设置窗口，不会发送消息。
5. 成功提示和菜单栏均可「撤销上次替换」。如果已继续编辑，撤销会暂停并展示快照，不覆盖新内容。

替换成功提示默认显示 2 秒，可在「通用 → 替换成功提示时长」调整为 0–30 秒，自动保存。设为 0 秒时完全不显示该提示，仍可从菜单栏撤销。

Key 存入 macOS 钥匙串。Base URL、模型和偏好存入 UserDefaults；Prompt 不写入配置或日志。原文和最近结果仅在内存中保留，快照从捕获起最多 30 分钟，退出即清除。新操作只保留当前预览和最近一次可撤销替换，不是历史记录工具。

## API 配置

- 支持 OpenAI 兼容的 **Chat Completions** 与 **Responses** 文本接口；需使用服务商提供的 API Key，不读取 Codex/Cursor 登录凭据。
- Base URL 例如 `https://api.example.com/v1`，不包括 `chat/completions` / `responses` 具体路径。
- 远程地址要求 HTTPS，本机 `localhost`、`127.0.0.1`、`::1` 可使用 HTTP。
- 连接测试只发送固定短文本；优化仅发送本次主动捕获的 Prompt 和优化指令。API 可能产生服务商费用。
- 请求非流式返回；可取消。拒绝重定向，不向重定向目的地转发密钥；空结果、格式错误和 HTTP 错误不会替换原文。
- 当前系统提示词全文及中文说明见 [优化规则](docs/optimization-prompt.md)。1.0.2 仅修改界面，未补充编号或其他优化规则。
- 1.0.3 可在「AI 服务 → 优化提示词」直接编辑系统提示词，保存后用于后续请求；可恢复默认，也可取消草稿。默认规则内容不变，旧配置自动迁移。

## 保护与兼容性

- 被动跟踪只读取输入框角色、位置和可写能力；点击优化或显式检测时才读取文本。
- 使用公开 Accessibility `AXValue` 读写，不模拟全选、剪贴板粘贴、回车或鼠标发送。
- 替换前校验同一应用、窗口、输入框和完整原文；写回后读回核对。部分写入或不确定状态会停止自动重试和回滚，并保留快照。
- 写入只执行一次；对仍读到原文或暂时读取失败的情况，异步短暂等待读回更新。严格匹配后才关闭浮窗并保留撤销；不会忽略空格、换行或 Unicode 差异。系统写入失败、读取失败、持续旧值及不同内容分别显示原因。
- 安全文本框、无法读取的控件拒绝优化；不支持直接写回的控件允许预览但禁用替换。内嵌附件使用下述图文模式，无法确认附件边界时仅预览。
- **Codex Desktop、Cursor 等应用的具体版本需实测。** 控件声明可写不代表已验证兼容；富文本格式和附件不保证保真，建议先用无附件的普通 Prompt 验证。原生 ⌘Z 不保证可用，应使用工具自身的撤销。
- 远程应用的输入法组合状态未必向 Accessibility 公开；请先确认中文候选文字，再触发优化。组合输入、富文本、全屏/Spaces 等属于人工验收范围。
- 快速替换默认关闭，在「通用」中显式开启。每个应用在本次会话完成一次成功的确认替换后，才允许跳过预览。原文变化或目标失效时仍转入预览，不发送消息。

重新构建前请退出正在运行的 PromptPolish，以免覆盖运行中的二进制。

## 开发与检查

不依赖第三方库；Command Line Tools 即可构建，完整 Xcode 可打开 `Package.swift` 查看源码。

```sh
swift build --product PromptPolish
swift run PromptPolishChecks
bash scripts/build-app.sh
```

本机的 CLT SDK 缺少 XCTest/Testing 运行库，因此 `PromptPolishChecks` 是可执行的行为检查程序，失败时返回非零退出码，当前 81 项检查，覆盖请求序列化/解析、配置迁移、安全替换/撤销/冲突/取消、延迟读回、原生浮窗，以及内嵌附件的 UTF-16 范围、身份/位置核对、错误选区、局部替换、标记验证和取消后续写入。原生 UI 检查需可用的 macOS 桌面会话。

`dist/PromptPolish.app` 为当前机器架构的本地 ad-hoc 签名产物，未公证或对外发布。重编译后系统可能要求重新授予辅助功能权限；发行构建应使用固定 Developer ID 签名与公证。

## 结构

- `Sources/PromptPolishCore`：API、配置、安全替换事务、浮层位置算法。
- `Sources/PromptPolish`：应用入口。
- `Sources/PromptPolishUI`：AX 适配器、SwiftUI 预览/设置、菜单栏、浮层、Carbon 全局快捷键、Keychain。
- `Tests/PromptPolishCoreTests`：无外部请求的行为检查。
- `docs/superpowers/plans`：实现计划；`docs/progress.md`：验证记录。

Apple 参考：[AXIsProcessTrusted](https://developer.apple.com/documentation/applicationservices/1460720-axisprocesstrusted)、[AXUIElementSetAttributeValue](https://developer.apple.com/documentation/applicationservices/1460434-axuielementsetattributevalue)。

## 当前验证记录

首版 1.0.0 已通过 29 项行为检查及原生设置页检查，曾获辅助功能授权并在 TextEdit 读取成功；当时未执行真实外部写回。当前 1.0.1 修正版通过 39 项检查、Release 构建、Info.plist 和 codesign 验证，本次更新需按新签名刷新系统授权。独立代码审查提出的暂停仍写回、截断响应和清空后编辑器消失问题均有复现失败后通过的回归检查。

用户随后确认 1.0.1 在 Codex 中替换成功，并通过钥匙串「始终允许」解决重复确认。当前自动化工具的安全限制禁止操作 Codex 应用自身；1.0.2 浮窗在 Codex 中的实际位置、Cursor、富文本与输入法等兼容性仍需人工验收，测试和编译通过不等于这些场景已验证。

### 1.0.1 · 2026-11-05：预览失焦误报修正

修正点击预览内「替换原文」时，源应用的焦点信息为空而被误报为输入框已变化的问题。预览位于前台时核对捕获的原控件仍有效、仍属于原窗口，继续在实际写入前比较完整原文，并核对写后读回。不会按文本或位置重新匹配其他输入框。已知换窗口、换输入框、切换到无关应用、失效/安全控件及新编辑仍会被拒绝。

39 项检查通过，包含实际 AXTextAccess 与 TextTransaction 的失焦替换/撤销回归。此证据为受控 OS 边界检查，修正版在真实 Codex 中仍需复测；若遇到确实变化的目标，新提示会分别指出应用、窗口、输入框或焦点问题。

焦点属性与窗口归属不同：[Apple 的 AXFocusedWindow 文档](https://developer.apple.com/documentation/applicationservices/kaxfocusedwindowattribute)将应用级焦点窗口属性列为推荐属性；[AXWindow 文档](https://developer.apple.com/documentation/applicationservices/kaxwindowattribute)说明了控件所属窗口的属性。本工具使用原控件的实时窗口归属与完整文本核对保护替换。

### 1.0.2 · 2026-11-05：输入框旁即时对比

默认直接打开原文对比，等待 API 时也显示原文和加载状态。预览改为 720×520 的原生浮窗，优先位于源输入框外侧，随同一输入框位置更新；空间不足时缩小并限制在源屏幕内。切换焦点保留最近一次有效位置。成功替换后收起预览及设置，撤销入口继续保留；被安全校验拦截时保持浮窗和结果。

50 项检查通过，包含原生 NSPanel 可见性、成功关闭、拦截保留、取消晚到响应及多屏位置回归。优化系统提示词和文本安全校验未改动。实际 Codex 浮窗体验尚待用户复测。

### 1.0.3 · 2026-11-05：延迟确认与自定义提示词

用户确认 Codex 中实际已完整替换，却出现未确认提示。旧逻辑写入后立即读一次，旧值、读失败及写失败又被合并为相同提示；受控延迟读回检查复现了完整写入后的误报和浮窗不关闭。现改为一次写入后异步只读核对，确认一致才关闭并保留撤销。失败时显示具体阶段和系统读写错误码，持续不一致仍保留快照，不重复写入或回滚。此修改针对已复现的确认缺陷；实际 Codex 缓存时序或不可见字符差异仍需用新版实测区分。

「AI 服务」新增自定义优化提示词编辑器、恢复默认和保存/取消；Chat Completions、Responses 及重新优化均使用保存的规则。默认规则内容未改。

原因参考：[Chromium 辅助功能架构](https://chromium.googlesource.com/chromium/src/+/main/docs/accessibility/overview.md)说明缓存可能短暂落后于渲染进程；[Apple AX 写入接口](https://developer.apple.com/documentation/applicationservices/1460434-axuielementsetattributevalue)列出了消息通信失败等返回错误。它们解释可能机制，不能代替对用户当前 Codex 版本的实测。

## 1.1.0 · 内嵌附件图文模式

在控件提供可验证的富文本附件范围及局部写回能力时：

1. 自动提取文字，在预览中以 `⟦保留附件 1⟧` 等标记显示原附件位置；AI 只收到文字和标记，不接收图片数据。
2. 保留标记的数量和顺序，编辑周围文字；标记删改时禁用替换，可重新优化或修复标记。
3. 确认替换后，从后往前只更新不包含附件的文字范围。每段写入前核对原文本、附件及实际选区；写后核对全文、附件对象身份和位置。撤销也只改文字。
4. 图文模式始终先预览。关闭预览或暂停时，取消尚未执行的文字替换；已完成的部分不自动重写或回滚，以保护新编辑。

附件范围不可读、局部写入不支持、或附件扫描被截断时，仅开放优化预览。钉钉即使未返回图片占位字符，也必须取得完整附件结构才允许写回；不会退回整段覆盖。普通文字 `image` 和换行不会被猜测为图片；原输入框之外的独立附件不参与图文替换。默认优化规则不变，仅图文请求追加保留标记的格式约束。

**实际钉钉兼容性尚未验收。** 用户要求不再由助手操作钉钉；本版仅用隔离的富文本/AX 边界测试验证逻辑。用户可在钉钉的专用测试草稿中手动点击输入区，再到「权限与兼容性」运行「检测当前输入框（不发送 API）」查看是否支持局部写回。该能力声明仍需用测试内容完成实际替换/保图/撤销验收。跨进程 Accessibility 不提供通用的原子 compare-and-replace；不承诺任意第三方控件的无损支持。

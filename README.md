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
4. 在预览中编辑优化结果、查看原文对比或重新优化。点击「替换原文」或 **⌘ Return** 写回；不会发送消息。
5. 成功提示和菜单栏均可「撤销上次替换」。如果已继续编辑，撤销会暂停并展示快照，不覆盖新内容。

Key 存入 macOS 钥匙串。Base URL、模型和偏好存入 UserDefaults；Prompt 不写入配置或日志。原文和最近结果仅在内存中保留，快照从捕获起最多 30 分钟，退出即清除。新操作只保留当前预览和最近一次可撤销替换，不是历史记录工具。

## API 配置

- 支持 OpenAI 兼容的 **Chat Completions** 与 **Responses** 文本接口；需使用服务商提供的 API Key，不读取 Codex/Cursor 登录凭据。
- Base URL 例如 `https://api.example.com/v1`，不包括 `chat/completions` / `responses` 具体路径。
- 远程地址要求 HTTPS，本机 `localhost`、`127.0.0.1`、`::1` 可使用 HTTP。
- 连接测试只发送固定短文本；优化仅发送本次主动捕获的 Prompt 和优化指令。API 可能产生服务商费用。
- 请求非流式返回；可取消。拒绝重定向，不向重定向目的地转发密钥；空结果、格式错误和 HTTP 错误不会替换原文。

## 保护与兼容性

- 被动跟踪只读取输入框角色、位置和可写能力；点击优化或显式检测时才读取文本。
- 使用公开 Accessibility `AXValue` 读写，不模拟全选、剪贴板粘贴、回车或鼠标发送。
- 替换前校验同一应用、窗口、输入框和完整原文；写回后读回核对。部分写入或不确定状态会停止自动重试和回滚，并保留快照。
- 安全文本框、无法读取的控件拒绝优化；不支持直接写回的控件允许预览但禁用替换。含嵌入对象标记的文本不替换。
- **Codex Desktop、Cursor 等应用的具体版本需实测。** 控件声明可写不代表已验证兼容；富文本格式和附件不保证保真，建议先用无附件的普通 Prompt 验证。原生 ⌘Z 不保证可用，应使用工具自身的撤销。
- 远程应用的输入法组合状态未必向 Accessibility 公开；请先确认中文候选文字，再触发优化。组合输入、富文本、全屏/Spaces 等属于人工验收范围。
- 快速替换默认关闭，在「通用」中显式开启。原文变化或目标失效时仍转入预览，不发送消息。

## 开发与检查

不依赖第三方库；Command Line Tools 即可构建，完整 Xcode 可打开 `Package.swift` 查看源码。

```sh
swift build --product PromptPolish
swift run PromptPolishChecks
bash scripts/build-app.sh
```

本机的 CLT SDK 缺少 XCTest/Testing 运行库，因此 `PromptPolishChecks` 是可执行的行为检查程序，失败时返回非零退出码，覆盖真实请求序列化/解析、配置校验、比较后写入、部分写入、撤销冲突/过期及多屏浮层位置。

`dist/PromptPolish.app` 为当前机器架构的本地 ad-hoc 签名产物，未公证或对外发布。重编译后系统可能要求重新授予辅助功能权限；发行构建应使用固定 Developer ID 签名与公证。

## 结构

- `Sources/PromptPolishCore`：API、配置、安全替换事务、浮层位置算法。
- `Sources/PromptPolish`：AX 适配器、SwiftUI 预览/设置、菜单栏、浮层、Carbon 全局快捷键、Keychain。
- `Tests/PromptPolishCoreTests`：无外部请求的行为检查。
- `docs/superpowers/plans`：实现计划；`docs/progress.md`：验证记录。

Apple 参考：[AXIsProcessTrusted](https://developer.apple.com/documentation/applicationservices/1460720-axisprocesstrusted)、[AXUIElementSetAttributeValue](https://developer.apple.com/documentation/applicationservices/1460434-axuielementsetattributevalue)。

# AuraPane

macOS 原生 Markdown 编辑器与知识库：Tree-sitter 高亮、实时预览、本地 SAG2 检索引擎，以及完全跑在本机的 AI 助手。

**这个仓库只发布编译好的 App（DMG 安装包），不含源码。**

## 下载

前往 [Releases](../../releases/latest) 下载最新的 `AuraPane-<版本>.dmg`。

## 系统要求

| 项 | 要求 |
| --- | --- |
| 系统 | macOS 26.0 或更高 |
| 芯片 | Apple Silicon（arm64） |
| 磁盘 | 约 60 MB |

## 安装

1. 打开下载好的 `AuraPane-x.y.z.dmg`；
2. 把 **AuraPane** 拖进 **Applications**（应用程序）文件夹；
3. 第一次启动：在「应用程序」里 **右键 → 打开**，弹窗里再点一次「打开」。

这一步是必需的：App 采用本地签名、**没有走 Apple 公证**（个人开发者分发）。如果系统提示「无法验证开发者」或「已损坏，无法打开」，在终端执行一次即可：

```bash
xattr -dr com.apple.quarantine /Applications/AuraPane.app
```

之后正常双击启动，系统会记住这个选择。

## 隐私

- 文档、索引、AI 推理全部在本机完成，不上传任何内容；
- 本地检索索引存在你自己的磁盘上（SQLite），随笔记库走；
- 只有在你自己配置了远程模型服务时，才会按你的配置发出请求。

## 反馈

- 使用问题、功能建议、崩溃反馈：请开 [Issue](../../issues)；
- 提 Issue 时带上「AuraPane → 关于」里的版本号，以及 macOS 版本。

## 版本历史

每个 Release 的说明里写明了该版本修了什么、改了什么，见 [Releases](../../releases) 页面。

---

<sub>源码不在本仓库公开。此处只分发构建产物，版本号与源码仓库的 tag 一一对应。</sub>

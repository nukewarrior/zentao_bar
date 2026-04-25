# ZentaoBar

一个面向 macOS 菜单栏的禅道工时小工具。

ZentaoBar 会在菜单栏显示“今天已记录的工时总数”，并在下拉面板里展示当前分配给你的任务，以及每个任务今天已投入的工时。应用支持自定义禅道地址、账号登录、后台自动刷新、任务跳转、GitHub Actions 打包，以及基于 GitHub Releases 的新版本提醒。

## 功能

- 菜单栏显示今日工时总数
- 下拉面板展示当前分配任务及今日工时
- 点击任务可直接打开对应禅道任务页
- 支持自定义禅道地址、账号和密码登录
- 登录信息保存在本地，Token 使用 Keychain 保存
- 支持后台自动刷新工时
- 支持自动检查新版本并跳转到 GitHub Release 下载页
- 设置窗口提供：
  - `账户`
  - `设置`
  - `关于`
- 设置页支持：
  - 工时后台自动刷新开关与间隔
  - 自动检查新版本开关与检查间隔
  - 立即检查新版本
  - 前往 GitHub Release 下载最新版
- Debug 构建支持文件日志输出

## 当前状态

当前仓库已经实现：

- macOS 菜单栏应用骨架
- 禅道 API 登录与取数
- 旧版 / 新版接口的部分兼容回退
- 基于 Xcode app target 的 GitHub Actions 调试构建
- 基于版本标签的 Release workflow
- GitHub 自动生成 Release Notes
- 打包时自动注入应用图标
- 新版本提醒、GitHub Release 发布和 GitHub Pages 托管

当前仓库还没有完成：

- Developer ID 签名与 notarization
- 面向普通 macOS 用户的应用内自动下载安装更新

## 本地开发

### 本地环境

- macOS
- Swift 6
- 代码组织仍保留 `Package.swift`，方便本地阅读和轻量编译

### CI 构建

正式的 `.app` 构建现在由 GitHub Actions 在 runner 上完成：

- CI 会先使用 `project.yml` 生成 `ZentaoBar.xcodeproj`
- 再通过 `xcodebuild` 构建 macOS app target
- 调试构建支持 `apple-silicon / intel / universal`
- 正式发布固定构建 `Release universal app`

本机不需要额外安装 XcodeGen；仓库默认依赖 GitHub Actions 来完成正式打包。

## 调试日志

Debug 构建会输出日志到：

```text
~/.zentao_bar/zentao_bar.log
```

Release 构建默认不写日志。

## GitHub Actions

### 1. 开发构建

工作流文件：

- [.github/workflows/build-macos-app.yml](/Users/yang/Projects/ai/zentao_bar/.github/workflows/build-macos-app.yml)

用途：

- 推送到 `main` / `master` 时自动构建
- 也支持手动触发
- 可选构建：
  - Apple Silicon
  - Intel
  - Universal
- CI 内会自动安装 `XcodeGen` 并生成 `ZentaoBar.xcodeproj`
- 之后使用 `xcodebuild` 构建 `.app`

### 2. 正式发布

工作流文件：

- [.github/workflows/release.yml](/Users/yang/Projects/ai/zentao_bar/.github/workflows/release.yml)

用途：

- 当推送 `v1.2.3` 这种标签时自动触发
- 构建 Release 版 universal app
- 自动创建或更新 GitHub Release
- 自动生成面向用户的 Release Notes
- 渲染发布说明页
- 生成并发布 `releases.json` 到 GitHub Pages
- 应用内通过版本元数据提醒用户下载新版本

Release Notes 配置文件：

- [.github/release.yml](/Users/yang/Projects/ai/zentao_bar/.github/release.yml)

### 3. GitHub Pages 与版本提醒

发布 workflow 会把以下内容发布到 GitHub Pages：

- `releases.json`
- `notes/v1.2.3.html`

默认版本元数据地址：

```text
https://nukewarrior.github.io/zentao_bar/releases.json
```

说明：

- 应用会读取 `releases.json` 判断是否有新版本
- 发现新版本后，会打开对应的 GitHub Release 页面，由用户手动下载安装
- 当前不依赖 Apple Developer 账号，暂不实现应用内自动下载安装

## 版本标签约定

正式发布使用语义化版本标签：

```text
v1.2.3
```

Release workflow 会把：

- `CFBundleShortVersionString` 设为 `1.2.3`
- `CFBundleVersion` 设为 `1.2.3`

## 项目结构

```text
Sources/ZentaoBar/
  AppState.swift                # 应用状态与刷新逻辑
  PreferencesStore.swift        # 本地偏好设置
  UpdateReminderService.swift   # 新版本提醒与发布页跳转
  Services/
    ZentaoAPIClient.swift       # 禅道 API 客户端
    AppConfigurationStore.swift # 本地配置存储
    KeychainTokenStore.swift    # Token 存储
  Views/
    MenuPanelView.swift         # 菜单栏下拉面板
    SettingsView.swift          # 设置窗口容器
    AccountSettingsView.swift   # 账户页
    GeneralSettingsView.swift   # 设置页
    AboutSettingsView.swift     # 关于页
Xcode/
  ZentaoBar-Info.plist          # Xcode app target Info.plist
  Assets.xcassets/              # App 图标资源
project.yml                     # XcodeGen 工程描述
scripts/
  render_release_notes.py       # 发布说明页渲染
  write_release_metadata.py     # 当前版本元数据写入
  upsert_release_metadata.py    # 更新 releases.json
assets/
  zentao_icon.png               # 应用图标源图
```

## License

本项目使用 [MIT License](./LICENSE)。

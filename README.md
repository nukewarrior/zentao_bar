# ZentaoBar

一个面向 macOS 菜单栏的禅道工时小工具。

ZentaoBar 会在菜单栏显示“今天已记录的工时总数”，并在下拉面板里展示当前分配给你的任务，以及每个任务今天已投入的工时。应用支持自定义禅道地址、账号登录、后台自动刷新、任务跳转和 GitHub Actions 打包。

## 功能

- 菜单栏显示今日工时总数
- 下拉面板展示当前分配任务及今日工时
- 点击任务可直接打开对应禅道任务页
- 支持自定义禅道地址、账号和密码登录
- 登录信息保存在本地，Token 使用 Keychain 保存
- 支持后台自动刷新工时
- 设置窗口提供：
  - `账户`
  - `设置`
  - `关于`
- Debug 构建支持文件日志输出

## 当前状态

当前仓库已经实现：

- macOS 菜单栏应用骨架
- 禅道 API 登录与取数
- 旧版 / 新版接口的部分兼容回退
- GitHub Actions 调试构建
- 基于版本标签的 Release workflow
- GitHub 自动生成 Release Notes
- 打包时自动注入应用图标

当前仓库还没有完成：

- 基于 Sparkle 的自动更新集成
- appcast 发布与自动更新安装链路
- Developer ID 签名与 notarization

## 本地开发

### 环境

- macOS
- Xcode / Command Line Tools
- Swift 6

### 本地构建

仓库当前仍然使用 Swift Package 的方式构建可执行文件，再通过脚本打包成 `.app`：

```bash
swift build -c debug
BIN_PATH="$(swift build -c debug --show-bin-path)"
sh scripts/package-app.sh \
  "${BIN_PATH}/ZentaoBar" \
  "ZentaoBar-debug.app" \
  "0.1.0" \
  "0.1.0" \
  "debug"
```

Release 构建同理：

```bash
swift build -c release
BIN_PATH="$(swift build -c release --show-bin-path)"
sh scripts/package-app.sh \
  "${BIN_PATH}/ZentaoBar" \
  "ZentaoBar-release.app" \
  "0.1.0" \
  "0.1.0" \
  "release"
```

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

### 2. 正式发布

工作流文件：

- [.github/workflows/release.yml](/Users/yang/Projects/ai/zentao_bar/.github/workflows/release.yml)

用途：

- 当推送 `v1.2.3` 这种标签时自动触发
- 构建 Release 版 Apple Silicon 和 Intel 包
- 合并生成 Universal 包
- 自动创建或更新 GitHub Release
- 自动生成面向用户的 Release Notes

Release Notes 配置文件：

- [.github/release.yml](/Users/yang/Projects/ai/zentao_bar/.github/release.yml)

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
scripts/
  package-app.sh                # .app 打包脚本
assets/
  zentao_icon.png               # 应用图标源图
```

## License

本项目使用 [MIT License](./LICENSE)。

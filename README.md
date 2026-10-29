# 车机热点自动（纯巨魔 / 免越狱 / 免 Mac 编译）

上车连车机蓝牙 → 自动开个人热点；下车断开 → 自动关热点。
针对 iOS 16 的两个原生死穴：

- 蓝牙类自动化不能关闭「运行前询问」→ 本 App 自己监听蓝牙，不经快捷指令自动化引擎。
- 没有「蓝牙断开」状态判断 → 自己判断连/断。
- 全程只用公开 API（`CoreBluetooth` / `AVAudioSession` + `shortcuts://`），无私有框架、无特殊 entitlement，巨魔安装即稳定。

---

## 关于「直接给你 IPA」

**IPA 二进制我无法在本机直接产出**：iOS App 必须由 Xcode + iOS SDK 编译，而这两者在 macOS 上，当前环境是 Windows。
正确解法是下面的**云端构建**——仓库已全准备好（含 git 初始化），你只需推送，GitHub 免费 macOS Runner 自动编出 IPA 并生成**永久直链**。

编译阶段**不需要苹果开发者账号**：TrollStore 安装 IPA 时用自造根证书重签，所以我们直接出「未签名 IPA」即可。

---

## 你这边要做的操作步骤（零 Mac、零命令行也可）

### 第 0 步：准备本机工具（Windows）
二选一，推荐 B（不用记命令）：
- **A. 装 Git 命令行**：到 https://git-scm.com 下载 Git for Windows，一路下一步装好，右键文件夹可用「Git Bash Here」。
- **B. 装 GitHub Desktop**：到 https://desktop.github.com 下载安装，全程图形界面。

### 第 1 步：GitHub 上建一个空仓库
1. 浏览器登录 github.com → 右上角 `+` → **New repository**。
2. 仓库名随意，例如 `CarHotspotIPA`。
3. 可见性选 **Public**（原因见下方「重要提示」；不想公开就选 Private，但安装要绕一步）。
4. **不要**勾选 "Add a README file" / "Add .gitignore" / "Choose a license"——保持完全是空的。
5. 点 **Create repository**。

### 第 2 步：把工程推上去
工程目录就是 `CarHotspot/`（已经是 git 仓库、已提交）。

**用 Git 命令行：**
```
cd <CarHotspot 目录的路径>
git remote add origin https://github.com/你的用户名/仓库名.git
git branch -M main
git push -u origin main
```
**用 GitHub Desktop：**
1. 打开 GitHub Desktop → File → Add Local Repository → 选 `CarHotspot` 目录。
2. 右上角 **Publish repository** → 确认仓库名 / 选 Public → Publish。
（若第 1 步已在网页建好空仓库，Desktop 会直接推送；若没建，Desktop 也能顺便建。）

**纯网页版（不装任何客户端，推荐）：**
1. 第 1 步建好空仓库后，在空仓库页点 **「uploading an existing file」** 链接（或把文件拖进虚线框）。
2. 打开你电脑的「文件资源管理器」→ 进入 `C:\Users\WeiZiMu\WorkBuddy\2026-10-29-18-04-17\CarHotspot` →
   把整个 **`CarHotspot` 文件夹**拖进 GitHub 网页的上传区（浏览器会连同子文件夹一起上传）。
3. 等上传完 → 写个提交说明 → 点 **Commit changes**。
4. ⚠️ 上传后务必确认 `.github/workflows/build.yml` 也在仓库里（`.github` 是隐藏文件夹，个别浏览器拖拽会漏掉它）。
   若缺失：进仓库页 **Add file → Create new file** → 文件名填 `.github/workflows/build.yml` →
   把下面「构建脚本原文」整段粘进去 → Commit。（其余文件若也漏了，同样用 Create new file 补。）
5. 提交即触发构建，后续同第 3 步。

推送成功 = 自动触发构建。

> ⚠️ **重要提示（Public vs Private）**
> 手机用「直链一键安装」时，Safari/TrollStore 没登录你的 GitHub，Private 仓库的直链会被鉴权拦下。
> - 选 **Public**：直链匿名可下载，手机最省事。
> - 选 **Private**：请走「电脑下载 → 隔空传到手机」安装（见第 4 步方案二），或给直链加 token（不推荐）。

### 第 3 步：等构建完成、拿直链
1. 仓库页点顶部 **Actions** 标签 → 看到一个 workflow 在跑（黄点）→ 约 2–3 分钟变绿 ✅。
2. 构建完会自动建一个 **Release**（在仓库页右侧 Releases / 或 Actions 任务里的 Artifact）。
3. 永久直链格式（把用户名/仓库名换掉）：
   ```
   https://github.com/你的用户名/仓库名/releases/latest/download/CarHotspot.ipa
   ```
   建议复制这条备用。

### 第 4 步：手机上安装 IPA（巨魔）
**前提**：TrollStore 已装好（你说已巨魔）。建议 TrollStore 版本 ≥ 1.3（支持 `apple-magnifier` 一键装）。
老版本先在 TrollStore 里「Check for Updates」升级。

**方案一（Public 仓库，最省事）：**
1. 手机 Safari 打开这一整行（把 `<直链>` 换成第 3 步实际地址，**整段不能有空格/换行**）：
   ```
   apple-magnifier://install?url=https://github.com/你的用户名/仓库名/releases/latest/download/CarHotspot.ipa
   ```
2. 自动唤起 TrollStore 安装 → 等进度条走完 → 桌面出现「车机热点自动」。

**方案二（Private 仓库 / 不想用 scheme）：**
1. 电脑上打开 Release 页 → 下载 `CarHotspot.ipa` 到本机。
2. 用 隔空投送 / 微信文件 / 数据线+访达 等任意方式，把 `.ipa` 传到 iPhone 的「文件」App。
3. 手机打开「文件」App → 长按 `CarHotspot.ipa` → 共享 → 选 **TrollStore** → Install。

### 第 5 步：手机里自建两条快捷指令（关键）
App 本身不会直接开关热点，它去跑你建的快捷指令（用 iOS 16 自带的「设定个人热点」动作）。
1. 打开 **快捷指令** App → 底部点「快捷指令」（不是「自动化」）→ 右上角 `+` → 新建。
2. 第一条：命名 **`车机热点开`**，加动作「设定个人热点」→ 打开。
3. 第二条：命名 **`车机热点关`**，加动作「设定个人热点」→ 关闭。
4. 两条的名字**必须和 App 里一致**（App 默认值就是这两个中文名，不用改）。

### 第 6 步：手机热点 & 车机设置
- 设置 → 个人热点 → **允许其他人加入 = 开**。
- 车机端 Wi-Fi → 开「自动连接」。

### 第 7 步：App 里绑定车机 + 开监控
1. 打开「车机热点自动」App。
2. 模式默认 **省电(BLE唤醒)**（你的车机广播 BLE，正好对上）。
3. 点 **扫描周边 BLE** → 车机通电、手机靠近时列表里出现你的车机名 → 点它绑定。
4. 绑定成功后 App 对该设备保持「待连接」，由系统在你上车/下车时唤醒 App。
5. 打开 **后台监控** 开关。
6. 先点 App 里的 **测试开 / 测试关** 按钮，确认热点能被这两条快捷指令正常开关。

### 第 8 步：实车上路测试
- 上车、车机通电（BLE 广播）→ App 检测到 → 自动跑「车机热点开」→ 热点开；车机 Wi-Fi 自动连上。
- 下车、车机断电（BLE 消失）→ App 被系统唤醒 → 跑「车机热点关」→ 热点关。

---

## 两种模式（App 内可切）

| 模式 | 适用 | 耗电 | 说明 |
|---|---|---|---|
| 省电(BLE唤醒)（默认） | 车机 BLE **可连接** | 几乎为零 | 事件驱动；需先在前台扫描绑定车机 |
| 常驻(音频保活) | 所有车机（含经典蓝牙） | 约 1%/小时 | App 后台常驻，车载充电可忽略 |

若第 7 步绑定失败、或 App 提示「该车机 BLE 不可连接」（部分车机只广播不允许连接），
后台唤醒就不可用 → 把模式切到 **常驻(音频保活)** 即可（对所有车机都稳，只是常驻耗电）。

---

## 注意事项
- 锁屏时 `openURL` 可能被系统延后到解锁后执行：上车开热点一般没问题；下车关热点可能延后到下次亮屏（系统限制）。
- App 进程被杀就失效——非越狱 App 的固有限制；要「杀掉也生效」需走 Dopamine 越狱 + 系统级 tweak。
- 省电模式依赖车机 BLE 可连接；不可连接时切常驻模式。

## 目录结构
```
CarHotspot/                  ← 直接作为 Git 仓库根目录推送
  .github/workflows/build.yml  # 免 Mac 云端编译 + 自动建 Release 直链
  project.yml                  # xcodegen 工程描述（CI 用它生成 Xcode 工程）
  Sources/
    HotspotMonitor.swift       # 核心：BLE 绑定/唤醒 + 音频保活 + shortcuts:// 触发
    CarHotspotApp.swift
    ContentView.swift
    Info.plist
    CarHotspot.entitlements
  README.md
```

---

## 附：构建脚本原文（网页版补 `.github` 文件时用）

若网页拖拽漏掉了隐藏的 `.github` 文件夹，到仓库页 **Add file → Create new file**，
文件名填 **`.github/workflows/build.yml`**，内容粘贴下面整段：

```yaml
name: Build IPA (无需 Mac)

on:
  workflow_dispatch:
  push:
    branches: [main, master]

permissions:
  contents: write

jobs:
  build:
    runs-on: macos-15
    steps:
      - name: 拉取代码
        uses: actions/checkout@v4

      - name: 安装 xcodegen
        run: brew install xcodegen

      - name: 生成 Xcode 工程
        run: xcodegen generate

      - name: 未签名编译
        run: xcodebuild build -project CarHotspot.xcodeproj -scheme CarHotspot -configuration Release -destination generic/platform=iOS -derivedDataPath build CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY= CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= ARCHS=arm64 ONLY_ACTIVE_ARCH=NO

      - name: 打包成 IPA
        run: |
          mkdir -p Payload
          cp -r build/Build/Products/Release-iphoneos/CarHotspot.app Payload/
          zip -r CarHotspot.ipa Payload

      - name: 创建 Release
        run: gh release create "ipa-build-${{ github.run_number }}" CarHotspot.ipa --repo "${{ github.repository }}" --title "CarHotspot.ipa (build ${{ github.run_number }})" --notes "云端自动构建 · 未签名 IPA · 请用 TrollStore 安装" --latest
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}

      - name: 上传构建产物
        uses: actions/upload-artifact@v4
        with:
          name: CarHotspot.ipa
          path: CarHotspot.ipa
```
```

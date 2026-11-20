<div align="center">

<img src="assets/icon.png" width="128" alt="章鱼重命名 logo"/>

# 章鱼重命名 (Octopus Rename)

**章鱼的 8 只腕足 ↔ 规则链的 8 条重命名规则**

👉 **普通用户请看 [使用说明 USAGE.md](USAGE.md)**（下载、上手教程、规则详解、常见问题）；本文档面向开发者。

</div>

基于 Free Pascal / Lazarus 的 Windows 文件批量重命名工具（GUI 版），规则链模式，参考原 AHK 版本项目重写。

安全优先设计：先预览后执行、防覆盖、两阶段重命名中途失败自动回滚、撤销日志一键恢复。

## 使用

双击 `bin\fprename_gui.exe`（构建方法见下文）：

1. **添加文件**（可多选）/ **添加文件夹** / **从剪贴板添加** / 直接**拖放**到窗口
2. 设置**范围**（文件+文件夹 / 仅文件 / 仅文件夹）
3. 在**规则链**中勾选并排列规则（↑↓ 调整顺序，自上而下依次应用）：
   - ①添加前缀 ②添加后缀 ③查找替换（支持正则） ④序号（起始/步进/位数/位置）
   - ⑤大小写（名称+扩展名） ⑥清理非法字符 ⑦删除字符 ⑧自定义名
4. 列表**实时预览**新旧文件名与状态（就绪/无变化/目标已存在/目标重名/非法字符等）
5. 点 **执行重命名**（弹确认框；两阶段重命名，中途失败自动整体回滚）
6. 改错了点 **撤销上次** 一键恢复；**打开日志** 查看历史记录

## 目录结构

```
octopus-rename/
├── build.bat        # 一键构建脚本（exe 输出到 bin\；加 release 参数打包发布 zip）
├── CHANGELOG.md     # 更新日志
├── assets/
│   ├── logo.svg     # Logo 矢量源文件
│   ├── icon.png     # 256px PNG（由 logo.svg 渲染）
│   └── icon.ico     # 多尺寸 ICO（16~256，嵌入 exe）
├── src/             # Lazarus GUI 工程源码
│   ├── fprename_gui.lpi / .lpr   # 工程文件 / 程序入口
│   ├── unit1.pas / .lfm          # 主窗体（规则链核心逻辑）
│   ├── version.inc               # 版本号唯一来源（发布时只改这里）
│   ├── appicon.rc                # 应用图标资源声明（MAINICON）
│   ├── manifest_clean.rc         # Windows 清单资源模板（版本号由构建注入）
│   └── *.res / versioninfo.rc 等 # 编译期自动生成的资源文件（不入库）
├── tools/
│   ├── package.ps1  # 发布打包脚本（build.bat release 调用）
│   └── comtest.pas  # IFileOpenDialog 多选文件夹 COM 调试小程序
├── legacy/
│   └── fprename.pas # 命令行版（已归档，用法见 legacy/README.md）
└── bin/             # 构建产物（不入库）
```

## 构建

安装 [Lazarus](https://www.lazarus-ide.org/)（含 FPC 3.2.2）到 `C:\lazarus` 后，双击 `build.bat`，成功后生成 `bin\fprename_gui.exe`。

也可以用 Lazarus IDE 打开 `src\fprename_gui.lpi` 直接构建（产物同样输出到 `bin\`，首次构建前需先跑一次 `build.bat` 生成资源文件）。

## 版本与发布

- **版本号只在 `src/version.inc` 维护**（`APP_VERSION = '1.0.1';`），`build.bat` 每次构建自动读取并同步到 exe 属性的版本信息（VERSIONINFO）、Windows 清单和窗口标题
- 发布正式版：改好 `src/version.inc` 并更新 `CHANGELOG.md` 后运行 `build.bat release`，生成 `release\OctopusRename-v1.0.1-win64.zip`（内含 `章鱼重命名.exe`）
- 更新记录见 [CHANGELOG.md](CHANGELOG.md)

## 安全机制

- **实时预览**：执行前在列表中确认每一条改名结果，状态一目了然
- **防覆盖**：目标文件名已存在时拒绝执行（大小写变更除外）
- **两阶段回滚**：重命名中途失败自动整体回滚，不会留下半成品
- **撤销日志**：每次执行生成撤销日志，**撤销上次** 一键逆序恢复

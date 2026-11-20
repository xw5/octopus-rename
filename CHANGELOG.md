# 更新日志 (Changelog)

## 未发布

### 变更
- 项目更名为 **octopus-rename**（章鱼重命名 / Octopus Rename）：一个功能一个项目，本仓库专注批量重命名
- 窗口标题、exe 属性（ProductName/FileDescription）、发布 zip（`OctopusRename-v<版本>-win64.zip`，内含 `章鱼重命名.exe`）同步更名

## 1.0.1 - 2026-11-21

### 重构
- 使用 Free Pascal / Lazarus 重写为原生 Windows GUI（规则链批量重命名功能与 AHK 版一致），单文件 exe，不再依赖 AHK 运行时；原 AHK 版代码归档至 `legacy/`

### 新增
- 版本管理：`src/version.inc` 为唯一版本来源，`build.bat` 构建时自动生成 VERSIONINFO 资源（exe 属性可见版本号）并同步 manifest 版本
- 窗口标题栏显示版本号（章鱼文件 v1.0.1）
- `build.bat release` 一键打包发布 zip（`release\OctopusFile-v1.0.1-win64.zip`，内含 `章鱼文件.exe`）

## 1.0.0 - 2026-11-20（AHK 版，已归档）

- 中英文国际化、设置页、拖放添加、应用图标

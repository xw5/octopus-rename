# fprename CLI（已归档）

命令行版文件批量重命名工具。功能已由 GUI 版（`../src`）取代，此目录仅归档源码，不再参与构建。

默认 dry-run 预览模式，加 `-x` 才真正执行重命名。每次执行会生成撤销日志，可用 `--undo` 一键恢复。

## 编译

安装 [Free Pascal Compiler](https://www.freepascal.org/download.html) 后在本目录执行：

```bash
fpc -O2 fprename.pas
```

Windows 下生成 `fprename.exe`，Linux/macOS 下生成 `fprename`。

## 功能

| 模式 | 参数 | 说明 |
|------|------|------|
| 替换文字 | `-r old=new` | 只替换主名部分，扩展名保留 |
| 添加前缀 | `-p str` | 如 `2026_` |
| 添加后缀 | `-s str` | 加在扩展名之前 |
| 序号重命名 | `-n base` | 重命名为 `base_001.ext`，支持 `-N` 起始号、`-W` 位宽 |
| 改扩展名 | `-e .jpg` | 批量修改扩展名 |
| 小写/大写 | `-l` / `-u` | 主名转小写/大写 |
| 文件过滤 | `-m *.jpg` | 通配符过滤，默认 `*.*` |

## 使用示例

```bash
# 预览：给 D:\photos 所有文件加前缀 2026_
fprename D:\photos -p "2026_"

# 真正执行：替换 IMG 为 photo
fprename D:\photos -r "IMG=photo" -x

# 只处理 jpg，重命名为 trip_001.jpg、trip_002.jpg ...
fprename D:\photos -m "*.jpg" -n trip -N 1 -W 3 -x

# jpeg 扩展名统一改为 jpg
fprename D:\photos -m "*.jpeg" -e .jpg -x

# 主名转小写
fprename D:\photos -l -x
```

## 撤销（恢复原文件名）

每次执行重命名后，会在目标目录生成 `fprename_undo_时间戳_毫秒.log`（文件名先快照后重命名，不会被二次扫描），恢复方式：

```bash
fprename --undo "D:\photos\fprename_undo_20261120_213000_123.log"
```

## 安全机制

- **默认 dry-run**：不加 `-x` 只显示 `旧名 -> 新名` 预览，不动文件
- **防覆盖**：目标文件名已存在时自动跳过（大小写变更除外）
- **撤销日志**：完整记录 old|new 映射，逆序回滚
- 自动跳过目录和本工具生成的日志文件

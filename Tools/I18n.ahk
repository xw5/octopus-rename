; ============================================================
; I18n 中英文国际化模块  (AutoHotkey v2)
; 用法：
;   I18n("中文文案")          -> 按当前语言返回文案（en 未收录时原样返回中文）
;   TF("共 {1} 项", n)     -> 先翻译再替换 {1} {2} 占位符
;   I18n_SetLang("en")     -> 切换语言并写入 config.ini 持久化（"auto" = 跟随系统）
;   I18n_CurrentLang()     -> 取当前生效语言 "zh" / "en"
;   I18n_GetSetting()      -> 取用户设置项 "auto" / "zh" / "en"
; 语言优先级：config.ini [App] Lang > 系统语言自动判断
; 注意：所有 key 一律使用中文原文；新增界面文案请同步补 I18N_EN。
; ============================================================

global I18N_LANG := "zh"
global I18N_SETTING := "auto"      ; 用户设置：auto / zh / en

I18n_IniPath() => A_ScriptDir "\config.ini"

I18n_Init() {
    global I18N_LANG, I18N_SETTING
    setting := IniRead(I18n_IniPath(), "App", "Lang", "")
    if (setting != "zh" && setting != "en" && setting != "auto")
        setting := "auto"          ; 未配置：跟随系统
    I18N_SETTING := setting
    I18N_LANG := (setting = "auto") ? I18n_SystemLang() : setting
}

I18n_CurrentLang() {
    global I18N_LANG
    return I18N_LANG
}

I18n_SetLang(lang) {
    global I18N_LANG, I18N_SETTING
    if (lang != "zh" && lang != "en" && lang != "auto")
        return
    I18N_SETTING := lang
    I18N_LANG := (lang = "auto") ? I18n_SystemLang() : lang
    IniWrite(lang, I18n_IniPath(), "App", "Lang")
}

; 用户设置的语言选项："auto" / "zh" / "en"（auto = 跟随系统）
I18n_GetSetting() {
    global I18N_SETTING
    return I18N_SETTING
}

; 按系统 UI 语言（LCID）判断 zh / en
I18n_SystemLang() {
    for lcid in ["0804", "0404", "0C04", "1404", "1004", "0481"]
        if (A_Language = lcid)
            return "zh"
    return "en"
}

; 取词：zh 原文即 key
I18n(zh) {
    global I18N_LANG
    if (I18N_LANG != "en")
        return zh
    return I18N_EN.Has(zh) ? I18N_EN[zh] : zh
}

; 取词 + 占位符替换：TF("共 {1} 项", n)
TF(zh, params*) {
    return Format(I18n(zh), params*)
}

; ---------- 英文词典 ----------
global I18N_EN := Map(
    ; 主工具箱
    "章鱼工具", "Octopus Tools",
    "选择一个工具开始", "Pick a tool to start",
    "批量重命名", "Batch Rename",
    "选择一批文件或文件夹，按规则批量重命名（支持预览与撤销）", "Select files or folders and rename them in batch by rules (with preview & undo)",
    "关闭窗口将退出程序 · 右键托盘可重新打开", "Closing the window exits the program · right-click the tray icon to reopen",
    "显示主界面", "Show Main Window",
    "退出", "Exit",
    "语言 / Language", "Language",
    "设置", "Settings",
    "确定", "OK",
    "取消", "Cancel",
    "语言", "Language",
    "跟随系统", "Follow System",
    "English", "中文",

    ; 批量重命名 · 主窗口
    "添加文件", "Add Files",
    "添加文件夹", "Add Folders",
    "从剪贴板添加", "Add from Clipboard",
    "移除选中", "Remove Selected",
    "清空", "Clear",
    "范围", "Scope",
    "文件+文件夹", "Files + Folders",
    "仅文件", "Files Only",
    "仅文件夹", "Folders Only",
    "提示：可直接拖放文件/文件夹到窗口", "Tip: drag & drop files or folders onto the window",
    "原名称", "Original Name",
    "新名称", "New Name",
    "状态", "Status",
    "完整路径", "Full Path",
    "命名规则（勾选＝启用；↑↓ 调整顺序，自上而下依次应用）", "Naming Rules (checked = enabled; use ↑↓ to reorder, applied top to bottom)",
    "刷新预览", "Refresh Preview",
    "执行重命名", "Run Rename",
    "撤销上次", "Undo Last",
    "打开日志", "Open Log",
    "重置规则", "Reset Rules",

    ; 批量重命名 · 规则行
    "添加前缀", "Add Prefix",
    "追加到名称最前面", "Prepended to the front of the name",
    "添加后缀", "Add Suffix",
    "追加到扩展名之前", "Appended before the extension",
    "查找替换", "Find & Replace",
    "正则", "Regex",
    "查找留空则不执行", 'Does nothing when "Find" is empty',
    "序号", "Sequence",
    "起始", "Start",
    "步进", "Step",
    "位数", "Digits",
    "放开头", "At the front",
    "放结尾", "At the end",
    "替换名称", "Replace name",
    "只在本次选中的项目内递增", "Increments only among the items selected this run",
    "大小写", "Letter Case",
    "大小写不变", "Keep case",
    "全部大写", "ALL UPPERCASE",
    "全部小写", "all lowercase",
    "首字母大写", "Title Case",
    "扩展名", "Extension",
    "扩展名不变", "Keep ext case",
    "扩展名小写", "Ext lowercase",
    "扩展名大写", "Ext UPPERCASE",
    "仅影响名称部分，扩展名单独设置", "Applies to the name part only; extension is set separately",
    "清理非法字符", "Clean Illegal Chars",
    "替换为", "Replace with",
    '把 \ / : * ? " < > | 替换成该字符', 'Replaces \ / : * ? " < > | with this character',
    "删除字符", "Delete Chars",
    "起始位置", "Start Pos",
    "删除长度", "Length",
    "如 起 2 / 长 3 → 去掉第 2~4 个字符；长度留空＝删到末尾", "e.g. start 2 / length 3 removes chars 2~4; empty length = to the end",
    "自定义名", "Custom Name",
    "所有项目统一以此命名（留空不生效，可配序号避免重名）", "All items are named with this value (empty = off; add Sequence to avoid duplicates)",

    ; 批量重命名 · 流程与提示
    "将所有规则恢复默认（参数清空、顺序还原）？", "Reset all rules to defaults (params cleared, order restored)?",
    "选择文件（可多选）", "Select Files (multi-select)",
    "添加文件夹：选择一个文件夹，取消则结束", "Add Folders: pick one, Cancel to stop",
    "已添加：`n{1}`n`n继续添加下一个文件夹？", "Added:`n{1}`n`nAdd another folder?",
    "剪贴板中没有路径。", "No paths found in the clipboard.",
    "提示", "Notice",

    ; 批量重命名 · 状态
    "已完成", "Done",
    "跳过(范围)", "Skipped (Scope)",
    "就绪", "Ready",
    "名称为空", "Empty name",
    "非法字符", "Illegal chars",
    "名称过长", "Name too long",
    "无变化", "No change",
    "目标已存在", "Target exists",
    "目标重名", "Duplicate target",

    ; 批量重命名 · 状态栏 / 规则链描述
    "规则链：（没有生效的规则，不会改名）", "Rule chain: (no active rules; nothing will be renamed)",
    "规则链：", "Rule chain: ",
    "共 {1} 项，可重命名 {2} 项。未勾选的规则不参与；状态不是「就绪」的项目会被跳过。", '{1} item(s) total, {2} ready to rename. Unchecked rules are ignored; items not in "Ready" status will be skipped.',
    "自定义名「{1}」", 'Custom name "{1}"',
    "前缀「{1}」", 'Prefix "{1}"',
    "后缀「{1}」", 'Suffix "{1}"',
    "替换「{1}」→「{2}」", 'Replace "{1}" → "{2}"',
    "（正则）", " (regex)",
    "序号 {1} 起 / 步 {2} / {3} 位 / {4}", "Seq start {1} / step {2} / {3} digits / {4}",
    "全大写", "ALL UPPERCASE",
    "全小写", "all lowercase",
    "，", ", ",
    "清理非法字符为「{1}」", 'Clean illegal chars to "{1}"',
    "删第 {1} 位起", "Delete from pos {1}",
    "到末尾", " to the end",
    " {1} 个字符", " for {1} char(s)",

    ; 批量重命名 · 执行 / 撤销
    "无法重命名：{1}", "Cannot rename: {1}",
    "无法写入目标：{1}", "Cannot write target: {1}",
    "批量重命名日志 · {1}", "Batch rename log · {1}",
    "没有可重命名的项目。`n`n请先添加文件，并确认规则链有生效内容、状态为「就绪」。", 'Nothing to rename.`n`nAdd files first and make sure the rule chain has active rules and "Ready" status.',
    "即将重命名 {1} 项：`n`n{2}`n确认继续？", "About to rename {1} item(s):`n`n{2}`nContinue?",
    "…… 其余 {1} 项", "... and {1} more",
    "操作已回滚，文件保持原名。", "Operation rolled back; files keep their original names.",
    "失败", "Failed",
    "完成：成功重命名 {1} 项。", "Done: renamed {1} item(s).",
    "完成：成功重命名 {1} 项。`n可用「撤销上次」恢复。", 'Done: renamed {1} item(s).`nUse "Undo Last" to restore.',
    "没有可撤销的操作。", "Nothing to undo.",
    "将撤销上次重命名的 {1} 项，恢复原文件名。确认？", "Undo the last rename of {1} item(s) and restore original names. Continue?",
    "撤销", "Undo",
    "撤销失败，请手动检查。", "Undo failed; please check manually.",
    "已撤销上次重命名，恢复 {1} 项。", "Undid the last rename; restored {1} item(s).",
    "已撤销 {1} 项。", "Undid {1} item(s)."
)

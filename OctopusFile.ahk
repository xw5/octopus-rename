#Requires AutoHotkey v2.0
#SingleInstance Force
SetWorkingDir A_ScriptDir

; 编译指令（Ahk2Exe）
;@Ahk2Exe-SetName 章鱼文件
;@Ahk2Exe-SetVersion 1.0.0
;@Ahk2Exe-SetMainIcon assets\icon.ico

; 托盘/窗口图标
if FileExist(A_ScriptDir "\assets\icon.ico")
    TraySetIcon(A_ScriptDir "\assets\icon.ico")

#Include Tools\I18n.ahk
#Include Tools\BatchRename.ahk

I18n_Init()

; 入口注册表：后续新工具只需在此追加一项 + #Include 对应模块
; name/desc 存中文原文，显示时经 I18n() 翻译
class ToolBox {
    static gui := ""
    static settingsGui := ""
    static tools := [
        {name: "批量重命名", desc: "选择一批文件或文件夹，按规则批量重命名（支持预览与撤销）", fn: (*) => BR_Open()}
    ]

    static Show() {
        if !IsObject(ToolBox.gui) {
            g := Gui("+Resize +MinSize560x380", I18n("章鱼文件"))

            g.SetFont("s10", "Microsoft YaHei UI")
            g.AddText("x24 y20 w396 h24 +0x200 c666666", I18n("选择一个工具开始"))
            ; 右上角 ⋯ 按钮：弹出菜单（设置等入口，后续新入口在 ToolBox_MoreMenu 里追加）
            g.AddButton("x516 y14 w40 h30", "⋯").OnEvent("Click", (*) => ToolBox_MoreMenu())

            y := 56
            for t in ToolBox.tools {
                btn := g.AddButton("x24 y" y " w520 h62", I18n(t.name) "`n" I18n(t.desc))
                btn.OnEvent("Click", ToolBox_MakeHandler(t))
                y += 72
            }

            g.AddText("x24 y" (y + 6) " w520 h22 +0x200 c999999", I18n("关闭窗口将退出程序 · 右键托盘可重新打开"))
            g.OnEvent("Close", (*) => ExitApp())
            g.OnEvent("Escape", (*) => ExitApp())
            ToolBox.gui := g
        }
        ToolBox.gui.Show("w580 h" (108 + ToolBox.tools.Length * 72))

        A_TrayMenu.Delete()
        A_TrayMenu.Add(I18n("显示主界面"), (*) => ToolBox.gui.Show())
        A_TrayMenu.Add()
        langMenu := Menu()
        langMenu.Add("中文", (ItemName, ItemPos, MyMenu) => ToolBox_SetLang("zh"), "Radio")
        langMenu.Add("English", (ItemName, ItemPos, MyMenu) => ToolBox_SetLang("en"), "Radio")
        langMenu.Check(I18n_CurrentLang() = "zh" ? "中文" : "English")
        A_TrayMenu.Add(I18n("语言 / Language"), langMenu)
        A_TrayMenu.Add()
        A_TrayMenu.Add(I18n("退出"), (*) => ExitApp())
    }
}

; 切换语言并重建所有界面（批量重命名窗口下次打开时按新语言重建）
ToolBox_SetLang(lang) {
    if (I18n_CurrentLang() = lang)
        return
    I18n_SetLang(lang)
    if IsObject(ToolBox.gui) {
        ToolBox.gui.Destroy()
        ToolBox.gui := ""
    }
    BR_Rebuild()
    ToolBox.Show()
}

; ⋯ 弹出菜单：显示在鼠标位置（点击按钮后即在按钮处），后续新入口在此追加
ToolBox_MoreMenu() {
    m := Menu()
    m.Add(I18n("设置"), (ItemName, ItemPos, MyMenu) => ToolBox_Settings())
    m.Show()
}

; 设置页：当前只有语言切换，后续新设置项往下排控件即可
ToolBox_Settings() {
    if IsObject(ToolBox.settingsGui) {
        ToolBox.settingsGui.Show()
        return
    }
    g := Gui("+MinSize360x180", I18n("设置"))
    g.SetFont("s10", "Microsoft YaHei UI")

    g.AddGroupBox("x16 y16 w328 h86", I18n("语言"))
    ; 下拉选项：跟随系统 / 中文 / English（后两项固定母语显示，不翻译）
    ddlLang := g.AddDDL("x34 y44 w200", [I18n("跟随系统"), "中文", "English"])
    idx := 1                                ; 默认跟随系统
    if (I18n_GetSetting() = "zh")
        idx := 2
    else if (I18n_GetSetting() = "en")
        idx := 3
    ddlLang.Value := idx

    btnOk := g.AddButton("x112 y114 w100 h30 Default", I18n("确定"))
    g.AddButton("x224 y114 w100 h30", I18n("取消")).OnEvent("Click", (*) => ToolBox_SettingsClose())
    btnOk.OnEvent("Click", (ctrl, *) => ToolBox_SettingsApply(ddlLang))
    g.OnEvent("Close", (*) => ToolBox_SettingsClose())
    g.OnEvent("Escape", (*) => ToolBox_SettingsClose())

    ToolBox.settingsGui := g
    g.Show()
}

ToolBox_SettingsClose() {
    if IsObject(ToolBox.settingsGui) {
        g := ToolBox.settingsGui
        ToolBox.settingsGui := ""      ; 先清引用，防止 Destroy 触发 Close 事件时递归
        g.Destroy()
    }
}

; 应用设置：生效语言有变化才切换并重建界面（auto = 跟随系统）
ToolBox_SettingsApply(ddlLang) {
    setting := ["auto", "zh", "en"][ddlLang.Value]
    effective := (setting = "auto") ? I18n_SystemLang() : setting
    changed := (effective != I18n_CurrentLang())
    ToolBox_SettingsClose()
    if changed
        ToolBox_SetLang(setting)
}

; 创建按钮点击回调。
; 注意：不要用闭包/Bind 直接捕获 for 循环变量（在 AHK 2.0.31 实测会失效），
; 改为通过普通函数参数捕获工具对象，实测可靠。
ToolBox_MakeHandler(tool) {
    return (ctrl, *) => tool.fn()
}

ToolBox.Show()

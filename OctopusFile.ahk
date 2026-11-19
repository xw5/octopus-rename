#Requires AutoHotkey v2.0
#SingleInstance Force
SetWorkingDir A_ScriptDir

#Include Tools\BatchRename.ahk

; 入口注册表：后续新工具只需在此追加一项 + #Include 对应模块
class ToolBox {
    static gui := ""
    static tools := [
        {name: "批量重命名", desc: "选择一批文件或文件夹，按规则批量重命名（支持预览与撤销）", fn: (*) => BR_Open()}
    ]

    static Show() {
        if !IsObject(ToolBox.gui) {
            g := Gui("+Resize +MinSize560x380", "章鱼文件工具箱")

            g.SetFont("s10", "Microsoft YaHei UI")
            g.AddText("x24 y20 w520 h24 +0x200 c666666", "选择一个工具开始")

            y := 56
            for t in ToolBox.tools {
                btn := g.AddButton("x24 y" y " w520 h62", t.name "`n" t.desc)
                btn.OnEvent("Click", ToolBox_MakeHandler(t))
                y += 72
            }

            g.AddText("x24 y" (y + 6) " w520 h22 +0x200 c999999", "关闭窗口将退出程序 · 右键托盘可重新打开")
            g.OnEvent("Close", (*) => ExitApp())
            g.OnEvent("Escape", (*) => ExitApp())
            ToolBox.gui := g
        }
        ToolBox.gui.Show("w580 h" (108 + ToolBox.tools.Length * 72))

        A_TrayMenu.Delete()
        A_TrayMenu.Add("显示主界面", (*) => ToolBox.gui.Show())
        A_TrayMenu.Add()
        A_TrayMenu.Add("退出", (*) => ExitApp())
    }
}

; 创建按钮点击回调。
; 注意：不要用闭包/Bind 直接捕获 for 循环变量（在 AHK 2.0.31 实测会失效），
; 改为通过普通函数参数捕获工具对象，实测可靠。
ToolBox_MakeHandler(tool) {
    return (ctrl, *) => tool.fn()
}

ToolBox.Show()

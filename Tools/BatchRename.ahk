; ============================================================
; 批量重命名模块  v2.2  (AutoHotkey v2)
; 支持：文件 + 文件夹、规则链（勾选 + 排序）、实时预览、冲突检测、撤销、日志
; v2 变更：规则由「一排固定字段」改为「可勾选、可上下移动的规则链」，
;          每条规则独占一行，未勾选即不参与；新增「删除字符」规则；
;          底部状态栏实时显示当前生效的规则链。
; v2.1 变更：新增「自定义名」规则——输入名称后所有项目统一以此命名，
;          可配合「序号」规则避免重名；行高 38→34 以容纳第 8 条规则。
; v2.2 变更：接入 I18n 中英文国际化——界面文案一律经 I18n()/TF() 取词，
;          key 为中文原文；状态值内部保留中文 key 做逻辑判断，仅显示时翻译。
; 修复：IsArray 不存在、AddDropDown 无效、DropDownList.Value 为文本、
;       ListView.Add 参数形式、Integer() 不存在等 v2 兼容问题
; ============================================================

global BR := {gui: 0, lv: 0, items: [], undo: [], logPath: "",
              rules: [], ruleTop: 292, rowH: 34}

; ---------- 入口 ----------
BR_Open(*) {
    global BR
    if !IsObject(BR.gui)
        BR_BuildGui()
    BR.gui.Show("w1040 h688")
}

; 切换语言时销毁窗口，下次打开按新语言重建
BR_Rebuild() {
    global BR
    if IsObject(BR.gui) {
        BR.gui.Destroy()
        BR.gui := 0
    }
}

BR_BuildGui() {
    global BR
    g := Gui("+MinSize1040x688", I18n("批量重命名"))
    g.SetFont("s10", "Microsoft YaHei UI")
    BR.gui := g                          ; 先挂上，供规则重排时 WinRedraw 使用

    ; 顶部操作栏
    g.AddButton("x16  y12 w100 h30", I18n("添加文件")).OnEvent("Click", (*) => BR_AddFiles())
    g.AddButton("x124 y12 w100 h30", I18n("添加文件夹")).OnEvent("Click", (*) => BR_AddFolders())
    g.AddButton("x232 y12 w110 h30", I18n("从剪贴板添加")).OnEvent("Click", (*) => BR_AddClipboard())
    g.AddButton("x350 y12 w90  h30", I18n("移除选中")).OnEvent("Click", (*) => BR_RemoveSelected())
    g.AddButton("x448 y12 w70  h30", I18n("清空")).OnEvent("Click", (*) => BR_Clear())
    g.AddText("x540 y18 w40 h22 +0x200", I18n("范围"))
    BR.scope := g.AddDDL("x582 y14 w110", [I18n("文件+文件夹"), I18n("仅文件"), I18n("仅文件夹")])
    g.AddText("x704 y18 w310 h22 +0x200 c909090", I18n("提示：可直接拖放文件/文件夹到窗口"))

    ; 拖放支持：从资源管理器拖多个文件/文件夹丢到窗口即可全部加入
    g.OnEvent("DropFiles", BR_OnDropFiles)

    ; 列表
    BR.lv := g.AddListView("x16 y50 w1008 h208 +Grid +ReadOnly", [I18n("原名称"), I18n("新名称"), I18n("状态"), I18n("完整路径")])
    BR.lv.ModifyCol(1, 200)
    BR.lv.ModifyCol(2, 240)
    BR.lv.ModifyCol(3, 110)
    BR.lv.ModifyCol(4, 445)

    ; 规则链
    g.AddGroupBox("x16 y266 w1008 h300", I18n("命名规则（勾选＝启用；↑↓ 调整顺序，自上而下依次应用）"))
    BR_BuildRules(g)
    BR_LayoutRules()

    ; 底部操作
    g.AddButton("x16  y574 w110 h34", I18n("刷新预览")).OnEvent("Click", (*) => BR_Refresh())
    g.AddButton("x134 y574 w130 h34", I18n("执行重命名")).OnEvent("Click", (*) => BR_Execute())
    g.AddButton("x272 y574 w110 h34", I18n("撤销上次")).OnEvent("Click", (*) => BR_Undo())
    g.AddButton("x390 y574 w110 h34", I18n("打开日志")).OnEvent("Click", (*) => BR_OpenLog())
    g.AddButton("x508 y574 w110 h34", I18n("重置规则")).OnEvent("Click", (*) => BR_ResetRules())
    BR.status := g.AddEdit("x16 y614 w1008 h62 +ReadOnly +Multi", "")

    ; 范围变化也要重算
    BR.scope.OnEvent("Change", (*) => BR_Refresh())

    g.OnEvent("Close", (*) => g.Hide())
    g.OnEvent("Escape", (*) => g.Hide())
    BR.gui := g
    BR_Refresh()
}

; ============================================================
; 规则链构建
; ============================================================
BR_BuildRules(g) {
    global BR
    BR.rules := []

    ; ① 添加前缀
    r := BR_NewRule(g, "prefix", "添加前缀", true)
    BR_Put(r, "edit", "v", 166, 360, 26, 6, "")
    BR_Put(r, "text", "", 534, 330, 22, 9, I18n("追加到名称最前面"), "909090")

    ; ② 添加后缀
    r := BR_NewRule(g, "suffix", "添加后缀", true)
    BR_Put(r, "edit", "v", 166, 360, 26, 6, "")
    BR_Put(r, "text", "", 534, 330, 22, 9, I18n("追加到扩展名之前"), "909090")

    ; ③ 查找替换
    r := BR_NewRule(g, "replace", "查找替换", true)
    BR_Put(r, "edit", "find", 166, 180, 26, 6, "")
    BR_Put(r, "text", "", 352, 20, 22, 9, "→")
    BR_Put(r, "edit", "repl", 376, 180, 26, 6, "")
    BR_Put(r, "check", "regex", 566, 76, 22, 9, I18n("正则"))
    BR_Put(r, "text", "", 650, 220, 22, 9, I18n("查找留空则不执行"), "909090")

    ; ④ 序号
    r := BR_NewRule(g, "seq", "序号", false)
    BR_Put(r, "text", "", 166, 34, 22, 9, I18n("起始"))
    BR_Put(r, "edit", "start", 202, 52, 26, 6, "1")
    BR_Put(r, "text", "", 260, 34, 22, 9, I18n("步进"))
    BR_Put(r, "edit", "step", 296, 52, 26, 6, "1")
    BR_Put(r, "text", "", 354, 34, 22, 9, I18n("位数"))
    BR_Put(r, "edit", "digits", 390, 52, 26, 6, "3")
    BR_Put(r, "ddl", "pos", 450, 120, 26, 6, [I18n("放开头"), I18n("放结尾"), I18n("替换名称")])
    BR_Put(r, "text", "", 582, 290, 22, 9, I18n("只在本次选中的项目内递增"), "909090")

    ; ⑤ 大小写（文件名 + 扩展名）
    r := BR_NewRule(g, "case", "大小写", true)
    BR_Put(r, "ddl", "nm", 166, 120, 26, 6, [I18n("大小写不变"), I18n("全部大写"), I18n("全部小写"), I18n("首字母大写")])
    BR_Put(r, "text", "", 294, 44, 22, 9, I18n("扩展名"))
    BR_Put(r, "ddl", "ext", 340, 110, 26, 6, [I18n("扩展名不变"), I18n("扩展名小写"), I18n("扩展名大写")])
    BR_Put(r, "text", "", 470, 380, 22, 9, I18n("仅影响名称部分，扩展名单独设置"), "909090")

    ; ⑥ 清理非法字符
    r := BR_NewRule(g, "clean", "清理非法字符", false)
    BR_Put(r, "text", "", 166, 44, 22, 9, I18n("替换为"))
    BR_Put(r, "edit", "ch", 214, 50, 26, 6, "_")
    BR_Put(r, "text", "", 274, 440, 22, 9, I18n('把 \ / : * ? " < > | 替换成该字符'), "909090")

    ; ⑦ 删除字符
    r := BR_NewRule(g, "trim", "删除字符", false)
    BR_Put(r, "text", "", 166, 60, 22, 9, I18n("起始位置"))
    BR_Put(r, "edit", "pos", 230, 50, 26, 6, "")
    BR_Put(r, "text", "", 290, 60, 22, 9, I18n("删除长度"))
    BR_Put(r, "edit", "len", 354, 50, 26, 6, "")
    BR_Put(r, "text", "", 414, 430, 22, 9, I18n("如 起 2 / 长 3 → 去掉第 2~4 个字符；长度留空＝删到末尾"), "909090")

    ; ⑧ 自定义名
    r := BR_NewRule(g, "custom", "自定义名", true)
    BR_Put(r, "edit", "v", 166, 360, 26, 6, "")
    BR_Put(r, "text", "", 534, 330, 22, 9, I18n("所有项目统一以此命名（留空不生效，可配序号避免重名）"), "909090")

    ; 默认下拉选中项（v2 序号从 1 开始）
    for r in BR.rules {
        if (r.key = "case") {
            r.c["nm"].Value := 1
            r.c["ext"].Value := 1
        }
        if (r.key = "seq")
            r.c["pos"].Value := 1
    }
}

; 创建一条规则行：勾选框 + 标题 + 上移/下移
; title 存中文原文 key，显示时经 I18n() 翻译（BR_LayoutRules）
BR_NewRule(g, key, title, on) {
    global BR
    r := {key: key, title: title, on: on, c: Map(), ui: [], g: g}

    cb := g.AddCheckBox("w26 h22", "")
    cb.Value := on ? 1 : 0
    cb.OnEvent("Click", (c, *) => BR_ToggleRule(r, c))
    r.c["on"] := cb
    r.ui.Push({c: cb, x: 32, w: 26, h: 22, dy: 8})

    lbl := g.AddText("w110 h22 +0x200 +0x4000", "")
    r.c["lbl"] := lbl
    r.ui.Push({c: lbl, x: 64, w: 110, h: 22, dy: 9})

    up := g.AddButton("w40 h26", "↑")
    up.OnEvent("Click", (*) => BR_MoveRule(key, -1))
    r.c["up"] := up
    r.ui.Push({c: up, x: 884, w: 40, h: 26, dy: 6})

    dn := g.AddButton("w40 h26", "↓")
    dn.OnEvent("Click", (*) => BR_MoveRule(key, +1))
    r.c["dn"] := dn
    r.ui.Push({c: dn, x: 930, w: 40, h: 26, dy: 6})

    BR.rules.Push(r)
    return r
}

; 勾选/取消勾选一条规则
BR_ToggleRule(r, c) {
    r.on := c.Value
    BR_Refresh()
}

; 往规则行里加一个控件，登记相对坐标，布局时统一 Move
BR_Put(r, kind, id, x, w, h, dy, label := "", color := "") {
    opt := "w" w " h" h
    if (color != "")
        opt .= " c" color
    switch kind {
        case "edit":  c := r.g.AddEdit(opt, label)
        case "text":  c := r.g.AddText(opt " +0x200", label)
        case "check": c := r.g.AddCheckBox(opt, label)
        case "ddl":   c := r.g.AddDDL("w" w, label)
        default:      return
    }
    if (kind = "edit" || kind = "ddl")
        c.OnEvent("Change", (*) => BR_Refresh())
    else if (kind = "check")
        c.OnEvent("Click", (*) => BR_Refresh())

    if (id != "")
        r.c[id] := c
    r.ui.Push({c: c, x: x, w: w, h: h, dy: dy})
    return c
}

; 按当前顺序重排所有规则行
BR_LayoutRules() {
    global BR
    top := BR.ruleTop
    cnt := BR.rules.Length
    for i, r in BR.rules {
        y := top + (i - 1) * BR.rowH
        for sp in r.ui
            sp.c.Move(sp.x, y + sp.dy, sp.w, sp.h)
        r.c["lbl"].Text := Chr(0x2460 + i - 1) "  " I18n(r.title)
        r.c["up"].Enabled := (i > 1)
        r.c["dn"].Enabled := (i < cnt)
    }
    ; 控件移动后旧位置不会自动擦除，强制整窗重绘，避免残影
    if IsObject(BR.gui)
        WinRedraw(BR.gui)
}

BR_MoveRule(key, dir) {
    global BR
    idx := 0
    for i, r in BR.rules {
        if (r.key = key) {
            idx := i
            break
        }
    }
    if (idx = 0)
        return
    j := idx + dir
    if (j < 1 || j > BR.rules.Length)
        return
    t := BR.rules[idx]
    BR.rules[idx] := BR.rules[j]
    BR.rules[j] := t
    BR_LayoutRules()
    BR_Refresh()
}

; 一键回到出厂状态（全部重置为默认值 + 默认勾选）
BR_ResetRules() {
    global BR
    if MsgBox(I18n("将所有规则恢复默认（参数清空、顺序还原）？"), I18n("重置规则"), "YesNo") = "No"
        return
    defOn := Map("prefix", 1, "suffix", 1, "replace", 1, "seq", 0, "case", 1, "clean", 0, "trim", 0, "custom", 1)
    defOrder := ["custom", "seq", "prefix", "suffix", "replace", "case", "clean", "trim"]
    byKey := Map()
    for r in BR.rules
        byKey[r.key] := r

    for r in BR.rules {
        r.on := defOn.Has(r.key) ? defOn[r.key] : 0
        ; 勾选框
        r.c["on"].Value := r.on
        ; 清空文本类参数
        if r.c.Has("v")
            r.c["v"].Value := ""
        if r.key = "replace" {
            r.c["find"].Value := ""
            r.c["repl"].Value := ""
        }
        if r.key = "seq" {
            r.c["start"].Value := "1"
            r.c["step"].Value := "1"
            r.c["digits"].Value := "3"
            r.c["pos"].Value := 1
        }
        if r.key = "clean"
            r.c["ch"].Value := "_"
        if r.key = "trim" {
            r.c["pos"].Value := ""
            r.c["len"].Value := ""
        }
        if r.key = "case" {
            r.c["nm"].Value := 1
            r.c["ext"].Value := 1
        }
    }
    ; 顺序还原
    BR.rules := []
    for k in defOrder
        BR.rules.Push(byKey[k])
    BR_LayoutRules()
    BR_Refresh()
}

; ---------- 工具函数 ----------
; 安全取整数：空或非数字时返回默认值（v2 没有 Integer()）
BR_Int(v, def) {
    s := Trim(v "")
    if RegExMatch(s, "^-?\d+$")
        return s + 0
    return def
}

; 统一成数组：FileSelect("M") 返回数组，DirSelect 返回字符串
BR_NormalizePicked(paths) {
    if !IsSet(paths)
        return []
    if IsObject(paths)
        return paths
    return (paths = "") ? [] : [paths]
}

; 是否参与本次重命名（未完成 + 命中范围）
BR_Eligible(item) {
    global BR
    if item.done
        return false
    scope := BR.scope.Value
    if (scope = 2 && item.isDir) || (scope = 3 && !item.isDir)
        return false
    return true
}

; ---------- 添加项目 ----------
BR_AddFiles() {
    picked := FileSelect("M", A_Desktop, I18n("选择文件（可多选）"), "所有文件 (*.*)")
    BR_AddPaths(BR_NormalizePicked(picked))
}

BR_AddFolders() {
    loop {
        f := DirSelect(A_Desktop, 0, I18n("添加文件夹：选择一个文件夹，取消则结束"))
        if f = ""
            break
        BR_AddPaths([f])
        if MsgBox(TF("已添加：`n{1}`n`n继续添加下一个文件夹？", f), I18n("添加文件夹"), "YesNo") = "No"
            break
    }
}

; 拖放处理：一次可拖入多个文件/文件夹（拖放不走 COM 弹窗，稳定可靠）
BR_OnDropFiles(g, ctrl, files, x, y) {
    BR_AddPaths(files)
}

BR_AddClipboard() {
    txt := Trim(A_Clipboard)
    if txt = "" {
        MsgBox(I18n("剪贴板中没有路径。"), I18n("提示"), "Iconi")
        return
    }
    paths := []
    loop Parse, txt, "`n", "`r" {
        line := Trim(A_LoopField)
        if line != ""
            paths.Push(line)
    }
    BR_AddPaths(paths)
}

BR_AddPaths(paths) {
    global BR
    added := 0
    for p in paths {
        if !FileExist(p)
            continue
        dup := false
        for it in BR.items {
            if StrLower(it.path) = StrLower(p) {
                dup := true
                break
            }
        }
        if dup
            continue
        SplitPath(p, &name, &dir, &ext, &nameNoExt)
        if (ext != "")                       ; SplitPath 返回的扩展名不带点
            ext := "." ext
        BR.items.Push({path: p, dir: dir, name: name, stem: nameNoExt, ext: ext,
                       isDir: InStr(FileExist(p), "D") > 0, done: false})
        added++
    }
    if added > 0
        BR_Refresh()
}

BR_RemoveSelected() {
    global BR
    rows := []
    r := 0
    loop {
        r := BR.lv.GetNext(r)
        if !r
            break
        rows.Push(r)
    }
    if rows.Length = 0
        return
    loop rows.Length {
        i := rows.Length - A_Index + 1
        BR.items.RemoveAt(rows[i])
    }
    BR_Refresh()
}

BR_Clear() {
    global BR
    BR.items := []
    BR_Refresh()
}

; ---------- 名称计算（按规则链顺序） ----------
; 状态为中文原文 key，逻辑判断用 key，显示时经 I18n() 翻译
BR_Compute(item, seqNo) {
    global BR
    if item.done
        return {name: item.name, path: item.path, status: "已完成", enabled: false}
    if !BR_Eligible(item)
        return {name: item.name, path: item.path, status: "跳过(范围)", enabled: false}

    s := item.stem
    e := item.ext

    for r in BR.rules {
        if !r.on
            continue
        switch r.key {
            case "custom":
                cv := r.c["v"].Value
                if (cv != "")
                    s := cv

            case "prefix":
                s := r.c["v"].Value s

            case "suffix":
                s := s r.c["v"].Value

            case "replace":
                f := r.c["find"].Value
                if (f != "") {
                    v := r.c["repl"].Value
                    s := r.c["regex"].Value ? RegExReplace(s, f, v) : StrReplace(s, f, v)
                }

            case "seq":
                if (seqNo > 0) {
                    st := BR_Int(r.c["start"].Value, 1)
                    sp := BR_Int(r.c["step"].Value, 1)
                    if (sp = 0)
                        sp := 1
                    dg := BR_Int(r.c["digits"].Value, 3)
                    if (dg < 1 || dg > 10)
                        dg := 3
                    num := Format("{:0" dg "d}", st + (seqNo - 1) * sp)
                    switch r.c["pos"].Value {
                        case 1: s := num s
                        case 2: s := s num
                        case 3: s := num
                    }
                }

            case "case":
                switch r.c["nm"].Value {
                    case 2: s := StrUpper(s)
                    case 3: s := StrLower(s)
                    case 4: s := StrTitle(s)
                }
                switch r.c["ext"].Value {
                    case 2: e := StrLower(e)
                    case 3: e := StrUpper(e)
                }

            case "clean":
                ch := SubStr(Trim(r.c["ch"].Value ""), 1, 1)
                if (ch = "")
                    ch := "_"
                s := RegExReplace(s, "[\\/:*?`"<>|]", ch)

            case "trim":
                pv := Trim(r.c["pos"].Value "")
                if (pv != "" && RegExMatch(pv, "^\d+$")) {
                    p := pv + 0
                    if (p < 1)
                        p := 1
                    lv := Trim(r.c["len"].Value "")
                    if (lv = "" || !RegExMatch(lv, "^\d+$"))
                        s := SubStr(s, 1, p - 1)
                    else
                        s := SubStr(s, 1, p - 1) SubStr(s, p + (lv + 0))
                }
        }
    }

    newName := s e
    newPath := item.dir "\" newName
    status := "就绪"

    if newName = ""
        status := "名称为空"
    else if RegExMatch(newName, "[\\/:*?`"<>|]")
        status := "非法字符"
    else if StrLen(newName) > 255
        status := "名称过长"
    else if StrLower(newPath) = StrLower(item.path)
        status := "无变化"
    else if FileExist(newPath)
        status := "目标已存在"

    return {name: newName, path: newPath, status: status, enabled: status = "就绪"}
}

BR_Refresh() {
    global BR
    if !IsObject(BR.lv)
        return
    BR.lv.Opt("-Redraw")
    BR.lv.Delete()
    seen := Map()
    seqNo := 0

    for i, item in BR.items {
        if BR_Eligible(item)
            seqNo++                          ; 序号只统计真正参与重命名的项目
        r := BR_Compute(item, seqNo)
        item.newName := r.name
        item.newPath := r.path
        item.status  := r.status
        item.enabled := r.enabled
        if r.enabled {
            key := StrLower(r.path)
            if seen.Has(key) {
                item.status  := "目标重名"
                item.enabled := false
            } else
                seen[key] := i
        }
        BR.lv.Add("", item.name, item.newName, I18n(item.status), item.path)
    }
    BR.lv.Opt("+Redraw")

    ready := 0
    for item in BR.items
        if item.enabled
            ready++

    BR.status.Value := BR_ChainDesc() "`n"
                     . TF("共 {1} 项，可重命名 {2} 项。未勾选的规则不参与；状态不是「就绪」的项目会被跳过。", BR.items.Length, ready)
}

; 生成当前生效规则链的文字说明
BR_ChainDesc() {
    global BR
    parts := []
    n := 0
    for r in BR.rules {
        if !r.on
            continue
        d := BR_RuleDesc(r)
        if (d = "")
            continue
        n++
        parts.Push(Chr(0x2460 + n - 1) " " d)
    }
    if (parts.Length = 0)
        return I18n("规则链：（没有生效的规则，不会改名）")
    out := I18n("规则链：")
    for i, p in parts
        out .= (i = 1 ? "" : "  →  ") p
    return out
}

; 单条规则的一句话描述；无实质参数时返回空串，避免噪声
BR_RuleDesc(r) {
    switch r.key {
        case "custom":
            v := r.c["v"].Value
            return (v = "") ? "" : TF("自定义名「{1}」", v)

        case "prefix":
            v := r.c["v"].Value
            return (v = "") ? "" : TF("前缀「{1}」", v)

        case "suffix":
            v := r.c["v"].Value
            return (v = "") ? "" : TF("后缀「{1}」", v)

        case "replace":
            f := r.c["find"].Value
            if (f = "")
                return ""
            return TF("替换「{1}」→「{2}」", f, r.c["repl"].Value) (r.c["regex"].Value ? I18n("（正则）") : "")

        case "seq":
            posTxt := [I18n("放开头"), I18n("放结尾"), I18n("替换名称")]
            p := r.c["pos"].Value
            if (p < 1 || p > 3)
                p := 1
            return TF("序号 {1} 起 / 步 {2} / {3} 位 / {4}", r.c["start"].Value, r.c["step"].Value, r.c["digits"].Value, posTxt[p])

        case "case":
            d := ""
            switch r.c["nm"].Value {
                case 2: d := I18n("全大写")
                case 3: d := I18n("全小写")
                case 4: d := I18n("首字母大写")
            }
            switch r.c["ext"].Value {
                case 2: d .= (d = "" ? "" : I18n("，")) I18n("扩展名小写")
                case 3: d .= (d = "" ? "" : I18n("，")) I18n("扩展名大写")
            }
            return d

        case "clean":
            return TF("清理非法字符为「{1}」", SubStr(Trim(r.c["ch"].Value ""), 1, 1))

        case "trim":
            pv := Trim(r.c["pos"].Value "")
            if (pv = "")
                return ""
            lv := Trim(r.c["len"].Value "")
            return TF("删第 {1} 位起", pv) (lv = "" ? I18n("到末尾") : TF(" {1} 个字符", lv))
    }
    return ""
}

; ---------- 重命名执行 ----------
BR_DoMove(from, to, isDir) {
    try {
        if isDir
            DirMove(from, to, 0)
        else
            FileMove(from, to, 0)
        return true
    } catch
        return false
}

; 两阶段重命名：先全部改临时名，再改目标名，避免互换/大小写冲突
BR_RenameBatch(pairs) {
    temps := []
    for i, p in pairs {
        SplitPath(p.from, , &d, &e)
        tmp := d "\.__br_tmp_" A_TickCount "_" i (p.isDir ? "" : e)
        if FileExist(tmp)
            tmp := d "\.__br_tmp_" A_TickCount "_" i "_" Random(1000, 9999) (p.isDir ? "" : e)
        if !BR_DoMove(p.from, tmp, p.isDir) {
            for j, t in temps
                BR_DoMove(t.from, t.old, t.isDir)
            return {ok: false, msg: TF("无法重命名：{1}", p.from)}
        }
        temps.Push({old: p.from, from: tmp, to: p.to, isDir: p.isDir})
    }
    done := []
    for i, t in temps {
        if !BR_DoMove(t.from, t.to, t.isDir) {
            ; 已完成的目标先退回临时名，再把全部临时名还原为原名
            for j, x in done
                BR_DoMove(x.to, x.from, x.isDir)
            for j, u in temps
                if FileExist(u.from)
                    BR_DoMove(u.from, u.old, u.isDir)
            return {ok: false, msg: TF("无法写入目标：{1}", t.to)}
        }
        done.Push(t)
    }
    return {ok: true}
}

BR_Log(lines) {
    global BR
    dir := A_ScriptDir "\logs"
    DirCreate(dir)
    if BR.logPath = "" {
        BR.logPath := dir "\rename_" FormatTime(A_Now, "yyyyMMdd_HHmmss") ".log"
        FileAppend(TF("批量重命名日志 · {1}", FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")) "`n", BR.logPath, "UTF-8")
    }
    for line in lines
        FileAppend(line "`n", BR.logPath, "UTF-8")
}

BR_Execute() {
    global BR
    BR_Refresh()
    pairs := []
    for item in BR.items
        if item.enabled
            pairs.Push({from: item.path, to: item.newPath, isDir: item.isDir})

    if pairs.Length = 0 {
        MsgBox(I18n("没有可重命名的项目。`n`n请先添加文件，并确认规则链有生效内容、状态为「就绪」。"), I18n("批量重命名"), "Iconi")
        return
    }

    preview := ""
    for i, p in pairs {
        if i > 8
            break
        preview .= BR_ShortName(p.from) "  →  " BR_ShortName(p.to) "`n"
    }
    if pairs.Length > 8
        preview .= TF("…… 其余 {1} 项", pairs.Length - 8) "`n"

    if MsgBox(TF("即将重命名 {1} 项：`n`n{2}`n确认继续？", pairs.Length, preview), I18n("批量重命名"), "YesNo") = "No"
        return

    res := BR_RenameBatch(pairs)
    if !res.ok {
        MsgBox res.msg "`n`n" I18n("操作已回滚，文件保持原名。"), I18n("失败"), "Iconx"
        return
    }

    BR.undo.Push(pairs)
    logs := []
    for p in pairs {
        logs.Push("OK  " p.from "  ->  " p.to)
        for item in BR.items {
            if StrLower(item.path) = StrLower(p.from) {
                item.path := p.to
                item.dir  := RegExReplace(p.to, "\\[^\\]*$")
                SplitPath(p.to, &n, , &e, &ne)
                item.name := n
                item.stem := ne
                item.ext  := (e = "" ? "" : "." e)
                item.done := true
                break
            }
        }
    }
    BR_Log(logs)
    BR_Refresh()
    BR.status.Value := TF("完成：成功重命名 {1} 项。`n可用「撤销上次」恢复。", pairs.Length)
    MsgBox(TF("完成：成功重命名 {1} 项。", pairs.Length), I18n("批量重命名"), "Iconi")
}

BR_ShortName(path) {
    SplitPath(path, &name)
    return name
}

BR_Undo() {
    global BR
    if BR.undo.Length = 0 {
        MsgBox(I18n("没有可撤销的操作。"), I18n("提示"), "Iconi")
        return
    }
    batch := BR.undo[BR.undo.Length]
    pairs := []
    loop batch.Length {
        i := batch.Length - A_Index + 1
        pairs.Push({from: batch[i].to, to: batch[i].from, isDir: batch[i].isDir})
    }

    if MsgBox(TF("将撤销上次重命名的 {1} 项，恢复原文件名。确认？", pairs.Length), I18n("撤销"), "YesNo") = "No"
        return

    res := BR_RenameBatch(pairs)
    if !res.ok {
        MsgBox res.msg "`n`n" I18n("撤销失败，请手动检查。"), I18n("失败"), "Iconx"
        return
    }

    BR.undo.RemoveAt(BR.undo.Length)
    BR.items := []
    for i, p in batch {
        SplitPath(p.from, &name, &dir, &ext, &nameNoExt)
        if (ext != "")
            ext := "." ext
        BR.items.Push({path: p.from, dir: dir, name: name, stem: nameNoExt, ext: ext,
                       isDir: p.isDir, done: false})
    }
    logs := []
    for p in pairs
        logs.Push("UNDO  " p.from "  ->  " p.to)
    BR_Log(logs)
    BR_Refresh()
    BR.status.Value := TF("已撤销上次重命名，恢复 {1} 项。", pairs.Length)
    MsgBox(TF("已撤销 {1} 项。", pairs.Length), I18n("撤销"), "Iconi")
}

BR_OpenLog() {
    dir := A_ScriptDir "\logs"
    DirCreate(dir)
    Run('explorer.exe "' dir '"')
}

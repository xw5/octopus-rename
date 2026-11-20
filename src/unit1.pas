unit Unit1;

{ 批量重命名（参考 octopus-file AHK 项目重写为 Free Pascal/Lazarus 版）
  支持：文件 + 文件夹、规则链（勾选 + 上下排序）、实时预览、冲突检测、
        两阶段重命名（中途失败自动回滚）、撤销栈、日志
  规则：①自定义名 ②前缀 ③后缀 ④查找替换(含正则) ⑤序号 ⑥大小写 ⑦清理非法字符 ⑧删除字符 }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, StrUtils, Math, FileCtrl, Forms, Controls, Dialogs,
  Graphics, StdCtrls, ExtCtrls, ComCtrls, Clipbrd, LCLType, LCLIntf, RegExpr,
  Windows, ActiveX, ShlObj;

type
  TItemRec = record
    Path, Dir, Name, Stem, Ext: string;
    IsDir: Boolean;
    Done: Boolean;
    NewName, NewPath, Status: string;
    Enabled: Boolean;
  end;

  TParamKind = (pkEdit, pkLabel, pkCheck, pkCombo);

  TParamCtl = record
    Kind: TParamKind;
    ID: string;
    X, W, H, DY: Integer;
    Ed: TEdit;
    Lb: TLabel;
    Ck: TCheckBox;
    Cmb: TComboBox;
  end;

  TRule = record
    Key: string;
    Title: string;
    IsOn: Boolean;
    DefaultOn: Boolean;
    OriginalIdx: Integer;
    CB: TCheckBox;
    Lbl: TLabel;
    UpBtn: TButton;
    DnBtn: TButton;
    Params: array of TParamCtl;
  end;

  TPairRec = record
    FromPath, ToPath: string;
    IsDir: Boolean;
  end;

  { TForm1 }

  TForm1 = class(TForm)
    procedure FormCreate(Sender: TObject);
  private
    Lv: TListView;
    Scope: TComboBox;
    StatusMemo: TMemo;
    Rules: array of TRule;
    RuleTop: Integer;
    RowH: Integer;
    FItems: array of TItemRec;
    UndoStack: array of array of TPairRec;
    procedure BuildTopBar;
    procedure BuildList;
    procedure BuildRules;
    procedure LayoutRules;
    function NewRule(const Key, Title: string; OnDefault: Boolean): Integer;
    procedure PutParam(RuleIdx: Integer; Kind: TParamKind; const ID: string;
      X, W, H, DY: Integer; const ACaption: string; Gray: Boolean);
    function GetEdit(const Key, ID: string): TEdit;
    function GetCheck(const Key, ID: string): TCheckBox;
    function GetCombo(const Key, ID: string): TComboBox;
    procedure MoveUpClick(Sender: TObject);
    procedure MoveDownClick(Sender: TObject);
    procedure ResetRules(Sender: TObject);
    procedure RefreshAll(Sender: TObject);
    procedure AddFiles(Sender: TObject);
    procedure AddFolders(Sender: TObject);
    procedure AddClipboard(Sender: TObject);
    procedure RemoveSelected(Sender: TObject);
    procedure ClearItems(Sender: TObject);
    procedure DoDropFiles(Sender: TObject; const FileNames: array of string);
    procedure DoExecute(Sender: TObject);
    procedure DoUndo(Sender: TObject);
    procedure DoOpenLog(Sender: TObject);
    procedure AddOnePath(const P: string);
    function Eligible(const It: TItemRec): Boolean;
    function ComputeItem(var It: TItemRec; SeqNo: Integer): Boolean;
    function ContainsAnyIllegal(const AName: string): Boolean;
    function FirstLetterUpper(const S: string): string;
    function ChainDesc: string;
    function RuleDesc(const R: TRule): string;
    function RenameBatch(var Pairs: array of TPairRec): string;
    function AppendLog(Lines: TStrings): string;
    procedure SetStatusText(const Msg: string);
    function IntVal(const S: string; Def: Integer): Integer;
    function MakeBtn(const ACaption: string; X, Y, W: Integer;
      Handler: TNotifyEvent): TButton;
  end;

var
  Form1: TForm1;

implementation

{$R *.lfm}

// ---------- Windows 现代文件夹多选对话框（IFileOpenDialog） ----------
// 使用 FPC 官方 ShlObj 单元的 COM 声明（接口 vtable 必须与 Windows 完全一致，
// 手写声明曾因 GetFileName/SetTitle 顺序颠倒导致 Access violation）。
// 支持一次选中多个文件夹（FOS_PICKFOLDERS + FOS_ALLOWMULTISELECT）。

const
  IID_IFileOpenDialog: TGUID = '{D57C7288-D4AD-4768-BE02-9D969532D960}';
  IID_IShellItem: TGUID = '{43826D1E-E718-42EE-BC55-A1E261C37BFE}';
  SIGDN_PARSE_ABS: DWORD = DWORD($80028000); // SIGDN_DESKTOPABSOLUTEPARSING

function SHCreateItemFromParsingName(pszPath: PWideChar; pbc: Pointer;
  const riid: TGUID; out ppv): HResult;
  stdcall; external 'shell32.dll' name 'SHCreateItemFromParsingName';

const
  HINT_COLOR = TColor($909090);
  CIRCLED: array[0..7] of string = ('①', '②', '③', '④', '⑤', '⑥', '⑦', '⑧');
  // 出厂规则顺序（重置时还原）
  DEFAULT_ORDER: array[0..7] of string =
    ('custom', 'prefix', 'suffix', 'replace', 'seq', 'case', 'clean', 'trim');

{ TForm1 }

procedure TForm1.FormCreate(Sender: TObject);
begin
  Randomize;
  Font.Name := 'Microsoft YaHei UI';
  Font.Size := 10;
  ClientWidth := 1040;
  ClientHeight := 688;
  BorderStyle := bsSingle;
  Position := poScreenCenter;
  AllowDropFiles := True;
  OnDropFiles := @DoDropFiles;

  RuleTop := 292;
  RowH := 34;

  BuildTopBar;
  BuildList;
  BuildRules;

  MakeBtn('刷新预览', 16, 574, 110, @RefreshAll);
  MakeBtn('执行重命名', 134, 574, 130, @DoExecute);
  MakeBtn('撤销上次', 272, 574, 110, @DoUndo);
  MakeBtn('打开日志', 390, 574, 110, @DoOpenLog);
  MakeBtn('重置规则', 508, 574, 110, @ResetRules);

  StatusMemo := TMemo.Create(Self);
  StatusMemo.Parent := Self;
  StatusMemo.SetBounds(16, 614, 1008, 62);
  StatusMemo.ReadOnly := True;
  StatusMemo.Color := clBtnFace;
  StatusMemo.BorderStyle := bsNone;

  LayoutRules;
  RefreshAll(nil);
end;

function TForm1.MakeBtn(const ACaption: string; X, Y, W: Integer;
  Handler: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := Self;
  Result.SetBounds(X, Y, W, 34);
  Result.Caption := ACaption;
  Result.OnClick := Handler;
end;

procedure TForm1.BuildTopBar;
var
  B: TButton;
  Lb: TLabel;
begin
  B := TButton.Create(Self);
  B.Parent := Self; B.SetBounds(16, 12, 100, 30); B.Caption := '添加文件';
  B.OnClick := @AddFiles;

  B := TButton.Create(Self);
  B.Parent := Self; B.SetBounds(124, 12, 100, 30); B.Caption := '添加文件夹';
  B.OnClick := @AddFolders;

  B := TButton.Create(Self);
  B.Parent := Self; B.SetBounds(232, 12, 110, 30); B.Caption := '从剪贴板添加';
  B.OnClick := @AddClipboard;

  B := TButton.Create(Self);
  B.Parent := Self; B.SetBounds(350, 12, 90, 30); B.Caption := '移除选中';
  B.OnClick := @RemoveSelected;

  B := TButton.Create(Self);
  B.Parent := Self; B.SetBounds(448, 12, 70, 30); B.Caption := '清空';
  B.OnClick := @ClearItems;

  Lb := TLabel.Create(Self);
  Lb.Parent := Self;
  Lb.SetBounds(540, 18, 40, 22);
  Lb.Caption := '范围';

  Scope := TComboBox.Create(Self);
  Scope.Parent := Self;
  Scope.Style := csDropDownList;
  Scope.SetBounds(582, 14, 110, 28);
  Scope.Items.Add('文件+文件夹');
  Scope.Items.Add('仅文件');
  Scope.Items.Add('仅文件夹');
  Scope.ItemIndex := 0;
  Scope.OnChange := @RefreshAll;

  Lb := TLabel.Create(Self);
  Lb.Parent := Self;
  Lb.SetBounds(704, 18, 310, 22);
  Lb.Caption := '提示：可直接拖放文件/文件夹到窗口';
  Lb.Font.Color := HINT_COLOR;
end;

procedure TForm1.BuildList;
var
  Col: TListColumn;
begin
  Lv := TListView.Create(Self);
  Lv.Parent := Self;
  Lv.SetBounds(16, 50, 1008, 208);
  Lv.ViewStyle := vsReport;
  Lv.GridLines := True;
  Lv.RowSelect := True;
  Lv.ReadOnly := True;

  Col := Lv.Columns.Add; Col.Caption := '原名称'; Col.Width := 200;
  Col := Lv.Columns.Add; Col.Caption := '新名称'; Col.Width := 240;
  Col := Lv.Columns.Add; Col.Caption := '状态';   Col.Width := 110;
  Col := Lv.Columns.Add; Col.Caption := '完整路径'; Col.Width := 445;
end;

// ---------- 规则链 ----------

procedure TForm1.BuildRules;
begin
  // ① 自定义名
  NewRule('custom', '自定义名', True);
  PutParam(0, pkEdit, 'v', 166, 360, 26, 6, '', False);
  PutParam(0, pkLabel, '', 534, 330, 22, 9,
    '所有项目统一以此命名（留空不生效，可配序号避免重名）', True);

  // ② 添加前缀
  NewRule('prefix', '添加前缀', True);
  PutParam(1, pkEdit, 'v', 166, 360, 26, 6, '', False);
  PutParam(1, pkLabel, '', 534, 330, 22, 9, '追加到名称最前面', True);

  // ③ 添加后缀
  NewRule('suffix', '添加后缀', True);
  PutParam(2, pkEdit, 'v', 166, 360, 26, 6, '', False);
  PutParam(2, pkLabel, '', 534, 330, 22, 9, '追加到扩展名之前', True);

  // ④ 查找替换
  NewRule('replace', '查找替换', True);
  PutParam(3, pkEdit, 'find', 166, 180, 26, 6, '', False);
  PutParam(3, pkLabel, '', 352, 20, 22, 9, '→', False);
  PutParam(3, pkEdit, 'repl', 376, 180, 26, 6, '', False);
  PutParam(3, pkCheck, 'regex', 566, 76, 22, 9, '正则', False);
  PutParam(3, pkLabel, '', 650, 220, 22, 9, '查找留空则不执行', True);

  // ⑤ 序号
  NewRule('seq', '序号', False);
  PutParam(4, pkLabel, '', 166, 34, 22, 9, '起始', False);
  PutParam(4, pkEdit, 'start', 202, 52, 26, 6, '1', False);
  PutParam(4, pkLabel, '', 260, 34, 22, 9, '步进', False);
  PutParam(4, pkEdit, 'step', 296, 52, 26, 6, '1', False);
  PutParam(4, pkLabel, '', 354, 34, 22, 9, '位数', False);
  PutParam(4, pkEdit, 'digits', 390, 52, 26, 6, '3', False);
  PutParam(4, pkCombo, 'pos', 450, 120, 26, 6, '', False);
  GetCombo('seq', 'pos').Items.Add('放开头');
  GetCombo('seq', 'pos').Items.Add('放结尾');
  GetCombo('seq', 'pos').Items.Add('替换名称');
  GetCombo('seq', 'pos').ItemIndex := 0;
  PutParam(4, pkLabel, '', 582, 290, 22, 9, '只在本次选中的项目内递增', True);

  // ⑥ 大小写（文件名 + 扩展名）
  NewRule('case', '大小写', True);
  PutParam(5, pkCombo, 'nm', 166, 120, 26, 6, '', False);
  GetCombo('case', 'nm').Items.Add('大小写不变');
  GetCombo('case', 'nm').Items.Add('全部大写');
  GetCombo('case', 'nm').Items.Add('全部小写');
  GetCombo('case', 'nm').Items.Add('首字母大写');
  GetCombo('case', 'nm').ItemIndex := 0;
  PutParam(5, pkLabel, '', 294, 44, 22, 9, '扩展名', False);
  PutParam(5, pkCombo, 'ext', 340, 110, 26, 6, '', False);
  GetCombo('case', 'ext').Items.Add('扩展名不变');
  GetCombo('case', 'ext').Items.Add('扩展名小写');
  GetCombo('case', 'ext').Items.Add('扩展名大写');
  GetCombo('case', 'ext').ItemIndex := 0;
  PutParam(5, pkLabel, '', 470, 380, 22, 9, '仅影响名称部分，扩展名单独设置', True);

  // ⑦ 清理非法字符
  NewRule('clean', '清理非法字符', False);
  PutParam(6, pkLabel, '', 166, 44, 22, 9, '替换为', False);
  PutParam(6, pkEdit, 'ch', 214, 50, 26, 6, '_', False);
  PutParam(6, pkLabel, '', 274, 440, 22, 9,
    '把 \ / : * ? " < > | 替换成该字符', True);

  // ⑧ 删除字符
  NewRule('trim', '删除字符', False);
  PutParam(7, pkLabel, '', 166, 60, 22, 9, '起始位置', False);
  PutParam(7, pkEdit, 'pos', 230, 50, 26, 6, '', False);
  PutParam(7, pkLabel, '', 290, 60, 22, 9, '删除长度', False);
  PutParam(7, pkEdit, 'len', 354, 50, 26, 6, '', False);
  PutParam(7, pkLabel, '', 414, 430, 22, 9,
    '如 起 2 / 长 3 → 去掉第 2~4 个字符；长度留空＝删到末尾', True);
end;

function TForm1.NewRule(const Key, Title: string; OnDefault: Boolean): Integer;
var
  CB: TCheckBox;
  Lbl: TLabel;
  Up, Dn: TButton;
  N: Integer;
begin
  N := Length(Rules);
  SetLength(Rules, N + 1);
  Rules[N].Key := Key;
  Rules[N].Title := Title;
  Rules[N].IsOn := OnDefault;
  Rules[N].DefaultOn := OnDefault;
  Rules[N].OriginalIdx := N;
  SetLength(Rules[N].Params, 0);

  CB := TCheckBox.Create(Self);
  CB.Parent := Self;
  CB.Caption := '';
  CB.Checked := OnDefault;
  CB.OnClick := @RefreshAll;
  Rules[N].CB := CB;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := Self;
  Lbl.Caption := Title;
  Rules[N].Lbl := Lbl;

  Up := TButton.Create(Self);
  Up.Parent := Self;
  Up.Caption := '↑';
  Up.Tag := N;
  Up.OnClick := @MoveUpClick;
  Rules[N].UpBtn := Up;

  Dn := TButton.Create(Self);
  Dn.Parent := Self;
  Dn.Caption := '↓';
  Dn.Tag := N;
  Dn.OnClick := @MoveDownClick;
  Rules[N].DnBtn := Dn;

  Result := N;
end;

procedure TForm1.PutParam(RuleIdx: Integer; Kind: TParamKind; const ID: string;
  X, W, H, DY: Integer; const ACaption: string; Gray: Boolean);
var
  P: TParamCtl;
  N: Integer;
begin
  P.Kind := Kind;
  P.ID := ID;
  P.X := X;
  P.W := W;
  P.H := H;
  P.DY := DY;
  P.Ed := nil;
  P.Lb := nil;
  P.Ck := nil;
  P.Cmb := nil;

  case Kind of
    pkEdit:
      begin
        P.Ed := TEdit.Create(Self);
        P.Ed.Parent := Self;
        P.Ed.Text := ACaption;
        P.Ed.OnChange := @RefreshAll;
      end;
    pkLabel:
      begin
        P.Lb := TLabel.Create(Self);
        P.Lb.Parent := Self;
        P.Lb.Caption := ACaption;
        if Gray then
          P.Lb.Font.Color := HINT_COLOR;
      end;
    pkCheck:
      begin
        P.Ck := TCheckBox.Create(Self);
        P.Ck.Parent := Self;
        P.Ck.Caption := ACaption;
        P.Ck.OnClick := @RefreshAll;
      end;
    pkCombo:
      begin
        P.Cmb := TComboBox.Create(Self);
        P.Cmb.Parent := Self;
        P.Cmb.Style := csDropDownList;
        P.Cmb.OnChange := @RefreshAll;
      end;
  end;

  N := Length(Rules[RuleIdx].Params);
  SetLength(Rules[RuleIdx].Params, N + 1);
  Rules[RuleIdx].Params[N] := P;
end;

procedure TForm1.LayoutRules;
var
  I, J, Y: Integer;
begin
  for I := 0 to High(Rules) do
  begin
    Y := RuleTop + I * RowH;
    Rules[I].CB.SetBounds(32, Y + 8, 26, 22);
    Rules[I].Lbl.SetBounds(64, Y + 9, 110, 22);
    Rules[I].Lbl.Caption := CIRCLED[I] + '  ' + Rules[I].Title;
    Rules[I].UpBtn.SetBounds(884, Y + 6, 40, 26);
    Rules[I].DnBtn.SetBounds(930, Y + 6, 40, 26);
    // Tag 必须跟随当前位置，否则交换顺序后 ↑↓ 会移动错误的行
    Rules[I].UpBtn.Tag := I;
    Rules[I].DnBtn.Tag := I;
    Rules[I].UpBtn.Enabled := I > 0;
    Rules[I].DnBtn.Enabled := I < High(Rules);
    for J := 0 to High(Rules[I].Params) do
      with Rules[I].Params[J] do
        case Kind of
          pkEdit:  Ed.SetBounds(X, Y + DY, W, H);
          pkLabel: Lb.SetBounds(X, Y + DY, W, H);
          pkCheck: Ck.SetBounds(X, Y + DY, W, H);
          pkCombo: Cmb.SetBounds(X, Y + DY, W, H);
        end;
  end;
  // 强制整窗重绘，避免控件移动后残影
  RedrawWindow(Handle, nil, 0, RDW_INVALIDATE or RDW_ALLCHILDREN);
end;

procedure TForm1.MoveUpClick(Sender: TObject);
var
  I: Integer;
  T: TRule;
begin
  I := (Sender as TButton).Tag;
  if I <= 0 then
    Exit;
  T := Rules[I - 1];
  Rules[I - 1] := Rules[I];
  Rules[I] := T;
  LayoutRules;
  RefreshAll(nil);
end;

procedure TForm1.MoveDownClick(Sender: TObject);
var
  I: Integer;
  T: TRule;
begin
  I := (Sender as TButton).Tag;
  if I >= High(Rules) then
    Exit;
  T := Rules[I + 1];
  Rules[I + 1] := Rules[I];
  Rules[I] := T;
  LayoutRules;
  RefreshAll(nil);
end;

procedure TForm1.ResetRules(Sender: TObject);
var
  I, J, N: Integer;
  Tmp: array of TRule;
begin
  if MessageDlg('将所有规则恢复默认（参数清空、顺序还原）？', mtConfirmation,
    [mbYes, mbNo], 0) <> mrYes then
    Exit;

  // 恢复默认参数值
  GetEdit('prefix', 'v').Text := '';
  GetEdit('suffix', 'v').Text := '';
  GetEdit('replace', 'find').Text := '';
  GetEdit('replace', 'repl').Text := '';
  GetCheck('replace', 'regex').Checked := False;
  GetEdit('seq', 'start').Text := '1';
  GetEdit('seq', 'step').Text := '1';
  GetEdit('seq', 'digits').Text := '3';
  GetCombo('seq', 'pos').ItemIndex := 0;
  GetCombo('case', 'nm').ItemIndex := 0;
  GetCombo('case', 'ext').ItemIndex := 0;
  GetEdit('clean', 'ch').Text := '_';
  GetEdit('trim', 'pos').Text := '';
  GetEdit('trim', 'len').Text := '';
  GetEdit('custom', 'v').Text := '';

  // 恢复默认勾选
  for I := 0 to High(Rules) do
  begin
    Rules[I].IsOn := Rules[I].DefaultOn;
    Rules[I].CB.Checked := Rules[I].IsOn;
  end;

  // 恢复出厂顺序
  SetLength(Tmp, Length(Rules));
  for I := 0 to High(Rules) do
    Tmp[I] := Rules[I];
  N := 0;
  for I := 0 to High(DEFAULT_ORDER) do
    for J := 0 to High(Tmp) do
      if Tmp[J].Key = DEFAULT_ORDER[I] then
      begin
        Rules[N] := Tmp[J];
        Inc(N);
        Break;
      end;

  LayoutRules;
  RefreshAll(nil);
end;

// ---------- 控件查找 ----------

function TForm1.GetEdit(const Key, ID: string): TEdit;
var
  I, J: Integer;
begin
  Result := nil;
  for I := 0 to High(Rules) do
    if Rules[I].Key = Key then
      for J := 0 to High(Rules[I].Params) do
        if (Rules[I].Params[J].Kind = pkEdit) and
           (Rules[I].Params[J].ID = ID) then
          Exit(Rules[I].Params[J].Ed);
end;

function TForm1.GetCheck(const Key, ID: string): TCheckBox;
var
  I, J: Integer;
begin
  Result := nil;
  for I := 0 to High(Rules) do
    if Rules[I].Key = Key then
      for J := 0 to High(Rules[I].Params) do
        if (Rules[I].Params[J].Kind = pkCheck) and
           (Rules[I].Params[J].ID = ID) then
          Exit(Rules[I].Params[J].Ck);
end;

function TForm1.GetCombo(const Key, ID: string): TComboBox;
var
  I, J: Integer;
begin
  Result := nil;
  for I := 0 to High(Rules) do
    if Rules[I].Key = Key then
      for J := 0 to High(Rules[I].Params) do
        if (Rules[I].Params[J].Kind = pkCombo) and
           (Rules[I].Params[J].ID = ID) then
          Exit(Rules[I].Params[J].Cmb);
end;

// ---------- 名称计算 ----------

function TForm1.IntVal(const S: string; Def: Integer): Integer;
var
  T: string;
  C: Integer;
begin
  T := Trim(S);
  Val(T, Result, C);
  if (C <> 0) or (T = '') then
    Result := Def;
end;

function TForm1.ContainsAnyIllegal(const AName: string): Boolean;
var
  Ch: Char;
begin
  Result := False;
  for Ch in AName do
    if CharInSet(Ch, ['\', '/', ':', '*', '?', '"', '<', '>', '|']) then
      Exit(True);
end;

function TForm1.FirstLetterUpper(const S: string): string;
var
  I: Integer;
  WordChar, PrevWordChar: Boolean;
begin
  Result := '';
  PrevWordChar := False;
  for I := 1 to Length(S) do
  begin
    WordChar := CharInSet(S[I], ['a'..'z', 'A'..'Z', '0'..'9']);
    if WordChar and not PrevWordChar then
      Result := Result + UpperCase(S[I])
    else
      Result := Result + LowerCase(S[I]);
    PrevWordChar := WordChar;
  end;
end;

// 按规则链计算一个项目的新名字。返回 True 表示状态为「就绪」。
function TForm1.ComputeItem(var It: TItemRec; SeqNo: Integer): Boolean;
var
  I, St, Sp, Dg, P, L: Integer;
  S, E, Num, Ch: string;
begin
  It.NewName := It.Name;
  It.NewPath := It.Path;
  if It.Done then
  begin
    It.Status := '已完成';
    It.Enabled := False;
    Exit(False);
  end;
  if not Eligible(It) then
  begin
    It.Status := '跳过(范围)';
    It.Enabled := False;
    Exit(False);
  end;

  S := It.Stem;
  E := It.Ext;

  for I := 0 to High(Rules) do
  begin
    if not Rules[I].IsOn then
      Continue;
    case Rules[I].Key of
      'custom':
        if GetEdit('custom', 'v').Text <> '' then
          S := GetEdit('custom', 'v').Text;

      'prefix':
        S := GetEdit('prefix', 'v').Text + S;

      'suffix':
        S := S + GetEdit('suffix', 'v').Text;

      'replace':
        if GetEdit('replace', 'find').Text <> '' then
        begin
          if GetCheck('replace', 'regex').Checked then
            S := ReplaceRegExpr(GetEdit('replace', 'find').Text, S,
              GetEdit('replace', 'repl').Text, True)
          else
            S := StringReplace(S, GetEdit('replace', 'find').Text,
              GetEdit('replace', 'repl').Text, [rfReplaceAll]);
        end;

      'seq':
        if SeqNo > 0 then
        begin
          St := IntVal(GetEdit('seq', 'start').Text, 1);
          Sp := IntVal(GetEdit('seq', 'step').Text, 1);
          if Sp = 0 then
            Sp := 1;
          Dg := IntVal(GetEdit('seq', 'digits').Text, 3);
          if (Dg < 1) or (Dg > 10) then
            Dg := 3;
          Num := AddChar('0', IntToStr(St + (SeqNo - 1) * Sp), Dg);
          case GetCombo('seq', 'pos').ItemIndex of
            1: S := S + Num;      // 放结尾
            2: S := Num;          // 替换名称
          else
            S := Num + S;         // 放开头
          end;
        end;

      'case':
        begin
          case GetCombo('case', 'nm').ItemIndex of
            1: S := UpperCase(S);
            2: S := LowerCase(S);
            3: S := FirstLetterUpper(S);
          end;
          case GetCombo('case', 'ext').ItemIndex of
            1: E := LowerCase(E);
            2: E := UpperCase(E);
          end;
        end;

      'clean':
        begin
          Ch := Copy(Trim(GetEdit('clean', 'ch').Text), 1, 1);
          if Ch = '' then
            Ch := '_';
          S := ReplaceRegExpr('[\\/:*?"<>|]', S, Ch, False);
        end;

      'trim':
        begin
          P := IntVal(GetEdit('trim', 'pos').Text, 0);
          if P > 0 then
          begin
            L := IntVal(GetEdit('trim', 'len').Text, 0);
            if L <= 0 then
              S := Copy(S, 1, P - 1)
            else
              S := Copy(S, 1, P - 1) + Copy(S, P + L, MaxInt);
          end;
        end;
    end;
  end;
  It.NewName := S + E;
  It.NewPath := IncludeTrailingPathDelimiter(It.Dir) + It.NewName;
  It.Status := '就绪';
  It.Enabled := True;

  if It.NewName = '' then
  begin
    It.Status := '名称为空';
    It.Enabled := False;
  end
  else if ContainsAnyIllegal(It.NewName) then
  begin
    It.Status := '非法字符';
    It.Enabled := False;
  end
  else if Length(It.NewName) > 255 then
  begin
    It.Status := '名称过长';
    It.Enabled := False;
  end
  else if LowerCase(It.NewPath) = LowerCase(It.Path) then
  begin
    It.Status := '无变化';
    It.Enabled := False;
  end
  else if FileExists(It.NewPath) or DirectoryExists(It.NewPath) then
  begin
    It.Status := '目标已存在';
    It.Enabled := False;
  end;

  Result := It.Enabled;
end;

function TForm1.Eligible(const It: TItemRec): Boolean;
begin
  if It.Done then
    Exit(False);
  case Scope.ItemIndex of
    1: Result := not It.IsDir;
    2: Result := It.IsDir;
  else
    Result := True;
  end;
end;

function TForm1.ChainDesc: string;
var
  I, N: Integer;
  D: string;
begin
  Result := '';
  N := 0;
  for I := 0 to High(Rules) do
  begin
    if not Rules[I].IsOn then
      Continue;
    D := RuleDesc(Rules[I]);
    if D = '' then
      Continue;
    if Result = '' then
      Result := '规则链：'
    else
      Result := Result + '  →  ';
    Result := Result + CIRCLED[N] + ' ' + D;
    Inc(N);
  end;
  if Result = '' then
    Result := '规则链：（没有生效的规则，不会改名）';
end;

function TForm1.RuleDesc(const R: TRule): string;
var
  V, P: string;
begin
  Result := '';
  case R.Key of
    'custom':
      begin
        V := GetEdit('custom', 'v').Text;
        if V <> '' then
          Result := '自定义名「' + V + '」';
      end;
    'prefix':
      begin
        V := GetEdit('prefix', 'v').Text;
        if V <> '' then
          Result := '前缀「' + V + '」';
      end;
    'suffix':
      begin
        V := GetEdit('suffix', 'v').Text;
        if V <> '' then
          Result := '后缀「' + V + '」';
      end;
    'replace':
      begin
        V := GetEdit('replace', 'find').Text;
        if V <> '' then
        begin
          Result := '替换「' + V + '」→「' + GetEdit('replace', 'repl').Text + '」';
          if GetCheck('replace', 'regex').Checked then
            Result := Result + '（正则）';
        end;
      end;
    'seq':
      begin
        P := '放开头';
        if GetCombo('seq', 'pos').ItemIndex = 1 then
          P := '放结尾'
        else if GetCombo('seq', 'pos').ItemIndex = 2 then
          P := '替换名称';
        Result := Format('序号 %s 起 / 步 %s / %s 位 / %s',
          [GetEdit('seq', 'start').Text, GetEdit('seq', 'step').Text,
           GetEdit('seq', 'digits').Text, P]);
      end;
    'case':
      begin
        case GetCombo('case', 'nm').ItemIndex of
          1: Result := '全大写';
          2: Result := '全小写';
          3: Result := '首字母大写';
        end;
        case GetCombo('case', 'ext').ItemIndex of
          1: Result := Result + IfThen(Result <> '', '，') + '扩展名小写';
          2: Result := Result + IfThen(Result <> '', '，') + '扩展名大写';
        end;
      end;
    'clean':
      Result := '清理非法字符为「' + Copy(Trim(GetEdit('clean', 'ch').Text), 1, 1) + '」';
    'trim':
      begin
        V := Trim(GetEdit('trim', 'pos').Text);
        if V <> '' then
        begin
          Result := '删第 ' + V + ' 位起';
          if Trim(GetEdit('trim', 'len').Text) = '' then
            Result := Result + '到末尾'
          else
            Result := Result + ' ' + Trim(GetEdit('trim', 'len').Text) + ' 个字符';
        end;
      end;
  end;
end;

procedure TForm1.SetStatusText(const Msg: string);
begin
  if StatusMemo <> nil then
    StatusMemo.Lines.Text := Msg;
end;

procedure TForm1.RefreshAll(Sender: TObject);
var
  I, SeqNo, Ready: Integer;
  Seen: TStringList;
  LI: TListItem;
begin
  if Lv = nil then
    Exit;
  // 勾选框状态 → 规则生效标记（IsOn 只在这里统一同步）
  for I := 0 to High(Rules) do
    Rules[I].IsOn := Rules[I].CB.Checked;
  Lv.Items.BeginUpdate;
  try
    Lv.Items.Clear;
    Seen := TStringList.Create;
    Seen.Sorted := True;
    Seen.Duplicates := dupError;
    try
      SeqNo := 0;
      for I := 0 to High(FItems) do
      begin
        if Eligible(FItems[I]) then
          Inc(SeqNo);           // 序号只统计真正参与重命名的项目
        ComputeItem(FItems[I], SeqNo);
        if FItems[I].Enabled then
        begin
          if Seen.IndexOf(LowerCase(FItems[I].NewPath)) >= 0 then
          begin
            FItems[I].Status := '目标重名';
            FItems[I].Enabled := False;
          end
          else
            Seen.Add(LowerCase(FItems[I].NewPath));
        end;
        LI := Lv.Items.Add;
        LI.Caption := FItems[I].Name;
        LI.SubItems.Add(FItems[I].NewName);
        LI.SubItems.Add(FItems[I].Status);
        LI.SubItems.Add(FItems[I].Path);
      end;
    finally
      Seen.Free;
    end;
  finally
    Lv.Items.EndUpdate;
  end;

  Ready := 0;
  for I := 0 to High(FItems) do
    if FItems[I].Enabled then
      Inc(Ready);

  SetStatusText(ChainDesc + #13#10 +
    Format('共 %d 项，可重命名 %d 项。未勾选的规则不参与；状态不是「就绪」的项目会被跳过。',
      [Length(FItems), Ready]));
end;

// ---------- 添加项目 ----------

procedure TForm1.AddOnePath(const P: string);
var
  I: Integer;
  AName, AExt: string;
  IsDirFlag: Boolean;
begin
  if P = '' then
    Exit;
  if DirectoryExists(P) then
    IsDirFlag := True
  else if FileExists(P) then
    IsDirFlag := False
  else
    Exit;

  // 去重（大小写不敏感）
  for I := 0 to High(FItems) do
    if LowerCase(FItems[I].Path) = LowerCase(P) then
      Exit;

  AName := ExtractFileName(P);
  AExt := ExtractFileExt(AName);
  SetLength(FItems, Length(FItems) + 1);
  with FItems[High(FItems)] do
  begin
    Path := P;
    Dir := ExtractFileDir(P);
    Name := AName;
    Stem := Copy(AName, 1, Length(AName) - Length(AExt));
    Ext := AExt;
    IsDir := IsDirFlag;
    Done := False;
  end;
end;

procedure TForm1.AddFiles(Sender: TObject);
var
  Dlg: TOpenDialog;
  I: Integer;
begin
  Dlg := TOpenDialog.Create(Self);
  try
    Dlg.Options := Dlg.Options + [ofAllowMultiSelect, ofFileMustExist];
    Dlg.InitialDir := SysUtils.GetEnvironmentVariable('USERPROFILE');
    Dlg.Title := '选择文件（可多选）';
    if Dlg.Execute then
    begin
      for I := 0 to Dlg.Files.Count - 1 do
        AddOnePath(Dlg.Files[I]);
      RefreshAll(nil);
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TForm1.AddFolders(Sender: TObject);
var
  Dialog: IFileOpenDialog;
  Results: IShellItemArray;
  Item: IShellItem;
  StartItem: IShellItem;
  Count, I: DWORD;
  NamePtr: PWideChar;
  AName: string;
begin
  NamePtr := nil;
  if CoCreateInstance(CLSID_FileOpenDialog, nil, CLSCTX_INPROC_SERVER,
      IID_IFileOpenDialog, Dialog) <> S_OK then
  begin
    MessageDlg('系统不支持现代文件夹选择对话框。', mtError, [mbOK], 0);
    Exit;
  end;
  Dialog.SetOptions(FOS_PICKFOLDERS or FOS_ALLOWMULTISELECT);
  Dialog.SetTitle('选择文件夹（可按住 Ctrl / Shift 多选）');
  // 初始目录：用户主目录
  if SHCreateItemFromParsingName(
      PWideChar(UTF8Decode(SysUtils.GetEnvironmentVariable('USERPROFILE'))), nil,
      IID_IShellItem, StartItem) = S_OK then
    Dialog.SetFolder(StartItem);
  if Dialog.Show(Handle) <> S_OK then
    Exit;
  if Dialog.GetResults(Results) <> S_OK then
    Exit;
  Count := 0;
  Results.GetCount(Count);
  for I := 0 to Count - 1 do
  begin
    if Results.GetItemAt(I, Item) <> S_OK then
      Continue;
    // 注意：ShlObj 的 GetDisplayName 声明少一层间址（LCL 同样用 @变量 绕过），必须传 @NamePtr
    if Item.GetDisplayName(SIGDN_PARSE_ABS, @NamePtr) <> S_OK then
      Continue;
    AName := UTF8Encode(WideString(NamePtr));
    CoTaskMemFree(NamePtr);
    AddOnePath(AName);
  end;
  RefreshAll(nil);
end;

procedure TForm1.AddClipboard(Sender: TObject);
var
  Txt: string;
  Lines: TStringList;
  I: Integer;
begin
  Txt := Trim(Clipboard.AsText);
  if Txt = '' then
  begin
    MessageDlg('剪贴板中没有路径。', mtInformation, [mbOK], 0);
    Exit;
  end;
  Lines := TStringList.Create;
  try
    Lines.Text := Txt;
    for I := 0 to Lines.Count - 1 do
      AddOnePath(Trim(Lines[I]));
    RefreshAll(nil);
  finally
    Lines.Free;
  end;
end;

procedure TForm1.DoDropFiles(Sender: TObject; const FileNames: array of string);
var
  I: Integer;
begin
  for I := 0 to High(FileNames) do
    AddOnePath(FileNames[I]);
  RefreshAll(nil);
end;

procedure TForm1.RemoveSelected(Sender: TObject);
var
  I: Integer;
  Keep: array of TItemRec;
begin
  SetLength(Keep, 0);
  for I := 0 to High(FItems) do
    if not Lv.Items[I].Selected then
    begin
      SetLength(Keep, Length(Keep) + 1);
      Keep[High(Keep)] := FItems[I];
    end;
  if Length(Keep) < Length(FItems) then
  begin
    FItems := Keep;
    RefreshAll(nil);
  end;
end;

procedure TForm1.ClearItems(Sender: TObject);
begin
  SetLength(FItems, 0);
  RefreshAll(nil);
end;

// ---------- 重命名执行 ----------

{ 两阶段重命名：先全部改临时名，再改目标名。
  任一步失败即整体回滚，返回错误信息；成功返回空串。 }
function TForm1.RenameBatch(var Pairs: array of TPairRec): string;
var
  I, J, Tick: Int64;
  Dir, Ext, Tmp: string;
  Temps, DoneList: array of TPairRec;
begin
  Result := '';
  Tick := GetTickCount64;
  SetLength(Temps, 0);

  // 第一阶段：全部改成临时名
  for I := 0 to High(Pairs) do
  begin
    Dir := ExtractFileDir(Pairs[I].FromPath);
    Ext := ExtractFileExt(Pairs[I].FromPath);
    if Pairs[I].IsDir then
      Ext := '';
    Tmp := Dir + '\.__br_tmp_' + IntToStr(Tick) + '_' + IntToStr(I) + Ext;
    if FileExists(Tmp) or DirectoryExists(Tmp) then
      Tmp := Dir + '\.__br_tmp_' + IntToStr(Tick) + '_' + IntToStr(I) + '_' +
        IntToStr(Random(9000) + 1000) + Ext;
    if not RenameFile(Pairs[I].FromPath, Tmp) then
    begin
      for J := 0 to High(Temps) do
        RenameFile(Temps[J].ToPath, Temps[J].FromPath);
      Exit('无法重命名：' + Pairs[I].FromPath);
    end;
    SetLength(Temps, Length(Temps) + 1);
    Temps[High(Temps)].FromPath := Pairs[I].FromPath;
    Temps[High(Temps)].ToPath := Tmp;
    Temps[High(Temps)].IsDir := Pairs[I].IsDir;
  end;

  // 第二阶段：临时名 → 目标名
  SetLength(DoneList, 0);
  for I := 0 to High(Temps) do
  begin
    if not RenameFile(Temps[I].ToPath, Pairs[I].ToPath) then
    begin
      for J := 0 to High(DoneList) do
        RenameFile(DoneList[J].ToPath, DoneList[J].FromPath);
      for J := 0 to High(Temps) do
        RenameFile(Temps[J].ToPath, Temps[J].FromPath);
      Exit('无法写入目标：' + Pairs[I].ToPath);
    end;
    SetLength(DoneList, Length(DoneList) + 1);
    DoneList[High(DoneList)].FromPath := Temps[I].ToPath;
    DoneList[High(DoneList)].ToPath := Pairs[I].ToPath;
    DoneList[High(DoneList)].IsDir := Temps[I].IsDir;
  end;
end;

function TForm1.AppendLog(Lines: TStrings): string;
var
  Dir: string;
  SL: TStringList;
  I: Integer;
begin
  Result := '';
  Dir := ExtractFilePath(Application.ExeName) + 'logs';
  ForceDirectories(Dir);
  SL := TStringList.Create;
  try
    SL.Add('批量重命名日志 · ' + FormatDateTime('yyyy-mm-dd hh:nn:ss', Now));
    for I := 0 to Lines.Count - 1 do
      SL.Add(Lines[I]);
    Result := Dir + '\rename_' + FormatDateTime('yyyymmdd_hhnnss', Now) + '.log';
    SL.SaveToFile(Result, TEncoding.UTF8);
  finally
    SL.Free;
  end;
end;

procedure TForm1.DoExecute(Sender: TObject);
var
  I, J, N: Integer;
  Pairs: array of TPairRec;
  Preview, Err, LogFile: string;
  Logs: TStringList;
begin
  RefreshAll(nil);
  SetLength(Pairs, 0);
  for I := 0 to High(FItems) do
    if FItems[I].Enabled then
    begin
      SetLength(Pairs, Length(Pairs) + 1);
      Pairs[High(Pairs)].FromPath := FItems[I].Path;
      Pairs[High(Pairs)].ToPath := FItems[I].NewPath;
      Pairs[High(Pairs)].IsDir := FItems[I].IsDir;
    end;
  N := Length(Pairs);
  if N = 0 then
  begin
    MessageDlg('没有可重命名的项目。' + #13#10#13#10 +
      '请先添加文件，并确认规则链有生效内容、状态为「就绪」。', mtInformation, [mbOK], 0);
    Exit;
  end;

  Preview := '';
  for I := 0 to Min(N, 8) - 1 do
    Preview := Preview + ExtractFileName(Pairs[I].FromPath) + '  →  ' +
      ExtractFileName(Pairs[I].ToPath) + #13#10;
  if N > 8 then
    Preview := Preview + Format('…… 其余 %d 项', [N - 8]) + #13#10;

  if MessageDlg(Format('即将重命名 %d 项：' + #13#10#13#10 + '%s' + #13#10 +
    '确认继续？', [N, Preview]), mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
    Exit;

  Err := RenameBatch(Pairs);
  if Err <> '' then
  begin
    MessageDlg(Err + #13#10#13#10 + '操作已回滚，文件保持原名。', mtError, [mbOK], 0);
    Exit;
  end;

  // 压入撤销栈
  SetLength(UndoStack, Length(UndoStack) + 1);
  SetLength(UndoStack[High(UndoStack)], N);
  for I := 0 to N - 1 do
    UndoStack[High(UndoStack)][I] := Pairs[I];

  // 更新 items 与日志
  Logs := TStringList.Create;
  try
    for I := 0 to N - 1 do
    begin
      Logs.Add('OK  ' + Pairs[I].FromPath + '  ->  ' + Pairs[I].ToPath);
      for J := 0 to High(FItems) do
        if LowerCase(FItems[J].Path) = LowerCase(Pairs[I].FromPath) then
        begin
          FItems[J].Path := Pairs[I].ToPath;
          FItems[J].Dir := ExtractFileDir(Pairs[I].ToPath);
          FItems[J].Name := ExtractFileName(Pairs[I].ToPath);
          FItems[J].Ext := ExtractFileExt(FItems[J].Name);
          FItems[J].Stem := Copy(FItems[J].Name, 1,
            Length(FItems[J].Name) - Length(FItems[J].Ext));
          FItems[J].Done := True;
          Break;
        end;
    end;
    LogFile := AppendLog(Logs);
  finally
    Logs.Free;
  end;

  RefreshAll(nil);
  SetStatusText(Format('完成：成功重命名 %d 项。可用「撤销上次」恢复。', [N]) +
    #13#10 + '日志: ' + LogFile);
  MessageDlg(Format('完成：成功重命名 %d 项。', [N]), mtInformation, [mbOK], 0);
end;

procedure TForm1.DoUndo(Sender: TObject);
var
  I, N: Integer;
  Pairs: array of TPairRec;
  Err: string;
  Logs: TStringList;
  Batch: array of TPairRec;
begin
  if Length(UndoStack) = 0 then
  begin
    MessageDlg('没有可撤销的操作。', mtInformation, [mbOK], 0);
    Exit;
  end;

  Batch := Copy(UndoStack[High(UndoStack)], 0, Length(UndoStack[High(UndoStack)]));
  N := Length(Batch);
  SetLength(Pairs, N);
  for I := 0 to N - 1 do
  begin
    Pairs[I].FromPath := Batch[N - 1 - I].ToPath;
    Pairs[I].ToPath := Batch[N - 1 - I].FromPath;
    Pairs[I].IsDir := Batch[N - 1 - I].IsDir;
  end;

  if MessageDlg(Format('将撤销上次重命名的 %d 项，恢复原文件名。确认？', [N]),
    mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
    Exit;

  Err := RenameBatch(Pairs);
  if Err <> '' then
  begin
    MessageDlg(Err + #13#10#13#10 + '撤销失败，请手动检查。', mtError, [mbOK], 0);
    Exit;
  end;

  // 弹出撤销栈
  SetLength(UndoStack, Length(UndoStack) - 1);

  // 重建 items
  SetLength(FItems, N);
  for I := 0 to N - 1 do
  begin
    FItems[I].Path := Batch[I].FromPath;
    FItems[I].Dir := ExtractFileDir(Batch[I].FromPath);
    FItems[I].Name := ExtractFileName(Batch[I].FromPath);
    FItems[I].Ext := ExtractFileExt(FItems[I].Name);
    FItems[I].Stem := Copy(FItems[I].Name, 1,
      Length(FItems[I].Name) - Length(FItems[I].Ext));
    FItems[I].IsDir := Batch[I].IsDir;
    FItems[I].Done := False;
  end;

  Logs := TStringList.Create;
  try
    for I := 0 to N - 1 do
      Logs.Add('UNDO  ' + Pairs[I].FromPath + '  ->  ' + Pairs[I].ToPath);
    AppendLog(Logs);
  finally
    Logs.Free;
  end;

  RefreshAll(nil);
  SetStatusText(Format('已撤销上次重命名，恢复 %d 项。', [N]));
  MessageDlg(Format('已撤销 %d 项。', [N]), mtInformation, [mbOK], 0);
end;

procedure TForm1.DoOpenLog(Sender: TObject);
var
  Dir: string;
begin
  Dir := ExtractFilePath(Application.ExeName) + 'logs';
  ForceDirectories(Dir);
  OpenDocument(Dir);
end;

end.

program fprename;

{ fprename - 文件批量重命名工具 (Free Pascal)
  默认 dry-run 预览模式，加 -x 才真正执行重命名。
  每次执行会生成撤销日志，可用 --undo 一键恢复。 }

{$mode objfpc}{$H+}

uses
  SysUtils, StrUtils, Classes;

const
  AppVersion = '1.0';

type
  TOperation = (opNone, opReplace, opPrefix, opSuffix, opSequence, opExt, opLower, opUpper);

var
  TargetDir: string = '';
  FileMask: string = '*.*';
  Operation: TOperation = opNone;
  ReplaceOld: string = '';
  ReplaceNew: string = '';
  PrefixStr: string = '';
  SuffixStr: string = '';
  SeqBase: string = '';
  SeqStart: Integer = 1;
  SeqPad: Integer = 3;
  NewExt: string = '';
  ExecuteNow: Boolean = False;
  WantUndo: Boolean = False;
  UndoLogFile: string = '';

procedure Usage;
begin
  WriteLn('fprename v', AppVersion, ' - batch file rename tool (Free Pascal)');
  WriteLn;
  WriteLn('Usage:');
  WriteLn('  fprename <dir> [options]');
  WriteLn('  fprename --undo <undo.log>');
  WriteLn;
  WriteLn('Options (default is DRY-RUN preview, add -x to execute):');
  WriteLn('  -m <mask>     file mask, default *.*');
  WriteLn('  -r <old=new>  replace text in name (base part only, extension kept)');
  WriteLn('  -p <str>      add prefix');
  WriteLn('  -s <str>      add suffix (before extension)');
  WriteLn('  -n <base>     rename to <base>_NNN.ext sequence');
  WriteLn('  -N <start>    sequence start number, default 1');
  WriteLn('  -W <width>    sequence number width, default 3');
  WriteLn('  -e <ext>      change extension (with dot, e.g. .jpg)');
  WriteLn('  -l            lowercase base name');
  WriteLn('  -u            uppercase base name');
  WriteLn('  -x            execute rename (without it: preview only)');
  WriteLn;
  WriteLn('Examples:');
  WriteLn('  fprename D:\photos -p "2026_"');
  WriteLn('  fprename D:\photos -r "IMG=photo" -x');
  WriteLn('  fprename D:\photos -m *.jpg -n trip -N 1 -W 3 -x');
  WriteLn('  fprename D:\photos -m *.jpeg -e .jpg -x');
  WriteLn('  fprename --undo D:\photos\fprename_undo_20261120_213000.log');
end;

{ 根据操作模式生成新文件名（SeqNum 为序号） }
function BuildNewName(const FileName: string; SeqNum: Integer): string;
var
  Ext, Base: string;
begin
  Ext := ExtractFileExt(FileName);
  Base := Copy(FileName, 1, Length(FileName) - Length(Ext));
  case Operation of
    opReplace:
      if ReplaceOld <> '' then
        Base := StringReplace(Base, ReplaceOld, ReplaceNew, [rfReplaceAll]);
    opPrefix:
      Base := PrefixStr + Base;
    opSuffix:
      Base := Base + SuffixStr;
    opSequence:
      Base := SeqBase + '_' + AddChar('0', IntToStr(SeqNum), SeqPad);
    opLower:
      Base := LowerCase(Base);
    opUpper:
      Base := UpperCase(Base);
  end;
  if Operation = opExt then
    Ext := NewExt;
  Result := Base + Ext;
end;

{ 真正执行批量重命名 }
procedure DoRename;
var
  SR: TSearchRec;
  SearchPath: string;
  OldName, NewName, OldPath, NewPath: string;
  Seq, Renamed, Failed, Skipped: Integer;
  i: Integer;
  Files: TStringList;
  Log: TextFile;
  LogPath: string;
begin
  SearchPath := IncludeTrailingPathDelimiter(TargetDir) + FileMask;

  LogPath := '';
  if ExecuteNow then
  begin
    LogPath := IncludeTrailingPathDelimiter(TargetDir) +
      FormatDateTime('"fprename_undo_"yyyymmdd_hhnnss"_"zzz".log"', Now);
    AssignFile(Log, LogPath);
    try
      Rewrite(Log);
    except
      on E: Exception do
      begin
        WriteLn('ERROR: cannot create undo log: ', E.Message);
        Halt(1);
      end;
    end;
    WriteLn(Log, '# old|new  (one rename per line, newest first)');
  end;

  Seq := SeqStart;
  Renamed := 0;
  Failed := 0;
  Skipped := 0;

  // 第一步：先快照所有待处理文件名，再统一重命名。
  // 避免边扫边改导致新生成的文件名被 FindNext 再次扫到而二次重命名。
  Files := TStringList.Create;
  try
    Files.Sorted := True;
    if FindFirst(SearchPath, faAnyFile, SR) = 0 then
    begin
      repeat
        // 只处理普通文件，跳过目录和本工具生成的撤销日志
        if (SR.Attr and faDirectory) = 0 then
          if Pos('fprename_undo_', LowerCase(SR.Name)) <> 1 then
            Files.Add(SR.Name);
      until FindNext(SR) <> 0;
      FindClose(SR);
    end;

    if Files.Count = 0 then
      WriteLn('No files matched mask "', FileMask, '" in ', TargetDir);

    // 第二步：基于快照执行重命名
    for i := 0 to Files.Count - 1 do
    begin
      OldName := Files[i];
      NewName := BuildNewName(OldName, Seq);
      Inc(Seq);

      if OldName = NewName then
      begin
        WriteLn('  = ', OldName, '  (unchanged, skipped)');
        Inc(Skipped);
        Continue;
      end;

      OldPath := IncludeTrailingPathDelimiter(TargetDir) + OldName;
      NewPath := IncludeTrailingPathDelimiter(TargetDir) + NewName;

      // 目标名已存在（大小写不同除外），跳过防止覆盖
      if (not SameText(OldName, NewName)) and FileExists(NewPath) then
      begin
        WriteLn('  ! ', OldName, ' -> ', NewName, '  (target exists, skipped)');
        Inc(Skipped);
        Continue;
      end;

      WriteLn('  ', OldName, ' -> ', NewName);

      if ExecuteNow then
      begin
        if RenameFile(OldPath, NewPath) then
        begin
          WriteLn(Log, OldName, '|', NewName);
          Inc(Renamed);
        end
        else
        begin
          WriteLn('    ERROR: rename failed');
          Inc(Failed);
        end;
      end;
    end;
  finally
    Files.Free;
  end;

  if ExecuteNow then
  begin
    CloseFile(Log);
    WriteLn;
    WriteLn('Done. Renamed: ', Renamed, ', Failed: ', Failed, ', Skipped: ', Skipped);
    WriteLn('Undo log: ', LogPath);
    WriteLn('To revert: fprename --undo "', LogPath, '"');
  end
  else
  begin
    WriteLn;
    WriteLn('DRY-RUN preview only, no files were changed.');
    WriteLn('Add -x to execute.');
  end;
end;

{ 读取撤销日志，逆序恢复文件名 }
procedure DoUndo;
var
  SL: TStringList;
  Dir: string;
  i, p: Integer;
  Line, OldName, NewName: string;
  Restored, Failed: Integer;
begin
  UndoLogFile := ExpandFileName(UndoLogFile);
  if not FileExists(UndoLogFile) then
  begin
    WriteLn('ERROR: undo log not found: ', UndoLogFile);
    Halt(1);
  end;

  Dir := IncludeTrailingPathDelimiter(ExtractFilePath(UndoLogFile));
  SL := TStringList.Create;
  try
    SL.LoadFromFile(UndoLogFile);
    WriteLn('Reverting ', Dir, ' using ', ExtractFileName(UndoLogFile));
    WriteLn;

    Restored := 0;
    Failed := 0;
    // 逆序回滚，避免链式覆盖
    for i := SL.Count - 1 downto 0 do
    begin
      Line := Trim(SL[i]);
      if (Line = '') or (Line[1] = '#') then
        Continue;
      p := Pos('|', Line);
      if p = 0 then
        Continue;
      OldName := Copy(Line, 1, p - 1);
      NewName := Copy(Line, p + 1, MaxInt);
      if not FileExists(Dir + NewName) then
      begin
        WriteLn('  ! ', NewName, ' not found (already renamed back?), skipped');
        Continue;
      end;
      WriteLn('  ', NewName, ' -> ', OldName);
      if RenameFile(Dir + NewName, Dir + OldName) then
        Inc(Restored)
      else
      begin
        WriteLn('    ERROR: rename failed');
        Inc(Failed);
      end;
    end;
    WriteLn;
    WriteLn('Undo done. Restored: ', Restored, ', Failed: ', Failed);
  finally
    SL.Free;
  end;
end;

procedure ParseArgs;
var
  i, p: Integer;
  a, s: string;
  Code: Integer;
begin
  i := 1;
  while i <= ParamCount do
  begin
    a := ParamStr(i);
    if (a = '-h') or (a = '--help') then
    begin
      Usage;
      Halt(0);
    end
    else if a = '-m' then
    begin
      Inc(i);
      FileMask := ParamStr(i);
    end
    else if a = '-r' then
    begin
      Inc(i);
      s := ParamStr(i);
      p := Pos('=', s);
      if p = 0 then
      begin
        WriteLn('ERROR: -r requires old=new format');
        Halt(1);
      end;
      ReplaceOld := Copy(s, 1, p - 1);
      ReplaceNew := Copy(s, p + 1, MaxInt);
      Operation := opReplace;
    end
    else if a = '-p' then
    begin
      Inc(i);
      PrefixStr := ParamStr(i);
      Operation := opPrefix;
    end
    else if a = '-s' then
    begin
      Inc(i);
      SuffixStr := ParamStr(i);
      Operation := opSuffix;
    end
    else if a = '-n' then
    begin
      Inc(i);
      SeqBase := ParamStr(i);
      Operation := opSequence;
    end
    else if a = '-N' then
    begin
      Inc(i);
      Val(ParamStr(i), SeqStart, Code);
      if Code <> 0 then
      begin
        WriteLn('ERROR: -N requires a number');
        Halt(1);
      end;
    end
    else if a = '-W' then
    begin
      Inc(i);
      Val(ParamStr(i), SeqPad, Code);
      if Code <> 0 then
      begin
        WriteLn('ERROR: -W requires a number');
        Halt(1);
      end;
    end
    else if a = '-e' then
    begin
      Inc(i);
      NewExt := ParamStr(i);
      if (NewExt <> '') and (NewExt[1] <> '.') then
        NewExt := '.' + NewExt;
      Operation := opExt;
    end
    else if a = '-l' then
      Operation := opLower
    else if a = '-u' then
      Operation := opUpper
    else if a = '-x' then
      ExecuteNow := True
    else if a = '--undo' then
    begin
      WantUndo := True;
      Inc(i);
      UndoLogFile := ParamStr(i);
    end
    else
    begin
      // 位置参数：目录
      if TargetDir = '' then
        TargetDir := a
      else
      begin
        WriteLn('ERROR: unknown argument: ', a);
        WriteLn('Use -h for help.');
        Halt(1);
      end;
    end;
    Inc(i);
  end;
end;

var
  CanContinue: Boolean;
begin
  try
    ParseArgs;

    if WantUndo then
    begin
      DoUndo;
      Halt(0);
    end;

    CanContinue := (TargetDir <> '') and DirectoryExists(TargetDir);
    if not CanContinue then
    begin
      WriteLn('ERROR: directory not found or not specified.');
      WriteLn;
      Usage;
      Halt(1);
    end;

    if Operation = opNone then
    begin
      WriteLn('ERROR: no rename operation specified.');
      WriteLn;
      Usage;
      Halt(1);
    end;

    if not ExecuteNow then
      WriteLn('--- DRY-RUN PREVIEW (add -x to execute) ---');
    WriteLn('Directory: ', ExpandFileName(TargetDir));
    WriteLn('Mask:      ', FileMask);
    WriteLn;

    DoRename;
  except
    on E: Exception do
    begin
      WriteLn('FATAL: ', E.Message);
      Halt(1);
    end;
  end;
end.

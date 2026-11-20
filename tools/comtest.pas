program comtest;

{ 独立测试 IFileOpenDialog 多选文件夹 COM 调用链（使用 FPC 官方 ShlObj 声明） }

{$mode objfpc}{$H+}

uses
  Windows, SysUtils, ActiveX, ShlObj;

const
  IID_IFileOpenDialog: TGUID = '{D57C7288-D4AD-4768-BE02-9D969532D960}';
  IID_IShellItem: TGUID = '{43826D1E-E718-42EE-BC55-A1E261C37BFE}';
  IID_IShellItemArray: TGUID = '{B63EA76D-1F85-456F-A19C-48159EFA858B}';

function SHCreateItemFromParsingName(pszPath: PWideChar; pbc: Pointer;
  const riid: TGUID; out ppv): HResult;
  stdcall; external 'shell32.dll' name 'SHCreateItemFromParsingName';
function SHCreateShellItemArrayFromShellItem(psi: IShellItem; const riid: TGUID;
  out ppv): HResult;
  stdcall; external 'shell32.dll' name 'SHCreateShellItemArrayFromShellItem';

var
  Dialog: IFileOpenDialog;
  Results: IShellItemArray;
  Item: IShellItem;
  StartItem: IShellItem;
  Count, I: DWORD;
  NamePtr: PWideChar;
  HR: HResult;
begin
  try
    CoInitializeEx(nil, 0);
    WriteLn('step1 CoCreateInstance...');
    HR := CoCreateInstance(CLSID_FileOpenDialog, nil, CLSCTX_INPROC_SERVER,
      IID_IFileOpenDialog, Dialog);
    WriteLn('  hr=', IntToHex(HR, 8));
    if HR <> 0 then Halt(1);

    WriteLn('step2 SetOptions...');
    HR := Dialog.SetOptions(FOS_PICKFOLDERS or FOS_ALLOWMULTISELECT);
    WriteLn('  hr=', IntToHex(HR, 8));

    WriteLn('step3 SetTitle...');
    HR := Dialog.SetTitle('test');
    WriteLn('  hr=', IntToHex(HR, 8));

    WriteLn('step4 SHCreateItemFromParsingName...');
    HR := SHCreateItemFromParsingName(
      PWideChar(WideString(SysUtils.GetEnvironmentVariable('USERPROFILE'))),
      nil, IID_IShellItem, StartItem);
    WriteLn('  hr=', IntToHex(HR, 8));
    if HR = 0 then
    begin
      WriteLn('step5 SetFolder...');
      HR := Dialog.SetFolder(StartItem);
      WriteLn('  hr=', IntToHex(HR, 8));
    end;

    WriteLn('step6 Show...');
    if (ParamCount > 0) and (ParamStr(1) = 'results') then
    begin
      // 无 UI 模式：合成单元素 IShellItemArray，验证结果处理链路
      WriteLn('  skipped (results mode)');
      if SHCreateShellItemArrayFromShellItem(StartItem, IID_IShellItemArray,
          Results) <> 0 then
        Halt(4);
      Count := 0;
      Results.GetCount(Count);
      WriteLn('  count=', Count);
      for I := 0 to Count - 1 do
      begin
        WriteLn('  -- item ', I, ' GetItemAt...'); Flush(Output);
        if Results.GetItemAt(I, Item) <> 0 then
          Continue;
        WriteLn('  -- GetDisplayName...'); Flush(Output);
        // ShlObj 声明少一层间址，必须传 @NamePtr
        if Item.GetDisplayName(SIGDN_DESKTOPABSOLUTEPARSING, @NamePtr) <> 0 then
          Continue;
        WriteLn('  item: ', UTF8Encode(WideString(NamePtr)));
        CoTaskMemFree(NamePtr);
        NamePtr := nil;
      end;
      WriteLn('RESULTS-PATH OK');
      Halt(0);
    end;
    if (ParamCount > 0) and (ParamStr(1) = 'nogui') then
    begin
      WriteLn('  skipped (nogui mode)');
      WriteLn('PRE-SHOW OK');
      Halt(0);
    end;
    HR := Dialog.Show(0);
    WriteLn('  show hr=', IntToHex(HR, 8));
    if HR <> 0 then
    begin
      WriteLn('canceled by user');
      Halt(0);
    end;

    WriteLn('step7 GetResults...');
    HR := Dialog.GetResults(Results);
    WriteLn('  hr=', IntToHex(HR, 8));
    if HR <> 0 then Halt(2);

    Count := 0;
    Results.GetCount(Count);
    WriteLn('  count=', Count); Flush(Output);
    for I := 0 to Count - 1 do
    begin
      WriteLn('  -- item ', I, ' GetItemAt...'); Flush(Output);
      if Results.GetItemAt(I, Item) <> 0 then
      begin
        WriteLn('  GetItemAt failed');
        Continue;
      end;
      WriteLn('  -- GetDisplayName...'); Flush(Output);
      // 注意：ShlObj 的 GetDisplayName 声明少一层间址，必须传 @NamePtr
      if Item.GetDisplayName(SIGDN_DESKTOPABSOLUTEPARSING, @NamePtr) <> 0 then
      begin
        WriteLn('  GetDisplayName failed');
        Continue;
      end;
      WriteLn('  -- converting...');
      WriteLn('  item: ', UTF8Encode(WideString(NamePtr)));
      CoTaskMemFree(NamePtr);
      NamePtr := nil;
    end;
    WriteLn('ALL OK');
  except
    on E: Exception do
    begin
      WriteLn('EXCEPTION: ', E.ClassName, ': ', E.Message);
      Halt(3);
    end;
  end;
end.

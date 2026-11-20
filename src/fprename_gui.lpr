program fprename_gui;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces, // LCL widgetset
  Forms,
  Unit1;

{$R *.res}
{$R appicon.res}
{$R versioninfo.res}

begin
  RequireDerivedFormResource := True;
  Application.Title := '章鱼文件';
  Application.Scaled := True;
  Application.Initialize;
  Application.CreateForm(TForm1, Form1);
  Application.Run;
end.

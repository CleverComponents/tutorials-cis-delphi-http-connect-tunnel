program Test;

{$IFDEF CONSOLE_TESTRUNNER}
{$APPTYPE CONSOLE}
{$ENDIF}

uses
  System.SysUtils,
{$IFDEF CONSOLE_TESTRUNNER}
  System.Classes,
  DUnitX.TestFramework,
  DUnitX.Loggers.Console,
  DUnitX.Loggers.Xml.NUnit,
{$ELSE}
  DUnitX.TestFramework,
  DUnitX.Loggers.GUI.VCL,
{$ENDIF}
  clHttpTunnelServer in '..\..\..\src\clHttpTunnelServer.pas',
  clHttpTunnelServerTests in '..\..\clHttpTunnelServerTests.pas';

{$IFDEF CONSOLE_TESTRUNNER}
var
  runner: ITestRunner;
  results: IRunResults;
  logger: ITestLogger;
  nunitLogger: ITestLogger;
  xmlStream: TStream;
{$ENDIF}
begin
  ReportMemoryLeaksOnShutdown := True;

{$IFDEF CONSOLE_TESTRUNNER}
  xmlStream := nil;
  try
    TDUnitX.CheckCommandLine();
    TDUnitX.Options.ExitBehavior := TDUnitXExitBehavior.Continue;

    runner := TDUnitX.CreateRunner();
    runner.UseRTTI := False;
    runner.FailsOnNoAsserts := False;

    if (TDUnitX.Options.ConsoleMode <> TDunitXConsoleMode.Off) then
    begin
      logger := TDUnitXConsoleLogger.Create(TDUnitX.Options.ConsoleMode = TDunitXConsoleMode.Quiet);
      runner.AddLogger(logger);
    end;

    xmlStream := TFileStream.Create(
      ExpandFileName(ExtractFilePath(ParamStr(0)) + 'dunitx-results.xml'), fmCreate);
    nunitLogger := TDUnitXXMLNUnitLogger.Create(xmlStream, True);
    xmlStream := nil;
    runner.AddLogger(nunitLogger);

    results := runner.Execute();
    if (not results.AllPassed) then
    begin
      ExitCode := 1;
    end;
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      ExitCode := 2;
    end;
  end;
  xmlStream.Free();
{$ELSE}
  DUnitX.Loggers.GUI.VCL.Run();
{$ENDIF}
end.

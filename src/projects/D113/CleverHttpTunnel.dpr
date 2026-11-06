program CleverHttpTunnel;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  clHttpTunnelServer in '..\..\clHttpTunnelServer.pas',
  clHttpTunnelConfig in '..\..\clHttpTunnelConfig.pas';

var
  server: TclHttpTunnelServer;
  iniPath: string;
begin
  ReportMemoryLeaksOnShutdown := True;
  server := nil;
  try
    server := TclHttpTunnelServer.Create(nil);
    iniPath := TclHttpTunnelConfig.DefaultIniFileName();
    TclHttpTunnelConfig.LoadFromIni(iniPath, server);
    Writeln(Format('CleverHttpTunnel listen *:%d (allowlist from %s)',
      [server.Port, iniPath]));
    server.Start();
    try
      Writeln('Press Enter to stop...');
      Readln;
    finally
      server.Stop();
    end;
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
  server.Free();
end.

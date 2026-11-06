{
  CleverHttpTunnel
  Copyright (C) 2026 Clever Components
  All Rights Reserved
  www.CleverComponents.com
}

unit clHttpTunnelConfig;

interface

{$I clVer.inc}

uses
{$IFNDEF DELPHIXE2}
  Classes, SysUtils, IniFiles,
{$ELSE}
  System.Classes, System.SysUtils, System.IniFiles,
{$ENDIF}
  clHttpTunnelServer;

type
  EclHttpTunnelConfigError = class(Exception);

  TclHttpTunnelConfig = class
  public
    class function DefaultIniFileName: string;
    class function ServiceDataDirectory: string;
    class function ServiceIniFileName: string;
    class function ServiceLogFileName: string;
    class procedure LoadFromIni(const AFileName: string; AServer: TclHttpTunnelServer);
  end;

implementation

function SplitCommaList(const AValue: string; ADest: TStrings): Integer;
var
  items: TStringList;
  i: Integer;
  item: string;
begin
  Result := 0;
  ADest.Clear();
  items := TStringList.Create();
  try
    items.StrictDelimiter := True;
    items.Delimiter := ',';
    items.DelimitedText := AValue;
    for i := 0 to items.Count - 1 do
    begin
      item := Trim(items[i]);
      if (item <> '') then
      begin
        ADest.Add(item);
        Inc(Result);
      end;
    end;
  finally
    items.Free();
  end;
end;

{ TclHttpTunnelConfig }

class function TclHttpTunnelConfig.DefaultIniFileName: string;
begin
  Result := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) + 'CleverHttpTunnel.ini';
end;

class function TclHttpTunnelConfig.ServiceDataDirectory: string;
var
  programData: string;
begin
  programData := GetEnvironmentVariable('ProgramData');
  if (programData = '') then
  begin
    programData := GetEnvironmentVariable('ALLUSERSPROFILE');
  end;
  if (programData = '') then
  begin
    raise EclHttpTunnelConfigError.Create('ProgramData path is not available');
  end;
  Result := IncludeTrailingPathDelimiter(programData) +
    'CleverComponents\CleverHttpTunnel\';
end;

class function TclHttpTunnelConfig.ServiceIniFileName: string;
begin
  Result := ServiceDataDirectory() + 'CleverHttpTunnel.ini';
end;

class function TclHttpTunnelConfig.ServiceLogFileName: string;
begin
  Result := ServiceDataDirectory() + 'Logs\CleverHttpTunnel.log';
end;

class procedure TclHttpTunnelConfig.LoadFromIni(const AFileName: string;
  AServer: TclHttpTunnelServer);
var
  ini: TIniFile;
  hostsRaw, portsRaw, localBinding: string;
  port, i, parsedPort, optionalInt: Integer;
  hosts, ports: TStringList;
begin
  if (AServer = nil) then
  begin
    raise EclHttpTunnelConfigError.Create('Server is not assigned');
  end;
  if (AFileName = '') or (not FileExists(AFileName)) then
  begin
    raise EclHttpTunnelConfigError.CreateFmt('Config file not found: %s', [AFileName]);
  end;

  hosts := nil;
  ports := nil;
  ini := TIniFile.Create(AFileName);
  try
    port := ini.ReadInteger('Server', 'Port', -1);
    if (port < 1) or (port > 65535) then
    begin
      raise EclHttpTunnelConfigError.Create('Invalid [Server] Port');
    end;

    localBinding := Trim(ini.ReadString('Server', 'LocalBinding', ''));

    hostsRaw := ini.ReadString('Allowlist', 'Hosts', '');
    portsRaw := ini.ReadString('Allowlist', 'Ports', '');

    hosts := TStringList.Create();
    ports := TStringList.Create();
    if (SplitCommaList(hostsRaw, hosts) = 0) then
    begin
      raise EclHttpTunnelConfigError.Create('[Allowlist] Hosts is empty');
    end;
    if (SplitCommaList(portsRaw, ports) = 0) then
    begin
      raise EclHttpTunnelConfigError.Create('[Allowlist] Ports is empty');
    end;

    for i := 0 to ports.Count - 1 do
    begin
      parsedPort := StrToIntDef(ports[i], -1);
      if (parsedPort < 1) or (parsedPort > 65535) then
      begin
        raise EclHttpTunnelConfigError.CreateFmt('Invalid [Allowlist] Ports entry: %s', [ports[i]]);
      end;
      ports[i] := IntToStr(parsedPort);
    end;

    AServer.Port := port;
    if (localBinding <> '') then
    begin
      AServer.LocalBinding := localBinding;
    end;
    AServer.AllowedHosts := hosts;
    AServer.AllowedPorts := ports;

    if ini.ValueExists('Server', 'RequestTimeoutSec') then
    begin
      optionalInt := ini.ReadInteger('Server', 'RequestTimeoutSec', -1);
      if (optionalInt < 0) then
      begin
        raise EclHttpTunnelConfigError.Create('Invalid [Server] RequestTimeoutSec');
      end;
      AServer.RequestTimeoutSec := optionalInt;
    end;
    if ini.ValueExists('Server', 'ConnectTimeoutSec') then
    begin
      optionalInt := ini.ReadInteger('Server', 'ConnectTimeoutSec', -1);
      if (optionalInt < 0) then
      begin
        raise EclHttpTunnelConfigError.Create('Invalid [Server] ConnectTimeoutSec');
      end;
      AServer.ConnectTimeoutSec := optionalInt;
    end;
    if ini.ValueExists('Server', 'IdleTimeoutSec') then
    begin
      optionalInt := ini.ReadInteger('Server', 'IdleTimeoutSec', -1);
      if (optionalInt < 0) then
      begin
        raise EclHttpTunnelConfigError.Create('Invalid [Server] IdleTimeoutSec');
      end;
      AServer.IdleTimeoutSec := optionalInt;
    end;
    if ini.ValueExists('Server', 'BufferSizeBytes') then
    begin
      optionalInt := ini.ReadInteger('Server', 'BufferSizeBytes', -1);
      if (optionalInt < 1) then
      begin
        raise EclHttpTunnelConfigError.Create('Invalid [Server] BufferSizeBytes');
      end;
      AServer.BatchSize := optionalInt;
    end;
    if ini.ValueExists('Server', 'MaxHeaderSizeBytes') then
    begin
      optionalInt := ini.ReadInteger('Server', 'MaxHeaderSizeBytes', -1);
      if (optionalInt < 1) then
      begin
        raise EclHttpTunnelConfigError.Create('Invalid [Server] MaxHeaderSizeBytes');
      end;
      AServer.MaxHeaderSizeBytes := optionalInt;
    end;
    if ini.ValueExists('Server', 'MaxConnectionsPerIP') then
    begin
      optionalInt := ini.ReadInteger('Server', 'MaxConnectionsPerIP', -1);
      if (optionalInt < 0) then
      begin
        raise EclHttpTunnelConfigError.Create('Invalid [Server] MaxConnectionsPerIP');
      end;
      AServer.MaxConnectionsPerIP := optionalInt;
    end;
    if ini.ValueExists('Server', 'RelayMaxThreadCount') then
    begin
      optionalInt := ini.ReadInteger('Server', 'RelayMaxThreadCount', -1);
      if (optionalInt < 2) then
      begin
        raise EclHttpTunnelConfigError.Create('Invalid [Server] RelayMaxThreadCount');
      end;
      AServer.RelayMaxThreadCount := optionalInt;
    end;
  finally
    ports.Free();
    hosts.Free();
    ini.Free();
  end;
end;

end.

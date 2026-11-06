{
  CleverHttpTunnel
  Copyright (C) 2026 Clever Components
  All Rights Reserved
  www.CleverComponents.com
}

unit clHttpTunnelServerTests;

interface

{$I clVer.inc}

uses
  SysUtils, Classes, Windows,
  DUnitX.TestFramework,
  clHttpTunnelServer, clHttp, clHttpProxy, clSocket, clSocketUtils;

type
  [TestFixture]
  TclHttpTunnelServerTests = class
  private
    procedure ConfigureSmokeAllowlist(AServer: TclHttpTunnelServer);
    function StartLocalServer(AServer: TclHttpTunnelServer): TclHttp;
    procedure ExpectProxyStatus(AHttp: TclHttp; AExpectedCode: Integer);
    function OpenRawProxyClient: TclTcpClientConnection;
    function ReadProxyStatusCode(AClient: TclTcpClientConnection): Integer;
  public
    [Test]
    procedure TestStartStop;
    [Test]
    procedure TestConnect;
    [Test]
    procedure TestAllowlistEmptyDenies;
    [Test]
    procedure TestAllowlistHostMissDenies;
    [Test]
    procedure TestAllowlistPortMissDenies;
    [Test]
    procedure TestAllowlistHostCaseInsensitive;
    [Test]
    procedure TestHeaderTooLargeReturns431;
    [Test]
    procedure TestRequestTimeoutReturns408;
    [Test]
    procedure TestOutboundRefusedReturns502;
    [Test]
    procedure TestConnectTimeoutReturns504;
    [Test]
    procedure TestMaxConnectionsPerIPReturns503;
  end;

implementation

{$IFDEF LOGGER}
uses
  clLogger;
{$ENDIF}

const
  cSmokeHost = 'www.microsoft.com';
  cSmokeUrl = 'https://www.microsoft.com/robots.txt';
  cRefusedHost = '127.0.0.1';
  cRefusedPort = 59999;

{ TclHttpTunnelServerTests }

procedure TclHttpTunnelServerTests.ConfigureSmokeAllowlist(AServer: TclHttpTunnelServer);
begin
  AServer.AllowedHosts.Clear();
  AServer.AllowedHosts.Add(cSmokeHost);
  AServer.AllowedPorts.Clear();
  AServer.AllowedPorts.Add('443');
end;

function TclHttpTunnelServerTests.StartLocalServer(AServer: TclHttpTunnelServer): TclHttp;
begin
  AServer.Port := 2110;
  AServer.LocalBinding := '127.0.0.1';
  AServer.Start();
  Sleep(200);
  Assert.IsTrue(AServer.Active);

  Result := TclHttp.Create(nil);
  Result.TimeOut := 30000;
  Result.ProxySettings.Server := '127.0.0.1';
  Result.ProxySettings.Port := 2110;
end;

procedure TclHttpTunnelServerTests.ExpectProxyStatus(AHttp: TclHttp; AExpectedCode: Integer);
begin
  try
    AHttp.Get(cSmokeUrl);
    Assert.Fail(Format('Expected EclHttpProxyError %d', [AExpectedCode]));
  except
    on E: EclHttpProxyError do
    begin
      Assert.AreEqual(AExpectedCode, E.ErrorCode);
    end;
  end;
end;

function TclHttpTunnelServerTests.OpenRawProxyClient: TclTcpClientConnection;
begin
  Result := TclTcpClientConnection.Create();
  Result.NetworkStream := TclNetworkStream.Create();
  Result.DisableGuiProcessing := True;
  Result.TimeOut := 15000;
  Result.Open('127.0.0.1', 2110);
end;

function TclHttpTunnelServerTests.ReadProxyStatusCode(AClient: TclTcpClientConnection): Integer;
var
  response, statusLine: string;
  lineEnd, sp1, sp2: Integer;
  codeText: string;
begin
  AClient.IsReadUntilClose := True;
  response := AClient.ReadString();
  Assert.IsTrue(response <> '', 'Empty proxy response');

  lineEnd := Pos(#13#10, response);
  if (lineEnd > 0) then
  begin
    statusLine := Copy(response, 1, lineEnd - 1);
  end else
  begin
    statusLine := Trim(response);
  end;

  sp1 := Pos(' ', statusLine);
  Assert.IsTrue(sp1 > 0, 'Malformed status line: ' + statusLine);
  sp2 := Pos(' ', Copy(statusLine, sp1 + 1, MaxInt));
  if (sp2 > 0) then
  begin
    codeText := Copy(statusLine, sp1 + 1, sp2 - 1);
  end else
  begin
    codeText := Trim(Copy(statusLine, sp1 + 1, MaxInt));
  end;
  Result := StrToIntDef(codeText, -1);
  Assert.AreNotEqual(-1, Result, 'Non-numeric status: ' + statusLine);
end;

procedure TclHttpTunnelServerTests.TestStartStop;
var
  server: TclHttpTunnelServer;
begin
  server := nil;
  try
    server := TclHttpTunnelServer.Create(nil);
    Assert.AreEqual(8080, server.Port);
    Assert.AreEqual(DefaultMaxHeaderSizeBytes, server.MaxHeaderSizeBytes);
    Assert.AreEqual(DefaultBatchSizeBytes, server.BatchSize);
    Assert.AreEqual(DefaultRequestTimeoutSec, server.RequestTimeoutSec);
    Assert.AreEqual(DefaultConnectTimeoutSec, server.ConnectTimeoutSec);
    Assert.AreEqual(DefaultIdleTimeoutSec, server.IdleTimeoutSec);
    Assert.AreEqual(DefaultMaxConnectionsPerIP, server.MaxConnectionsPerIP);
    Assert.AreEqual(DefaultRelayMaxThreadCount, server.RelayMaxThreadCount);
    Assert.AreEqual(0, server.AllowedHosts.Count);
    Assert.AreEqual(0, server.AllowedPorts.Count);

    server.Port := 2110;
    server.LocalBinding := '127.0.0.1';
    Assert.AreEqual(2110, server.Port);
    Assert.AreEqual('127.0.0.1', server.LocalBinding);

    server.Start();
    Sleep(100);
    server.Stop();

    server.Start();
    try
      Assert.IsTrue(server.Active);
      Sleep(100);
    finally
      server.Stop();
    end;
    Assert.IsFalse(server.Active);
  finally
    server.Free();
  end;
end;

procedure TclHttpTunnelServerTests.TestConnect;
var
  server: TclHttpTunnelServer;
  http: TclHttp;
  body: string;
begin
  server := nil;
  http := nil;
  try
    server := TclHttpTunnelServer.Create(nil);
    ConfigureSmokeAllowlist(server);
    http := StartLocalServer(server);
    try
{$IFDEF LOGGER}clPutLogMessage(http, edInside, 'TestConnect GET via proxy');{$ENDIF}
      body := http.Get(cSmokeUrl);
{$IFDEF LOGGER}clPutLogMessage(http, edInside, 'TestConnect body length ' + IntToStr(Length(body)));{$ENDIF}

      Assert.IsTrue(Pos('User-agent', body) > 0, 'Unexpected body: ' + Copy(body, 1, 200));
    finally
      server.Stop();
    end;
  finally
    http.Free();
    server.Free();
  end;
end;

procedure TclHttpTunnelServerTests.TestAllowlistEmptyDenies;
var
  server: TclHttpTunnelServer;
  http: TclHttp;
begin
  server := nil;
  http := nil;
  try
    server := TclHttpTunnelServer.Create(nil);
    http := StartLocalServer(server);
    try
      ExpectProxyStatus(http, 403);
    finally
      server.Stop();
    end;
  finally
    http.Free();
    server.Free();
  end;
end;

procedure TclHttpTunnelServerTests.TestAllowlistHostMissDenies;
var
  server: TclHttpTunnelServer;
  http: TclHttp;
begin
  server := nil;
  http := nil;
  try
    server := TclHttpTunnelServer.Create(nil);
    server.AllowedHosts.Add('denied.example');
    server.AllowedPorts.Add('443');
    http := StartLocalServer(server);
    try
      ExpectProxyStatus(http, 403);
    finally
      server.Stop();
    end;
  finally
    http.Free();
    server.Free();
  end;
end;

procedure TclHttpTunnelServerTests.TestAllowlistPortMissDenies;
var
  server: TclHttpTunnelServer;
  http: TclHttp;
begin
  server := nil;
  http := nil;
  try
    server := TclHttpTunnelServer.Create(nil);
    server.AllowedHosts.Add(cSmokeHost);
    server.AllowedPorts.Add('80');
    http := StartLocalServer(server);
    try
      ExpectProxyStatus(http, 403);
    finally
      server.Stop();
    end;
  finally
    http.Free();
    server.Free();
  end;
end;

procedure TclHttpTunnelServerTests.TestAllowlistHostCaseInsensitive;
var
  server: TclHttpTunnelServer;
  http: TclHttp;
  body: string;
begin
  server := nil;
  http := nil;
  try
    server := TclHttpTunnelServer.Create(nil);
    server.AllowedHosts.Add('WWW.MICROSOFT.COM');
    server.AllowedPorts.Add('443');
    http := StartLocalServer(server);
    try
      body := http.Get(cSmokeUrl);
      Assert.IsTrue(Pos('User-agent', body) > 0, 'Unexpected body: ' + Copy(body, 1, 200));
    finally
      server.Stop();
    end;
  finally
    http.Free();
    server.Free();
  end;
end;

procedure TclHttpTunnelServerTests.TestHeaderTooLargeReturns431;
var
  server: TclHttpTunnelServer;
  client: TclTcpClientConnection;
  payload: string;
  statusCode: Integer;
begin
  server := nil;
  client := nil;
  try
    server := TclHttpTunnelServer.Create(nil);
    server.MaxHeaderSizeBytes := 64;
    server.Port := 2110;
    server.LocalBinding := '127.0.0.1';
    server.Start();
    Sleep(200);

    client := OpenRawProxyClient();
    payload := 'CONNECT example.com:443 HTTP/1.1'#13#10
      + 'Host: example.com:443'#13#10
      + 'X-Padding: ' + StringOfChar('A', 128) + #13#10
      + #13#10;
    client.WriteString(payload);
    statusCode := ReadProxyStatusCode(client);
    Assert.AreEqual(431, statusCode);
  finally
    if (client <> nil) then
    begin
      try
        client.Close(False);
      except
        on EclSocketError do;
      end;
      client.Free();
    end;
    if (server <> nil) then
    begin
      server.Stop();
      server.Free();
    end;
  end;
end;

procedure TclHttpTunnelServerTests.TestRequestTimeoutReturns408;
var
  server: TclHttpTunnelServer;
  client: TclTcpClientConnection;
  statusCode: Integer;
begin
  server := nil;
  client := nil;
  try
    server := TclHttpTunnelServer.Create(nil);
    server.RequestTimeoutSec := 1;
    server.Port := 2110;
    server.LocalBinding := '127.0.0.1';
    server.Start();
    Sleep(200);

    client := OpenRawProxyClient();
    client.WriteString('CONNECT ');
    client.TimeOut := 5000;
    statusCode := ReadProxyStatusCode(client);
    Assert.AreEqual(408, statusCode);
  finally
    if (client <> nil) then
    begin
      try
        client.Close(False);
      except
        on EclSocketError do;
      end;
      client.Free();
    end;
    if (server <> nil) then
    begin
      server.Stop();
      server.Free();
    end;
  end;
end;

procedure TclHttpTunnelServerTests.TestOutboundRefusedReturns502;
var
  server: TclHttpTunnelServer;
  http: TclHttp;
begin
  server := nil;
  http := nil;
  try
    server := TclHttpTunnelServer.Create(nil);
    server.AllowedHosts.Add(cRefusedHost);
    server.AllowedPorts.Add(IntToStr(cRefusedPort));
    http := StartLocalServer(server);
    try
      try
        http.Get(Format('https://%s:%d/', [cRefusedHost, cRefusedPort]));
        Assert.Fail('Expected EclHttpProxyError 502');
      except
        on E: EclHttpProxyError do
        begin
          Assert.AreEqual(502, E.ErrorCode);
        end;
      end;
    finally
      server.Stop();
    end;
  finally
    http.Free();
    server.Free();
  end;
end;

procedure TclHttpTunnelServerTests.TestConnectTimeoutReturns504;
var
  server: TclHttpTunnelServer;
  listener: TclTcpListenConnection;
  filler, client: TclTcpClientConnection;
  listenPort, statusCode: Integer;
begin
  server := nil;
  listener := nil;
  filler := nil;
  client := nil;
  try
    server := TclHttpTunnelServer.Create(nil);
    server.ConnectTimeoutSec := 2;
    server.Port := 2110;
    server.LocalBinding := '127.0.0.1';
    server.Start();
    Sleep(200);

    listener := TclTcpListenConnection.Create();
    listener.NetworkStream := TclNetworkStream.Create();
    listener.LocalBinding := '127.0.0.1';
    listener.UseIpV6 := False;
    listenPort := listener.Listen(0);
    Assert.IsTrue(listenPort > 0);

    filler := TclTcpClientConnection.Create();
    filler.NetworkStream := TclNetworkStream.Create();
    filler.DisableGuiProcessing := True;
    filler.TimeOut := 2000;
    filler.Open('127.0.0.1', listenPort);

    server.AllowedHosts.Clear();
    server.AllowedHosts.Add('127.0.0.1');
    server.AllowedPorts.Clear();
    server.AllowedPorts.Add(IntToStr(listenPort));

    client := OpenRawProxyClient();
    client.TimeOut := 10000;
    client.WriteString(Format('CONNECT 127.0.0.1:%d HTTP/1.1'#13#10#13#10, [listenPort]));
    statusCode := ReadProxyStatusCode(client);
    Assert.AreEqual(504, statusCode);
  finally
    if (client <> nil) then
    begin
      try
        client.Close(False);
      except
        on EclSocketError do;
      end;
      client.Free();
    end;
    if (filler <> nil) then
    begin
      try
        filler.Abort();
        filler.Close(False);
      except
        on EclSocketError do;
      end;
      filler.Free();
    end;
    if (listener <> nil) then
    begin
      try
        listener.Close(False);
      except
        on EclSocketError do;
      end;
      listener.Free();
    end;
    if (server <> nil) then
    begin
      server.Stop();
      server.Free();
    end;
  end;
end;

procedure TclHttpTunnelServerTests.TestMaxConnectionsPerIPReturns503;
var
  server: TclHttpTunnelServer;
  holder, client: TclTcpClientConnection;
  statusCode: Integer;
begin
  server := nil;
  holder := nil;
  client := nil;
  try
    server := TclHttpTunnelServer.Create(nil);
    server.MaxConnectionsPerIP := 1;
    server.Port := 2110;
    server.LocalBinding := '127.0.0.1';
    server.Start();
    Sleep(200);

    holder := OpenRawProxyClient();
    Sleep(100);

    client := OpenRawProxyClient();
    statusCode := ReadProxyStatusCode(client);
    Assert.AreEqual(503, statusCode);
  finally
    if (client <> nil) then
    begin
      try
        client.Close(False);
      except
        on EclSocketError do;
      end;
      client.Free();
    end;
    if (holder <> nil) then
    begin
      try
        holder.Close(False);
      except
        on EclSocketError do;
      end;
      holder.Free();
    end;
    if (server <> nil) then
    begin
      server.Stop();
      server.Free();
    end;
  end;
end;

initialization
{$IFDEF LOGGER}
  TclLogger.Instance().InitLogMessage(
    ExpandFileName(ExtractFilePath(ParamStr(0)) + 'tunnel-tests.log'));
{$ENDIF}
  TDUnitX.RegisterTestFixture(TclHttpTunnelServerTests);

end.

{
  CleverHttpTunnel
  Copyright (C) 2026 Clever Components
  All Rights Reserved
  www.CleverComponents.com
}

unit clHttpTunnelServer;

interface

{$I clVer.inc}

uses
{$IFNDEF DELPHIXE2}
  Classes, SysUtils, SyncObjs, Windows, WinSock,
{$ELSE}
  System.Classes, System.SysUtils, System.SyncObjs, Winapi.Windows, Winapi.WinSock,
{$ENDIF}
  clTcpServer, clSocket, clThreadPool, clSocketUtils;

const
  DefaultMaxHeaderSizeBytes = 1024;
  DefaultBatchSizeBytes = 16384;
  DefaultRequestTimeoutSec = 10;
  DefaultConnectTimeoutSec = 10;
  DefaultIdleTimeoutSec = 300;
  DefaultMaxConnectionsPerIP = 30;
  DefaultRelayMaxThreadCount = 10;

  HttpReasonBadRequest = 'Bad Request';
  HttpReasonMethodNotAllowed = 'Method Not Allowed';
  HttpReasonForbidden = 'Forbidden';
  HttpReasonRequestTimeout = 'Request Timeout';
  HttpReasonHeaderTooLarge = 'Request Header Fields Too Large';
  HttpReasonBadGateway = 'Bad Gateway';
  HttpReasonServiceUnavailable = 'Service Unavailable';
  HttpReasonGatewayTimeout = 'Gateway Timeout';

type
  TclHttpTunnelConnection = class(TclUserConnection)
  private
    FRequestBuffer: TMemoryStream;
    FRelayQueue: TMemoryStream;
    FRelayQueueAccessor: TCriticalSection;
    FRelayDataEvent: THandle;
    FRequestPhaseDoneEvent: THandle;
    FDest: TclTcpClientConnection;
    FRelaying: Boolean;
    FRelayActive: Boolean;
    FIpLimitCounted: Boolean;
    FTargetHost: string;
    FTargetPort: Integer;
  protected
    procedure DoDestroy; override;
  public
    constructor Create;

    procedure EnqueueRelayData(AData: TStream);
    function DequeueRelayData(ADestination: TStream): Boolean;
    procedure SignalRelayStop;
    procedure SignalRequestPhaseDone;

    property RequestBuffer: TMemoryStream read FRequestBuffer;
    property Dest: TclTcpClientConnection read FDest write FDest;
    property Relaying: Boolean read FRelaying write FRelaying;
    property RelayActive: Boolean read FRelayActive write FRelayActive;
    property IpLimitCounted: Boolean read FIpLimitCounted write FIpLimitCounted;
    property RelayDataEvent: THandle read FRelayDataEvent;
    property RequestPhaseDoneEvent: THandle read FRequestPhaseDoneEvent;
    property TargetHost: string read FTargetHost write FTargetHost;
    property TargetPort: Integer read FTargetPort write FTargetPort;
  end;

  TclHttpTunnelResponseEvent = procedure(Sender: TObject; AConnection: TclUserConnection;
    AStatusCode: Integer; const ATargetHost: string; ATargetPort: Integer) of object;

  TclHttpTunnelServer = class(TclTcpServer)
  private
    FMaxHeaderSizeBytes: Integer;
    FRequestTimeoutSec: Integer;
    FConnectTimeoutSec: Integer;
    FIdleTimeoutSec: Integer;
    FMaxConnectionsPerIP: Integer;
    FRelayMaxThreadCount: Integer;
    FAllowedHosts: TStrings;
    FAllowedPorts: TStrings;
    FConnectionCounts: TStringList;
    FConnectionCountsAccessor: TCriticalSection;
    FRelayThreadPool: TclThreadPool;
    FTimeoutThreadPool: TclThreadPool;
    FOnTunnelResponse: TclHttpTunnelResponseEvent;

    procedure SetMaxHeaderSizeBytes(const Value: Integer);
    procedure SetRequestTimeoutSec(const Value: Integer);
    procedure SetConnectTimeoutSec(const Value: Integer);
    procedure SetIdleTimeoutSec(const Value: Integer);
    procedure SetMaxConnectionsPerIP(const Value: Integer);
    procedure SetRelayMaxThreadCount(const Value: Integer);
    procedure SetAllowedHosts(const Value: TStrings);
    procedure SetAllowedPorts(const Value: TStrings);
    procedure ApplyIdleTimeout;
    procedure DecrementConnectionsForIP(const AIP: string);
    function TryAcceptConnectionLimit(AConnection: TclHttpTunnelConnection): Boolean;
    procedure ScheduleRequestTimeout(AConnection: TclHttpTunnelConnection);
    procedure SendHttpStatus(AConnection: TclUserConnection; AStatusCode: Integer;
      const AReason: string); overload;
    procedure SendHttpStatus(AConnection: TclUserConnection; AStatusCode: Integer;
      const AReason, ATargetHost: string; ATargetPort: Integer); overload;
    procedure SendRawResponse(AConnection: TclUserConnection; const AResponse: string);
    procedure SilentClose(AConnection: TclUserConnection);
    function ExtractHeaderLength(ABuffer: TMemoryStream): Integer;
    function ParseConnectRequest(ABuffer: TMemoryStream; out AHost: string;
      out APort: Integer; out AHeaderLength: Integer): Integer;
    function NormalizeHost(const AHost: string): string;
    function IsDestinationAllowed(const AHost: string; APort: Integer): Boolean;
    procedure RejectHeaderTooLarge(AConnection: TclHttpTunnelConnection);
    procedure StartRelay(AConnection: TclHttpTunnelConnection);
    procedure ProcessConnectRequest(AConnection: TclHttpTunnelConnection);
    procedure HandleTunnelData(AConnection: TclHttpTunnelConnection; AData: TStream);
  protected
    procedure DoDestroy; override;
    function CreateDefaultConnection: TclUserConnection; override;
    procedure DoAcceptConnection(AConnection: TclUserConnection; var Handled: Boolean); override;
    procedure DoReadConnection(AConnection: TclUserConnection; AData: TStream); override;
    procedure DoCloseConnection(AConnection: TclUserConnection); override;
    procedure DoTunnelResponse(AConnection: TclUserConnection; AStatusCode: Integer;
      const ATargetHost: string; ATargetPort: Integer); virtual;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property MaxHeaderSizeBytes: Integer read FMaxHeaderSizeBytes write SetMaxHeaderSizeBytes
      default DefaultMaxHeaderSizeBytes;
    property RequestTimeoutSec: Integer read FRequestTimeoutSec write SetRequestTimeoutSec
      default DefaultRequestTimeoutSec;
    property ConnectTimeoutSec: Integer read FConnectTimeoutSec write SetConnectTimeoutSec
      default DefaultConnectTimeoutSec;
    property IdleTimeoutSec: Integer read FIdleTimeoutSec write SetIdleTimeoutSec
      default DefaultIdleTimeoutSec;
    property MaxConnectionsPerIP: Integer read FMaxConnectionsPerIP write SetMaxConnectionsPerIP
      default DefaultMaxConnectionsPerIP;
    property RelayMaxThreadCount: Integer read FRelayMaxThreadCount write SetRelayMaxThreadCount
      default DefaultRelayMaxThreadCount;
    property AllowedHosts: TStrings read FAllowedHosts write SetAllowedHosts;
    property AllowedPorts: TStrings read FAllowedPorts write SetAllowedPorts;
    property OnTunnelResponse: TclHttpTunnelResponseEvent read FOnTunnelResponse
      write FOnTunnelResponse;
  end;

implementation

uses
  clTranslator, clUtils, clWinSock2{$IFDEF LOGGER}, clLogger{$ENDIF};

type
  TclHttpTunnelRelayWorkItem = class(TclWorkItem)
  private
    FServer: TclHttpTunnelServer;
    FConnection: IclUserConnection_;
    procedure FlushClientToDest(AConnection: TclHttpTunnelConnection);
    procedure PumpDestToClient(AConnection: TclHttpTunnelConnection; AEnumEvents: Boolean);
    function OpenDestination(AConnection: TclHttpTunnelConnection): Integer;
  protected
    procedure Execute(AThread: TThread); override;
  public
    constructor Create(AServer: TclHttpTunnelServer; AConnection: IclUserConnection_);
  end;

  TclHttpTunnelRequestTimeoutWorkItem = class(TclWorkItem)
  private
    FServer: TclHttpTunnelServer;
    FConnection: IclUserConnection_;
  protected
    procedure Execute(AThread: TThread); override;
  public
    constructor Create(AServer: TclHttpTunnelServer; AConnection: IclUserConnection_);
  end;

const
  crlfcrlf: array[0..3] of Byte = (13, 10, 13, 10);

{ TclHttpTunnelConnection }

constructor TclHttpTunnelConnection.Create;
begin
  inherited Create();
  FRequestBuffer := TMemoryStream.Create();
  FRelayQueue := TMemoryStream.Create();
  FRelayQueueAccessor := TCriticalSection.Create();
  FRelayDataEvent := CreateEvent(nil, False, False, nil);
  FRequestPhaseDoneEvent := CreateEvent(nil, True, False, nil);
  FDest := nil;
  FRelaying := False;
  FRelayActive := False;
  FIpLimitCounted := False;
  FTargetHost := '';
  FTargetPort := 0;
end;

procedure TclHttpTunnelConnection.DoDestroy;
begin
  SignalRelayStop();
  SignalRequestPhaseDone();
  if (FDest <> nil) then
  begin
    try
      FDest.Abort();
      FDest.Close(False);
    except
      on EclSocketError do;
    end;
    FDest.Free();
    FDest := nil;
  end;
  if (FRequestPhaseDoneEvent <> 0) then
  begin
    CloseHandle(FRequestPhaseDoneEvent);
    FRequestPhaseDoneEvent := 0;
  end;
  if (FRelayDataEvent <> 0) then
  begin
    CloseHandle(FRelayDataEvent);
    FRelayDataEvent := 0;
  end;
  FRelayQueueAccessor.Free();
  FRelayQueue.Free();
  FRequestBuffer.Free();
  inherited DoDestroy();
end;

procedure TclHttpTunnelConnection.EnqueueRelayData(AData: TStream);
var
  count: Int64;
begin
  if (AData = nil) then Exit;
  count := AData.Size - AData.Position;
  if (count <= 0) then Exit;

  FRelayQueueAccessor.Enter();
  try
    FRelayQueue.Seek(0, soEnd);
    FRelayQueue.CopyFrom(AData, count);
  finally
    FRelayQueueAccessor.Leave();
  end;
  SetEvent(FRelayDataEvent);
end;

function TclHttpTunnelConnection.DequeueRelayData(ADestination: TStream): Boolean;
var
  count: Int64;
begin
  Result := False;
  if (ADestination = nil) then Exit;

  FRelayQueueAccessor.Enter();
  try
    count := FRelayQueue.Size;
    if (count <= 0) then
    begin
      FRelayQueue.Position := 0;
      Exit;
    end;
    FRelayQueue.Position := 0;
    ADestination.CopyFrom(FRelayQueue, count);
    FRelayQueue.Size := 0;
    FRelayQueue.Position := 0;
    Result := True;
  finally
    FRelayQueueAccessor.Leave();
  end;
end;

procedure TclHttpTunnelConnection.SignalRelayStop;
begin
  FRelayActive := False;
  if (FRelayDataEvent <> 0) then
  begin
    SetEvent(FRelayDataEvent);
  end;
  if (FDest <> nil) then
  begin
    try
      FDest.Abort();
    except
      on EclSocketError do;
    end;
  end;
end;

procedure TclHttpTunnelConnection.SignalRequestPhaseDone;
begin
  if (FRequestPhaseDoneEvent <> 0) then
  begin
    SetEvent(FRequestPhaseDoneEvent);
  end;
end;

{ TclHttpTunnelRequestTimeoutWorkItem }

constructor TclHttpTunnelRequestTimeoutWorkItem.Create(AServer: TclHttpTunnelServer;
  AConnection: IclUserConnection_);
begin
  inherited Create();
  FServer := AServer;
  FConnection := AConnection;
end;

procedure TclHttpTunnelRequestTimeoutWorkItem.Execute(AThread: TThread);
var
  conn: TclHttpTunnelConnection;
  timeoutMs: Integer;
  waitResult: DWORD;
begin
  Assert(FConnection <> nil);
  conn := FConnection.Connection as TclHttpTunnelConnection;
  try
    timeoutMs := FServer.RequestTimeoutSec * 1000;
    if (timeoutMs < 1) then
    begin
      Exit;
    end;

    waitResult := WaitForSingleObject(conn.RequestPhaseDoneEvent, DWORD(timeoutMs));
    if (waitResult = WAIT_TIMEOUT) and conn.Active and (not conn.Relaying) then
    begin
{$IFDEF LOGGER}clPutLogMessage(FServer, edInside, 'request timeout 408');{$ENDIF}
      FServer.SendHttpStatus(conn, 408, HttpReasonRequestTimeout);
      FServer.SilentClose(conn);
    end;
  finally
    FConnection := nil;
  end;
end;

{ TclHttpTunnelRelayWorkItem }

constructor TclHttpTunnelRelayWorkItem.Create(AServer: TclHttpTunnelServer;
  AConnection: IclUserConnection_);
begin
  inherited Create();
  FServer := AServer;
  FConnection := AConnection;
end;

function TclHttpTunnelRelayWorkItem.OpenDestination(AConnection: TclHttpTunnelConnection): Integer;
var
  dest: TclTcpClientConnection;
  ip: string;
  connectTimeoutMs: Integer;
begin
  dest := TclTcpClientConnection.Create();
  try
    dest.NetworkStream := TclNetworkStream.Create();
    dest.BatchSize := FServer.BatchSize;
    dest.BitsPerSec := FServer.BitsPerSec;
    dest.UseIpV6 := False;
    dest.DisableGuiProcessing := True;

    if (FServer.ConnectTimeoutSec > 0) then
    begin
      connectTimeoutMs := FServer.ConnectTimeoutSec * 1000;
      dest.ConnectTimeOut := connectTimeoutMs;
      dest.TimeOut := connectTimeoutMs;
    end else
    begin
      dest.ConnectTimeOut := 0;
      dest.TimeOut := -1;
    end;

{$IFDEF LOGGER}clPutLogMessage(FServer, edInside, 'resolve ' + AConnection.TargetHost);{$ENDIF}
    ip := TclHostResolver.GetIPAddress(AConnection.TargetHost, False);
{$IFDEF LOGGER}clPutLogMessage(FServer, edInside, 'open ' + ip + ':' + IntToStr(AConnection.TargetPort));{$ENDIF}
    dest.Open(ip, AConnection.TargetPort);
{$IFDEF LOGGER}clPutLogMessage(FServer, edInside, 'open ok');{$ENDIF}

    AConnection.Dest := dest;
    dest := nil;
    Result := 0;
  except
    on E: EclSocketError do
    begin
{$IFDEF LOGGER}clPutLogMessage(FServer, edInside, 'open fail', E);{$ENDIF}
      if (E.ErrorCode = TimeoutOccurredCode) then
      begin
        Result := 504;
      end else
      begin
        Result := 502;
      end;
      try
        dest.Abort();
      except
        on EclSocketError do;
      end;
      dest.Free();
    end;
    on E: Exception do
    begin
{$IFDEF LOGGER}clPutLogMessage(FServer, edInside, 'open fail', E);{$ENDIF}
      Result := 502;
      try
        dest.Abort();
      except
        on EclSocketError do;
      end;
      dest.Free();
    end;
  end;
end;

procedure TclHttpTunnelRelayWorkItem.FlushClientToDest(AConnection: TclHttpTunnelConnection);
var
  data: TMemoryStream;
  networkEvents: TWSANetworkEvents;
  waitResult: DWORD;
begin
  if (AConnection.Dest = nil) or (not AConnection.Dest.Active) then Exit;

  data := TMemoryStream.Create();
  try
    if not AConnection.DequeueRelayData(data) then Exit;
{$IFDEF LOGGER}clPutLogMessage(FServer, edInside, Format('flush client->dest bytes=%d',
      [Integer(data.Size)]));{$ENDIF}
    data.Position := 0;
    while (data.Position < data.Size) and AConnection.RelayActive and AConnection.Dest.Active do
    begin
      if AConnection.Dest.NetworkStream.Write(data) then Break;

      waitResult := WaitForSingleObject(AConnection.Dest.SocketEvent, 1000);
      if (waitResult <> WAIT_OBJECT_0) then Break;

      if (WSAEnumNetworkEvents(AConnection.Dest.Socket.Socket, AConnection.Dest.SocketEvent,
        @networkEvents) = SOCKET_ERROR) then
      begin
        Break;
      end;
      if ((networkEvents.lNetworkEvents and FD_CLOSE) <> 0) then
      begin
        AConnection.SignalRelayStop();
        Break;
      end;
      if ((networkEvents.lNetworkEvents and FD_READ) <> 0) then
      begin
        AConnection.Dest.NetworkStream.HasReadData := True;
        PumpDestToClient(AConnection, False);
      end;
    end;
  finally
    data.Free();
  end;
end;

procedure TclHttpTunnelRelayWorkItem.PumpDestToClient(AConnection: TclHttpTunnelConnection;
  AEnumEvents: Boolean);
var
  data: TMemoryStream;
  networkEvents: TWSANetworkEvents;
begin
  if (AConnection.Dest = nil) or (not AConnection.Dest.Active) then Exit;

  if AEnumEvents then
  begin
    if (WSAEnumNetworkEvents(AConnection.Dest.Socket.Socket, AConnection.Dest.SocketEvent,
      @networkEvents) = SOCKET_ERROR) then
    begin
      AConnection.SignalRelayStop();
      Exit;
    end;
    if ((networkEvents.lNetworkEvents and FD_CLOSE) <> 0) then
    begin
      AConnection.SignalRelayStop();
    end;
    if ((networkEvents.lNetworkEvents and FD_READ) <> 0) then
    begin
      AConnection.Dest.NetworkStream.HasReadData := True;
    end;
  end;

  if (not AConnection.Dest.NetworkStream.HasReadData)
    and (not AEnumEvents) then
  begin
    { opportunistic non-blocking drain }
  end;

  data := TMemoryStream.Create();
  try
    AConnection.Dest.NetworkStream.HasReadData := False;
    if (not AConnection.Dest.NetworkStream.Read(data))
      and (WSAGetLastError() <> WSAEWOULDBLOCK)
      and (data.Size = 0) then
    begin
      AConnection.SignalRelayStop();
      Exit;
    end;
    if AConnection.Dest.NeedClose and (data.Size = 0) then
    begin
      AConnection.SignalRelayStop();
    end;
    if (data.Size > 0) then
    begin
{$IFDEF LOGGER}clPutLogMessage(FServer, edInside, Format('pump dest->client bytes=%d',
        [Integer(data.Size)]));{$ENDIF}
      data.Position := 0;
      AConnection.WriteData(data);
      FServer.WriteData(AConnection, nil);
    end;
  finally
    data.Free();
  end;
end;

procedure TclHttpTunnelRelayWorkItem.Execute(AThread: TThread);
var
  conn: TclHttpTunnelConnection;
  events: array[0..1] of THandle;
  waitResult: DWORD;
  openStatus: Integer;
begin
  Assert(FConnection <> nil);
  conn := FConnection.Connection as TclHttpTunnelConnection;
  try
    try
{$IFDEF LOGGER}clPutLogMessage(FServer, edEnter, 'RelayWorkItem');{$ENDIF}
      openStatus := OpenDestination(conn);
      if (openStatus <> 0) then
      begin
{$IFDEF LOGGER}clPutLogMessage(FServer, edInside, 'RelayWorkItem open failed');{$ENDIF}
        if (openStatus = 504) then
        begin
          FServer.SendHttpStatus(conn, 504, HttpReasonGatewayTimeout,
            conn.TargetHost, conn.TargetPort);
        end else
        begin
          FServer.SendHttpStatus(conn, 502, HttpReasonBadGateway,
            conn.TargetHost, conn.TargetPort);
        end;
        FServer.WriteData(conn, nil);
        FServer.SilentClose(conn);
        Exit;
      end;

{$IFDEF LOGGER}clPutLogMessage(FServer, edInside, 'send 200');{$ENDIF}
      FServer.SendRawResponse(conn, 'HTTP/1.1 200 Connection Established'#13#10#13#10);
      FServer.DoTunnelResponse(conn, 200, conn.TargetHost, conn.TargetPort);
      FServer.WriteData(conn, nil);
{$IFDEF LOGGER}clPutLogMessage(FServer, edInside, 'send 200 done');{$ENDIF}

      events[0] := conn.RelayDataEvent;
      events[1] := conn.Dest.SocketEvent;

      while conn.RelayActive and conn.Active and (conn.Dest <> nil) and conn.Dest.Active do
      begin
        FlushClientToDest(conn);
        if (not conn.RelayActive) then Break;

        waitResult := WaitForMultipleObjects(2, @events[0], False, 50);
        if (not conn.RelayActive) then Break;

        if (waitResult = WAIT_OBJECT_0) then
        begin
          FlushClientToDest(conn);
        end else
        if (waitResult = WAIT_OBJECT_0 + 1) then
        begin
          PumpDestToClient(conn, True);
        end else
        if (waitResult = WAIT_TIMEOUT) then
        begin
          PumpDestToClient(conn, False);
        end else
        begin
          Break;
        end;
      end;
    except
      on E: EclSocketError do
      begin
{$IFDEF LOGGER}clPutLogMessage(FServer, edInside, 'RelayWorkItem socket error', E);{$ENDIF}
      end;
      on E: Exception do
      begin
{$IFDEF LOGGER}clPutLogMessage(FServer, edInside, 'RelayWorkItem error', E);{$ENDIF}
        if (FServer <> nil) then
        begin
          FServer.DoServerError(conn, E);
        end;
      end;
    end;
{$IFDEF LOGGER}clPutLogMessage(FServer, edLeave, 'RelayWorkItem');{$ENDIF}
  finally
    conn.RelayActive := False;
    conn.Relaying := False;
    try
      if (conn.Dest <> nil) then
      begin
        conn.Dest.Close(False);
      end;
    except
      on EclSocketError do;
    end;
    if conn.Active then
    begin
      FServer.CloseConnection(conn);
    end;
    FConnection := nil;
  end;
end;

{ TclHttpTunnelServer }

constructor TclHttpTunnelServer.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Port := 8080;
  BatchSize := DefaultBatchSizeBytes;
  FMaxHeaderSizeBytes := DefaultMaxHeaderSizeBytes;
  FRequestTimeoutSec := DefaultRequestTimeoutSec;
  FConnectTimeoutSec := DefaultConnectTimeoutSec;
  FIdleTimeoutSec := DefaultIdleTimeoutSec;
  FMaxConnectionsPerIP := DefaultMaxConnectionsPerIP;
  FRelayMaxThreadCount := DefaultRelayMaxThreadCount;
  ApplyIdleTimeout();
  FAllowedHosts := TStringList.Create();
  FAllowedPorts := TStringList.Create();
  FConnectionCounts := TStringList.Create();
  FConnectionCounts.Sorted := True;
  FConnectionCounts.Duplicates := dupIgnore;
  FConnectionCountsAccessor := TCriticalSection.Create();
  FRelayThreadPool := TclThreadPool.Create(nil);
  FRelayThreadPool.MinThreadCount := 1;
  FRelayThreadPool.MaxThreadCount := FRelayMaxThreadCount;
  FTimeoutThreadPool := TclThreadPool.Create(nil);
  FTimeoutThreadPool.MinThreadCount := 1;
  FTimeoutThreadPool.MaxThreadCount := 10;
end;

procedure TclHttpTunnelServer.DoDestroy;
begin
  if (FTimeoutThreadPool <> nil) then
  begin
    FTimeoutThreadPool.Stop();
    FTimeoutThreadPool.Free();
    FTimeoutThreadPool := nil;
  end;
  if (FRelayThreadPool <> nil) then
  begin
    FRelayThreadPool.Stop();
    FRelayThreadPool.Free();
    FRelayThreadPool := nil;
  end;
  FConnectionCountsAccessor.Free();
  FConnectionCounts.Free();
  FAllowedPorts.Free();
  FAllowedHosts.Free();
  inherited DoDestroy();
end;

function TclHttpTunnelServer.CreateDefaultConnection: TclUserConnection;
begin
  Result := TclHttpTunnelConnection.Create();
end;

procedure TclHttpTunnelServer.ApplyIdleTimeout;
begin
  if (FIdleTimeoutSec > 0) then
  begin
    SessionTimeOut := FIdleTimeoutSec * 1000;
  end else
  begin
    SessionTimeOut := 0;
  end;
end;

procedure TclHttpTunnelServer.SetMaxHeaderSizeBytes(const Value: Integer);
begin
  if (Value > 0) then
  begin
    FMaxHeaderSizeBytes := Value;
  end;
end;

procedure TclHttpTunnelServer.SetRequestTimeoutSec(const Value: Integer);
begin
  if (Value >= 0) then
  begin
    FRequestTimeoutSec := Value;
  end;
end;

procedure TclHttpTunnelServer.SetConnectTimeoutSec(const Value: Integer);
begin
  if (Value >= 0) then
  begin
    FConnectTimeoutSec := Value;
  end;
end;

procedure TclHttpTunnelServer.SetIdleTimeoutSec(const Value: Integer);
begin
  if (Value >= 0) then
  begin
    FIdleTimeoutSec := Value;
    ApplyIdleTimeout();
  end;
end;

procedure TclHttpTunnelServer.SetAllowedHosts(const Value: TStrings);
begin
  FAllowedHosts.Assign(Value);
end;

procedure TclHttpTunnelServer.SetAllowedPorts(const Value: TStrings);
begin
  FAllowedPorts.Assign(Value);
end;

procedure TclHttpTunnelServer.SetMaxConnectionsPerIP(const Value: Integer);
begin
  if (Value >= 0) then
  begin
    FMaxConnectionsPerIP := Value;
  end;
end;

procedure TclHttpTunnelServer.SetRelayMaxThreadCount(const Value: Integer);
begin
  if (Value > 1) then
  begin
    FRelayMaxThreadCount := Value;
    FRelayThreadPool.MaxThreadCount := Value;
  end;
end;

procedure TclHttpTunnelServer.DecrementConnectionsForIP(const AIP: string);
var
  i, count: Integer;
begin
  FConnectionCountsAccessor.Enter();
  try
    i := FConnectionCounts.IndexOf(AIP);
    if (i < 0) then
    begin
      Exit;
    end;
    count := Integer(FConnectionCounts.Objects[i]) - 1;
    if (count <= 0) then
    begin
      FConnectionCounts.Delete(i);
    end else
    begin
      FConnectionCounts.Objects[i] := TObject(count);
    end;
  finally
    FConnectionCountsAccessor.Leave();
  end;
end;

function TclHttpTunnelServer.TryAcceptConnectionLimit(
  AConnection: TclHttpTunnelConnection): Boolean;
var
  peerIP: string;
  i, count: Integer;
begin
  Result := True;
  if (FMaxConnectionsPerIP < 1) then
  begin
    Exit;
  end;

  peerIP := AConnection.PeerIP;
  FConnectionCountsAccessor.Enter();
  try
    i := FConnectionCounts.IndexOf(peerIP);
    if (i < 0) then
    begin
      count := 0;
    end else
    begin
      count := Integer(FConnectionCounts.Objects[i]);
    end;
    if (count >= FMaxConnectionsPerIP) then
    begin
      Result := False;
      Exit;
    end;
    Inc(count);
    if (i < 0) then
    begin
      FConnectionCounts.AddObject(peerIP, TObject(count));
    end else
    begin
      FConnectionCounts.Objects[i] := TObject(count);
    end;
    AConnection.IpLimitCounted := True;
  finally
    FConnectionCountsAccessor.Leave();
  end;
end;

procedure TclHttpTunnelServer.ScheduleRequestTimeout(AConnection: TclHttpTunnelConnection);
begin
  if (FRequestTimeoutSec < 1) or (AConnection = nil) then
  begin
    Exit;
  end;
  FTimeoutThreadPool.QueueWorkItem(
    TclHttpTunnelRequestTimeoutWorkItem.Create(Self, IclUserConnection_(AConnection)));
end;

procedure TclHttpTunnelServer.DoAcceptConnection(AConnection: TclUserConnection;
  var Handled: Boolean);
var
  tunnelConn: TclHttpTunnelConnection;
begin
  inherited DoAcceptConnection(AConnection, Handled);
  if not (AConnection is TclHttpTunnelConnection) then
  begin
    Exit;
  end;

  tunnelConn := TclHttpTunnelConnection(AConnection);
  if not TryAcceptConnectionLimit(tunnelConn) then
  begin
    SendHttpStatus(tunnelConn, 503, HttpReasonServiceUnavailable);
    SilentClose(tunnelConn);
    Exit;
  end;

  ScheduleRequestTimeout(tunnelConn);
end;

function TclHttpTunnelServer.NormalizeHost(const AHost: string): string;
begin
  Result := Trim(AHost);
  if (Length(Result) > 0) and (Result[Length(Result)] = '.') then
  begin
    SetLength(Result, Length(Result) - 1);
  end;
end;

function TclHttpTunnelServer.IsDestinationAllowed(const AHost: string; APort: Integer): Boolean;
var
  i, allowedPort: Integer;
  normalizedHost, entry: string;
begin
  Result := False;
  if (FAllowedHosts.Count = 0) or (FAllowedPorts.Count = 0) then
  begin
    Exit;
  end;

  normalizedHost := NormalizeHost(AHost);
  if (normalizedHost = '') then
  begin
    Exit;
  end;

  for i := 0 to FAllowedHosts.Count - 1 do
  begin
    if SameText(normalizedHost, NormalizeHost(FAllowedHosts[i])) then
    begin
      Result := True;
      Break;
    end;
  end;
  if not Result then
  begin
    Exit;
  end;

  Result := False;
  for i := 0 to FAllowedPorts.Count - 1 do
  begin
    entry := Trim(FAllowedPorts[i]);
    if (entry = '') then
    begin
      Continue;
    end;
    allowedPort := StrToIntDef(entry, -1);
    if (allowedPort = APort) then
    begin
      Result := True;
      Exit;
    end;
  end;
end;

procedure TclHttpTunnelServer.SilentClose(AConnection: TclUserConnection);
begin
  if (AConnection is TclHttpTunnelConnection) then
  begin
    TclHttpTunnelConnection(AConnection).SignalRequestPhaseDone();
    TclHttpTunnelConnection(AConnection).SignalRelayStop();
  end;
  CloseConnection(AConnection);
end;

procedure TclHttpTunnelServer.SendRawResponse(AConnection: TclUserConnection;
  const AResponse: string);
var
  bytes: TclByteArray;
  stream: TMemoryStream;
begin
{$IFNDEF DELPHI2005}bytes := nil;{$ENDIF}
  bytes := TclTranslator.GetBytes(AResponse);
  stream := TMemoryStream.Create();
  try
    if (Length(bytes) > 0) then
    begin
      stream.WriteBuffer(bytes[0], Length(bytes));
      stream.Position := 0;
      AConnection.WriteData(stream);
    end;
  finally
    stream.Free();
  end;
end;

procedure TclHttpTunnelServer.DoTunnelResponse(AConnection: TclUserConnection;
  AStatusCode: Integer; const ATargetHost: string; ATargetPort: Integer);
begin
  if Assigned(OnTunnelResponse) then
  begin
    OnTunnelResponse(Self, AConnection, AStatusCode, ATargetHost, ATargetPort);
  end;
end;

procedure TclHttpTunnelServer.SendHttpStatus(AConnection: TclUserConnection;
  AStatusCode: Integer; const AReason: string);
begin
  SendHttpStatus(AConnection, AStatusCode, AReason, '', 0);
end;

procedure TclHttpTunnelServer.SendHttpStatus(AConnection: TclUserConnection;
  AStatusCode: Integer; const AReason, ATargetHost: string; ATargetPort: Integer);
begin
  SendRawResponse(AConnection,
    Format('HTTP/1.1 %d %s'#13#10'Connection: close'#13#10#13#10, [AStatusCode, AReason]));
  DoTunnelResponse(AConnection, AStatusCode, ATargetHost, ATargetPort);
end;

procedure TclHttpTunnelServer.RejectHeaderTooLarge(AConnection: TclHttpTunnelConnection);
begin
  SendHttpStatus(AConnection, 431, HttpReasonHeaderTooLarge);
  SilentClose(AConnection);
end;

function TclHttpTunnelServer.ExtractHeaderLength(ABuffer: TMemoryStream): Integer;
var
  i, n: Integer;
  p: PByte;
begin
  Result := -1;
  n := Integer(ABuffer.Size);
  if (n < Length(crlfcrlf)) then Exit;
  p := ABuffer.Memory;
  for i := 0 to n - Length(crlfcrlf) do
  begin
    if (p[i] = crlfcrlf[0]) and (p[i + 1] = crlfcrlf[1])
      and (p[i + 2] = crlfcrlf[2]) and (p[i + 3] = crlfcrlf[3]) then
    begin
      Result := i + Length(crlfcrlf);
      Exit;
    end;
  end;
end;

function TclHttpTunnelServer.ParseConnectRequest(ABuffer: TMemoryStream;
  out AHost: string; out APort: Integer; out AHeaderLength: Integer): Integer;
var
  headerBytes: TclByteArray;
  headerText, requestLine, method, target, version, hostPart, portPart: string;
  lineEnd, sp1, sp2, colonPos: Integer;
begin
{$IFNDEF DELPHI2005}headerBytes := nil;{$ENDIF}
  AHost := '';
  APort := 0;
  AHeaderLength := ExtractHeaderLength(ABuffer);
  if (AHeaderLength < 0) then
  begin
    Result := -1;
    Exit;
  end;

  SetLength(headerBytes, AHeaderLength);
  if (AHeaderLength > 0) then
  begin
    Move(ABuffer.Memory^, headerBytes[0], AHeaderLength);
  end;
  headerText := TclTranslator.GetString(headerBytes);

  lineEnd := Pos(#13#10, headerText);
  if (lineEnd <= 1) then
  begin
    Result := 2;
    Exit;
  end;
  requestLine := Copy(headerText, 1, lineEnd - 1);

  sp1 := Pos(' ', requestLine);
  if (sp1 <= 1) then
  begin
    Result := 2;
    Exit;
  end;
  method := Copy(requestLine, 1, sp1 - 1);
  sp2 := Pos(' ', Copy(requestLine, sp1 + 1, MaxInt));
  if (sp2 <= 1) then
  begin
    Result := 2;
    Exit;
  end;
  sp2 := sp1 + sp2;
  target := Copy(requestLine, sp1 + 1, sp2 - sp1 - 1);
  version := Trim(Copy(requestLine, sp2 + 1, MaxInt));
  if (version = '') then
  begin
    Result := 2;
    Exit;
  end;

  if not SameText(method, 'CONNECT') then
  begin
    Result := 1;
    Exit;
  end;

  colonPos := LastDelimiter(':', target);
  if (colonPos <= 1) or (colonPos >= Length(target)) then
  begin
    Result := 2;
    Exit;
  end;
  hostPart := Copy(target, 1, colonPos - 1);
  portPart := Copy(target, colonPos + 1, MaxInt);
  if (hostPart = '') or (portPart = '') then
  begin
    Result := 2;
    Exit;
  end;
  APort := StrToIntDef(portPart, -1);
  if (APort < 1) or (APort > 65535) then
  begin
    Result := 2;
    Exit;
  end;
  AHost := hostPart;
  Result := 0;
end;

procedure TclHttpTunnelServer.StartRelay(AConnection: TclHttpTunnelConnection);
begin
  AConnection.SignalRequestPhaseDone();
  AConnection.Relaying := True;
  AConnection.RelayActive := True;
{$IFDEF LOGGER}clPutLogMessage(Self, edInside, 'StartRelay ' + AConnection.TargetHost + ':' + IntToStr(AConnection.TargetPort));{$ENDIF}
  FRelayThreadPool.QueueWorkItem(
    TclHttpTunnelRelayWorkItem.Create(Self, IclUserConnection_(AConnection)));
end;

procedure TclHttpTunnelServer.ProcessConnectRequest(AConnection: TclHttpTunnelConnection);
var
  host: string;
  port, parseResult, headerLength: Integer;
  leftover: TMemoryStream;
begin
  parseResult := ParseConnectRequest(AConnection.RequestBuffer, host, port, headerLength);
  if (parseResult < 0) then
  begin
    if (AConnection.RequestBuffer.Size > MaxHeaderSizeBytes) then
    begin
      RejectHeaderTooLarge(AConnection);
    end;
    Exit;
  end;

  if (headerLength > MaxHeaderSizeBytes) then
  begin
    RejectHeaderTooLarge(AConnection);
    Exit;
  end;

  if (parseResult = 1) then
  begin
    SendHttpStatus(AConnection, 405, HttpReasonMethodNotAllowed);
    SilentClose(AConnection);
    Exit;
  end;
  if (parseResult = 2) then
  begin
    SendHttpStatus(AConnection, 400, HttpReasonBadRequest);
    SilentClose(AConnection);
    Exit;
  end;

  if not IsDestinationAllowed(host, port) then
  begin
    SendHttpStatus(AConnection, 403, HttpReasonForbidden, host, port);
    SilentClose(AConnection);
    Exit;
  end;

  leftover := TMemoryStream.Create();
  try
    if (AConnection.RequestBuffer.Size > headerLength) then
    begin
      AConnection.RequestBuffer.Position := headerLength;
      leftover.CopyFrom(AConnection.RequestBuffer, AConnection.RequestBuffer.Size - headerLength);
      leftover.Position := 0;
    end;
    AConnection.RequestBuffer.Size := 0;
    AConnection.RequestBuffer.Position := 0;

    AConnection.TargetHost := host;
    AConnection.TargetPort := port;
    StartRelay(AConnection);

    if (leftover.Size > 0) then
    begin
      leftover.Position := 0;
      AConnection.EnqueueRelayData(leftover);
    end;
  finally
    leftover.Free();
  end;
end;

procedure TclHttpTunnelServer.HandleTunnelData(AConnection: TclHttpTunnelConnection;
  AData: TStream);
begin
  if AConnection.Relaying then
  begin
{$IFDEF LOGGER}clPutLogMessage(Self, edInside, Format('enqueue relay bytes=%d',
      [Integer(AData.Size - AData.Position)]));{$ENDIF}
    AConnection.EnqueueRelayData(AData);
    Exit;
  end;

  if (AData <> nil) and (AData.Size - AData.Position > 0) then
  begin
    AConnection.RequestBuffer.Seek(0, soEnd);
    AConnection.RequestBuffer.CopyFrom(AData, AData.Size - AData.Position);
  end;

  if (AConnection.RequestBuffer.Size > MaxHeaderSizeBytes)
    and (ExtractHeaderLength(AConnection.RequestBuffer) < 0) then
  begin
    RejectHeaderTooLarge(AConnection);
    Exit;
  end;

  ProcessConnectRequest(AConnection);
end;

procedure TclHttpTunnelServer.DoReadConnection(AConnection: TclUserConnection; AData: TStream);
begin
  if (AConnection is TclHttpTunnelConnection) then
  begin
    HandleTunnelData(TclHttpTunnelConnection(AConnection), AData);
  end;
  inherited DoReadConnection(AConnection, AData);
end;

procedure TclHttpTunnelServer.DoCloseConnection(AConnection: TclUserConnection);
var
  tunnelConn: TclHttpTunnelConnection;
begin
  if (AConnection is TclHttpTunnelConnection) then
  begin
    tunnelConn := TclHttpTunnelConnection(AConnection);
    tunnelConn.SignalRequestPhaseDone();
    tunnelConn.SignalRelayStop();
    if tunnelConn.IpLimitCounted then
    begin
      tunnelConn.IpLimitCounted := False;
      DecrementConnectionsForIP(tunnelConn.PeerIP);
    end;
  end;
  inherited DoCloseConnection(AConnection);
end;

end.

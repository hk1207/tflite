unit uMediaPipeBridge;

// Pose from MediaPipe (Python) : tools/mediapipe_bridge.py runs the MediaPipe
// Pose Landmarker on the camera and sends the landmarks as text lines over UDP.
// This estimator listens on 127.0.0.1 and returns the last pose.
//
// The camera belongs to the Python program, so UsesCamera is False.

interface

uses
  System.SysUtils, System.Classes, System.SyncObjs, Winapi.Windows,
  IdUDPServer, IdGlobal, IdSocketHandle,
  uPoseEstimator;

const
  MEDIAPIPE_DEFAULT_PORT = 5005;

type
  TMediaPipeBridge = class(TPoseEstimator)
    protected
      FServer   : TIdUDPServer;
      FLock     : TCriticalSection;
      FLine     : string;
      FLineTick : UInt64;
      FPort     : integer;

      procedure UDPRead(AThread : TIdUDPListenerThread; const AData : TIdBytes; ABinding : TIdSocketHandle);
    public
      constructor Create(aPort : integer = MEDIAPIPE_DEFAULT_PORT);
      destructor  Destroy; override;

      function Name : string; override;
      function UsesCamera : boolean; override;
      function Estimate(aFrame : Pointer; aW, aH, aPitch : integer; aBGRA : boolean) : TPoseResult; override;
  end;

implementation

uses
  uMediaPipeProtocol;

const
  // A pose that is older than this is not valid anymore (the bridge stopped).
  MAX_AGE_MS = 700;

constructor TMediaPipeBridge.Create(aPort : integer);
begin
  inherited Create;

  FPort := aPort;
  FLock := TCriticalSection.Create;

  FServer := TIdUDPServer.Create(nil);
  FServer.ThreadedEvent := True;
  FServer.OnUDPRead     := UDPRead;

  with FServer.Bindings.Add do
    begin
      IP   := '127.0.0.1';
      Port := FPort;
    end;

  FServer.Active := True;
end;

destructor TMediaPipeBridge.Destroy;
begin
  FServer.Active := False;
  FServer.Free;
  FLock.Free;

  inherited Destroy;
end;

procedure TMediaPipeBridge.UDPRead(AThread : TIdUDPListenerThread; const AData : TIdBytes; ABinding : TIdSocketHandle);
var
  TempLine : string;
begin
  TempLine := TEncoding.ASCII.GetString(TBytes(AData));

  FLock.Enter;
  try
    FLine     := TempLine;
    FLineTick := GetTickCount64;
  finally
    FLock.Leave;
  end;
end;

function TMediaPipeBridge.Name : string;
begin
  Result := Format('MediaPipe bridge, UDP %d (3D)', [FPort]);
end;

function TMediaPipeBridge.UsesCamera : boolean;
begin
  Result := False;
end;

function TMediaPipeBridge.Estimate(aFrame : Pointer; aW, aH, aPitch : integer; aBGRA : boolean) : TPoseResult;
var
  TempLine : string;
  TempAge : UInt64;
begin
  FillChar(Result, SizeOf(Result), 0);

  FLock.Enter;
  try
    TempLine := FLine;
    TempAge  := GetTickCount64 - FLineTick;
  finally
    FLock.Leave;
  end;

  if (TempLine = '') or (TempAge > MAX_AGE_MS) then exit;

  if not(ParseMediaPipeLine(TempLine, Result)) then
    FillChar(Result, SizeOf(Result), 0);
end;

end.

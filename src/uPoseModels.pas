unit uPoseModels;

// Opens a pose model and creates the matching estimator.
//
//   *.tflite   TensorFlow Lite (tensorflowlite_c.dll)
//   *.onnx     ONNX Runtime (onnxruntime.dll)
//   udp://host:port   the MediaPipe bridge (tools/mediapipe_bridge.py)
//
// The kind of the model is found from its outputs : BlazePose (195 landmark
// values), YOLO pose ([1, 56, N]) or MoveNet ([1, 1, 17, 3]).

interface

uses
  System.SysUtils, uInference, uPoseEstimator;

const
  // The source of the MediaPipe bridge, as it is shown in the model list.
  MEDIAPIPE_SOURCE = 'udp://127.0.0.1:5005';

/// <summary>
/// aSource : a .tflite or .onnx file, or the address of the MediaPipe bridge.
/// </summary>
function LoadPoseEstimator(const aSource : string; aThreads : integer = 2) : TPoseEstimator;

/// <summary>
/// Name of a source for the user interface.
/// </summary>
function PoseSourceCaption(const aSource : string) : string;

implementation

uses
  uTFLite, uOnnxRuntime, uMoveNet, uBlazePose, uYoloPose, uMediaPipeBridge;

function IsBridge(const aSource : string) : boolean;
begin
  Result := aSource.StartsWith('udp:', True);
end;

function PoseSourceCaption(const aSource : string) : string;
begin
  if IsBridge(aSource) then
    Result := 'MediaPipe (Python bridge, ' + aSource + ')'
   else
    Result := ExtractFileName(aSource);
end;

function BridgePort(const aSource : string) : integer;
var
  TempPos : integer;
begin
  // udp://127.0.0.1:5005
  TempPos := aSource.LastIndexOf(':');
  Result  := StrToIntDef(Copy(aSource, TempPos + 2, 10), MEDIAPIPE_DEFAULT_PORT);
end;

function LoadPoseEstimator(const aSource : string; aThreads : integer) : TPoseEstimator;
var
  TempEngine : TInferenceEngine;
  TempKind, i : integer;
begin
  if IsBridge(aSource) then
    exit(TMediaPipeBridge.Create(BridgePort(aSource)));

  if SameText(ExtractFileExt(aSource), '.onnx') then
    TempEngine := TOnnxEngine.Create(aSource, aThreads)
   else
    TempEngine := TTFLiteInterpreter.Create(aSource, aThreads);

  // 1 = BlazePose, 2 = YOLO pose, 3 = MoveNet, 0 = unknown
  TempKind := 0;

  try
    if TBlazePose.IsBlazePose(TempEngine) then
      TempKind := 1
     else
      if TYoloPose.IsYoloPose(TempEngine) then
        TempKind := 2
       else
        for i := 0 to pred(TempEngine.OutputCount) do
          if (TempEngine.OutputValueCount(i) = 51) then
            TempKind := 3;

    if (TempKind = 0) then
      raise EInferenceError.CreateFmt('%s is not a known pose model (BlazePose, YOLO pose or MoveNet)',
                                      [ExtractFileName(aSource)]);
  except
    TempEngine.Free;
    raise;
  end;

  // From here the estimator owns the engine, also when its constructor fails
  // (the destructor frees it).
  case TempKind of
    1 : Result := TBlazePose.Create(TempEngine);
    2 : Result := TYoloPose.Create(TempEngine);
    else Result := TMoveNet.Create(TempEngine);
  end;
end;

end.

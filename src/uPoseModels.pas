unit uPoseModels;

// Opens a pose model and creates the matching estimator.
//
//   *.tflite   TensorFlow Lite (tensorflowlite_c.dll)
//   *.onnx     ONNX Runtime (onnxruntime.dll)
//   udp://host:port   the MediaPipe bridge (tools/mediapipe_bridge.py)
//
// The kind of the model is found from its outputs : BlazePose (195 landmark
// values), YOLO pose ([1, 56, N]) or MoveNet ([1, 1, 17, 3]).
//
// BlazePose : the pose detector model of MediaPipe is used when it is in the
// same folder (pose_detection.tflite, pose_detector.tflite or .onnx), so the
// application finds the person in the whole image and follows a rotated body,
// like MediaPipe does. Without it the person has to be at the center.

interface

uses
  System.SysUtils, uInference, uPoseEstimator;

const
  // The source of the MediaPipe bridge, as it is shown in the model list.
  MEDIAPIPE_SOURCE = 'udp://127.0.0.1:5005';

/// <summary>
/// aSource : a .tflite or .onnx file, or the address of the MediaPipe bridge.
/// aDetector : the BlazePose detector file ('' = search it next to aSource).
/// </summary>
function LoadPoseEstimator(const aSource : string; aThreads : integer = 2; const aDetector : string = '') : TPoseEstimator;

/// <summary>
/// The detector model of BlazePose that is next to the landmark model aModelFile
/// ('' if there is none).
/// </summary>
function FindBlazeDetector(const aModelFile : string) : string;

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

function CreateEngine(const aFile : string; aThreads : integer) : TInferenceEngine;
begin
  if SameText(ExtractFileExt(aFile), '.onnx') then
    Result := TOnnxEngine.Create(aFile, aThreads)
   else
    Result := TTFLiteInterpreter.Create(aFile, aThreads);
end;

function FindBlazeDetector(const aModelFile : string) : string;
const
  NAMES : array[0..1] of string = ('pose_detection', 'pose_detector');
var
  TempDir, TempExt : string;
  i : integer;
begin
  TempDir := ExtractFilePath(aModelFile);
  TempExt := ExtractFileExt(aModelFile);

  for i := low(NAMES) to high(NAMES) do
    if FileExists(TempDir + NAMES[i] + TempExt) then
      exit(TempDir + NAMES[i] + TempExt);

  Result := '';
end;

function LoadPoseEstimator(const aSource : string; aThreads : integer; const aDetector : string) : TPoseEstimator;
var
  TempEngine, TempDetector : TInferenceEngine;
  TempKind, i : integer;
  TempDetectorFile : string;
begin
  if IsBridge(aSource) then
    exit(TMediaPipeBridge.Create(BridgePort(aSource)));

  TempEngine := CreateEngine(aSource, aThreads);

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

  // From here the estimator owns the engines, also when its constructor fails
  // (the destructor frees them).
  case TempKind of
    1 :
      begin
        TempDetector := nil;

        if (aDetector <> '') then
          TempDetectorFile := aDetector
         else
          TempDetectorFile := FindBlazeDetector(aSource);

        if (TempDetectorFile <> '') then
          try
            TempDetector := CreateEngine(TempDetectorFile, aThreads);
          except
            TempEngine.Free;
            raise;
          end;

        Result := TBlazePose.Create(TempEngine, TempDetector);
      end;

    2 : Result := TYoloPose.Create(TempEngine);
    else Result := TMoveNet.Create(TempEngine);
  end;
end;

end.

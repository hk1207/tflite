unit uPoseModels;

// Loads a pose model and creates the matching estimator.

interface

uses
  System.SysUtils, uTFLite, uPoseEstimator;

/// <summary>
/// Loads the .tflite file : a BlazePose landmark model (3D) or a MoveNet
/// SinglePose model (2D). The kind of the model is found from its outputs.
/// </summary>
function LoadPoseEstimator(const aModelPath : string; aThreads : integer = 2; const aDllPath : string = '') : TPoseEstimator;

implementation

uses
  uMoveNet, uBlazePose;

function LoadPoseEstimator(const aModelPath : string; aThreads : integer; const aDllPath : string) : TPoseEstimator;
var
  TempInterpreter : TTFLiteInterpreter;
  TempBlaze : boolean;
begin
  TempInterpreter := TTFLiteInterpreter.Create(aModelPath, aThreads, aDllPath);

  try
    TempBlaze := TBlazePose.IsBlazePose(TempInterpreter);
  except
    TempInterpreter.Free;
    raise;
  end;

  // From here the estimator owns the interpreter, also when its constructor
  // fails (the destructor frees it).
  if TempBlaze then
    Result := TBlazePose.Create(TempInterpreter)
   else
    Result := TMoveNet.Create(TempInterpreter);
end;

end.

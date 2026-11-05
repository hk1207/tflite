unit uMoveNet;

// MoveNet SinglePose (Lightning or Thunder) pose estimation with TensorFlow
// Lite. See models/README.md to get the .tflite file.
//
// Output of the model : float32 [1, 1, 17, 3] with (y, x, score) for each of
// the 17 keypoints, normalized to the input image (0..1).

interface

uses
  System.SysUtils, uTFLite, uPoseSolver;

type
  TMoveNet = class
    protected
      FInterpreter : TTFLiteInterpreter;
      FInputSize   : integer;
    public
      constructor Create(const aModelPath : string; aThreads : integer = 2; const aDllPath : string = '');
      destructor  Destroy; override;

      /// <summary>
      /// aRGB has InputSize x InputSize x 3 bytes. The keypoints are returned
      /// with x, y in 0..1 (relative to the input image).
      /// </summary>
      function Detect(aRGB : PByte) : TKeypoints;

      /// <summary>
      /// Width and height of the model input (192 Lightning, 256 Thunder).
      /// </summary>
      property InputSize : integer read FInputSize;
  end;

implementation

constructor TMoveNet.Create(const aModelPath : string; aThreads : integer; const aDllPath : string);
begin
  inherited Create;

  FInterpreter := TTFLiteInterpreter.Create(aModelPath, aThreads, aDllPath);

  // Input : [1, height, width, 3]
  if (FInterpreter.InputDimCount <> 4) or (FInterpreter.InputDim(3) <> 3) or
     (FInterpreter.InputDim(1) <> FInterpreter.InputDim(2)) then
    raise ETFLiteError.Create('This is not a MoveNet SinglePose model (the input must be [1, N, N, 3])');

  FInputSize := FInterpreter.InputDim(1);
end;

destructor TMoveNet.Destroy;
begin
  FInterpreter.Free;

  inherited Destroy;
end;

function TMoveNet.Detect(aRGB : PByte) : TKeypoints;
var
  TempOutput : TArray<Single>;
  i : integer;
begin
  FInterpreter.SetInputRGB(aRGB, FInputSize, FInputSize);
  FInterpreter.Invoke;
  FInterpreter.ReadOutput(0, TempOutput);

  if (length(TempOutput) < (KEYPOINT_COUNT * 3)) then
    raise ETFLiteError.Create('Unexpected output of the model');

  for i := 0 to pred(KEYPOINT_COUNT) do
    begin
      Result[i].Y     := TempOutput[(i * 3) + 0];
      Result[i].X     := TempOutput[(i * 3) + 1];
      Result[i].Score := TempOutput[(i * 3) + 2];
    end;
end;

end.

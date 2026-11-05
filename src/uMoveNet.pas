unit uMoveNet;

// MoveNet SinglePose (Lightning or Thunder) pose estimation with TensorFlow
// Lite. 2D keypoints only. See models/README.md to get the .tflite file.
//
// Output of the model : float32 [1, 1, 17, 3] with (y, x, score) for each of
// the 17 keypoints, normalized to the input image (0..1).

interface

uses
  System.SysUtils, uTFLite, uPoseSolver, uPoseEstimator;

type
  TMoveNet = class(TPoseEstimator)
    protected
      FInterpreter : TTFLiteInterpreter;
      FInputSize   : integer;
      FInput       : TBytes;
    public
      /// <summary>
      /// The estimator owns aInterpreter.
      /// </summary>
      constructor Create(aInterpreter : TTFLiteInterpreter);
      destructor  Destroy; override;

      function Name : string; override;
      function Estimate(aFrame : Pointer; aW, aH, aPitch : integer; aBGRA : boolean) : TPoseResult; override;

      /// <summary>
      /// Width and height of the model input (192 Lightning, 256 Thunder).
      /// </summary>
      property InputSize : integer read FInputSize;
  end;

implementation

uses
  uPoseImage;

constructor TMoveNet.Create(aInterpreter : TTFLiteInterpreter);
begin
  inherited Create;

  FInterpreter := aInterpreter;

  // Input : [1, height, width, 3]
  if (FInterpreter.InputDimCount <> 4) or (FInterpreter.InputDim(3) <> 3) or
     (FInterpreter.InputDim(1) <> FInterpreter.InputDim(2)) then
    raise ETFLiteError.Create('This is not a MoveNet SinglePose model (the input must be [1, N, N, 3])');

  FInputSize := FInterpreter.InputDim(1);
  SetLength(FInput, FInputSize * FInputSize * 3);
end;

destructor TMoveNet.Destroy;
begin
  FInterpreter.Free;

  inherited Destroy;
end;

function TMoveNet.Name : string;
begin
  Result := Format('MoveNet %dx%d (2D)', [FInputSize, FInputSize]);
end;

function TMoveNet.Estimate(aFrame : Pointer; aW, aH, aPitch : integer; aBGRA : boolean) : TPoseResult;
var
  TempOutput : TArray<Single>;
  TempCropX, TempCropY, TempCropSize, i : integer;
begin
  FillChar(Result, SizeOf(Result), 0);

  CropResizeToRGB(aFrame, aW, aH, aPitch, aBGRA, @FInput[0], FInputSize,
                  TempCropX, TempCropY, TempCropSize);

  FInterpreter.SetInputRGB(@FInput[0], FInputSize, FInputSize);
  FInterpreter.Invoke;
  FInterpreter.ReadOutput(0, TempOutput);

  if (length(TempOutput) < (KEYPOINT_COUNT * 3)) then
    raise ETFLiteError.Create('Unexpected output of the model');

  for i := 0 to pred(KEYPOINT_COUNT) do
    begin
      // Output : (y, x, score) relative to the square -> pixels of the frame
      Result.Keypoints[i].Y     := TempCropY + (TempOutput[(i * 3) + 0] * TempCropSize);
      Result.Keypoints[i].X     := TempCropX + (TempOutput[(i * 3) + 1] * TempCropSize);
      Result.Keypoints[i].Score := TempOutput[(i * 3) + 2];
    end;

  Result.Found := True;
end;

end.

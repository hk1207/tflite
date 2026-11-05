unit uYoloPose;

// YOLO pose models (YOLOv8-pose / YOLO11-pose exported to ONNX, input 640x640
// RGB 0..1, output [1, 56, 8400] or [1, 8400, 56]) : 17 COCO keypoints of the
// person with the best score. 2D only (the depth is estimated by the solver).

interface

uses
  System.SysUtils, uInference, uPoseSolver, uPoseEstimator;

type
  TYoloPose = class(TPoseEstimator)
    protected
      FEngine        : TInferenceEngine;
      FInputSize     : integer;
      FInput         : TBytes;
      FChannelsFirst : boolean;
      FCount         : integer;
    public
      /// <summary>
      /// The estimator owns aEngine.
      /// </summary>
      constructor Create(aEngine : TInferenceEngine);
      destructor  Destroy; override;

      function Name : string; override;
      function Estimate(aFrame : Pointer; aW, aH, aPitch : integer; aBGRA : boolean) : TPoseResult; override;

      /// <summary>
      /// True if the first output of aEngine looks like the output of a YOLO pose model.
      /// </summary>
      class function IsYoloPose(aEngine : TInferenceEngine) : boolean;
  end;

implementation

uses
  uPoseImage, uYoloDecode;

class function TYoloPose.IsYoloPose(aEngine : TInferenceEngine) : boolean;
begin
  Result := (aEngine.OutputCount > 0) and (aEngine.OutputDimCount(0) = 3) and
            ((aEngine.OutputDim(0, 1) = YOLO_VALUES) or (aEngine.OutputDim(0, 2) = YOLO_VALUES));
end;

constructor TYoloPose.Create(aEngine : TInferenceEngine);
begin
  inherited Create;

  FEngine := aEngine;

  if (FEngine.InputWidth <= 0) or (FEngine.InputWidth <> FEngine.InputHeight) then
    raise EInferenceError.Create('This is not a YOLO pose model (the input must be a square image)');

  if not(IsYoloPose(FEngine)) then
    raise EInferenceError.Create('This is not a YOLO pose model (the output must be [1, 56, N] or [1, N, 56])');

  FInputSize     := FEngine.InputWidth;
  FChannelsFirst := (FEngine.OutputDim(0, 1) = YOLO_VALUES);

  if FChannelsFirst then
    FCount := FEngine.OutputDim(0, 2)
   else
    FCount := FEngine.OutputDim(0, 1);

  SetLength(FInput, FInputSize * FInputSize * 3);
end;

destructor TYoloPose.Destroy;
begin
  FEngine.Free;

  inherited Destroy;
end;

function TYoloPose.Name : string;
begin
  Result := Format('YOLO pose %dx%d (2D)', [FInputSize, FInputSize]);
end;

function TYoloPose.Estimate(aFrame : Pointer; aW, aH, aPitch : integer; aBGRA : boolean) : TPoseResult;
var
  TempOutput : TSingleArray;
  TempCropX, TempCropY, TempCropSize : integer;
begin
  CropResizeToRGB(aFrame, aW, aH, aPitch, aBGRA, @FInput[0], FInputSize,
                  TempCropX, TempCropY, TempCropSize);

  FEngine.SetInputRGB(@FInput[0], FInputSize, FInputSize, 1 / 255);
  FEngine.Invoke;
  FEngine.ReadOutput(0, TempOutput);

  YoloDecode(TempOutput, FCount, FChannelsFirst, FInputSize, TempCropX, TempCropY, TempCropSize, 0.25, Result);

  Result.FrameWidth  := aW;
  Result.FrameHeight := aH;
end;

end.

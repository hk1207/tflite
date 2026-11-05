unit uBlazePose;

// MediaPipe BlazePose with TensorFlow Lite : 33 landmarks with 3D world
// coordinates (meters). It uses the landmark model (pose_landmark_lite / full /
// heavy .tflite, input 256x256). The pose detector model is not used : the
// first frame uses the square at the center of the image, so the person has to
// stand in the middle of the image with the whole body visible. Then the square
// follows the body (like the tracking of MediaPipe).
//
// Outputs are found by their size : 195 values = landmarks, 117 values = world
// landmarks, 1 value = pose presence.

interface

uses
  System.SysUtils, uInference, uPoseSolver, uPoseEstimator, uBlazeDecode;

type
  TBlazePose = class(TPoseEstimator)
    protected
      FInterpreter : TInferenceEngine;
      FInputSize   : integer;
      FInput       : TBytes;
      FLandmarksIdx, FWorldIdx, FPresenceIdx : integer;
      FRoi         : TBlazeRoi;
      FTracking    : boolean;
    public
      /// <summary>
      /// The estimator owns aInterpreter.
      /// </summary>
      constructor Create(aInterpreter : TInferenceEngine);
      destructor  Destroy; override;

      function Name : string; override;
      function Estimate(aFrame : Pointer; aW, aH, aPitch : integer; aBGRA : boolean) : TPoseResult; override;
      procedure ResetTracking; override;

      /// <summary>
      /// True if aInterpreter looks like a BlazePose landmark model.
      /// </summary>
      class function IsBlazePose(aInterpreter : TInferenceEngine) : boolean;
  end;

implementation

uses
  uPoseImage;

class function TBlazePose.IsBlazePose(aInterpreter : TInferenceEngine) : boolean;
var
  i : integer;
begin
  Result := False;

  for i := 0 to pred(aInterpreter.OutputCount) do
    if (aInterpreter.OutputValueCount(i) = BLAZE_LANDMARK_SIZE) then
      Result := True;
end;

constructor TBlazePose.Create(aInterpreter : TInferenceEngine);
var
  i, TempCount : integer;
begin
  inherited Create;

  FInterpreter := aInterpreter;

  if (FInterpreter.InputWidth <= 0) or (FInterpreter.InputWidth <> FInterpreter.InputHeight) then
    raise EInferenceError.Create('This is not a BlazePose landmark model (the input must be a square image)');

  FInputSize := FInterpreter.InputWidth;
  SetLength(FInput, FInputSize * FInputSize * 3);

  FLandmarksIdx := -1;
  FWorldIdx     := -1;
  FPresenceIdx  := -1;

  for i := 0 to pred(FInterpreter.OutputCount) do
    begin
      TempCount := FInterpreter.OutputValueCount(i);

      if (TempCount = BLAZE_LANDMARK_SIZE) and (FLandmarksIdx < 0) then
        FLandmarksIdx := i
       else
        if (TempCount = BLAZE_WORLD_SIZE) and (FWorldIdx < 0) then
          FWorldIdx := i
         else
          if (TempCount = 1) and (FPresenceIdx < 0) then
            FPresenceIdx := i;
    end;

  if (FLandmarksIdx < 0) then
    raise EInferenceError.Create('This is not a BlazePose landmark model (no output with 195 values)');

  FTracking := False;
end;

destructor TBlazePose.Destroy;
begin
  FInterpreter.Free;

  inherited Destroy;
end;

function TBlazePose.Name : string;
begin
  if (FWorldIdx >= 0) then
    Result := Format('BlazePose %dx%d (3D)', [FInputSize, FInputSize])
   else
    Result := Format('BlazePose %dx%d (no world output)', [FInputSize, FInputSize]);
end;

procedure TBlazePose.ResetTracking;
begin
  FTracking := False;
end;

function TBlazePose.Estimate(aFrame : Pointer; aW, aH, aPitch : integer; aBGRA : boolean) : TPoseResult;
var
  TempLandmarks, TempWorld, TempPresence : TSingleArray;
  TempNext : TBlazeRoi;
  TempFlag : Single;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.FrameWidth  := aW;
  Result.FrameHeight := aH;

  if not(FTracking) then
    BlazeFullFrameRoi(aW, aH, FRoi);

  CropRegionToRGB(aFrame, aW, aH, aPitch, aBGRA, FRoi.CX, FRoi.CY, FRoi.Side, @FInput[0], FInputSize);

  // The landmark model wants float values 0..1
  FInterpreter.SetInputRGB(@FInput[0], FInputSize, FInputSize, 1 / 255);
  FInterpreter.Invoke;
  FInterpreter.ReadOutput(FLandmarksIdx, TempLandmarks);

  if (FWorldIdx >= 0) then
    FInterpreter.ReadOutput(FWorldIdx, TempWorld)
   else
    SetLength(TempWorld, 0);

  if (FPresenceIdx >= 0) then
    begin
      FInterpreter.ReadOutput(FPresenceIdx, TempPresence);
      TempFlag := TempPresence[0];

      // The flag is a probability. Convert it if the model gives a logit.
      if (TempFlag < 0) or (TempFlag > 1) then
        TempFlag := BlazeSigmoid(TempFlag);

      if (TempFlag < 0.5) then
        begin
          // The body was lost : search again in the whole image.
          FTracking := False;
          exit;
        end;
    end;

  BlazeDecode(TempLandmarks, TempWorld, FInputSize, FRoi, aW, aH, Result, TempNext);

  if Result.Found then
    begin
      FRoi      := TempNext;
      FTracking := True;
    end;
end;

end.

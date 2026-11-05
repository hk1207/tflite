unit uBlazePose;

// MediaPipe BlazePose with TensorFlow Lite or ONNX Runtime : 33 landmarks with
// 3D world coordinates (meters). It follows the pose graph of MediaPipe :
//
//   * the pose detector (pose_detection.tflite / pose_detector.tflite, input
//     224x224) finds the body in the whole frame and gives the center and the
//     size of the body,
//   * a rotated square around the body is given to the landmark model
//     (pose_landmark_lite / full / heavy, input 256x256),
//   * then the square is calculated from the landmarks of the previous frame
//     (tracking) and the detector is not used again until the body is lost.
//
// If there is no detector model the first frame uses the square at the center of
// the image : the person has to stand in the middle with the whole body visible.
//
// The outputs of the models are found by their size : landmark model 195 values
// = landmarks, 117 = world landmarks, 1 = pose presence; detector 27048 values
// = regressors, 2254 = scores.

interface

uses
  System.SysUtils, uInference, uPoseSolver, uPoseEstimator, uBlazeDecode, uBlazeDetect;

type
  TBlazePose = class(TPoseEstimator)
    protected
      FInterpreter : TInferenceEngine;
      FDetector    : TInferenceEngine;
      FInputSize   : integer;
      FInput       : TBytes;
      FDetInput    : TBytes;
      FLandmarksIdx, FWorldIdx, FPresenceIdx : integer;
      FRegressorsIdx, FScoresIdx : integer;
      FAnchors     : TBlazeAnchors;
      FRoi         : TBlazeRoi;
      FTracking    : boolean;

      function Detect(aFrame : Pointer; aW, aH, aPitch : integer; aBGRA : boolean) : boolean;
    public
      /// <summary>
      /// The estimator owns aLandmarkEngine and aDetectorEngine (nil = no detector).
      /// </summary>
      constructor Create(aLandmarkEngine : TInferenceEngine; aDetectorEngine : TInferenceEngine = nil);
      destructor  Destroy; override;

      function Name : string; override;
      function Estimate(aFrame : Pointer; aW, aH, aPitch : integer; aBGRA : boolean) : TPoseResult; override;
      procedure ResetTracking; override;

      /// <summary>
      /// True if aInterpreter looks like a BlazePose landmark model.
      /// </summary>
      class function IsBlazePose(aInterpreter : TInferenceEngine) : boolean;
      /// <summary>
      /// True if aInterpreter looks like the BlazePose detector model.
      /// </summary>
      class function IsBlazeDetector(aInterpreter : TInferenceEngine) : boolean;
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

class function TBlazePose.IsBlazeDetector(aInterpreter : TInferenceEngine) : boolean;
var
  i : integer;
  TempRegressors, TempScores : boolean;
begin
  TempRegressors := False;
  TempScores     := False;

  for i := 0 to pred(aInterpreter.OutputCount) do
    begin
      if (aInterpreter.OutputValueCount(i) = BLAZE_DETECTOR_ANCHORS * BLAZE_DETECTOR_VALUES) then TempRegressors := True;
      if (aInterpreter.OutputValueCount(i) = BLAZE_DETECTOR_ANCHORS) then TempScores := True;
    end;

  Result := TempRegressors and TempScores;
end;

constructor TBlazePose.Create(aLandmarkEngine : TInferenceEngine; aDetectorEngine : TInferenceEngine);
var
  i, TempCount : integer;
begin
  inherited Create;

  FInterpreter := aLandmarkEngine;
  FDetector    := aDetectorEngine;

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

  FRegressorsIdx := -1;
  FScoresIdx     := -1;

  if (FDetector <> nil) then
    begin
      if not(IsBlazeDetector(FDetector)) or (FDetector.InputWidth <> BLAZE_DETECTOR_SIZE) or
         (FDetector.InputHeight <> BLAZE_DETECTOR_SIZE) then
        raise EInferenceError.Create('This is not the BlazePose detector model (input 224x224, outputs 2254 x 12 and 2254)');

      for i := 0 to pred(FDetector.OutputCount) do
        begin
          TempCount := FDetector.OutputValueCount(i);

          if (TempCount = BLAZE_DETECTOR_ANCHORS * BLAZE_DETECTOR_VALUES) then FRegressorsIdx := i;
          if (TempCount = BLAZE_DETECTOR_ANCHORS) then FScoresIdx := i;
        end;

      SetLength(FDetInput, BLAZE_DETECTOR_SIZE * BLAZE_DETECTOR_SIZE * 3);
      BlazeBuildAnchors(FAnchors);
    end;

  FTracking := False;
end;

destructor TBlazePose.Destroy;
begin
  FInterpreter.Free;
  FDetector.Free;

  inherited Destroy;
end;

function TBlazePose.Name : string;
var
  TempDetector : string;
begin
  if (FDetector <> nil) then
    TempDetector := ' + detector'
   else
    TempDetector := '';

  if (FWorldIdx >= 0) then
    Result := Format('BlazePose %dx%d%s (3D)', [FInputSize, FInputSize, TempDetector])
   else
    Result := Format('BlazePose %dx%d%s (no world output)', [FInputSize, FInputSize, TempDetector]);
end;

procedure TBlazePose.ResetTracking;
begin
  FTracking := False;
end;

// Pose detector : finds the body in the whole frame and sets FRoi.
function TBlazePose.Detect(aFrame : Pointer; aW, aH, aPitch : integer; aBGRA : boolean) : boolean;
var
  TempSquare : TBlazeRoi;
  TempRegressors, TempScores : TSingleArray;
  TempScore : Single;
begin
  BlazeFullFrameRoi(aW, aH, TempSquare);

  if (FDetector = nil) then
    begin
      // No detector model : the person is supposed to be at the center.
      FRoi   := TempSquare;
      Result := True;
      exit;
    end;

  // The frame in a black square 224x224, values -1..1
  CropRegionToRGB(aFrame, aW, aH, aPitch, aBGRA, TempSquare.CX, TempSquare.CY, TempSquare.Side,
                  @FDetInput[0], BLAZE_DETECTOR_SIZE);

  FDetector.SetInputRGB(@FDetInput[0], BLAZE_DETECTOR_SIZE, BLAZE_DETECTOR_SIZE, 1 / 127.5, -1);
  FDetector.Invoke;
  FDetector.ReadOutput(FRegressorsIdx, TempRegressors);
  FDetector.ReadOutput(FScoresIdx, TempScores);

  Result := BlazeDetectPose(TempRegressors, TempScores, FAnchors, TempSquare, 0.5, FRoi, TempScore);
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
    if not(Detect(aFrame, aW, aH, aPitch, aBGRA)) then exit;

  CropRotatedToRGB(aFrame, aW, aH, aPitch, aBGRA, FRoi.CX, FRoi.CY, FRoi.Side, FRoi.Rotation,
                   @FInput[0], FInputSize);

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
          // The body was lost : search it again with the detector.
          FTracking := False;
          exit;
        end;
    end;

  BlazeDecode(TempLandmarks, TempWorld, FInputSize, FRoi, aW, aH, Result, TempNext);

  if Result.Found then
    begin
      FRoi      := TempNext;
      FTracking := True;
    end
   else
    FTracking := False;
end;

end.

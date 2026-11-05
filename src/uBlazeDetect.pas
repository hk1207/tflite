unit uBlazeDetect;

{$IFDEF FPC}{$MODE Delphi}{$ENDIF}

// Decoding of the MediaPipe BlazePose detector (pose_detection.tflite /
// pose_detector.tflite) : finds the person in the frame. The detector gives the
// center of the body and a point on the circle that surrounds it. They make the
// rotated square that is given to the landmark model (uBlazeDecode), like the
// pose detection graph of MediaPipe.
//
// Model : input 224x224x3 float32 in -1..1 (the frame with black borders to make
// it square), output regressors [1, 2254, 12] and scores [1, 2254, 1].
// It has no dependencies on TFLite, so it can be tested on any platform.

interface

uses
  uBlazeDecode;

const
  BLAZE_DETECTOR_SIZE    = 224;
  BLAZE_DETECTOR_ANCHORS = 2254;
  BLAZE_DETECTOR_VALUES  = 12;     // 4 box values + 4 keypoints x 2

type
  TBlazeAnchor = record
    X, Y : Single;   // center, 0..1 of the input
  end;
  TBlazeAnchors = array of TBlazeAnchor;

/// <summary>
/// The 2254 anchors of the pose detector (SSD anchors : 5 layers, strides
/// 8, 16, 32, 32, 32, scales 0.1484375 .. 0.75).
/// </summary>
procedure BlazeBuildAnchors(out aAnchors : TBlazeAnchors);

/// <summary>
/// Finds the best detection above aMinScore. The frame was given to the model
/// as the square aSquare (the biggest square at the center : see
/// BlazeFullFrameRoi). Returns the square (rotated, scaled 1.25) for the
/// landmark model. aScore is the score of the detection.
/// </summary>
function BlazeDetectPose(const aRegressors, aScores : array of Single; const aAnchors : TBlazeAnchors;
                         const aSquare : TBlazeRoi; aMinScore : Single;
                         out aRoi : TBlazeRoi; out aScore : Single) : boolean;

implementation

uses
  {$IFDEF FPC}Math{$ELSE}System.Math{$ENDIF};

const
  MIN_SCALE = 0.1484375;
  MAX_SCALE = 0.75;
  LAYERS    = 5;
  STRIDES   : array[0..LAYERS - 1] of integer = (8, 16, 32, 32, 32);

function CalculateScale(aLayer : integer) : Single;
begin
  Result := MIN_SCALE + ((MAX_SCALE - MIN_SCALE) * aLayer / (LAYERS - 1));
end;

procedure BlazeBuildAnchors(out aAnchors : TBlazeAnchors);
var
  TempLayer, TempLast, TempCount, TempPerCell, TempMap, x, y, a, TempIndex : integer;
  TempScale, TempNext : Single;
begin
  SetLength(aAnchors, BLAZE_DETECTOR_ANCHORS);
  TempIndex := 0;
  TempLayer := 0;

  while (TempLayer < LAYERS) do
    begin
      // The layers with the same stride share the feature map : each one gives
      // 2 anchors per cell (the scale of the layer and the interpolated scale).
      TempLast    := TempLayer;
      TempPerCell := 0;

      while (TempLast < LAYERS) and (STRIDES[TempLast] = STRIDES[TempLayer]) do
        begin
          TempScale := CalculateScale(TempLast);

          if (TempLast = LAYERS - 1) then
            TempNext := 1.0
           else
            TempNext := CalculateScale(TempLast + 1);

          TempPerCell := TempPerCell + 2;
          inc(TempLast);
        end;

      TempMap := (BLAZE_DETECTOR_SIZE + STRIDES[TempLayer] - 1) div STRIDES[TempLayer];

      for y := 0 to pred(TempMap) do
        for x := 0 to pred(TempMap) do
          for a := 0 to pred(TempPerCell) do
            begin
              aAnchors[TempIndex].X := (x + 0.5) / TempMap;
              aAnchors[TempIndex].Y := (y + 0.5) / TempMap;
              inc(TempIndex);
            end;

      TempLayer := TempLast;
    end;

  TempCount := TempIndex;

  if (TempCount <> BLAZE_DETECTOR_ANCHORS) then
    SetLength(aAnchors, TempCount);
end;

function Sigmoid(aValue : Single) : Single;
begin
  if (aValue < -100) then aValue := -100;
  if (aValue > 100) then aValue := 100;

  Result := 1 / (1 + Exp(-aValue));
end;

function BlazeDetectPose(const aRegressors, aScores : array of Single; const aAnchors : TBlazeAnchors;
                         const aSquare : TBlazeRoi; aMinScore : Single;
                         out aRoi : TBlazeRoi; out aScore : Single) : boolean;
var
  i, TempBest : integer;
  TempScore, TempBestScore : Single;
  TempX0, TempY0, TempX1, TempY1 : Single;
begin
  Result := False;
  aScore := 0;
  FillChar(aRoi, SizeOf(aRoi), 0);

  if (length(aAnchors) <> BLAZE_DETECTOR_ANCHORS) or (length(aScores) < BLAZE_DETECTOR_ANCHORS) or
     (length(aRegressors) < (BLAZE_DETECTOR_ANCHORS * BLAZE_DETECTOR_VALUES)) then exit;

  TempBest      := -1;
  TempBestScore := aMinScore;

  for i := 0 to pred(BLAZE_DETECTOR_ANCHORS) do
    begin
      TempScore := Sigmoid(aScores[i]);

      if (TempScore >= TempBestScore) then
        begin
          TempBestScore := TempScore;
          TempBest      := i;
        end;
    end;

  if (TempBest < 0) then exit;

  // Keypoint 0 : the center of the body (hips), keypoint 1 : the point on the
  // circle around the body. Normalized to the 224x224 input, relative to the anchor.
  TempX0 := (aRegressors[(TempBest * BLAZE_DETECTOR_VALUES) + 4] / BLAZE_DETECTOR_SIZE) + aAnchors[TempBest].X;
  TempY0 := (aRegressors[(TempBest * BLAZE_DETECTOR_VALUES) + 5] / BLAZE_DETECTOR_SIZE) + aAnchors[TempBest].Y;
  TempX1 := (aRegressors[(TempBest * BLAZE_DETECTOR_VALUES) + 6] / BLAZE_DETECTOR_SIZE) + aAnchors[TempBest].X;
  TempY1 := (aRegressors[(TempBest * BLAZE_DETECTOR_VALUES) + 7] / BLAZE_DETECTOR_SIZE) + aAnchors[TempBest].Y;

  // To pixels of the frame
  TempX0 := aSquare.CX - (aSquare.Side / 2) + (TempX0 * aSquare.Side);
  TempY0 := aSquare.CY - (aSquare.Side / 2) + (TempY0 * aSquare.Side);
  TempX1 := aSquare.CX - (aSquare.Side / 2) + (TempX1 * aSquare.Side);
  TempY1 := aSquare.CY - (aSquare.Side / 2) + (TempY1 * aSquare.Side);

  BlazeRoiFromPoints(TempX0, TempY0, TempX1, TempY1, 1.25, aRoi);

  aScore := TempBestScore;
  Result := (aRoi.Side > 1);
end;

end.

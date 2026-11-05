unit uBlazeDecode;

{$IFDEF FPC}{$MODE Delphi}{$ENDIF}

// Decoding of the MediaPipe BlazePose landmark model output (pose_landmark_lite /
// full / heavy .tflite) : 39 landmarks (33 body + 6 auxiliary) with
// x, y, z, visibility, presence, and 39 world landmarks (meters, origin at the
// hips). It has no dependencies on TFLite, so it can be tested on any platform.

interface

uses
  uPoseSolver, uPoseEstimator;

const
  BLAZE_LANDMARK_COUNT = 39;
  BLAZE_LANDMARK_VALUES = 5;
  BLAZE_LANDMARK_SIZE = BLAZE_LANDMARK_COUNT * BLAZE_LANDMARK_VALUES;   // 195
  BLAZE_WORLD_SIZE = BLAZE_LANDMARK_COUNT * 3;                          // 117

  // BlazePose landmark of each MoveNet keypoint : nose, eyes, ears, shoulders,
  // elbows, wrists, hips, knees, ankles.
  BLAZE_TO_KEYPOINT : array[0..KEYPOINT_COUNT - 1] of integer = (
    0, 2, 5, 7, 8, 11, 12, 13, 14, 15, 16, 23, 24, 25, 26, 27, 28);

type
  /// <summary>
  /// Square of the frame that is given to the model (pixels of the frame).
  /// </summary>
  TBlazeRoi = record
    CX, CY, Side : Single;
    Rotation     : Single;   // radians, clockwise in the image (y down), 0 = upright
  end;

/// <summary>
/// The square of MediaPipe for a body : centered at (aX0, aY0) (the body center),
/// with a side of aScale * 2 * the distance to (aX1, aY1) (a point on the circle
/// that surrounds the body), rotated so that the line from the first to the
/// second point is vertical. aScale is 1.25 in MediaPipe.
/// </summary>
procedure BlazeRoiFromPoints(aX0, aY0, aX1, aY1, aScale : Single; out aRoi : TBlazeRoi);

/// <summary>
/// The biggest square at the center of the frame.
/// </summary>
procedure BlazeFullFrameRoi(aW, aH : Single; out aRoi : TBlazeRoi);

/// <summary>
/// aLandmarks : 195 floats, aWorld : 117 floats (empty if the model has no
/// world output). aInputSize : the model input size (256). aRoi : the square
/// that was used for this frame. aNextRoi : the square for the next frame, from
/// the auxiliary landmarks 33 (body center) and 34 (body size).
/// </summary>
procedure BlazeDecode(const aLandmarks, aWorld : array of Single; aInputSize : integer;
                      const aRoi : TBlazeRoi; aFrameW, aFrameH : Single;
                      out aResult : TPoseResult; out aNextRoi : TBlazeRoi);

function BlazeSigmoid(aValue : Single) : Single;

implementation

uses
  {$IFDEF FPC}Math{$ELSE}System.Math{$ENDIF};

function BlazeSigmoid(aValue : Single) : Single;
begin
  if (aValue < -30) then aValue := -30;
  if (aValue > 30) then aValue := 30;

  Result := 1 / (1 + Exp(-aValue));
end;

procedure BlazeRoiFromPoints(aX0, aY0, aX1, aY1, aScale : Single; out aRoi : TBlazeRoi);
var
  TempAngle : Single;
begin
  aRoi.CX   := aX0;
  aRoi.CY   := aY0;
  aRoi.Side := 2 * Sqrt(Sqr(aX1 - aX0) + Sqr(aY1 - aY0)) * aScale;

  // target angle 90 degrees : the vector from the first to the second point looks up.
  TempAngle := (Pi / 2) - ArcTan2(-(aY1 - aY0), aX1 - aX0);

  // to -Pi..Pi
  while (TempAngle > Pi) do TempAngle := TempAngle - (2 * Pi);
  while (TempAngle < -Pi) do TempAngle := TempAngle + (2 * Pi);

  aRoi.Rotation := TempAngle;
end;

procedure BlazeFullFrameRoi(aW, aH : Single; out aRoi : TBlazeRoi);
begin
  aRoi.CX := aW / 2;
  aRoi.CY := aH / 2;
  aRoi.Rotation := 0;

  if (aW < aH) then
    aRoi.Side := aW
   else
    aRoi.Side := aH;
end;

procedure BlazeDecode(const aLandmarks, aWorld : array of Single; aInputSize : integer;
                      const aRoi : TBlazeRoi; aFrameW, aFrameH : Single;
                      out aResult : TPoseResult; out aNextRoi : TBlazeRoi);
var
  i, TempLm : integer;
  TempFactor, TempCos, TempSin, TempWx, TempWy : Single;
  TempX33, TempY33, TempX34, TempY34, TempRadius, TempMin, TempMax : Single;
  TempNext : TBlazeRoi;

  // A point of the model input (pixels) -> the frame : the square is rotated
  // around its center.
  function FrameX(aX, aY : Single) : Single;
  begin
    Result := aRoi.CX + (((aX * TempFactor) - (aRoi.Side / 2)) * TempCos)
                      - (((aY * TempFactor) - (aRoi.Side / 2)) * TempSin);
  end;

  function FrameY(aX, aY : Single) : Single;
  begin
    Result := aRoi.CY + (((aX * TempFactor) - (aRoi.Side / 2)) * TempSin)
                      + (((aY * TempFactor) - (aRoi.Side / 2)) * TempCos);
  end;

begin
  FillChar(aResult, SizeOf(aResult), 0);
  aNextRoi := aRoi;

  if (length(aLandmarks) < BLAZE_LANDMARK_SIZE) then exit;

  TempFactor := aRoi.Side / aInputSize;
  TempCos    := Cos(aRoi.Rotation);
  TempSin    := Sin(aRoi.Rotation);

  aResult.FrameWidth  := aFrameW;
  aResult.FrameHeight := aFrameH;
  aResult.Has3D := (length(aWorld) >= BLAZE_WORLD_SIZE);

  for i := 0 to pred(KEYPOINT_COUNT) do
    begin
      TempLm := BLAZE_TO_KEYPOINT[i] * BLAZE_LANDMARK_VALUES;

      aResult.Keypoints[i].X     := FrameX(aLandmarks[TempLm], aLandmarks[TempLm + 1]);
      aResult.Keypoints[i].Y     := FrameY(aLandmarks[TempLm], aLandmarks[TempLm + 1]);
      aResult.Keypoints[i].Score := BlazeSigmoid(aLandmarks[TempLm + 3]);

      if aResult.Has3D then
        begin
          TempLm := BLAZE_TO_KEYPOINT[i] * 3;

          // The world landmarks are in the rotated square : turn them back
          // (x to the right, y down), then to our axes (y up, z to the camera).
          TempWx := (aWorld[TempLm] * TempCos) - (aWorld[TempLm + 1] * TempSin);
          TempWy := (aWorld[TempLm] * TempSin) + (aWorld[TempLm + 1] * TempCos);

          aResult.World[i] := Vec3(TempWx, -TempWy, -aWorld[TempLm + 2]);
        end;
    end;

  aResult.Found := True;

  // Next square : centered at the body center (landmark 33), the landmark 34 is
  // on the circle that surrounds the whole body.
  TempX33 := FrameX(aLandmarks[33 * BLAZE_LANDMARK_VALUES], aLandmarks[(33 * BLAZE_LANDMARK_VALUES) + 1]);
  TempY33 := FrameY(aLandmarks[33 * BLAZE_LANDMARK_VALUES], aLandmarks[(33 * BLAZE_LANDMARK_VALUES) + 1]);
  TempX34 := FrameX(aLandmarks[34 * BLAZE_LANDMARK_VALUES], aLandmarks[(34 * BLAZE_LANDMARK_VALUES) + 1]);
  TempY34 := FrameY(aLandmarks[34 * BLAZE_LANDMARK_VALUES], aLandmarks[(34 * BLAZE_LANDMARK_VALUES) + 1]);
  TempRadius := Sqrt(Sqr(TempX34 - TempX33) + Sqr(TempY34 - TempY33));

  if (TempRadius > 1) then
    begin
      BlazeRoiFromPoints(TempX33, TempY33, TempX34, TempY34, 1.25, TempNext);

      if (aFrameW < aFrameH) then TempMin := aFrameW else TempMin := aFrameH;
      if (aFrameW > aFrameH) then TempMax := aFrameW else TempMax := aFrameH;

      if (TempNext.Side < (0.25 * TempMin)) then TempNext.Side := 0.25 * TempMin;
      if (TempNext.Side > (1.5 * TempMax)) then TempNext.Side := 1.5 * TempMax;

      aNextRoi := TempNext;
    end;
end;

end.

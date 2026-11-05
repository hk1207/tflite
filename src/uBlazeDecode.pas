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
  end;

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

procedure BlazeFullFrameRoi(aW, aH : Single; out aRoi : TBlazeRoi);
begin
  aRoi.CX := aW / 2;
  aRoi.CY := aH / 2;

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
  TempLeft, TempTop, TempFactor : Single;
  TempX33, TempY33, TempX34, TempY34, TempRadius, TempSide, TempMin, TempMax : Single;

  function FrameX(aX : Single) : Single;
  begin
    Result := TempLeft + (aX * TempFactor);
  end;

  function FrameY(aY : Single) : Single;
  begin
    Result := TempTop + (aY * TempFactor);
  end;

begin
  FillChar(aResult, SizeOf(aResult), 0);
  aNextRoi := aRoi;

  if (length(aLandmarks) < BLAZE_LANDMARK_SIZE) then exit;

  TempLeft   := aRoi.CX - (aRoi.Side / 2);
  TempTop    := aRoi.CY - (aRoi.Side / 2);
  TempFactor := aRoi.Side / aInputSize;

  aResult.FrameWidth  := aFrameW;
  aResult.FrameHeight := aFrameH;
  aResult.Has3D := (length(aWorld) >= BLAZE_WORLD_SIZE);

  for i := 0 to pred(KEYPOINT_COUNT) do
    begin
      TempLm := BLAZE_TO_KEYPOINT[i] * BLAZE_LANDMARK_VALUES;

      aResult.Keypoints[i].X     := FrameX(aLandmarks[TempLm]);
      aResult.Keypoints[i].Y     := FrameY(aLandmarks[TempLm + 1]);
      aResult.Keypoints[i].Score := BlazeSigmoid(aLandmarks[TempLm + 3]);

      if aResult.Has3D then
        begin
          TempLm := BLAZE_TO_KEYPOINT[i] * 3;

          // MediaPipe : x to the right, y down, z away from the camera.
          aResult.World[i] := Vec3(aWorld[TempLm], -aWorld[TempLm + 1], -aWorld[TempLm + 2]);
        end;
    end;

  aResult.Found := True;

  // Next square : centered at the body center (landmark 33), the landmark 34 is
  // on the circle that surrounds the whole body.
  TempX33 := FrameX(aLandmarks[33 * BLAZE_LANDMARK_VALUES]);
  TempY33 := FrameY(aLandmarks[(33 * BLAZE_LANDMARK_VALUES) + 1]);
  TempX34 := FrameX(aLandmarks[34 * BLAZE_LANDMARK_VALUES]);
  TempY34 := FrameY(aLandmarks[(34 * BLAZE_LANDMARK_VALUES) + 1]);
  TempRadius := Sqrt(Sqr(TempX34 - TempX33) + Sqr(TempY34 - TempY33));

  if (TempRadius > 1) then
    begin
      TempSide := TempRadius * 2 * 1.25;

      if (aFrameW < aFrameH) then TempMin := aFrameW else TempMin := aFrameH;
      if (aFrameW > aFrameH) then TempMax := aFrameW else TempMax := aFrameH;

      if (TempSide < (0.25 * TempMin)) then TempSide := 0.25 * TempMin;
      if (TempSide > (1.5 * TempMax)) then TempSide := 1.5 * TempMax;

      aNextRoi.CX   := TempX33;
      aNextRoi.CY   := TempY33;
      aNextRoi.Side := TempSide;
    end;
end;

end.

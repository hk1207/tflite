unit uYoloDecode;

{$IFDEF FPC}{$MODE Delphi}{$ENDIF}

// Decoding of the output of YOLO pose models (YOLOv8 / YOLO11 "-pose" exported
// to ONNX) : 56 values for each of the N candidate detections = 4 box values
// (center x, center y, width, height), 1 person score and 17 keypoints with
// x, y, score. The keypoints are in the COCO order, the same as MoveNet.
// It has no dependencies on ONNX Runtime, so it can be tested on any platform.

interface

uses
  uPoseSolver, uPoseEstimator;

const
  YOLO_VALUES = 56;

/// <summary>
/// aOutput : the output tensor. aCount : number of candidate detections (for
/// example 8400). aChannelsFirst : True for [1, 56, N] (the default export),
/// False for [1, N, 56]. aInputSize : the model input size (640). The model got
/// the square (aCropX, aCropY, aCropSize) of the frame stretched to the input.
/// The best person above aMinScore is returned (a single person).
/// </summary>
function YoloDecode(const aOutput : array of Single; aCount : integer; aChannelsFirst : boolean;
                    aInputSize : integer; aCropX, aCropY, aCropSize : Single;
                    aMinScore : Single; out aResult : TPoseResult) : boolean;

implementation

function YoloDecode(const aOutput : array of Single; aCount : integer; aChannelsFirst : boolean;
                    aInputSize : integer; aCropX, aCropY, aCropSize : Single;
                    aMinScore : Single; out aResult : TPoseResult) : boolean;
var
  i, k, TempBest : integer;
  TempScore, TempBestScore, TempFactor : Single;

  function Value(aAnchor, aChannel : integer) : Single;
  begin
    if aChannelsFirst then
      Result := aOutput[(aChannel * aCount) + aAnchor]
     else
      Result := aOutput[(aAnchor * YOLO_VALUES) + aChannel];
  end;

begin
  FillChar(aResult, SizeOf(aResult), 0);
  Result := False;

  if (aCount <= 0) or (length(aOutput) < (aCount * YOLO_VALUES)) then exit;

  TempBest      := -1;
  TempBestScore := aMinScore;

  for i := 0 to pred(aCount) do
    begin
      TempScore := Value(i, 4);

      if (TempScore >= TempBestScore) then
        begin
          TempBestScore := TempScore;
          TempBest      := i;
        end;
    end;

  if (TempBest < 0) then exit;

  TempFactor := aCropSize / aInputSize;

  for k := 0 to pred(KEYPOINT_COUNT) do
    begin
      aResult.Keypoints[k].X     := aCropX + (Value(TempBest, 5 + (k * 3)) * TempFactor);
      aResult.Keypoints[k].Y     := aCropY + (Value(TempBest, 6 + (k * 3)) * TempFactor);
      aResult.Keypoints[k].Score := Value(TempBest, 7 + (k * 3));
    end;

  aResult.Found := True;
  Result        := True;
end;

end.

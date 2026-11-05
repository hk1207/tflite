unit uMediaPipeProtocol;

{$IFDEF FPC}{$MODE Delphi}{$ENDIF}

// Text protocol between tools/mediapipe_bridge.py (Python + MediaPipe) and the
// application. One line for each frame :
//
//   MP1 <frame width> <frame height> <found 0/1> [ 33 x (x y z visibility)  33 x (wx wy wz) ]
//
// x, y : 0..1 (relative to the frame), z : MediaPipe depth, wx, wy, wz : world
// landmarks in meters (MediaPipe axes : x right, y down, z away from the camera).
// Numbers use a dot as the decimal separator. It has no dependencies on the
// network, so it can be tested on any platform.

interface

uses
  uPoseSolver, uPoseEstimator;

const
  MEDIAPIPE_LANDMARKS = 33;
  MEDIAPIPE_PROTOCOL_TAG = 'MP1';

/// <summary>
/// Returns False if the line is not a valid message. For a valid message with
/// no body aResult.Found is False.
/// </summary>
function ParseMediaPipeLine(const aLine : string; out aResult : TPoseResult) : boolean;

implementation

uses
  SysUtils, uBlazeDecode;

function ParseMediaPipeLine(const aLine : string; out aResult : TPoseResult) : boolean;
var
  TempValues : array of Single;
  TempCount, TempPos, TempStart, i, TempLm : integer;
  TempFormat : TFormatSettings;
  TempWord, TempTag : string;
  TempW, TempH : Single;
  TempFound : integer;
  TempExpected : integer;
begin
  FillChar(aResult, SizeOf(aResult), 0);
  Result := False;

  TempFormat := FormatSettings;
  TempFormat.DecimalSeparator := '.';

  // Split at the spaces
  TempCount := 0;
  SetLength(TempValues, 0);
  TempTag := '';
  TempPos := 1;

  while (TempPos <= length(aLine)) do
    begin
      while (TempPos <= length(aLine)) and (aLine[TempPos] in [' ', #9, #13, #10]) do inc(TempPos);
      TempStart := TempPos;
      while (TempPos <= length(aLine)) and not(aLine[TempPos] in [' ', #9, #13, #10]) do inc(TempPos);

      if (TempPos > TempStart) then
        begin
          TempWord := Copy(aLine, TempStart, TempPos - TempStart);

          if (TempTag = '') then
            TempTag := TempWord
           else
            begin
              SetLength(TempValues, TempCount + 1);

              try
                TempValues[TempCount] := StrToFloat(TempWord, TempFormat);
              except
                exit;
              end;

              inc(TempCount);
            end;
        end;
    end;

  if (TempTag <> MEDIAPIPE_PROTOCOL_TAG) or (TempCount < 3) then exit;

  TempW     := TempValues[0];
  TempH     := TempValues[1];
  TempFound := round(TempValues[2]);

  aResult.FrameWidth  := TempW;
  aResult.FrameHeight := TempH;

  if (TempW < 1) or (TempH < 1) then exit;

  if (TempFound = 0) then
    begin
      Result := True;
      exit;
    end;

  TempExpected := 3 + (MEDIAPIPE_LANDMARKS * 4) + (MEDIAPIPE_LANDMARKS * 3);
  if (TempCount < TempExpected) then exit;

  aResult.Has3D := True;

  for i := 0 to pred(KEYPOINT_COUNT) do
    begin
      TempLm := BLAZE_TO_KEYPOINT[i];

      aResult.Keypoints[i].X     := TempValues[3 + (TempLm * 4)] * TempW;
      aResult.Keypoints[i].Y     := TempValues[4 + (TempLm * 4)] * TempH;
      aResult.Keypoints[i].Score := TempValues[6 + (TempLm * 4)];

      // MediaPipe world axes : x right, y down, z away from the camera.
      aResult.World[i] := Vec3(TempValues[3 + (MEDIAPIPE_LANDMARKS * 4) + (TempLm * 3)],
                               -TempValues[4 + (MEDIAPIPE_LANDMARKS * 4) + (TempLm * 3)],
                               -TempValues[5 + (MEDIAPIPE_LANDMARKS * 4) + (TempLm * 3)]);
    end;

  aResult.Found := True;
  Result        := True;
end;

end.

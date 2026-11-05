unit uPoseImage;

{$IFDEF FPC}{$MODE Delphi}{$ENDIF}

// Image preparation for MoveNet : the camera frame is cropped to the biggest
// centered square and resized (bilinear) to the model input size as RGB bytes.
// It doesn't depend on any framework, so it can be tested on any platform.

interface

uses
  {$IFDEF FPC}Math{$ELSE}System.Math{$ENDIF};

type
  PPixelBytes = ^TPixelBytes;
  TPixelBytes = array[0..134217727] of Byte;

/// <summary>
/// aSrc : pixels of the frame, 4 bytes each (BGRA if aBGRA, RGBA if not),
/// aPitch = bytes of a row. aDst : aDstSize * aDstSize * 3 bytes (RGB).
/// aCropX, aCropY and aCropSize describe the square that was used, in pixels of
/// the frame. A keypoint (nx, ny) of the model output is the frame position
/// (aCropX + nx * aCropSize, aCropY + ny * aCropSize).
/// </summary>
procedure CropResizeToRGB(aSrc : Pointer; aW, aH, aPitch : integer; aBGRA : boolean;
                          aDst : Pointer; aDstSize : integer;
                          out aCropX, aCropY, aCropSize : integer);

/// <summary>
/// Same as CropResizeToRGB for any square of the frame : the center is (aCenterX,
/// aCenterY) and the side aSide, in pixels of the frame. The part of the square
/// that is outside of the frame is black.
/// </summary>
procedure CropRegionToRGB(aSrc : Pointer; aW, aH, aPitch : integer; aBGRA : boolean;
                          aCenterX, aCenterY, aSide : Single;
                          aDst : Pointer; aDstSize : integer);

/// <summary>
/// Same as CropRegionToRGB for a square that is rotated by aRotation radians
/// (clockwise in the image, y down) around its center. The model sees the
/// square upright : a point of the model image (u, v) relative to the center
/// (units of the frame) is at the frame position
///   x = aCenterX + u cos(r) - v sin(r),  y = aCenterY + u sin(r) + v cos(r).
/// </summary>
procedure CropRotatedToRGB(aSrc : Pointer; aW, aH, aPitch : integer; aBGRA : boolean;
                           aCenterX, aCenterY, aSide, aRotation : Single;
                           aDst : Pointer; aDstSize : integer);

implementation

procedure CropResizeToRGB(aSrc : Pointer; aW, aH, aPitch : integer; aBGRA : boolean;
                          aDst : Pointer; aDstSize : integer;
                          out aCropX, aCropY, aCropSize : integer);
var
  TempSrc, TempDst : PPixelBytes;
  x, y, x0, y0, x1, y1, c : integer;
  TempSx, TempSy, TempFx, TempFy, TempRatio : Single;
  TempIdx : array[0..2] of integer;
  TempP00, TempP10, TempP01, TempP11, TempValue : Single;
begin
  if (aW < aH) then aCropSize := aW else aCropSize := aH;

  aCropX := (aW - aCropSize) div 2;
  aCropY := (aH - aCropSize) div 2;

  TempSrc := PPixelBytes(aSrc);
  TempDst := PPixelBytes(aDst);

  // Byte offsets of R, G and B in a source pixel
  if aBGRA then
    begin
      TempIdx[0] := 2; TempIdx[1] := 1; TempIdx[2] := 0;
    end
   else
    begin
      TempIdx[0] := 0; TempIdx[1] := 1; TempIdx[2] := 2;
    end;

  TempRatio := aCropSize / aDstSize;

  for y := 0 to pred(aDstSize) do
    begin
      TempSy := ((y + 0.5) * TempRatio) - 0.5;
      if (TempSy < 0) then TempSy := 0;
      y0 := trunc(TempSy);
      y1 := y0 + 1;
      if (y1 >= aCropSize) then y1 := aCropSize - 1;
      TempFy := TempSy - y0;

      for x := 0 to pred(aDstSize) do
        begin
          TempSx := ((x + 0.5) * TempRatio) - 0.5;
          if (TempSx < 0) then TempSx := 0;
          x0 := trunc(TempSx);
          x1 := x0 + 1;
          if (x1 >= aCropSize) then x1 := aCropSize - 1;
          TempFx := TempSx - x0;

          for c := 0 to 2 do
            begin
              TempP00 := TempSrc^[((aCropY + y0) * aPitch) + ((aCropX + x0) * 4) + TempIdx[c]];
              TempP10 := TempSrc^[((aCropY + y0) * aPitch) + ((aCropX + x1) * 4) + TempIdx[c]];
              TempP01 := TempSrc^[((aCropY + y1) * aPitch) + ((aCropX + x0) * 4) + TempIdx[c]];
              TempP11 := TempSrc^[((aCropY + y1) * aPitch) + ((aCropX + x1) * 4) + TempIdx[c]];

              TempValue := (TempP00 * (1 - TempFx) * (1 - TempFy)) +
                           (TempP10 * TempFx * (1 - TempFy)) +
                           (TempP01 * (1 - TempFx) * TempFy) +
                           (TempP11 * TempFx * TempFy);

              TempDst^[(((y * aDstSize) + x) * 3) + c] := Byte(round(TempValue));
            end;
        end;
    end;
end;


procedure CropRegionToRGB(aSrc : Pointer; aW, aH, aPitch : integer; aBGRA : boolean;
                          aCenterX, aCenterY, aSide : Single;
                          aDst : Pointer; aDstSize : integer);
begin
  CropRotatedToRGB(aSrc, aW, aH, aPitch, aBGRA, aCenterX, aCenterY, aSide, 0, aDst, aDstSize);
end;

procedure CropRotatedToRGB(aSrc : Pointer; aW, aH, aPitch : integer; aBGRA : boolean;
                           aCenterX, aCenterY, aSide, aRotation : Single;
                           aDst : Pointer; aDstSize : integer);
var
  TempSrc, TempDst : PPixelBytes;
  x, y, x0, y0, c : integer;
  TempRatio, TempU, TempV, TempSx, TempSy, TempFx, TempFy, TempValue, TempCos, TempSin : Single;
  TempIdx : array[0..2] of integer;

  function Pixel(aX, aY, aC : integer) : Single;
  begin
    if (aX < 0) or (aY < 0) or (aX >= aW) or (aY >= aH) then
      Result := 0
     else
      Result := TempSrc^[(aY * aPitch) + (aX * 4) + TempIdx[aC]];
  end;

begin
  TempSrc := PPixelBytes(aSrc);
  TempDst := PPixelBytes(aDst);

  if aBGRA then
    begin
      TempIdx[0] := 2; TempIdx[1] := 1; TempIdx[2] := 0;
    end
   else
    begin
      TempIdx[0] := 0; TempIdx[1] := 1; TempIdx[2] := 2;
    end;

  TempRatio := aSide / aDstSize;
  TempCos   := Cos(aRotation);
  TempSin   := Sin(aRotation);

  for y := 0 to pred(aDstSize) do
    for x := 0 to pred(aDstSize) do
      begin
        // Position relative to the center of the square, in pixels of the frame
        TempU := ((x + 0.5) * TempRatio) - (aSide / 2);
        TempV := ((y + 0.5) * TempRatio) - (aSide / 2);

        TempSx := aCenterX + (TempU * TempCos) - (TempV * TempSin) - 0.5;
        TempSy := aCenterY + (TempU * TempSin) + (TempV * TempCos) - 0.5;

        x0     := Floor(TempSx);
        y0     := Floor(TempSy);
        TempFx := TempSx - x0;
        TempFy := TempSy - y0;

        for c := 0 to 2 do
          begin
            TempValue := (Pixel(x0, y0, c) * (1 - TempFx) * (1 - TempFy)) +
                         (Pixel(x0 + 1, y0, c) * TempFx * (1 - TempFy)) +
                         (Pixel(x0, y0 + 1, c) * (1 - TempFx) * TempFy) +
                         (Pixel(x0 + 1, y0 + 1, c) * TempFx * TempFy);

            TempDst^[(((y * aDstSize) + x) * 3) + c] := Byte(round(TempValue));
          end;
      end;
end;

end.

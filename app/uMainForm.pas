unit uMainForm;

// Main form : the camera image and its keypoints on the left, the 3D male model
// (Castle Game Engine) on the right. The whole form is created in code.

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes,
  System.Diagnostics, System.IOUtils,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Layouts, FMX.StdCtrls,
  FMX.Objects, FMX.Media, FMX.Controls.Presentation,
  Fmx.CastleControl,
  CastleViewport, CastleScene, CastleVectors,
  uPoseSolver, uMoveNet, uMaleAvatar;

type
  TMainForm = class(TForm)
    protected
      FPanel        : TLayout;
      FPreview      : TImage;
      FStatus       : TLabel;
      FMirrorCheck  : TCheckBox;
      FDepthCheck   : TCheckBox;
      FResetButton  : TButton;
      FControl      : TCastleControl;
      FViewport     : TCastleViewport;
      FAvatar       : TMaleAvatar;
      FCamera       : TCameraComponent;
      FFrame        : TBitmap;
      FMoveNet      : TMoveNet;
      FSolver       : TPoseSolver;
      FInput        : TBytes;
      FWatch        : TStopwatch;
      FLastFrame    : Double;
      FFps          : Double;

      function  NewLabel(aParent : TControl; aHeight : Single) : TLabel;
      function  NewCheck(const aText : string; aChecked : boolean) : TCheckBox;
      function  FindFile(const aName : string) : string;
      procedure BuildUi;
      procedure BuildScene;
      procedure LoadModel;
      procedure OptionChanged(Sender : TObject);
      procedure ResetClick(Sender : TObject);
      procedure FormShowEvent(Sender : TObject);
      procedure CameraFrame(Sender : TObject; const ATime : TMediaTime);
      procedure DrawKeypoints(const aKp : TKeypoints);
    public
      constructor Create(AOwner : TComponent); override;
      destructor  Destroy; override;
  end;

var
  MainForm : TMainForm;

implementation

uses
  uPoseImage, CastleTransform;

const
  MODEL_FILE = 'movenet.tflite';

constructor TMainForm.Create(AOwner : TComponent);
begin
  inherited CreateNew(AOwner);

  Caption      := 'Pose Motion - TensorFlow Lite MoveNet + Castle Game Engine';
  ClientWidth  := 1100;
  ClientHeight := 700;

  FSolver := TPoseSolver.Create;
  FFrame  := TBitmap.Create;
  FWatch  := TStopwatch.StartNew;

  BuildUi;
  BuildScene;
  LoadModel;

  OnShow := FormShowEvent;
end;

destructor TMainForm.Destroy;
begin
  if (FCamera <> nil) then FCamera.Active := False;

  FMoveNet.Free;
  FSolver.Free;
  FFrame.Free;

  inherited Destroy;
end;

function TMainForm.NewLabel(aParent : TControl; aHeight : Single) : TLabel;
begin
  Result          := TLabel.Create(Self);
  Result.Parent   := aParent;
  Result.Align    := TAlignLayout.Top;
  Result.Height   := aHeight;
  Result.WordWrap := True;
end;

function TMainForm.NewCheck(const aText : string; aChecked : boolean) : TCheckBox;
begin
  Result           := TCheckBox.Create(Self);
  Result.Parent    := FPanel;
  Result.Align     := TAlignLayout.Top;
  Result.Height    := 28;
  Result.Text      := aText;
  Result.IsChecked := aChecked;
  Result.OnChange  := OptionChanged;
end;

procedure TMainForm.BuildUi;
begin
  FPanel        := TLayout.Create(Self);
  FPanel.Parent := Self;
  FPanel.Align  := TAlignLayout.Left;
  FPanel.Width  := 340;

  FPreview          := TImage.Create(Self);
  FPreview.Parent   := FPanel;
  FPreview.Align    := TAlignLayout.Top;
  FPreview.Height   := 255;
  FPreview.WrapMode := TImageWrapMode.Fit;

  FStatus := NewLabel(FPanel, 90);
  FStatus.Text := 'Starting...';

  FMirrorCheck := NewCheck('Mirror (the avatar moves like a reflection)', True);
  FDepthCheck  := NewCheck('Flip the depth direction of the limbs', False);

  FResetButton         := TButton.Create(Self);
  FResetButton.Parent  := FPanel;
  FResetButton.Align   := TAlignLayout.Top;
  FResetButton.Height  := 32;
  FResetButton.Margins.Top := 6;
  FResetButton.Text    := 'Calibrate again (stand straight, facing the camera)';
  FResetButton.OnClick := ResetClick;

  FSolver.Mirror := FMirrorCheck.IsChecked;
end;

procedure TMainForm.BuildScene;
var
  TempLight : TCastleDirectionalLight;
begin
  FControl        := TCastleControl.Create(Self);
  FControl.Parent := Self;
  FControl.Align  := TAlignLayout.Client;

  FViewport                 := TCastleViewport.Create(Self);
  FViewport.FullSize        := True;
  FViewport.BackgroundColor := Vector4(0.10, 0.12, 0.16, 1);
  FViewport.Camera.SetWorldView(
    Vector3(0, 1.15, 3.6),
    Vector3(0, -0.04, -1),
    Vector3(0, 1, 0));
  FControl.Container.InsertFront(FViewport);

  // Key light and a weaker fill light
  TempLight           := TCastleDirectionalLight.Create(Self);
  TempLight.Direction := Vector3(-0.35, -1, -0.6);
  FViewport.Items.Add(TempLight);

  TempLight           := TCastleDirectionalLight.Create(Self);
  TempLight.Direction := Vector3(0.6, -0.3, -0.7);
  TempLight.Intensity := 0.5;
  FViewport.Items.Add(TempLight);

  FAvatar := TMaleAvatar.Create(Self);
  FViewport.Items.Add(FAvatar);
end;

// Searches next to the executable and in the parent folders (models, bin).
function TMainForm.FindFile(const aName : string) : string;
var
  TempDir : string;
  i : integer;
begin
  TempDir := ExtractFilePath(ParamStr(0));

  for i := 0 to 4 do
    begin
      Result := TPath.Combine(TempDir, aName);
      if FileExists(Result) then exit;

      Result := TPath.Combine(TPath.Combine(TempDir, 'models'), aName);
      if FileExists(Result) then exit;

      TempDir := ExtractFilePath(ExcludeTrailingPathDelimiter(TempDir));
    end;

  Result := '';
end;

procedure TMainForm.LoadModel;
var
  TempPath : string;
begin
  if (ParamCount >= 1) then
    TempPath := ParamStr(1)
   else
    TempPath := FindFile(MODEL_FILE);

  if (TempPath = '') then
    begin
      FStatus.Text := 'The model ' + MODEL_FILE + ' was not found. See models/README.md.';
      exit;
    end;

  try
    FMoveNet := TMoveNet.Create(TempPath);
    SetLength(FInput, FMoveNet.InputSize * FMoveNet.InputSize * 3);
    FStatus.Text := 'Model loaded : ' + ExtractFileName(TempPath) +
                    ' (' + IntToStr(FMoveNet.InputSize) + 'x' + IntToStr(FMoveNet.InputSize) + ')';
  except
    on e : Exception do
      begin
        FMoveNet.Free;
        FMoveNet := nil;
        FStatus.Text := 'Error : ' + e.Message;
      end;
  end;
end;

procedure TMainForm.FormShowEvent(Sender : TObject);
begin
  if (FMoveNet = nil) then exit;

  FCamera                   := TCameraComponent.Create(Self);
  FCamera.Quality           := TVideoCaptureQuality.MediumQuality;
  FCamera.OnSampleBufferReady := CameraFrame;
  FCamera.Active            := True;
end;

procedure TMainForm.OptionChanged(Sender : TObject);
begin
  FSolver.Mirror := FMirrorCheck.IsChecked;

  if FDepthCheck.IsChecked then
    FSolver.DepthSign := -1
   else
    FSolver.DepthSign := 1;
end;

procedure TMainForm.ResetClick(Sender : TObject);
begin
  FSolver.Reset;
end;

procedure TMainForm.CameraFrame(Sender : TObject; const ATime : TMediaTime);
var
  TempData : TBitmapData;
  TempKp : TKeypoints;
  TempPose : TAvatarPose;
  TempCropX, TempCropY, TempCropSize, i : integer;
  TempNow, TempStart, TempMs : Double;
begin
  if (FMoveNet = nil) then exit;

  FCamera.SampleBufferToBitmap(FFrame, True);

  if FFrame.IsEmpty then exit;

  if not(FFrame.Map(TMapAccess.Read, TempData)) then exit;

  try
    CropResizeToRGB(TempData.Data, FFrame.Width, FFrame.Height, TempData.Pitch,
                    FFrame.PixelFormat <> TPixelFormat.RGBA,
                    @FInput[0], FMoveNet.InputSize,
                    TempCropX, TempCropY, TempCropSize);
  finally
    FFrame.Unmap(TempData);
  end;

  TempStart := FWatch.Elapsed.TotalSeconds;
  try
    TempKp := FMoveNet.Detect(@FInput[0]);
  except
    on e : Exception do
      begin
        FStatus.Text := 'Error : ' + e.Message;
        FCamera.Active := False;
        exit;
      end;
  end;
  TempNow := FWatch.Elapsed.TotalSeconds;
  TempMs  := (TempNow - TempStart) * 1000;

  // Keypoints : relative to the square -> pixels of the camera frame
  for i := 0 to pred(KEYPOINT_COUNT) do
    begin
      TempKp[i].X := TempCropX + (TempKp[i].X * TempCropSize);
      TempKp[i].Y := TempCropY + (TempKp[i].Y * TempCropSize);
    end;

  TempPose := FSolver.Solve(TempKp, FFrame.Width, FFrame.Height, TempNow);
  FAvatar.ApplyPose(TempPose);

  DrawKeypoints(TempKp);

  if (FLastFrame > 0) and (TempNow > FLastFrame) then
    FFps := (0.9 * FFps) + (0.1 / (TempNow - FLastFrame));
  FLastFrame := TempNow;

  if TempPose.Valid then
    FStatus.Text := Format('%.0f FPS, inference %.1f ms', [FFps, TempMs])
   else
    FStatus.Text := 'No body found. Stand in front of the camera, so that the shoulders and hips are visible.';
end;

procedure TMainForm.DrawKeypoints(const aKp : TKeypoints);
var
  i : integer;
begin
  FPreview.Bitmap.Assign(FFrame);

  if FPreview.Bitmap.Canvas.BeginScene then
    try
      FPreview.Bitmap.Canvas.Fill.Color := TAlphaColors.Lime;

      for i := 0 to pred(KEYPOINT_COUNT) do
        if (aKp[i].Score >= FSolver.MinScore) then
          FPreview.Bitmap.Canvas.FillEllipse(
            RectF(aKp[i].X - 5, aKp[i].Y - 5, aKp[i].X + 5, aKp[i].Y + 5), 1);
    finally
      FPreview.Bitmap.Canvas.EndScene;
    end;
end;

end.

unit uMainForm;

// Main form : the camera image and its keypoints on the left, the 3D human
// model (Castle Game Engine) on the right. The whole form is created in code.

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes,
  System.Diagnostics, System.IOUtils, System.Zip,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Layouts, FMX.StdCtrls,
  FMX.Objects, FMX.Media, FMX.ListBox, FMX.Controls.Presentation,
  Fmx.CastleControl,
  CastleViewport, CastleScene, CastleVectors,
  uPoseSolver, uPoseEstimator, uPoseModels, uRiggedAvatar;

type
  TMainForm = class(TForm)
    protected
      FPanel        : TLayout;
      FPreview      : TImage;
      FStatus       : TLabel;
      FPoseCombo    : TComboBox;
      FBodyCombo    : TComboBox;
      FMirrorCheck  : TCheckBox;
      FDepthCheck   : TCheckBox;
      FResetButton  : TButton;
      FControl      : TCastleControl;
      FViewport     : TCastleViewport;
      FAvatar       : TRiggedAvatar;
      FCamera       : TCameraComponent;
      FFrame        : TBitmap;
      FPose         : TPoseEstimator;
      FSolver       : TPoseSolver;
      FPoseFiles    : TStringList;
      FBodyFiles    : TStringList;
      FWatch        : TStopwatch;
      FLastFrame    : Double;
      FFps          : Double;
      FMessage      : string;

      function  NewLabel(aParent : TControl; aHeight : Single) : TLabel;
      function  NewCheck(const aText : string; aChecked : boolean) : TCheckBox;
      function  NewCombo(const aCaption : string) : TComboBox;
      procedure ScanFiles;
      procedure AddFiles(const aDir, aPattern : string; aList : TStrings);
      function  ExtractFromZip(const aZipFile, aSuffix : string) : string;
      function  ResolveBodyFile(const aFile : string) : string;
      function  ResolvePoseFile(const aFile : string) : string;
      procedure BuildUi;
      procedure BuildScene;
      procedure LoadPoseModel(const aFile : string);
      procedure LoadBodyModel(const aFile : string);
      procedure PoseChanged(Sender : TObject);
      procedure BodyChanged(Sender : TObject);
      procedure OptionChanged(Sender : TObject);
      procedure ResetClick(Sender : TObject);
      procedure FormShowEvent(Sender : TObject);
      procedure CameraFrame(Sender : TObject; const ATime : TMediaTime);
      procedure DrawKeypoints(const aResult : TPoseResult);
    public
      constructor Create(AOwner : TComponent); override;
      destructor  Destroy; override;
  end;

var
  MainForm : TMainForm;

implementation

uses
  CastleTransform;

// BlazePose (3D) before MoveNet (2D) : the names are sorted backwards
function CompareModelNames(aList : TStringList; aIndex1, aIndex2 : integer) : integer;
begin
  Result := -CompareText(ExtractFileName(aList[aIndex1]), ExtractFileName(aList[aIndex2]));
end;

constructor TMainForm.Create(AOwner : TComponent);
begin
  inherited CreateNew(AOwner);

  Caption      := 'Pose Motion - TensorFlow Lite + Castle Game Engine';
  ClientWidth  := 1100;
  ClientHeight := 720;

  FSolver    := TPoseSolver.Create;
  FFrame     := TBitmap.Create;
  FWatch     := TStopwatch.StartNew;
  FPoseFiles := TStringList.Create;
  FBodyFiles := TStringList.Create;

  ScanFiles;
  BuildUi;
  BuildScene;

  // Command line : pose model, body model. Otherwise the first files that are found.
  if (ParamCount >= 2) then
    LoadBodyModel(ParamStr(2))
   else
    if (FBodyFiles.Count > 0) then
      LoadBodyModel(FBodyFiles[0]);

  if (ParamCount >= 1) then
    LoadPoseModel(ParamStr(1))
   else
    if (FPoseFiles.Count > 0) then
      LoadPoseModel(FPoseFiles[0])
     else
      FMessage := 'No pose model (.tflite) was found. See models/README.md.';

  FStatus.Text := FMessage;
  OnShow := FormShowEvent;
end;

destructor TMainForm.Destroy;
begin
  if (FCamera <> nil) then FCamera.Active := False;

  FPose.Free;
  FSolver.Free;
  FFrame.Free;
  FPoseFiles.Free;
  FBodyFiles.Free;

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

function TMainForm.NewCombo(const aCaption : string) : TComboBox;
var
  TempLabel : TLabel;
begin
  TempLabel      := NewLabel(FPanel, 20);
  TempLabel.Text := aCaption;

  Result         := TComboBox.Create(Self);
  Result.Parent  := FPanel;
  Result.Align   := TAlignLayout.Top;
  Result.Height  := 28;
end;

// Adds the files of aDir to aList when they are not there yet (same file name).
procedure TMainForm.AddFiles(const aDir, aPattern : string; aList : TStrings);
var
  TempFile : string;
  i : integer;
  TempFound : boolean;
begin
  if not(DirectoryExists(aDir)) then exit;

  for TempFile in TDirectory.GetFiles(aDir, aPattern) do
    begin
      TempFound := False;

      for i := 0 to pred(aList.Count) do
        if SameText(ExtractFileName(aList[i]), ExtractFileName(TempFile)) then
          TempFound := True;

      if not(TempFound) then
        aList.Add(TempFile);
    end;
end;

// Searches the models next to the executable, in a models folder and in the parent folders.
procedure TMainForm.ScanFiles;
var
  TempDir : string;
  i : integer;
begin
  TempDir := ExcludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0)));

  for i := 0 to 4 do
    begin
      AddFiles(TempDir, '*.tflite', FPoseFiles);
      AddFiles(TempDir, '*.task', FPoseFiles);
      AddFiles(TPath.Combine(TempDir, 'models'), '*.task', FPoseFiles);
      AddFiles(TPath.Combine(TempDir, 'models'), '*.tflite', FPoseFiles);
      AddFiles(TempDir, '*.glb', FBodyFiles);
      AddFiles(TPath.Combine(TempDir, 'models'), '*.glb', FBodyFiles);
      AddFiles(TPath.Combine(TempDir, 'models'), '*.zip', FBodyFiles);

      TempDir := ExcludeTrailingPathDelimiter(ExtractFilePath(TempDir));
    end;

  // BlazePose (3D) before MoveNet (2D)
  FPoseFiles.CustomSort(CompareModelNames);
end;

// Extracts the first file of the zip whose name ends with aSuffix to the
// temporary folder (once) and returns its path.
function TMainForm.ExtractFromZip(const aZipFile, aSuffix : string) : string;
var
  TempZip : TZipFile;
  TempDir : string;
  i : integer;
begin
  TempDir := TPath.Combine(TPath.GetTempPath, 'PoseMotion');
  ForceDirectories(TempDir);

  TempZip := TZipFile.Create;
  try
    TempZip.Open(aZipFile, zmRead);

    for i := 0 to pred(TempZip.FileCount) do
      if TempZip.FileName[i].ToLower.EndsWith(aSuffix.ToLower) then
        begin
          Result := TPath.Combine(TempDir, ExtractFileName(TempZip.FileName[i]));

          if not(FileExists(Result)) or (TFile.GetSize(Result) <> TempZip.FileInfo[i].UncompressedSize) then
            TempZip.Extract(i, TempDir, False);

          exit;
        end;
  finally
    TempZip.Free;
  end;

  raise Exception.CreateFmt('%s has no %s file', [aZipFile, aSuffix]);
end;

// A body model can be a .zip that has the .glb file.
function TMainForm.ResolveBodyFile(const aFile : string) : string;
begin
  if SameText(ExtractFileExt(aFile), '.zip') then
    Result := ExtractFromZip(aFile, '.glb')
   else
    Result := aFile;
end;

// A pose model can be a MediaPipe .task file : a zip with the landmark model.
function TMainForm.ResolvePoseFile(const aFile : string) : string;
begin
  if SameText(ExtractFileExt(aFile), '.task') then
    Result := ExtractFromZip(aFile, 'landmarks_detector.tflite')
   else
    Result := aFile;
end;

procedure TMainForm.BuildUi;
var
  i : integer;
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

  FStatus := NewLabel(FPanel, 70);
  FStatus.Text := 'Starting...';

  FPoseCombo := NewCombo('Pose model (BlazePose = 3D, MoveNet = 2D)');
  for i := 0 to pred(FPoseFiles.Count) do
    FPoseCombo.Items.Add(ExtractFileName(FPoseFiles[i]));
  if (FPoseCombo.Items.Count > 0) then FPoseCombo.ItemIndex := 0;
  FPoseCombo.OnChange := PoseChanged;

  FBodyCombo := NewCombo('3D model');
  for i := 0 to pred(FBodyFiles.Count) do
    FBodyCombo.Items.Add(ExtractFileName(FBodyFiles[i]));
  if (FBodyCombo.Items.Count > 0) then FBodyCombo.ItemIndex := 0;
  FBodyCombo.OnChange := BodyChanged;

  FMirrorCheck := NewCheck('Mirror (the avatar moves like a reflection)', True);
  FDepthCheck  := NewCheck('Flip the depth direction', False);

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
  TempGround : TCastleBox;
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

  TempGround             := TCastleBox.Create(Self);
  TempGround.Size        := Vector3(6, 0.02, 6);
  TempGround.Translation := Vector3(0, -0.01, 0);
  TempGround.Color       := Vector4(0.30, 0.33, 0.30, 1);
  FViewport.Items.Add(TempGround);
end;

procedure TMainForm.LoadPoseModel(const aFile : string);
begin
  FreeAndNil(FPose);

  try
    FPose := LoadPoseEstimator(ResolvePoseFile(aFile));
    FMessage := 'Pose model : ' + FPose.Name;
  except
    on e : Exception do
      FMessage := 'Error : ' + e.Message;
  end;

  FSolver.Reset;
end;

procedure TMainForm.LoadBodyModel(const aFile : string);
var
  TempAvatar : TRiggedAvatar;
begin
  try
    TempAvatar := TRiggedAvatar.Create(Self, ResolveBodyFile(aFile));
  except
    on e : Exception do
      begin
        FMessage := 'Error : ' + e.Message;
        exit;
      end;
  end;

  if (FAvatar <> nil) then
    begin
      FViewport.Items.Remove(FAvatar);
      FAvatar.Free;
    end;

  FAvatar := TempAvatar;
  FViewport.Items.Add(FAvatar);
  FSolver.Reset;
end;

procedure TMainForm.FormShowEvent(Sender : TObject);
begin
  FCamera                     := TCameraComponent.Create(Self);
  FCamera.Quality             := TVideoCaptureQuality.MediumQuality;
  FCamera.OnSampleBufferReady := CameraFrame;
  FCamera.Active              := True;
end;

procedure TMainForm.PoseChanged(Sender : TObject);
begin
  if (FPoseCombo.ItemIndex >= 0) then
    begin
      LoadPoseModel(FPoseFiles[FPoseCombo.ItemIndex]);
      FStatus.Text := FMessage;
    end;
end;

procedure TMainForm.BodyChanged(Sender : TObject);
begin
  if (FBodyCombo.ItemIndex >= 0) then
    begin
      LoadBodyModel(FBodyFiles[FBodyCombo.ItemIndex]);
      FStatus.Text := FMessage;
    end;
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

  if (FPose <> nil) then
    FPose.ResetTracking;
end;

procedure TMainForm.CameraFrame(Sender : TObject; const ATime : TMediaTime);
var
  TempData : TBitmapData;
  TempResult : TPoseResult;
  TempPose : TAvatarPose;
  TempNow, TempStart, TempMs : Double;
begin
  if (FPose = nil) or (FAvatar = nil) then exit;

  FCamera.SampleBufferToBitmap(FFrame, True);

  if FFrame.IsEmpty then exit;

  if not(FFrame.Map(TMapAccess.Read, TempData)) then exit;

  TempStart := FWatch.Elapsed.TotalSeconds;
  try
    try
      TempResult := FPose.Estimate(TempData.Data, FFrame.Width, FFrame.Height, TempData.Pitch,
                                   FFrame.PixelFormat <> TPixelFormat.RGBA);
    finally
      FFrame.Unmap(TempData);
    end;
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

  if TempResult.Found then
    begin
      if TempResult.Has3D then
        TempPose := FSolver.Solve3D(TempResult.Keypoints, TempResult.World, FFrame.Width, FFrame.Height, TempNow)
       else
        TempPose := FSolver.Solve(TempResult.Keypoints, FFrame.Width, FFrame.Height, TempNow);

      FAvatar.ApplyPose(TempPose);
    end
   else
    TempPose.Valid := False;

  DrawKeypoints(TempResult);

  if (FLastFrame > 0) and (TempNow > FLastFrame) then
    FFps := (0.9 * FFps) + (0.1 / (TempNow - FLastFrame));
  FLastFrame := TempNow;

  if TempPose.Valid then
    FStatus.Text := Format('%s'#13#10'%.0f FPS, inference %.1f ms', [FPose.Name, FFps, TempMs])
   else
    FStatus.Text := 'No body found. Stand in front of the camera, so that the shoulders and hips are visible.';
end;

procedure TMainForm.DrawKeypoints(const aResult : TPoseResult);
var
  i : integer;
begin
  FPreview.Bitmap.Assign(FFrame);

  if not(aResult.Found) then exit;

  if FPreview.Bitmap.Canvas.BeginScene then
    try
      FPreview.Bitmap.Canvas.Fill.Color := TAlphaColors.Lime;

      for i := 0 to pred(KEYPOINT_COUNT) do
        if (aResult.Keypoints[i].Score >= FSolver.MinScore) then
          FPreview.Bitmap.Canvas.FillEllipse(
            RectF(aResult.Keypoints[i].X - 5, aResult.Keypoints[i].Y - 5,
                  aResult.Keypoints[i].X + 5, aResult.Keypoints[i].Y + 5), 1);
    finally
      FPreview.Bitmap.Canvas.EndScene;
    end;
end;

end.

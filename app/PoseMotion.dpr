program PoseMotion;

// Real time pose measurement (TensorFlow Lite : BlazePose 3D or MoveNet 2D)
// that moves a rigged glTF human model (Castle Game Engine). FMX application
// for Windows.
//
// Command line (all optional) :  PoseMotion.exe [pose model .tflite] [body model .glb/.zip]

uses
  FMX.Forms,
  Fmx.CastleControl,
  uMainForm in 'uMainForm.pas',
  uTFLite in '..\src\uTFLite.pas',
  uPoseImage in '..\src\uPoseImage.pas',
  uPoseSolver in '..\src\uPoseSolver.pas',
  uPoseRig in '..\src\uPoseRig.pas',
  uPoseEstimator in '..\src\uPoseEstimator.pas',
  uBlazeDecode in '..\src\uBlazeDecode.pas',
  uMoveNet in '..\src\uMoveNet.pas',
  uBlazePose in '..\src\uBlazePose.pas',
  uPoseModels in '..\src\uPoseModels.pas',
  uRiggedAvatar in '..\src\uRiggedAvatar.pas';

begin
  Application.Initialize;
  Application.CreateForm(TMainForm, MainForm);
  TCastleControl.ApplicationRun;
end.

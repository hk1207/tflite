program PoseMotion;

// Real time pose measurement (TensorFlow Lite MoveNet) that moves a 3D male
// model (Castle Game Engine). FMX application for Windows.

uses
  FMX.Forms,
  Fmx.CastleControl,
  uMainForm in 'uMainForm.pas',
  uTFLite in '..\src\uTFLite.pas',
  uMoveNet in '..\src\uMoveNet.pas',
  uPoseImage in '..\src\uPoseImage.pas',
  uPoseSolver in '..\src\uPoseSolver.pas',
  uMaleAvatar in '..\src\uMaleAvatar.pas';

begin
  Application.Initialize;
  Application.CreateForm(TMainForm, MainForm);
  TCastleControl.ApplicationRun;
end.

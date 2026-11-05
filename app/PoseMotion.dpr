program PoseMotion;

// Real time pose measurement (TensorFlow Lite or ONNX Runtime : BlazePose 3D,
// MoveNet / YOLO pose 2D, or MediaPipe through a Python bridge)
// that moves a rigged glTF human model (Castle Game Engine). FMX application
// for Windows.
//
// Command line (all optional) :  PoseMotion.exe [pose model .tflite/.onnx/.task or udp://127.0.0.1:5005] [body model .glb/.zip]

uses
  FMX.Forms,
  Fmx.CastleControl,
  uMainForm in 'uMainForm.pas',
  uInference in '..\src\uInference.pas',
  uTFLite in '..\src\uTFLite.pas',
  uOnnxRuntime in '..\src\uOnnxRuntime.pas',
  uPoseImage in '..\src\uPoseImage.pas',
  uPoseSolver in '..\src\uPoseSolver.pas',
  uPoseRig in '..\src\uPoseRig.pas',
  uPoseEstimator in '..\src\uPoseEstimator.pas',
  uBlazeDecode in '..\src\uBlazeDecode.pas',
  uBlazeDetect in '..\src\uBlazeDetect.pas',
  uMoveNet in '..\src\uMoveNet.pas',
  uBlazePose in '..\src\uBlazePose.pas',
  uYoloDecode in '..\src\uYoloDecode.pas',
  uYoloPose in '..\src\uYoloPose.pas',
  uMediaPipeProtocol in '..\src\uMediaPipeProtocol.pas',
  uMediaPipeBridge in '..\src\uMediaPipeBridge.pas',
  uPoseModels in '..\src\uPoseModels.pas',
  uRiggedAvatar in '..\src\uRiggedAvatar.pas';

begin
  Application.Initialize;
  Application.CreateForm(TMainForm, MainForm);
  TCastleControl.ApplicationRun;
end.

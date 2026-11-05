program TestPose;

// Console tests of the pose solver and image preparation (no Windows needed).
// Build with Free Pascal :
//   fpc -Mdelphi -Fu../src TestPose.pas

{$MODE Delphi}
{$APPTYPE CONSOLE}

uses
  SysUtils, Math, uPoseSolver, uPoseImage;

var
  Failures : integer = 0;
  Total    : integer = 0;

procedure Check(const aName : string; aCondition : boolean; const aInfo : string = '');
begin
  inc(Total);
  if aCondition then
    writeln('ok    ', aName)
   else
    begin
      inc(Failures);
      writeln('FAIL  ', aName, ' ', aInfo);
    end;
end;

function Near(a, b, aTol : Single) : boolean;
begin
  Result := Abs(a - b) <= aTol;
end;

const
  FRAME_W = 1920;
  FRAME_H = 1080;

// Projects a body position (meters, pelvis at the origin height) to pixels
procedure Put(var aKp : TKeypoints; aIdx : integer; aX, aY : Single; aMPerPx : Single);
begin
  aKp[aIdx].X     := (FRAME_W / 2) + (aX / aMPerPx);
  aKp[aIdx].Y     := (FRAME_H / 2) - ((aY - 1.0) / aMPerPx);
  aKp[aIdx].Score := 1;
end;

// A person standing and facing the camera. aArms : 0 = hanging, 1 = T-pose,
// 2 = pointing to the camera
function Standing(aMPerPx : Single; aArms : integer; aNoseDx : Single) : TKeypoints;
var
  TempHip, TempSh, TempSide : Single;
begin
  FillChar(Result, SizeOf(Result), 0);

  TempHip  := PELVIS_HEIGHT;
  TempSh   := PELVIS_HEIGHT + TORSO_LEN;
  TempSide := SHOULDER_WIDTH / 2;

  // person's left = +X
  Put(Result, KP_L_SHOULDER,  TempSide, TempSh, aMPerPx);
  Put(Result, KP_R_SHOULDER, -TempSide, TempSh, aMPerPx);
  Put(Result, KP_L_HIP,       HIP_WIDTH / 2, TempHip, aMPerPx);
  Put(Result, KP_R_HIP,      -HIP_WIDTH / 2, TempHip, aMPerPx);
  Put(Result, KP_L_KNEE,      HIP_WIDTH / 2, TempHip - THIGH_LEN, aMPerPx);
  Put(Result, KP_R_KNEE,     -HIP_WIDTH / 2, TempHip - THIGH_LEN, aMPerPx);
  Put(Result, KP_L_ANKLE,     HIP_WIDTH / 2, FOOT_HEIGHT, aMPerPx);
  Put(Result, KP_R_ANKLE,    -HIP_WIDTH / 2, FOOT_HEIGHT, aMPerPx);
  Put(Result, KP_L_EAR,       0.08, TempSh + HEAD_DISTANCE, aMPerPx);
  Put(Result, KP_R_EAR,      -0.08, TempSh + HEAD_DISTANCE, aMPerPx);
  Put(Result, KP_NOSE,        aNoseDx, TempSh + HEAD_DISTANCE - 0.03, aMPerPx);

  case aArms of
    0 : begin
          Put(Result, KP_L_ELBOW,  TempSide, TempSh - UPPER_ARM_LEN, aMPerPx);
          Put(Result, KP_R_ELBOW, -TempSide, TempSh - UPPER_ARM_LEN, aMPerPx);
          Put(Result, KP_L_WRIST,  TempSide, TempSh - UPPER_ARM_LEN - FOREARM_LEN, aMPerPx);
          Put(Result, KP_R_WRIST, -TempSide, TempSh - UPPER_ARM_LEN - FOREARM_LEN, aMPerPx);
        end;
    1 : begin
          Put(Result, KP_L_ELBOW,  TempSide + UPPER_ARM_LEN, TempSh, aMPerPx);
          Put(Result, KP_R_ELBOW, -TempSide - UPPER_ARM_LEN, TempSh, aMPerPx);
          Put(Result, KP_L_WRIST,  TempSide + UPPER_ARM_LEN + FOREARM_LEN, TempSh, aMPerPx);
          Put(Result, KP_R_WRIST, -TempSide - UPPER_ARM_LEN - FOREARM_LEN, TempSh, aMPerPx);
        end;
    2 : begin
          // The left arm points to the camera : the 2D positions are the same
          // as the shoulder.
          Put(Result, KP_L_ELBOW,  TempSide, TempSh, aMPerPx);
          Put(Result, KP_L_WRIST,  TempSide, TempSh, aMPerPx);
          Put(Result, KP_R_ELBOW, -TempSide, TempSh - UPPER_ARM_LEN, aMPerPx);
          Put(Result, KP_R_WRIST, -TempSide, TempSh - UPPER_ARM_LEN - FOREARM_LEN, aMPerPx);
        end;
  end;
end;

// Feeds the same keypoints for some frames, so the filters settle
function SolveFrames(aSolver : TPoseSolver; const aKp : TKeypoints; aFrames : integer) : TAvatarPose;
var
  i : integer;
begin
  for i := 0 to pred(aFrames) do
    Result := aSolver.Solve(aKp, FRAME_W, FRAME_H, i / 30);
end;

function Dist(const a, b : TVec3) : Single;
begin
  Result := VecLength(VecSub(a, b));
end;

var
  TempSolver : TPoseSolver;
  TempPose, TempPose2 : TAvatarPose;
  TempKp : TKeypoints;
  TempAxis, TempV, TempDir : TVec3;
  TempAngle : Single;
  i, j : integer;
  TempSrc : array[0..(8 * 6 * 4) - 1] of Byte;
  TempDst : array[0..(4 * 4 * 3) - 1] of Byte;
  TempCx, TempCy, TempCs : integer;
  TempFilter : TOneEuroFilter;
  TempOut : Single;
begin
  // ---- Vector helpers ----
  for i := 0 to 5 do
    begin
      case i of
        0 : TempDir := Vec3(0, 1, 0);
        1 : TempDir := Vec3(0, -1, 0);
        2 : TempDir := Vec3(1, 0, 0);
        3 : TempDir := Vec3(0.3, -0.5, 0.8);
        4 : TempDir := Vec3(-0.7, 0.2, -0.4);
        5 : TempDir := Vec3(0, 0, 1);
      end;
      AlignYAxis(TempDir, TempAxis, TempAngle);
      TempV := RotateAroundAxis(Vec3(0, 1, 0), TempAxis, TempAngle);
      TempDir := Vec3(TempDir.X / VecLength(TempDir), TempDir.Y / VecLength(TempDir), TempDir.Z / VecLength(TempDir));
      Check('AlignYAxis ' + IntToStr(i),
            Near(TempV.X, TempDir.X, 0.001) and Near(TempV.Y, TempDir.Y, 0.001) and Near(TempV.Z, TempDir.Z, 0.001));
    end;

  // ---- Standing, arms hanging ----
  TempSolver := TPoseSolver.Create;
  try
    TempPose := SolveFrames(TempSolver, Standing(0.0018, 0, 0), 5);
    Check('standing valid', TempPose.Valid);
    Check('pelvis height', Near(TempPose.Joints[jPelvis].Y, PELVIS_HEIGHT, 0.01));
    Check('chest height', Near(TempPose.Joints[jChest].Y, PELVIS_HEIGHT + TORSO_LEN, 0.01));
    Check('shoulder width', Near(Dist(TempPose.Joints[jLShoulder], TempPose.Joints[jRShoulder]), SHOULDER_WIDTH, 0.01));
    Check('left is +X', TempPose.Joints[jLShoulder].X > 0);
    Check('upper arm length', Near(Dist(TempPose.Joints[jLShoulder], TempPose.Joints[jLElbow]), UPPER_ARM_LEN, 0.01));
    Check('forearm length', Near(Dist(TempPose.Joints[jLElbow], TempPose.Joints[jLWrist]), FOREARM_LEN, 0.01));
    Check('thigh length', Near(Dist(TempPose.Joints[jLHip], TempPose.Joints[jLKnee]), THIGH_LEN, 0.01));
    Check('shin length', Near(Dist(TempPose.Joints[jLKnee], TempPose.Joints[jLAnkle]), SHIN_LEN, 0.01));
    Check('ankle height', Near(TempPose.Joints[jLAnkle].Y, FOOT_HEIGHT, 0.02));
    Check('head height', Near(TempPose.Joints[jHead].Y, PELVIS_HEIGHT + TORSO_LEN + HEAD_DISTANCE, 0.02));
    Check('no yaw', Near(TempPose.TorsoYaw, 0, 0.05));
  finally
    TempSolver.Free;
  end;

  // ---- The distance to the camera doesn't change the size of the avatar ----
  TempSolver := TPoseSolver.Create;
  try
    TempPose := SolveFrames(TempSolver, Standing(0.0018, 1, 0), 5);
  finally
    TempSolver.Free;
  end;
  TempSolver := TPoseSolver.Create;
  try
    TempPose2 := SolveFrames(TempSolver, Standing(0.0036, 1, 0), 5);
  finally
    TempSolver.Free;
  end;
  Check('same size when far', Near(Dist(TempPose.Joints[jLWrist], TempPose.Joints[jRWrist]),
                                   Dist(TempPose2.Joints[jLWrist], TempPose2.Joints[jRWrist]), 0.02));

  // ---- T-pose : arms in the image plane ----
  TempSolver := TPoseSolver.Create;
  try
    TempPose := SolveFrames(TempSolver, Standing(0.0018, 1, 0), 5);
    Check('T-pose wrist distance', Near(Dist(TempPose.Joints[jLWrist], TempPose.Joints[jRWrist]),
          SHOULDER_WIDTH + (2 * (UPPER_ARM_LEN + FOREARM_LEN)), 0.03));
    Check('T-pose wrist z', Near(TempPose.Joints[jLWrist].Z, 0, 0.03));
  finally
    TempSolver.Free;
  end;

  // ---- Arm pointing to the camera : depth from the missing length ----
  TempSolver := TPoseSolver.Create;
  try
    TempPose := SolveFrames(TempSolver, Standing(0.0018, 2, 0), 5);
    Check('arm to camera elbow z', Near(TempPose.Joints[jLElbow].Z, UPPER_ARM_LEN, 0.02));
    Check('arm to camera wrist z', Near(TempPose.Joints[jLWrist].Z, UPPER_ARM_LEN + FOREARM_LEN, 0.03));
    Check('arm to camera lengths', Near(Dist(TempPose.Joints[jLElbow], TempPose.Joints[jLWrist]), FOREARM_LEN, 0.02));
    TempSolver.DepthSign := -1;
    TempPose := SolveFrames(TempSolver, Standing(0.0018, 2, 0), 5);
    Check('DepthSign flips z', TempPose.Joints[jLElbow].Z < 0);
  finally
    TempSolver.Free;
  end;

  // ---- Mirror : the person's left side is shown on the other side ----
  TempSolver := TPoseSolver.Create;
  try
    TempKp := Standing(0.0018, 1, 0);
    TempSolver.Mirror := False;
    TempPose := SolveFrames(TempSolver, TempKp, 3);
  finally
    TempSolver.Free;
  end;
  TempSolver := TPoseSolver.Create;
  try
    TempSolver.Mirror := True;
    TempPose2 := SolveFrames(TempSolver, TempKp, 3);
    Check('mirror keeps anatomy', TempPose2.Joints[jLShoulder].X > 0);
    Check('mirror wrist', Near(TempPose2.Joints[jLWrist].X, TempPose.Joints[jLWrist].X, 0.03));
  finally
    TempSolver.Free;
  end;

  // ---- Turned body : narrow shoulders, yaw towards the nose ----
  TempSolver := TPoseSolver.Create;
  try
    TempKp := Standing(0.0018, 0, 0);
    // Turn 60 degrees : the horizontal distances become 0.5 * the width
    for i in [KP_L_SHOULDER, KP_L_HIP, KP_L_ELBOW, KP_L_WRIST, KP_L_KNEE, KP_L_ANKLE] do
      TempKp[i].X := (FRAME_W / 2) + ((TempKp[i].X - (FRAME_W / 2)) * 0.5);
    for i in [KP_R_SHOULDER, KP_R_HIP, KP_R_ELBOW, KP_R_WRIST, KP_R_KNEE, KP_R_ANKLE] do
      TempKp[i].X := (FRAME_W / 2) + ((TempKp[i].X - (FRAME_W / 2)) * 0.5);
    TempKp[KP_NOSE].X := (FRAME_W / 2) + 60;   // looking to the right of the image
    TempPose := SolveFrames(TempSolver, TempKp, 5);
    Check('yaw 60 degrees', Near(TempPose.TorsoYaw, DegToRad(60), 0.12), FloatToStr(RadToDeg(TempPose.TorsoYaw)));
    Check('right shoulder is nearer', TempPose.Joints[jRShoulder].Z > TempPose.Joints[jLShoulder].Z);
    Check('head yaw sign', TempPose.HeadYaw > 0);
  finally
    TempSolver.Free;
  end;

  // ---- Missing keypoints ----
  TempSolver := TPoseSolver.Create;
  try
    TempKp := Standing(0.0018, 0, 0);
    TempPose := SolveFrames(TempSolver, TempKp, 5);
    TempKp[KP_L_WRIST].Score := 0.01;
    TempKp[KP_L_WRIST].X := 0;
    TempPose2 := SolveFrames(TempSolver, TempKp, 5);
    Check('low score keeps last value', Near(Dist(TempPose.Joints[jLWrist], TempPose2.Joints[jLWrist]), 0, 0.02));
    // Keypoints that were seen before are held when they disappear
    FillChar(TempKp, SizeOf(TempKp), 0);
    TempPose2 := TempSolver.Solve(TempKp, FRAME_W, FRAME_H, 10);
    Check('lost keypoints are held', TempPose2.Valid);
  finally
    TempSolver.Free;
  end;

  // A body that was never detected is not valid
  TempSolver := TPoseSolver.Create;
  try
    FillChar(TempKp, SizeOf(TempKp), 0);
    TempPose2 := TempSolver.Solve(TempKp, FRAME_W, FRAME_H, 0);
    Check('invalid frame', not(TempPose2.Valid));
  finally
    TempSolver.Free;
  end;

  // ---- Reset recalibrates ----
  TempSolver := TPoseSolver.Create;
  try
    TempKp := Standing(0.0018, 0, 0);
    SolveFrames(TempSolver, TempKp, 3);
    TempSolver.Reset;
    TempPose := SolveFrames(TempSolver, Standing(0.0036, 0, 0), 3);
    Check('reset rescales', Near(TempPose.Joints[jChest].Y, PELVIS_HEIGHT + TORSO_LEN, 0.02));
  finally
    TempSolver.Free;
  end;

  // ---- One Euro filter ----
  TempFilter := TOneEuroFilter.Create;
  try
    TempOut := 0;
    for i := 0 to 90 do TempOut := TempFilter.Filter(100, i / 30);
    Check('filter constant', Near(TempOut, 100, 0.001));
    for i := 91 to 150 do TempOut := TempFilter.Filter(200, i / 30);
    Check('filter follows a step', Near(TempOut, 200, 1));
  finally
    TempFilter.Free;
  end;

  // ---- Image crop and resize ----
  // 8x6 BGRA image, left half blue-ish, right half red-ish. The crop is 6x6 at x=1.
  for j := 0 to 5 do
    for i := 0 to 7 do
      begin
        TempSrc[((j * 8) + i) * 4 + 0] := 10;                       // B
        TempSrc[((j * 8) + i) * 4 + 1] := 20;                       // G
        TempSrc[((j * 8) + i) * 4 + 2] := 30;                       // R
        TempSrc[((j * 8) + i) * 4 + 3] := 255;
      end;
  CropResizeToRGB(@TempSrc[0], 8, 6, 8 * 4, True, @TempDst[0], 4, TempCx, TempCy, TempCs);
  Check('crop size', (TempCs = 6) and (TempCx = 1) and (TempCy = 0));
  Check('BGRA to RGB', (TempDst[0] = 30) and (TempDst[1] = 20) and (TempDst[2] = 10));
  CropResizeToRGB(@TempSrc[0], 8, 6, 8 * 4, False, @TempDst[0], 4, TempCx, TempCy, TempCs);
  Check('RGBA to RGB', (TempDst[0] = 10) and (TempDst[1] = 20) and (TempDst[2] = 30));

  writeln;
  writeln(Total, ' checks, ', Failures, ' failures');
  if (Failures > 0) then Halt(1);
end.

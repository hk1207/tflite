program TestPose;

// Console tests of the pose solver and image preparation (no Windows needed).
// Build with Free Pascal :
//   fpc -Mdelphi -Fu../src TestPose.pas

{$MODE Delphi}
{$APPTYPE CONSOLE}

uses
  SysUtils, Math, uPoseSolver, uPoseImage, uPoseRig, uRigFixtures, uPoseEstimator, uBlazeDecode, uYoloDecode, uMediaPipeProtocol, uBlazeDetect;

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

// 3D positions (meters) of the standing person : aArms 0 = hanging,
// 2 = the left arm points to the camera. aYaw turns the whole body.
function StandingWorld(aArms : integer; aYaw : Single) : TKeypoints3D;
var
  TempHip, TempSh, TempSide : Single;

  procedure W(aIdx : integer; aX, aY, aZ : Single);
  begin
    // turn around the vertical axis : x' = x cos + z sin, z' = -x sin + z cos
    Result[aIdx] := Vec3((aX * Cos(aYaw)) + (aZ * Sin(aYaw)), aY, (-aX * Sin(aYaw)) + (aZ * Cos(aYaw)));
  end;

begin
  FillChar(Result, SizeOf(Result), 0);

  TempHip  := PELVIS_HEIGHT;
  TempSh   := PELVIS_HEIGHT + TORSO_LEN;
  TempSide := SHOULDER_WIDTH / 2;

  W(KP_L_SHOULDER,  TempSide, TempSh, 0);
  W(KP_R_SHOULDER, -TempSide, TempSh, 0);
  W(KP_L_HIP,       HIP_WIDTH / 2, TempHip, 0);
  W(KP_R_HIP,      -HIP_WIDTH / 2, TempHip, 0);
  W(KP_L_KNEE,      HIP_WIDTH / 2, TempHip - THIGH_LEN, 0);
  W(KP_R_KNEE,     -HIP_WIDTH / 2, TempHip - THIGH_LEN, 0);
  W(KP_L_ANKLE,     HIP_WIDTH / 2, FOOT_HEIGHT, 0);
  W(KP_R_ANKLE,    -HIP_WIDTH / 2, FOOT_HEIGHT, 0);
  W(KP_L_EAR,       0.08, TempSh + HEAD_DISTANCE, 0);
  W(KP_R_EAR,      -0.08, TempSh + HEAD_DISTANCE, 0);
  W(KP_NOSE,        0, TempSh + HEAD_DISTANCE - 0.03, 0.10);
  W(KP_R_ELBOW,    -TempSide, TempSh - UPPER_ARM_LEN, 0);
  W(KP_R_WRIST,    -TempSide, TempSh - UPPER_ARM_LEN - FOREARM_LEN, 0);

  if (aArms = 2) then
    begin
      W(KP_L_ELBOW, TempSide, TempSh, UPPER_ARM_LEN);
      W(KP_L_WRIST, TempSide, TempSh, UPPER_ARM_LEN + FOREARM_LEN);
    end
   else
    begin
      W(KP_L_ELBOW, TempSide, TempSh - UPPER_ARM_LEN, 0);
      W(KP_L_WRIST, TempSide, TempSh - UPPER_ARM_LEN - FOREARM_LEN, 0);
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

function SolveFrames3D(aSolver : TPoseSolver; const aKp : TKeypoints; const aWorld : TKeypoints3D; aFrames : integer) : TAvatarPose;
var
  i : integer;
begin
  for i := 0 to pred(aFrames) do
    Result := aSolver.Solve3D(aKp, aWorld, FRAME_W, FRAME_H, i / 30);
end;

function Dist(const a, b : TVec3) : Single;
begin
  Result := VecLength(VecSub(a, b));
end;

// Checks the retargeting for a profile : every arm and leg bone has to point
// to the next joint of the pose, whatever the rest orientation of the bone is.
procedure CheckRig(const aName : string; const aProfile : TRigProfile; const aRest : TRigRestArray;
                   const aPose : TAvatarPose; aTol : Single);
var
  TempRig : TRigPose;
  TempNewW : array of TQuat;
  i, TempParent : integer;
  TempDir, TempWant : TVec3;
  TempWorst, TempErr : Single;
begin
  BuildRigPose(aProfile, aRest, aPose, TempRig);
  SetLength(TempNewW, length(aProfile.Bones));
  TempWorst := 0;

  for i := 0 to high(aProfile.Bones) do
    begin
      TempParent := aProfile.Bones[i].Parent;

      if (TempParent >= 0) then
        TempNewW[i] := QuatMul(TempNewW[TempParent], TempRig.Rotation[i])
       else
        TempNewW[i] := TempRig.Rotation[i];

      if (aProfile.Bones[i].Role = rrLimb) then
        begin
          TempDir  := VecNormalize(QuatRotate(TempNewW[i], aRest[aProfile.Bones[i].Child].Translation));
          TempWant := VecNormalize(VecSub(aPose.Joints[aProfile.Bones[i].ToJoint], aPose.Joints[aProfile.Bones[i].FromJoint]));
          TempErr  := Dist(TempDir, TempWant);
          if (TempErr > TempWorst) then TempWorst := TempErr;
        end;
    end;

  Check('rig ' + aProfile.Name + ' ' + aName, TempWorst <= aTol, 'worst error ' + FloatToStr(TempWorst));
end;

// The parents of the profile have to be the parents in the glb file
procedure CheckProfile(const aProfile : TRigProfile; const aParents : TStringArray);
var
  i, j : integer;
  TempOk, TempInList : boolean;
begin
  TempOk := (length(aParents) = length(aProfile.Bones));

  for i := 0 to high(aProfile.Bones) do
    if TempOk then
      if (aProfile.Bones[i].Parent >= 0) then
        begin
          if (aProfile.Bones[i].Parent >= i) or (aProfile.Bones[aProfile.Bones[i].Parent].Node <> aParents[i]) then
            begin
              TempOk := False;
              writeln('  parent of ', aProfile.Bones[i].Node, ' is ', aParents[i]);
            end;
        end
       else
        begin
          // The parent is not a bone of the profile
          TempInList := False;
          for j := 0 to high(aProfile.Bones) do
            if (aProfile.Bones[j].Node = aParents[i]) then TempInList := True;

          if TempInList then
            begin
              TempOk := False;
              writeln('  parent of ', aProfile.Bones[i].Node, ' is a bone : ', aParents[i]);
            end;
        end;

  Check('profile ' + aProfile.Name + ' hierarchy', TempOk);
end;

procedure CheckRigAll(const aName : string; const aPose : TAvatarPose; aTol : Single);
begin
  CheckRig(aName, GhwmaqProfile, GhwmaqRest, aPose, aTol);
  CheckRig(aName, GhwBodyProfile, GhwBodyRest, aPose, aTol);
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
  TempRig : TRigPose;
  TempLm : array[0..194] of Single;
  TempWorld : array[0..116] of Single;
  TempRoi, TempRoi2 : TBlazeRoi;
  TempRes : TPoseResult;
  TempAnchors : TBlazeAnchors;
  TempReg : array[0..(2254 * 12) - 1] of Single;
  TempScores : array[0..2253] of Single;
  TempScore : Single;
  TempRoi3 : TBlazeRoi;
  TempFile : TextFile;
  TempLine : string;
  TempYolo : array[0..(3 * 56) - 1] of Single;
  TempYolo2 : array[0..(3 * 56) - 1] of Single;
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

  CheckProfile(GhwmaqProfile, GhwmaqParents);
  CheckProfile(GhwBodyProfile, GhwBodyParents);

  // ---- Rig : the bones of both models point to the joints of the pose ----
  TempSolver := TPoseSolver.Create;
  try
    CheckRigAll('standing', SolveFrames(TempSolver, Standing(0.0018, 0, 0), 5), 0.001);
    TempSolver.Reset;
    CheckRigAll('T-pose', SolveFrames(TempSolver, Standing(0.0018, 1, 0), 5), 0.001);
    TempSolver.Reset;
    CheckRigAll('arm to the camera', SolveFrames(TempSolver, Standing(0.0018, 2, 0), 5), 0.001);
  finally
    TempSolver.Free;
  end;
  TempSolver := TPoseSolver.Create;
  try
    TempKp := Standing(0.0018, 0, 0);
    for i in [KP_L_SHOULDER, KP_L_HIP, KP_L_ELBOW, KP_L_WRIST, KP_L_KNEE, KP_L_ANKLE,
              KP_R_SHOULDER, KP_R_HIP, KP_R_ELBOW, KP_R_WRIST, KP_R_KNEE, KP_R_ANKLE] do
      TempKp[i].X := (FRAME_W / 2) + ((TempKp[i].X - (FRAME_W / 2)) * 0.5);
    TempKp[KP_NOSE].X := (FRAME_W / 2) + 60;
    CheckRigAll('turned body', SolveFrames(TempSolver, TempKp, 5), 0.001);
  finally
    TempSolver.Free;
  end;

  // The rig of a standing pose changes little : the legs stay down
  TempSolver := TPoseSolver.Create;
  try
    BuildRigPose(GhwmaqProfile, GhwmaqRest, SolveFrames(TempSolver, Standing(0.0018, 0, 0), 5), TempRig);
    Check('rig root offset (standing)', Near(TempRig.RootOffset.Y, 0, 0.01) and Near(TempRig.RootOffset.X, 0, 0.01));
    Check('rig has a rotation for each bone', length(TempRig.Rotation) = length(GhwmaqProfile.Bones));
  finally
    TempSolver.Free;
  end;

  // ---- Quaternions ----
  TempV := QuatRotate(QuatAlign(Vec3(0, -1, 0), Vec3(1, 0, 0)), Vec3(0, -1, 0));
  Check('QuatAlign', Near(TempV.X, 1, 0.001) and Near(TempV.Y, 0, 0.001));
  TempV := QuatRotate(QuatAlign(Vec3(0, -1, 0), Vec3(0, 1, 0)), Vec3(0, -1, 0));
  Check('QuatAlign opposite', Near(TempV.Y, 1, 0.001));
  QuatToAxisAngle(QuatFromAxisAngle(Vec3(0, 1, 0), 0.7), TempAxis, TempAngle);
  Check('QuatToAxisAngle', Near(TempAxis.Y, 1, 0.001) and Near(TempAngle, 0.7, 0.001));

  // ---- Solve3D : the depth and the turn are measured ----
  TempSolver := TPoseSolver.Create;
  try
    TempPose := SolveFrames3D(TempSolver, Standing(0.0018, 0, 0), StandingWorld(0, 0), 5);
    Check('3D valid', TempPose.Valid);
    Check('3D no yaw', Near(TempPose.TorsoYaw, 0, 0.02));
    Check('3D upper arm length', Near(Dist(TempPose.Joints[jLShoulder], TempPose.Joints[jLElbow]), UPPER_ARM_LEN, 0.01));
    Check('3D arm hangs', Near(TempPose.Joints[jLWrist].Y, TempPose.Joints[jLShoulder].Y - UPPER_ARM_LEN - FOREARM_LEN, 0.02));
    Check('3D chest', Near(TempPose.Joints[jChest].Y, PELVIS_HEIGHT + TORSO_LEN, 0.02));
    Check('3D head yaw (facing the camera)', Near(TempPose.HeadYaw, 0, 0.05));
    CheckRigAll('3D standing', TempPose, 0.001);
    TempSolver.Reset;
    TempPose := SolveFrames3D(TempSolver, Standing(0.0018, 2, 0), StandingWorld(2, 0), 5);
    Check('3D arm to the camera (measured)', Near(TempPose.Joints[jLElbow].Z - TempPose.Joints[jLShoulder].Z, UPPER_ARM_LEN, 0.02));
    Check('3D arm to the camera, wrist', Near(TempPose.Joints[jLWrist].Z - TempPose.Joints[jLElbow].Z, FOREARM_LEN, 0.02));
    CheckRigAll('3D arm to the camera', TempPose, 0.001);
    TempSolver.DepthSign := -1;
    TempPose := SolveFrames3D(TempSolver, Standing(0.0018, 2, 0), StandingWorld(2, 0), 8);
    Check('3D DepthSign', TempPose.Joints[jLElbow].Z < TempPose.Joints[jLShoulder].Z);
  finally
    TempSolver.Free;
  end;
  // The body turned 70 degrees. The nose looks to the same side.
  TempSolver := TPoseSolver.Create;
  try
    TempPose := SolveFrames3D(TempSolver, Standing(0.0018, 0, 0), StandingWorld(0, DegToRad(70)), 5);
    Check('3D yaw 70 degrees', Near(TempPose.TorsoYaw, DegToRad(70), 0.05), FloatToStr(RadToDeg(TempPose.TorsoYaw)));
    Check('3D head yaw 70 degrees', Near(TempPose.HeadYaw, DegToRad(70), 0.1), FloatToStr(RadToDeg(TempPose.HeadYaw)));
    Check('3D right shoulder is nearer', TempPose.Joints[jRShoulder].Z > TempPose.Joints[jLShoulder].Z);
  finally
    TempSolver.Free;
  end;
  // Mirror : the same pose seen as a reflection
  TempSolver := TPoseSolver.Create;
  try
    TempSolver.Mirror := True;
    TempPose := SolveFrames3D(TempSolver, Standing(0.0018, 0, 0), StandingWorld(2, 0), 5);
    Check('3D mirror keeps the left side at +X', TempPose.Joints[jLShoulder].X > 0);
    // The person's left arm (to the camera) is the avatar's right arm now
    Check('3D mirror swaps the arms', TempPose.Joints[jRElbow].Z - TempPose.Joints[jRShoulder].Z > 0.2);
  finally
    TempSolver.Free;
  end;

  // ---- BlazePose output decoding ----
  FillChar(TempLm, SizeOf(TempLm), 0);
  FillChar(TempWorld, SizeOf(TempWorld), 0);
  BlazeFullFrameRoi(1280, 720, TempRoi);
  Check('full frame roi', Near(TempRoi.CX, 640, 0.01) and Near(TempRoi.Side, 720, 0.01));
  // left shoulder (landmark 11) at (128, 64) of the 256 input, visible
  TempLm[(11 * 5) + 0] := 128; TempLm[(11 * 5) + 1] := 64; TempLm[(11 * 5) + 3] := 8;
  // hip center (33) and the scale point (34) : radius 100 input pixels
  TempLm[(33 * 5) + 0] := 128; TempLm[(33 * 5) + 1] := 128;
  TempLm[(34 * 5) + 0] := 128; TempLm[(34 * 5) + 1] := 228;
  // world : left shoulder 0.2 m right, 0.5 m up (y is down), 0.1 m nearer to the camera (z smaller)
  TempWorld[(11 * 3) + 0] := 0.2; TempWorld[(11 * 3) + 1] := -0.5; TempWorld[(11 * 3) + 2] := -0.1;
  BlazeDecode(TempLm, TempWorld, 256, TempRoi, 1280, 720, TempRes, TempRoi2);
  Check('blaze found', TempRes.Found and TempRes.Has3D);
  // roi : left = 640 - 360 = 280, factor 720/256 = 2.8125
  Check('blaze keypoint x', Near(TempRes.Keypoints[KP_L_SHOULDER].X, 280 + (128 * 2.8125), 0.01));
  Check('blaze keypoint y', Near(TempRes.Keypoints[KP_L_SHOULDER].Y, 64 * 2.8125, 0.01));
  Check('blaze visibility', TempRes.Keypoints[KP_L_SHOULDER].Score > 0.99);
  Check('blaze world axes', Near(TempRes.World[KP_L_SHOULDER].X, 0.2, 0.001) and
        Near(TempRes.World[KP_L_SHOULDER].Y, 0.5, 0.001) and Near(TempRes.World[KP_L_SHOULDER].Z, 0.1, 0.001));
  Check('blaze next roi', Near(TempRoi2.CX, 640, 0.01) and Near(TempRoi2.CY, 360, 0.01) and
        Near(TempRoi2.Side, 100 * 2.8125 * 2 * 1.25, 0.1));
  BlazeDecode(TempLm, TempWorld[0..10], 256, TempRoi, 1280, 720, TempRes, TempRoi2);
  Check('blaze without world', TempRes.Found and not(TempRes.Has3D));

  // ---- BlazePose detector : anchors, decoding, rotated square ----
  BlazeBuildAnchors(TempAnchors);
  Check('2254 anchors', length(TempAnchors) = BLAZE_DETECTOR_ANCHORS);
  Check('first anchor', Near(TempAnchors[0].X, 0.5 / 28, 0.0001) and Near(TempAnchors[0].Y, 0.5 / 28, 0.0001));
  // layer 1 (stride 8) has 28 x 28 x 2 anchors, the second anchor of a cell has the same center
  Check('2 anchors per cell', Near(TempAnchors[1].X, TempAnchors[0].X, 0.0001));
  Check('second cell', Near(TempAnchors[2].X, 1.5 / 28, 0.0001));
  // stride 16 layer starts at 1568 : 14 x 14 cells
  Check('stride 16 layer', Near(TempAnchors[1568].X, 0.5 / 14, 0.0001) and Near(TempAnchors[1570].X, 1.5 / 14, 0.0001));
  // stride 32 layers start at 1568 + 392 = 1960 : 7 x 7 cells with 6 anchors
  Check('stride 32 layers', Near(TempAnchors[1960].X, 0.5 / 7, 0.0001) and Near(TempAnchors[1966].X, 1.5 / 7, 0.0001));
  Check('last anchor', Near(TempAnchors[2253].X, 6.5 / 7, 0.0001) and Near(TempAnchors[2253].Y, 6.5 / 7, 0.0001));

  FillChar(TempReg, SizeOf(TempReg), 0);
  FillChar(TempScores, SizeOf(TempScores), 0);
  for i := 0 to 2253 do TempScores[i] := -10;
  TempScores[1000] := 5;
  // center of the body at +0.1, +0.2 of the anchor, the second point 0.3 above it
  TempReg[(1000 * 12) + 4] := 0.1 * 224;
  TempReg[(1000 * 12) + 5] := 0.2 * 224;
  TempReg[(1000 * 12) + 6] := 0.1 * 224;
  TempReg[(1000 * 12) + 7] := (0.2 - 0.3) * 224;
  BlazeFullFrameRoi(1280, 720, TempRoi);
  Check('detector finds the person', BlazeDetectPose(TempReg, TempScores, TempAnchors, TempRoi, 0.5, TempRoi2, TempScore) and
        (TempScore > 0.99));
  // square 720 at x = 280 : center x = 280 + (anchor + 0.1) * 720
  Check('detector center', Near(TempRoi2.CX, 280 + ((TempAnchors[1000].X + 0.1) * 720), 0.01) and
        Near(TempRoi2.CY, (TempAnchors[1000].Y + 0.2) * 720, 0.01));
  Check('detector side', Near(TempRoi2.Side, 0.3 * 720 * 2 * 1.25, 0.01));
  Check('detector upright body : no rotation', Near(TempRoi2.Rotation, 0, 0.001));
  TempScores[1000] := -10;
  Check('detector nobody', not(BlazeDetectPose(TempReg, TempScores, TempAnchors, TempRoi, 0.5, TempRoi2, TempScore)));

  // Rotation of the square : the body leans to the right (the second point is up and to the right)
  BlazeRoiFromPoints(100, 100, 200, 0, 1.25, TempRoi2);
  Check('roi leaning to the right', Near(TempRoi2.Rotation, Pi / 4, 0.001));
  Check('roi side', Near(TempRoi2.Side, 2 * Sqrt(20000) * 1.25, 0.01));
  BlazeRoiFromPoints(100, 100, 0, 0, 1.25, TempRoi2);
  Check('roi leaning to the left', Near(TempRoi2.Rotation, -Pi / 4, 0.001));
  BlazeRoiFromPoints(100, 100, 100, 200, 1.25, TempRoi2);
  Check('roi upside down', Near(Abs(TempRoi2.Rotation), Pi, 0.001));

  // The landmarks follow the rotation : model "up" of a roi rotated by 90 degrees clockwise is to the right of the image
  FillChar(TempLm, SizeOf(TempLm), 0);
  FillChar(TempWorld, SizeOf(TempWorld), 0);
  TempRoi2.CX := 500; TempRoi2.CY := 400; TempRoi2.Side := 256; TempRoi2.Rotation := Pi / 2;
  // nose (landmark 0) at the top center of the model input (128, 0)
  TempLm[0] := 128; TempLm[1] := 0; TempLm[3] := 8;
  TempLm[(33 * 5) + 0] := 128; TempLm[(33 * 5) + 1] := 128;
  TempLm[(34 * 5) + 0] := 128; TempLm[(34 * 5) + 1] := 28;
  // world : the nose 0.5 m above the hips in the model (y down => -0.5)
  TempWorld[1] := -0.5;
  BlazeDecode(TempLm, TempWorld, 256, TempRoi2, 1280, 720, TempRes, TempRoi3);
  Check('rotated roi : keypoint', Near(TempRes.Keypoints[KP_NOSE].X, 500 + 128, 0.01) and Near(TempRes.Keypoints[KP_NOSE].Y, 400, 0.01),
        FloatToStr(TempRes.Keypoints[KP_NOSE].X) + ' ' + FloatToStr(TempRes.Keypoints[KP_NOSE].Y));
  // the world vector (0, -0.5) is turned 90 degrees clockwise : to the right of the image (+X)
  Check('rotated roi : world', Near(TempRes.World[KP_NOSE].X, 0.5, 0.001) and Near(TempRes.World[KP_NOSE].Y, 0, 0.001));
  Check('rotated roi : next roi rotation', Near(TempRoi3.Rotation, Pi / 2, 0.001));

  // ---- Rotated crop of the image ----
  FillChar(TempSrc, SizeOf(TempSrc), 0);
  // a bright pixel at the top of the 8x6 image, row 0, x = 4
  TempSrc[(0 * 8 + 4) * 4 + 0] := 250; TempSrc[(0 * 8 + 4) * 4 + 1] := 250; TempSrc[(0 * 8 + 4) * 4 + 2] := 250;
  CropRotatedToRGB(@TempSrc[0], 8, 6, 8 * 4, True, 4, 3, 6, 0, @TempDst[0], 4);
  Check('rotated crop : no rotation keeps the top', TempDst[((0 * 4) + 2) * 3] > 100);
  CropRotatedToRGB(@TempSrc[0], 8, 6, 8 * 4, True, 4, 3, 6, Pi / 2, @TempDst[0], 4);
  // rotated 90 degrees clockwise : the top of the frame is at the left of the model image
  Check('rotated crop : 90 degrees', TempDst[((1 * 4) + 0) * 3] > 100);
  Check('rotated crop : 90 degrees, not at the top', TempDst[((0 * 4) + 2) * 3] < 50);

  // ---- MediaPipe bridge protocol (line made by tools/mediapipe_bridge.py --selftest) ----
  AssignFile(TempFile, 'mediapipe_line.txt');
  Reset(TempFile);
  ReadLn(TempFile, TempLine);
  CloseFile(TempFile);
  Check('mediapipe line is valid', ParseMediaPipeLine(TempLine, TempRes));
  Check('mediapipe found 3D', TempRes.Found and TempRes.Has3D);
  Check('mediapipe frame size', Near(TempRes.FrameWidth, 640, 0.01) and Near(TempRes.FrameHeight, 480, 0.01));
  Check('mediapipe nose pixels', Near(TempRes.Keypoints[KP_NOSE].X, 320, 0.1) and Near(TempRes.Keypoints[KP_NOSE].Y, 96, 0.1));
  Check('mediapipe left shoulder pixels', Near(TempRes.Keypoints[KP_L_SHOULDER].X, 384, 0.1));
  Check('mediapipe left shoulder score', Near(TempRes.Keypoints[KP_L_SHOULDER].Score, 0.98, 0.001));
  Check('mediapipe world axes', Near(TempRes.World[KP_L_SHOULDER].X, 0.2, 0.001) and
        Near(TempRes.World[KP_L_SHOULDER].Y, 0.45, 0.001) and Near(TempRes.World[KP_L_SHOULDER].Z, -0.05, 0.001));
  Check('mediapipe no pose line', ParseMediaPipeLine('MP1 640 480 0', TempRes) and not(TempRes.Found));
  Check('mediapipe wrong tag', not(ParseMediaPipeLine('XX 640 480 0', TempRes)));
  Check('mediapipe short line', not(ParseMediaPipeLine('MP1 640 480 1 0.5 0.5', TempRes)));
  Check('mediapipe garbage', not(ParseMediaPipeLine('MP1 640 abc 1', TempRes)));

  // ---- YOLO pose decoding ----
  // 3 candidates, channels first : candidate 1 is the best person.
  FillChar(TempYolo, SizeOf(TempYolo), 0);
  for i := 0 to 2 do
    TempYolo[(4 * 3) + i] := 0.1;
  TempYolo[(4 * 3) + 1] := 0.9;
  // left shoulder (keypoint 5) of candidate 1 at (320, 160) of the 640 input, score 0.8
  TempYolo[((5 + (5 * 3)) * 3) + 1] := 320;
  TempYolo[((6 + (5 * 3)) * 3) + 1] := 160;
  TempYolo[((7 + (5 * 3)) * 3) + 1] := 0.8;
  Check('yolo found', YoloDecode(TempYolo, 3, True, 640, 100, 50, 480, 0.25, TempRes) and TempRes.Found);
  Check('yolo keypoint x', Near(TempRes.Keypoints[KP_L_SHOULDER].X, 100 + (320 * 0.75), 0.01));
  Check('yolo keypoint y', Near(TempRes.Keypoints[KP_L_SHOULDER].Y, 50 + (160 * 0.75), 0.01));
  Check('yolo score', Near(TempRes.Keypoints[KP_L_SHOULDER].Score, 0.8, 0.001));
  Check('yolo nobody', not(YoloDecode(TempYolo, 3, True, 640, 0, 0, 640, 0.95, TempRes)));
  // the same values with the anchors first
  FillChar(TempYolo2, SizeOf(TempYolo2), 0);
  TempYolo2[(1 * 56) + 4] := 0.9;
  TempYolo2[(1 * 56) + 5 + (5 * 3)] := 320;
  Check('yolo anchors first', YoloDecode(TempYolo2, 3, False, 640, 0, 0, 640, 0.25, TempRes) and
        Near(TempRes.Keypoints[KP_L_SHOULDER].X, 320, 0.01));

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

  // Region crop : the part outside of the frame is black
  FillChar(TempSrc, SizeOf(TempSrc), 200);
  CropRegionToRGB(@TempSrc[0], 8, 6, 8 * 4, True, 0, 0, 8, @TempDst[0], 4);
  Check('region outside is black', (TempDst[0] = 0) and (TempDst[1] = 0));
  Check('region inside has the color', TempDst[((3 * 4) + 3) * 3] > 100);

  writeln;
  writeln(Total, ' checks, ', Failures, ' failures');
  if (Failures > 0) then Halt(1);
end.

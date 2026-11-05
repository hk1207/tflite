unit uPoseSolver;

{$IFDEF FPC}{$MODE Delphi}{$ENDIF}

// Converts the 17 2D keypoints of MoveNet to the 3D joint positions of an
// adult male body (30s, 1.75 m).
//
// MoveNet only gives 2D positions. The depth (Z) of the limbs is estimated
// from the bone lengths of the body model : when a limb looks shorter than its
// real length, the rest of its length points to / away from the camera.
// The direction of that depth can't be measured, so a natural default is used
// (elbows and knees bend forward, see the Limb function).
//
// This unit has no dependencies on Windows, Castle Engine or TFLite, so it
// can be tested on any platform.
//
// World coordinates (meters) are the same as in Castle Game Engine : +X right,
// +Y up, the avatar looks to +Z (towards the camera).

interface

uses
  {$IFDEF FPC}Math{$ELSE}System.Math{$ENDIF};

const
  // MoveNet keypoint indexes. Left/right are the person's left/right.
  KP_NOSE = 0;       KP_L_EYE = 1;      KP_R_EYE = 2;
  KP_L_EAR = 3;      KP_R_EAR = 4;
  KP_L_SHOULDER = 5; KP_R_SHOULDER = 6;
  KP_L_ELBOW = 7;    KP_R_ELBOW = 8;
  KP_L_WRIST = 9;    KP_R_WRIST = 10;
  KP_L_HIP = 11;     KP_R_HIP = 12;
  KP_L_KNEE = 13;    KP_R_KNEE = 14;
  KP_L_ANKLE = 15;   KP_R_ANKLE = 16;
  KEYPOINT_COUNT = 17;

  // Body model : adult male, 30s, 1.75 m tall (meters).
  BODY_HEIGHT     = 1.75;
  FOOT_HEIGHT     = 0.08;   // ankle height
  SHIN_LEN        = 0.42;   // knee -> ankle
  THIGH_LEN       = 0.43;   // hip -> knee
  PELVIS_HEIGHT   = FOOT_HEIGHT + SHIN_LEN + THIGH_LEN;   // standing
  TORSO_LEN       = 0.52;   // pelvis center -> shoulder line center
  SHOULDER_WIDTH  = 0.39;   // distance between the shoulder joints
  HIP_WIDTH       = 0.18;   // distance between the hip joints
  UPPER_ARM_LEN   = 0.31;   // shoulder -> elbow
  FOREARM_LEN     = 0.27;   // elbow -> wrist
  HEAD_DISTANCE   = 0.19;   // shoulder line center -> head center

type
  TVec3 = record
    X, Y, Z : Single;
  end;

  TKeypoint = record
    X, Y  : Single;   // pixels of the camera frame
    Score : Single;   // 0..1
  end;

  TKeypoints = array[0..KEYPOINT_COUNT - 1] of TKeypoint;

  TJoint = (jPelvis, jChest, jHead,
            jLShoulder, jRShoulder, jLElbow, jRElbow, jLWrist, jRWrist,
            jLHip, jRHip, jLKnee, jRKnee, jLAnkle, jRAnkle);

  TAvatarPose = record
    Joints   : array[TJoint] of TVec3;
    TorsoYaw : Single;   // radians, rotation around +Y of the shoulders/hips
    HeadYaw  : Single;   // radians, rotation around +Y of the face
    HeadRoll : Single;   // radians, rotation around +Z of the head
    Valid    : boolean;  // False if the body wasn't detected in the frame
  end;

  /// <summary>
  /// One Euro filter : smooths noisy values and keeps the lag low when the
  /// value changes fast.
  /// </summary>
  TOneEuroFilter = class
    protected
      FStarted : boolean;
      FXPrev   : Single;
      FDxPrev  : Single;
      FTPrev   : Single;
      function Alpha(aCutoff, aDelta : Single) : Single;
    public
      MinCutoff : Single;   // Hz, smoothing of slow movements
      Beta      : Single;   // speed coefficient, less lag in fast movements
      DCutoff   : Single;   // Hz
      constructor Create;
      procedure Reset;
      function  Filter(aValue, aTime : Single) : Single;
  end;

  TPoseSolver = class
    protected
      FFilterX   : array[0..KEYPOINT_COUNT - 1] of TOneEuroFilter;
      FFilterY   : array[0..KEYPOINT_COUNT - 1] of TOneEuroFilter;
      FX, FY     : array[0..KEYPOINT_COUNT - 1] of Single;
      FSeen      : array[0..KEYPOINT_COUNT - 1] of boolean;
      FHasScale  : boolean;
      FScale     : Single;   // meters per pixel
      FHasRef    : boolean;
      FRefX      : Single;
      FRefY      : Single;
      FYawSign   : Single;
      FLastPose  : TAvatarPose;

      function Limb(const aParent : TVec3; aParentIdx, aChildIdx : integer; aLen, aSign : Single) : TVec3;
    public
      /// <summary>
      /// True if the camera image is shown as a mirror : the avatar then moves
      /// like the reflection of the person.
      /// </summary>
      Mirror    : boolean;
      /// <summary>
      /// 1 or -1. Changes the direction of the depth estimation of the limbs.
      /// </summary>
      DepthSign : Single;
      /// <summary>
      /// Keypoints with a lower score are ignored.
      /// </summary>
      MinScore  : Single;

      constructor Create;
      destructor  Destroy; override;
      /// <summary>
      /// Forget the scale and the reference position. The next frame
      /// calibrates the avatar again.
      /// </summary>
      procedure Reset;
      /// <summary>
      /// aRaw has the pixel positions in a frame of aFrameW x aFrameH, aTime is
      /// the time of the frame in seconds.
      /// </summary>
      function Solve(const aRaw : TKeypoints; aFrameW, aFrameH, aTime : Single) : TAvatarPose;
      property Scale : Single read FScale;
  end;

function Vec3(aX, aY, aZ : Single) : TVec3;
function VecAdd(const A, B : TVec3) : TVec3;
function VecSub(const A, B : TVec3) : TVec3;
function VecLength(const A : TVec3) : Single;

/// <summary>
/// Calculates the axis and angle of the rotation that turns the +Y axis to aDir.
/// </summary>
procedure AlignYAxis(const aDir : TVec3; out aAxis : TVec3; out aAngle : Single);
/// <summary>
/// Rotates aVec around the unit vector aAxis.
/// </summary>
function RotateAroundAxis(const aVec, aAxis : TVec3; aAngle : Single) : TVec3;

implementation

function Vec3(aX, aY, aZ : Single) : TVec3;
begin
  Result.X := aX;
  Result.Y := aY;
  Result.Z := aZ;
end;

function VecAdd(const A, B : TVec3) : TVec3;
begin
  Result := Vec3(A.X + B.X, A.Y + B.Y, A.Z + B.Z);
end;

function VecSub(const A, B : TVec3) : TVec3;
begin
  Result := Vec3(A.X - B.X, A.Y - B.Y, A.Z - B.Z);
end;

function VecLength(const A : TVec3) : Single;
begin
  Result := Sqrt((A.X * A.X) + (A.Y * A.Y) + (A.Z * A.Z));
end;

function Clamp01Signed(aValue : Single) : Single;
begin
  if (aValue < -1) then
    Result := -1
   else
    if (aValue > 1) then
      Result := 1
     else
      Result := aValue;
end;

procedure AlignYAxis(const aDir : TVec3; out aAxis : TVec3; out aAngle : Single);
var
  TempLen, TempSide : Single;
  TempDir : TVec3;
begin
  TempLen := VecLength(aDir);

  if (TempLen < 0.000001) then
    begin
      aAxis  := Vec3(1, 0, 0);
      aAngle := 0;
      exit;
    end;

  TempDir  := Vec3(aDir.X / TempLen, aDir.Y / TempLen, aDir.Z / TempLen);
  TempSide := Sqrt((TempDir.X * TempDir.X) + (TempDir.Z * TempDir.Z));

  if (TempSide < 0.000001) then
    begin
      aAxis := Vec3(1, 0, 0);

      if (TempDir.Y > 0) then
        aAngle := 0
       else
        aAngle := Pi;
    end
   else
    begin
      // Axis = Y x Dir, normalized
      aAxis  := Vec3(TempDir.Z / TempSide, 0, -TempDir.X / TempSide);
      aAngle := ArcCos(Clamp01Signed(TempDir.Y));
    end;
end;

function RotateAroundAxis(const aVec, aAxis : TVec3; aAngle : Single) : TVec3;
var
  TempCos, TempSin, TempDot : Single;
  TempCross : TVec3;
begin
  TempCos   := Cos(aAngle);
  TempSin   := Sin(aAngle);
  TempDot   := (aAxis.X * aVec.X) + (aAxis.Y * aVec.Y) + (aAxis.Z * aVec.Z);
  TempCross := Vec3((aAxis.Y * aVec.Z) - (aAxis.Z * aVec.Y),
                    (aAxis.Z * aVec.X) - (aAxis.X * aVec.Z),
                    (aAxis.X * aVec.Y) - (aAxis.Y * aVec.X));

  Result := Vec3((aVec.X * TempCos) + (TempCross.X * TempSin) + (aAxis.X * TempDot * (1 - TempCos)),
                 (aVec.Y * TempCos) + (TempCross.Y * TempSin) + (aAxis.Y * TempDot * (1 - TempCos)),
                 (aVec.Z * TempCos) + (TempCross.Z * TempSin) + (aAxis.Z * TempDot * (1 - TempCos)));
end;

{ TOneEuroFilter }

constructor TOneEuroFilter.Create;
begin
  inherited Create;

  MinCutoff := 1.5;
  Beta      := 0.02;
  DCutoff   := 1.0;
  Reset;
end;

procedure TOneEuroFilter.Reset;
begin
  FStarted := False;
  FXPrev   := 0;
  FDxPrev  := 0;
  FTPrev   := 0;
end;

function TOneEuroFilter.Alpha(aCutoff, aDelta : Single) : Single;
var
  TempTau : Single;
begin
  TempTau := 1 / (2 * Pi * aCutoff);
  Result  := 1 / (1 + (TempTau / aDelta));
end;

function TOneEuroFilter.Filter(aValue, aTime : Single) : Single;
var
  TempDelta, TempDx, TempCutoff, TempAlpha : Single;
begin
  if not(FStarted) then
    begin
      FStarted := True;
      FXPrev   := aValue;
      FDxPrev  := 0;
      FTPrev   := aTime;
      Result   := aValue;
      exit;
    end;

  TempDelta := aTime - FTPrev;

  if (TempDelta <= 0.0001) then
    begin
      Result := FXPrev;
      exit;
    end;

  TempDx     := (aValue - FXPrev) / TempDelta;
  FDxPrev    := FDxPrev + (Alpha(DCutoff, TempDelta) * (TempDx - FDxPrev));
  TempCutoff := MinCutoff + (Beta * Abs(FDxPrev));
  TempAlpha  := Alpha(TempCutoff, TempDelta);
  FXPrev     := FXPrev + (TempAlpha * (aValue - FXPrev));
  FTPrev     := aTime;
  Result     := FXPrev;
end;

{ TPoseSolver }

constructor TPoseSolver.Create;
var
  i : integer;
begin
  inherited Create;

  for i := 0 to pred(KEYPOINT_COUNT) do
    begin
      FFilterX[i] := TOneEuroFilter.Create;
      FFilterY[i] := TOneEuroFilter.Create;
    end;

  Mirror    := False;
  DepthSign := 1;
  MinScore  := 0.25;

  Reset;
end;

destructor TPoseSolver.Destroy;
var
  i : integer;
begin
  for i := 0 to pred(KEYPOINT_COUNT) do
    begin
      FFilterX[i].Free;
      FFilterY[i].Free;
    end;

  inherited Destroy;
end;

procedure TPoseSolver.Reset;
var
  i : integer;
begin
  for i := 0 to pred(KEYPOINT_COUNT) do
    begin
      FFilterX[i].Reset;
      FFilterY[i].Reset;
      FSeen[i] := False;
      FX[i]    := 0;
      FY[i]    := 0;
    end;

  FHasScale := False;
  FScale    := 0;
  FHasRef   := False;
  FRefX     := 0;
  FRefY     := 0;
  FYawSign  := 1;

  FillChar(FLastPose, SizeOf(FLastPose), 0);
  FLastPose.Valid := False;
end;

// Position of the joint aChildIdx when the bone from the joint aParentIdx
// (already known in 3D) has the length aLen. X and Y come from the image, Z
// from the part of the length that doesn't fit in the image.
function TPoseSolver.Limb(const aParent : TVec3; aParentIdx, aChildIdx : integer; aLen, aSign : Single) : TVec3;
var
  TempDx, TempDy, TempDz, TempLen2, TempFactor : Single;
begin
  if not(FSeen[aChildIdx]) then
    begin
      // Not detected yet : the limb hangs down.
      Result := Vec3(aParent.X, aParent.Y - aLen, aParent.Z);
      exit;
    end;

  TempDx   :=  (FX[aChildIdx] - FX[aParentIdx]) * FScale;
  TempDy   := -(FY[aChildIdx] - FY[aParentIdx]) * FScale;
  TempLen2 := Sqrt((TempDx * TempDx) + (TempDy * TempDy));

  if (TempLen2 > aLen) then
    begin
      TempFactor := aLen / TempLen2;
      TempDx     := TempDx * TempFactor;
      TempDy     := TempDy * TempFactor;
      TempDz     := 0;
    end
   else
    TempDz := Sqrt((aLen * aLen) - (TempLen2 * TempLen2)) * aSign * DepthSign;

  Result := Vec3(aParent.X + TempDx, aParent.Y + TempDy, aParent.Z + TempDz);
end;

function TPoseSolver.Solve(const aRaw : TKeypoints; aFrameW, aFrameH, aTime : Single) : TAvatarPose;
var
  i : integer;
  TempKp : TKeypoints;
  TempSwap : TKeypoint;
  TempShMidX, TempShMidY, TempHipMidX, TempHipMidY : Single;
  TempTorsoPx, TempTarget : Single;
  TempPelvis, TempChest, TempHeadDir : TVec3;
  TempDx, TempDy, TempDz, TempLen2 : Single;
  TempShoulderRatio, TempHipRatio, TempRatio, TempYaw, TempSinYaw : Single;
  TempOffset, TempThreshold : Single;
  TempHeadX, TempHeadY, TempHeadLen : Single;
  TempEarDist, TempHeadYaw : Single;
begin
  Result       := FLastPose;
  Result.Valid := False;

  // 1. Mirror : flip x and swap the left and right keypoints.
  TempKp := aRaw;

  if Mirror then
    begin
      for i := 0 to pred(KEYPOINT_COUNT) do
        TempKp[i].X := aFrameW - TempKp[i].X;

      i := 1;
      while (i < KEYPOINT_COUNT) do
        begin
          TempSwap      := TempKp[i];
          TempKp[i]     := TempKp[i + 1];
          TempKp[i + 1] := TempSwap;
          inc(i, 2);
        end;
    end;

  // 2. Smooth the keypoints. A keypoint with a low score keeps its last value.
  for i := 0 to pred(KEYPOINT_COUNT) do
    if (TempKp[i].Score >= MinScore) then
      begin
        FX[i]    := FFilterX[i].Filter(TempKp[i].X, aTime);
        FY[i]    := FFilterY[i].Filter(TempKp[i].Y, aTime);
        FSeen[i] := True;
      end;

  if not(FSeen[KP_L_SHOULDER] and FSeen[KP_R_SHOULDER] and
         FSeen[KP_L_HIP]      and FSeen[KP_R_HIP]) then
    exit;

  TempShMidX  := (FX[KP_L_SHOULDER] + FX[KP_R_SHOULDER]) / 2;
  TempShMidY  := (FY[KP_L_SHOULDER] + FY[KP_R_SHOULDER]) / 2;
  TempHipMidX := (FX[KP_L_HIP] + FX[KP_R_HIP]) / 2;
  TempHipMidY := (FY[KP_L_HIP] + FY[KP_R_HIP]) / 2;

  // 3. Scale (meters per pixel) from the torso length. It changes slowly,
  // because a torso that leans to the camera looks shorter.
  TempTorsoPx := Sqrt(Sqr(TempShMidX - TempHipMidX) + Sqr(TempShMidY - TempHipMidY));

  if (TempTorsoPx < 1) then exit;

  TempTarget := TORSO_LEN / TempTorsoPx;

  if not(FHasScale) then
    begin
      FScale    := TempTarget;
      FHasScale := True;
    end
   else
    begin
      if (TempTarget < (FScale * 0.85)) then TempTarget := FScale * 0.85;
      if (TempTarget > (FScale * 1.15)) then TempTarget := FScale * 1.15;
      FScale := FScale + (0.05 * (TempTarget - FScale));
    end;

  if not(FHasRef) then
    begin
      FRefX   := TempHipMidX;
      FRefY   := TempHipMidY;
      FHasRef := True;
    end;

  // 4. Pelvis, spine and chest.
  TempPelvis := Vec3((TempHipMidX - FRefX) * FScale,
                     PELVIS_HEIGHT - ((TempHipMidY - FRefY) * FScale),
                     0);

  TempDx   :=  (TempShMidX - TempHipMidX) * FScale;
  TempDy   := -(TempShMidY - TempHipMidY) * FScale;
  TempLen2 := Sqrt((TempDx * TempDx) + (TempDy * TempDy));

  if (TempLen2 > TORSO_LEN) then
    begin
      TempDx := TempDx * (TORSO_LEN / TempLen2);
      TempDy := TempDy * (TORSO_LEN / TempLen2);
      TempDz := 0;
    end
   else
    TempDz := Sqrt((TORSO_LEN * TORSO_LEN) - (TempLen2 * TempLen2)) * DepthSign;

  TempChest := Vec3(TempPelvis.X + TempDx, TempPelvis.Y + TempDy, TempPelvis.Z + TempDz);

  // 5. Torso yaw : the shoulders look narrower when the body turns. The turn
  // direction is the side where the nose is.
  TempShoulderRatio := Abs(FX[KP_L_SHOULDER] - FX[KP_R_SHOULDER]) * FScale / SHOULDER_WIDTH;
  TempHipRatio      := Abs(FX[KP_L_HIP] - FX[KP_R_HIP]) * FScale / HIP_WIDTH;
  TempRatio         := Clamp01Signed((0.7 * TempShoulderRatio) + (0.3 * TempHipRatio));

  if FSeen[KP_NOSE] then
    begin
      TempOffset    := FX[KP_NOSE] - TempShMidX;
      TempThreshold := 0.12 * Abs(FX[KP_L_SHOULDER] - FX[KP_R_SHOULDER]);

      if (Abs(TempOffset) > TempThreshold) then
        begin
          if (TempOffset > 0) then
            FYawSign := 1
           else
            FYawSign := -1;
        end;
    end;

  TempYaw    := ArcCos(TempRatio) * FYawSign;
  TempSinYaw := Sin(TempYaw);

  Result.TorsoYaw := TempYaw;
  Result.Joints[jPelvis] := TempPelvis;
  Result.Joints[jChest]  := TempChest;

  // The person's left side is at +X : its Z is -(w/2) sin(yaw).
  Result.Joints[jLShoulder] := Vec3(
    TempChest.X + ((FX[KP_L_SHOULDER] - TempShMidX) * FScale),
    TempChest.Y - ((FY[KP_L_SHOULDER] - TempShMidY) * FScale),
    TempChest.Z - ((SHOULDER_WIDTH / 2) * TempSinYaw));
  Result.Joints[jRShoulder] := Vec3(
    TempChest.X + ((FX[KP_R_SHOULDER] - TempShMidX) * FScale),
    TempChest.Y - ((FY[KP_R_SHOULDER] - TempShMidY) * FScale),
    TempChest.Z + ((SHOULDER_WIDTH / 2) * TempSinYaw));

  Result.Joints[jLHip] := Vec3(
    TempPelvis.X + ((FX[KP_L_HIP] - TempHipMidX) * FScale),
    TempPelvis.Y - ((FY[KP_L_HIP] - TempHipMidY) * FScale),
    TempPelvis.Z - ((HIP_WIDTH / 2) * TempSinYaw));
  Result.Joints[jRHip] := Vec3(
    TempPelvis.X + ((FX[KP_R_HIP] - TempHipMidX) * FScale),
    TempPelvis.Y - ((FY[KP_R_HIP] - TempHipMidY) * FScale),
    TempPelvis.Z + ((HIP_WIDTH / 2) * TempSinYaw));

  // 6. Arms and legs. Elbows and the forearms bend to the camera, the knees
  // bend to the camera and the shins go back.
  Result.Joints[jLElbow] := Limb(Result.Joints[jLShoulder], KP_L_SHOULDER, KP_L_ELBOW, UPPER_ARM_LEN, 1);
  Result.Joints[jRElbow] := Limb(Result.Joints[jRShoulder], KP_R_SHOULDER, KP_R_ELBOW, UPPER_ARM_LEN, 1);
  Result.Joints[jLWrist] := Limb(Result.Joints[jLElbow], KP_L_ELBOW, KP_L_WRIST, FOREARM_LEN, 1);
  Result.Joints[jRWrist] := Limb(Result.Joints[jRElbow], KP_R_ELBOW, KP_R_WRIST, FOREARM_LEN, 1);

  Result.Joints[jLKnee]  := Limb(Result.Joints[jLHip], KP_L_HIP, KP_L_KNEE, THIGH_LEN, 1);
  Result.Joints[jRKnee]  := Limb(Result.Joints[jRHip], KP_R_HIP, KP_R_KNEE, THIGH_LEN, 1);
  Result.Joints[jLAnkle] := Limb(Result.Joints[jLKnee], KP_L_KNEE, KP_L_ANKLE, SHIN_LEN, -1);
  Result.Joints[jRAnkle] := Limb(Result.Joints[jRKnee], KP_R_KNEE, KP_R_ANKLE, SHIN_LEN, -1);

  // 7. Head
  if FSeen[KP_L_EAR] and FSeen[KP_R_EAR] then
    begin
      TempHeadX := (FX[KP_L_EAR] + FX[KP_R_EAR]) / 2;
      TempHeadY := (FY[KP_L_EAR] + FY[KP_R_EAR]) / 2;
    end
   else
    if FSeen[KP_NOSE] then
      begin
        TempHeadX := FX[KP_NOSE];
        TempHeadY := FY[KP_NOSE];
      end
     else
      begin
        TempHeadX := TempShMidX;
        TempHeadY := TempShMidY - (HEAD_DISTANCE / FScale);
      end;

  TempDx := (TempHeadX - TempShMidX) * FScale;
  TempDy := -(TempHeadY - TempShMidY) * FScale;

  if (TempDy < 0.05) then TempDy := 0.05;

  TempHeadLen := Sqrt((TempDx * TempDx) + (TempDy * TempDy));
  TempHeadDir := Vec3(TempDx / TempHeadLen, TempDy / TempHeadLen, 0);

  Result.Joints[jHead] := Vec3(TempChest.X + (TempHeadDir.X * HEAD_DISTANCE),
                               TempChest.Y + (TempHeadDir.Y * HEAD_DISTANCE),
                               TempChest.Z);
  Result.HeadRoll := ArcTan2(-TempHeadDir.X, TempHeadDir.Y);

  TempHeadYaw := Result.TorsoYaw;

  if FSeen[KP_NOSE] and FSeen[KP_L_EAR] and FSeen[KP_R_EAR] then
    begin
      TempEarDist := Abs(FX[KP_L_EAR] - FX[KP_R_EAR]);

      if (TempEarDist > 4) then
        TempHeadYaw := ArcSin(Clamp01Signed((FX[KP_NOSE] - TempHeadX) / (0.5 * TempEarDist)));
    end;

  Result.HeadYaw := TempHeadYaw;
  Result.Valid   := True;
  FLastPose      := Result;
end;

end.

unit uPoseRig;

{$IFDEF FPC}{$MODE Delphi}{$ENDIF}

// Retargets the 3D joints of a TAvatarPose to the bones of a rigged glTF model.
//
// Every model has its own bone names and bone orientations (the rest pose), so
// the rig is described by a profile : the list of the bones that are moved, how
// they are connected and what each one does. The rotation of a bone is found
// with the rest rotations of the model, so it works with any bone orientation
// (for example the bones of Blender / Rigify that point along their local Y).
//
// Profiles : ghwmaq.glb (GhwmaqProfile) and GHWBodyModel.glb (GhwBodyProfile).
// To support another model, add a profile : the node names are the names of the
// glTF nodes (the bones), the parent of a bone must be before it in the list.
//
// This unit has no dependencies on Castle Engine, so it can be tested on any
// platform.

interface

uses
  uPoseSolver;

type
  TQuat = record
    X, Y, Z, W : Single;
  end;

  TRigRole = (
    rrFixed,    // not moved
    rrFollow,   // moves with its parent (hand, neck, clavicle ...)
    rrYaw,      // pelvis : turns around the vertical axis
    rrSpine,    // spine bone : takes a part (SpineIndex / SpineCount) of the lean and turn of the torso
    rrLimb,     // arm or leg bone : points from FromJoint to ToJoint of the pose
    rrFoot,     // stays flat, turns with the pelvis
    rrHead);    // head : roll and yaw from the pose

  TRigBoneDef = record
    Node       : string;     // glTF node name
    Parent     : integer;    // index in the profile, -1 if the parent is not a bone
    Role       : TRigRole;
    Child      : integer;    // rrLimb : the bone after this one, its offset is the rest direction
    FromJoint  : TJoint;     // rrLimb
    ToJoint    : TJoint;     // rrLimb
    SpineIndex : integer;    // rrSpine : 1..SpineCount
    SpineCount : integer;
  end;

  TRigProfile = record
    Name         : string;
    ArmatureNode : string;    // the parent node of the root bones, it can have a scale ('' = none)
    ModelHeight  : Single;    // height of the model in its own units
    RootNodes    : array of string;       // nodes that move the whole body
    Bones        : array of TRigBoneDef;
  end;

  /// <summary>
  /// Rest transformation of a bone node (relative to its parent).
  /// </summary>
  TRigRest = record
    Translation : TVec3;
    Rotation    : TQuat;
  end;
  TRigRestArray = array of TRigRest;

  TRigPose = record
    RootOffset : TVec3;                 // meters, displacement of the body from the standing pose
    Rotation   : array of TQuat;        // new local rotation of each bone of the profile
    Valid      : boolean;
  end;

function GhwmaqProfile : TRigProfile;
function GhwBodyProfile : TRigProfile;

function QuatIdentity : TQuat;
function QuatFromAxisAngle(const aAxis : TVec3; aAngle : Single) : TQuat;
function QuatMul(const A, B : TQuat) : TQuat;
function QuatConjugate(const A : TQuat) : TQuat;
function QuatRotate(const aQ : TQuat; const aV : TVec3) : TVec3;
/// <summary>
/// Minimal rotation that turns the direction aFrom to the direction aTo.
/// </summary>
function QuatAlign(const aFrom, aTo : TVec3) : TQuat;
function QuatSlerp(const A, B : TQuat; aT : Single) : TQuat;
procedure QuatToAxisAngle(const aQ : TQuat; out aAxis : TVec3; out aAngle : Single);

/// <summary>
/// aRest has one item for each bone of the profile.
/// </summary>
procedure BuildRigPose(const aProfile : TRigProfile; const aRest : TRigRestArray;
                       const aPose : TAvatarPose; out aRig : TRigPose);

implementation

uses
  {$IFDEF FPC}Math{$ELSE}System.Math{$ENDIF};

procedure AddBone(var aProfile : TRigProfile; const aNode : string; aParent : integer; aRole : TRigRole;
                  aChild : integer = -1; aFrom : TJoint = jPelvis; aTo : TJoint = jPelvis;
                  aSpineIndex : integer = 0; aSpineCount : integer = 0);
var
  TempIdx : integer;
begin
  TempIdx := length(aProfile.Bones);
  SetLength(aProfile.Bones, TempIdx + 1);

  aProfile.Bones[TempIdx].Node       := aNode;
  aProfile.Bones[TempIdx].Parent     := aParent;
  aProfile.Bones[TempIdx].Role       := aRole;
  aProfile.Bones[TempIdx].Child      := aChild;
  aProfile.Bones[TempIdx].FromJoint  := aFrom;
  aProfile.Bones[TempIdx].ToJoint    := aTo;
  aProfile.Bones[TempIdx].SpineIndex := aSpineIndex;
  aProfile.Bones[TempIdx].SpineCount := aSpineCount;
end;

// Adds an arm or a leg : 3 bones. The index of the first one is returned.
function AddLimb(var aProfile : TRigProfile; const aNode1, aNode2, aNode3 : string; aParent : integer;
                 aRole3 : TRigRole; aJ1, aJ2, aJ3 : TJoint) : integer;
begin
  Result := length(aProfile.Bones);
  AddBone(aProfile, aNode1, aParent, rrLimb, Result + 1, aJ1, aJ2);
  AddBone(aProfile, aNode2, Result, rrLimb, Result + 2, aJ2, aJ3);
  AddBone(aProfile, aNode3, Result + 1, aRole3);
end;

// ghwmaq.glb : bones pelvis, l.leg ..., spine1, spine2, l.arm1 ..., neck, head
function GhwmaqProfile : TRigProfile;
var
  TempRoot, TempPelvis, TempSpine2 : integer;
begin
  Result.Name         := 'ghwmaq';
  Result.ArmatureNode := 'Armature.001';
  Result.ModelHeight  := 8.84;
  SetLength(Result.RootNodes, 1);
  Result.RootNodes[0] := 'bone';
  SetLength(Result.Bones, 0);

  TempRoot := 0;
  AddBone(Result, 'bone', -1, rrFixed);

  TempPelvis := 1;
  AddBone(Result, 'pelvis', TempRoot, rrYaw);
  AddLimb(Result, 'l.leg', 'l.leg2', 'l.leg3', TempPelvis, rrFoot, jLHip, jLKnee, jLAnkle);
  AddLimb(Result, 'r.leg', 'r.leg2', 'r.leg3', TempPelvis, rrFoot, jRHip, jRKnee, jRAnkle);

  AddBone(Result, 'spine1', TempRoot, rrSpine, -1, jPelvis, jPelvis, 1, 2);
  TempSpine2 := length(Result.Bones);
  AddBone(Result, 'spine2', TempSpine2 - 1, rrSpine, -1, jPelvis, jPelvis, 2, 2);
  AddLimb(Result, 'l.arm1', 'l.arm2', 'l.hand', TempSpine2, rrFollow, jLShoulder, jLElbow, jLWrist);
  AddLimb(Result, 'r.arm1', 'r.arm2', 'r.hand', TempSpine2, rrFollow, jRShoulder, jRElbow, jRWrist);
  AddBone(Result, 'neck', TempSpine2, rrFollow);
  AddBone(Result, 'head', length(Result.Bones) - 1, rrHead);
end;

// GHWBodyModel.glb : Rigify like bones. The names of the right arm bones have
// a space at the end ('Shoulder R ', 'Upper Arm R ').
function GhwBodyProfile : TRigProfile;
var
  TempPelvis, TempSpine, TempSide : integer;
begin
  Result.Name         := 'GHWBodyModel';
  Result.ArmatureNode := 'Armature';
  Result.ModelHeight  := 8.87;
  SetLength(Result.RootNodes, 2);
  Result.RootNodes[0] := 'Spine001';
  Result.RootNodes[1] := 'Spine002';
  SetLength(Result.Bones, 0);

  // Lower body : Spine001 carries the hips and legs.
  TempPelvis := 0;
  AddBone(Result, 'Spine001', -1, rrYaw);
  TempSide := length(Result.Bones);
  AddBone(Result, 'Pelvis L', TempPelvis, rrFollow);
  AddLimb(Result, 'Thigh L', 'Shin L', 'Foot L', TempSide, rrFoot, jLHip, jLKnee, jLAnkle);
  TempSide := length(Result.Bones);
  AddBone(Result, 'Pelvis R', TempPelvis, rrFollow);
  AddLimb(Result, 'Thigh R', 'Shin R', 'Foot R', TempSide, rrFoot, jRHip, jRKnee, jRAnkle);

  // Upper body : 5 spine bones
  TempSpine := length(Result.Bones);
  AddBone(Result, 'Spine002', -1, rrSpine, -1, jPelvis, jPelvis, 1, 5);
  AddBone(Result, 'Spine003', TempSpine,     rrSpine, -1, jPelvis, jPelvis, 2, 5);
  AddBone(Result, 'Spine004', TempSpine + 1, rrSpine, -1, jPelvis, jPelvis, 3, 5);
  AddBone(Result, 'Spine005', TempSpine + 2, rrSpine, -1, jPelvis, jPelvis, 4, 5);
  AddBone(Result, 'Spine006', TempSpine + 3, rrSpine, -1, jPelvis, jPelvis, 5, 5);
  TempSpine := TempSpine + 4;   // Spine006

  // The shoulders are children of Spine005, the neck of Spine006.
  TempSide := length(Result.Bones);
  AddBone(Result, 'Shoulder L', TempSpine - 1, rrFollow);
  AddLimb(Result, 'Upper Arm L', 'Forearm L', 'Hand L', TempSide, rrFollow, jLShoulder, jLElbow, jLWrist);
  TempSide := length(Result.Bones);
  AddBone(Result, 'Shoulder R ', TempSpine - 1, rrFollow);
  AddLimb(Result, 'Upper Arm R ', 'Forearm R', 'Hand R', TempSide, rrFollow, jRShoulder, jRElbow, jRWrist);

  AddBone(Result, 'Neck', TempSpine, rrFollow);
  AddBone(Result, 'Head', length(Result.Bones) - 1, rrHead);
end;

function QuatIdentity : TQuat;
begin
  Result.X := 0; Result.Y := 0; Result.Z := 0; Result.W := 1;
end;

function QuatFromAxisAngle(const aAxis : TVec3; aAngle : Single) : TQuat;
var
  TempSin : Single;
begin
  TempSin  := Sin(aAngle / 2);
  Result.X := aAxis.X * TempSin;
  Result.Y := aAxis.Y * TempSin;
  Result.Z := aAxis.Z * TempSin;
  Result.W := Cos(aAngle / 2);
end;

// Hamilton product : A * B (B is applied first)
function QuatMul(const A, B : TQuat) : TQuat;
begin
  Result.W := (A.W * B.W) - (A.X * B.X) - (A.Y * B.Y) - (A.Z * B.Z);
  Result.X := (A.W * B.X) + (A.X * B.W) + (A.Y * B.Z) - (A.Z * B.Y);
  Result.Y := (A.W * B.Y) - (A.X * B.Z) + (A.Y * B.W) + (A.Z * B.X);
  Result.Z := (A.W * B.Z) + (A.X * B.Y) - (A.Y * B.X) + (A.Z * B.W);
end;

function QuatConjugate(const A : TQuat) : TQuat;
begin
  Result.X := -A.X; Result.Y := -A.Y; Result.Z := -A.Z; Result.W := A.W;
end;

function QuatRotate(const aQ : TQuat; const aV : TVec3) : TVec3;
var
  TempP, TempR : TQuat;
begin
  TempP.X := aV.X; TempP.Y := aV.Y; TempP.Z := aV.Z; TempP.W := 0;
  TempR   := QuatMul(QuatMul(aQ, TempP), QuatConjugate(aQ));
  Result  := Vec3(TempR.X, TempR.Y, TempR.Z);
end;

function QuatAlign(const aFrom, aTo : TVec3) : TQuat;
var
  TempFrom, TempTo, TempAxis : TVec3;
  TempLenF, TempLenT, TempDot, TempLenA : Single;
begin
  TempLenF := VecLength(aFrom);
  TempLenT := VecLength(aTo);

  if (TempLenF < 0.000001) or (TempLenT < 0.000001) then
    begin
      Result := QuatIdentity;
      exit;
    end;

  TempFrom := Vec3(aFrom.X / TempLenF, aFrom.Y / TempLenF, aFrom.Z / TempLenF);
  TempTo   := Vec3(aTo.X / TempLenT, aTo.Y / TempLenT, aTo.Z / TempLenT);
  TempDot  := (TempFrom.X * TempTo.X) + (TempFrom.Y * TempTo.Y) + (TempFrom.Z * TempTo.Z);

  TempAxis := Vec3((TempFrom.Y * TempTo.Z) - (TempFrom.Z * TempTo.Y),
                   (TempFrom.Z * TempTo.X) - (TempFrom.X * TempTo.Z),
                   (TempFrom.X * TempTo.Y) - (TempFrom.Y * TempTo.X));
  TempLenA := VecLength(TempAxis);

  if (TempLenA < 0.000001) then
    begin
      if (TempDot > 0) then
        Result := QuatIdentity
       else
        begin
          // Opposite directions : turn 180 degrees around any perpendicular axis
          if (Abs(TempFrom.X) < 0.9) then
            TempAxis := Vec3(0, -TempFrom.Z, TempFrom.Y)
           else
            TempAxis := Vec3(TempFrom.Z, 0, -TempFrom.X);

          TempLenA := VecLength(TempAxis);
          Result   := QuatFromAxisAngle(Vec3(TempAxis.X / TempLenA, TempAxis.Y / TempLenA, TempAxis.Z / TempLenA), Pi);
        end;

      exit;
    end;

  if (TempDot > 1) then TempDot := 1;
  if (TempDot < -1) then TempDot := -1;

  Result := QuatFromAxisAngle(Vec3(TempAxis.X / TempLenA, TempAxis.Y / TempLenA, TempAxis.Z / TempLenA), ArcCos(TempDot));
end;

function QuatSlerp(const A, B : TQuat; aT : Single) : TQuat;
var
  TempB : TQuat;
  TempDot, TempOmega, TempSin, TempS0, TempS1, TempLen : Single;
begin
  TempDot := (A.X * B.X) + (A.Y * B.Y) + (A.Z * B.Z) + (A.W * B.W);
  TempB   := B;

  if (TempDot < 0) then
    begin
      TempDot := -TempDot;
      TempB.X := -B.X; TempB.Y := -B.Y; TempB.Z := -B.Z; TempB.W := -B.W;
    end;

  if (TempDot > 0.9995) then
    begin
      // Almost the same : linear interpolation
      TempS0 := 1 - aT;
      TempS1 := aT;
    end
   else
    begin
      TempOmega := ArcCos(TempDot);
      TempSin   := Sin(TempOmega);
      TempS0    := Sin((1 - aT) * TempOmega) / TempSin;
      TempS1    := Sin(aT * TempOmega) / TempSin;
    end;

  Result.X := (A.X * TempS0) + (TempB.X * TempS1);
  Result.Y := (A.Y * TempS0) + (TempB.Y * TempS1);
  Result.Z := (A.Z * TempS0) + (TempB.Z * TempS1);
  Result.W := (A.W * TempS0) + (TempB.W * TempS1);

  TempLen := Sqrt((Result.X * Result.X) + (Result.Y * Result.Y) + (Result.Z * Result.Z) + (Result.W * Result.W));
  Result.X := Result.X / TempLen; Result.Y := Result.Y / TempLen;
  Result.Z := Result.Z / TempLen; Result.W := Result.W / TempLen;
end;

procedure QuatToAxisAngle(const aQ : TQuat; out aAxis : TVec3; out aAngle : Single);
var
  TempW, TempSin : Single;
begin
  TempW := aQ.W;
  if (TempW > 1) then TempW := 1;
  if (TempW < -1) then TempW := -1;

  aAngle  := 2 * ArcCos(TempW);
  TempSin := Sqrt(1 - (TempW * TempW));

  if (TempSin < 0.000001) then
    begin
      aAxis  := Vec3(1, 0, 0);
      aAngle := 0;
    end
   else
    aAxis := Vec3(aQ.X / TempSin, aQ.Y / TempSin, aQ.Z / TempSin);
end;

procedure BuildRigPose(const aProfile : TRigProfile; const aRest : TRigRestArray;
                       const aPose : TAvatarPose; out aRig : TRigPose);
var
  TempCount, i : integer;
  TempRestW, TempDelta, TempNewW : array of TQuat;
  TempYaw, TempTilt, TempFull, TempRoll, TempHeadYaw : TQuat;
  TempParent : integer;
  TempRestDir, TempPoseDir : TVec3;
begin
  TempCount := length(aProfile.Bones);

  SetLength(aRig.Rotation, TempCount);
  SetLength(TempRestW, TempCount);
  SetLength(TempDelta, TempCount);
  SetLength(TempNewW, TempCount);

  for i := 0 to pred(TempCount) do
    aRig.Rotation[i] := aRest[i].Rotation;

  aRig.Valid      := aPose.Valid;
  aRig.RootOffset := Vec3(aPose.Joints[jPelvis].X, aPose.Joints[jPelvis].Y - PELVIS_HEIGHT, aPose.Joints[jPelvis].Z);

  if not(aPose.Valid) then
    begin
      aRig.RootOffset := Vec3(0, 0, 0);
      exit;
    end;

  TempYaw  := QuatFromAxisAngle(Vec3(0, 1, 0), aPose.TorsoYaw);
  TempTilt := QuatAlign(Vec3(0, 1, 0), VecSub(aPose.Joints[jChest], aPose.Joints[jPelvis]));
  TempFull := QuatMul(TempTilt, TempYaw);
  TempRoll := QuatFromAxisAngle(Vec3(0, 0, 1), aPose.HeadRoll);
  TempHeadYaw := QuatFromAxisAngle(Vec3(0, 1, 0), aPose.HeadYaw);

  for i := 0 to pred(TempCount) do
    begin
      TempParent := aProfile.Bones[i].Parent;

      // Rest rotation in the world
      if (TempParent >= 0) then
        TempRestW[i] := QuatMul(TempRestW[TempParent], aRest[i].Rotation)
       else
        TempRestW[i] := aRest[i].Rotation;

      // Rotation that is added in the world
      case aProfile.Bones[i].Role of
        rrYaw, rrFoot :
          TempDelta[i] := TempYaw;

        rrSpine :
          TempDelta[i] := QuatSlerp(QuatIdentity, TempFull,
                                    aProfile.Bones[i].SpineIndex / aProfile.Bones[i].SpineCount);

        rrHead :
          TempDelta[i] := QuatMul(TempRoll, TempHeadYaw);

        rrLimb :
          begin
            // The bone looks to its child at rest, it has to look to the next joint.
            TempRestDir := QuatRotate(TempRestW[i], aRest[aProfile.Bones[i].Child].Translation);
            TempPoseDir := VecSub(aPose.Joints[aProfile.Bones[i].ToJoint], aPose.Joints[aProfile.Bones[i].FromJoint]);
            TempDelta[i] := QuatAlign(TempRestDir, TempPoseDir);
          end;

        rrFollow :
          if (TempParent >= 0) then
            TempDelta[i] := TempDelta[TempParent]
           else
            TempDelta[i] := QuatIdentity;

        else
          TempDelta[i] := QuatIdentity;
      end;

      TempNewW[i] := QuatMul(TempDelta[i], TempRestW[i]);

      if (TempParent >= 0) then
        aRig.Rotation[i] := QuatMul(QuatConjugate(TempNewW[TempParent]), TempNewW[i])
       else
        aRig.Rotation[i] := TempNewW[i];
    end;
end;

end.

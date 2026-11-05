unit uMaleAvatar;

// 3D model of an adult male in his 30s (1.75 m) for Castle Game Engine.
//
// The body is built in code from the engine primitives (ellipsoids, cylinders
// and boxes), so no model file is needed. Every bone is a cylinder that is
// stretched between two joints each frame, which makes the avatar follow the
// pose exactly. The proportions are in uPoseSolver (BODY_HEIGHT ...).
//
// To use a rigged glTF character instead, keep uPoseSolver and replace this
// unit : the TAvatarPose has everything that is needed to rotate the bones.

interface

uses
  System.Classes, System.SysUtils,
  CastleTransform, CastleScene, CastleVectors, CastleColors,
  uPoseSolver;

type
  TMaleAvatar = class(TCastleTransform)
    protected
      // Bones : the pivot is moved and rotated, its child is the cylinder.
      FNeck, FUpperArmL, FUpperArmR, FForearmL, FForearmR : TCastleTransform;
      FThighL, FThighR, FShinL, FShinR                    : TCastleTransform;
      // Joints and body parts that are only moved
      FShoulderL, FShoulderR, FElbowL, FElbowR, FHandL, FHandR : TCastleTransform;
      FKneeL, FKneeR, FFootL, FFootR                           : TCastleTransform;
      // Nodes that are moved and rotated
      FPelvis, FTorso, FTorsoYaw, FHead, FHeadRoll, FHeadYaw   : TCastleTransform;

      function  NewNode(aParent : TCastleTransform) : TCastleTransform;
      function  NewEllipsoid(aParent : TCastleTransform; aRx, aRy, aRz : Single;
                             const aColor : TCastleColor;
                             aX : Single = 0; aY : Single = 0; aZ : Single = 0) : TCastleSphere;
      function  NewBone(aRadius, aLength : Single; const aColor : TCastleColor) : TCastleTransform;
      function  NewJoint(aRadius : Single; const aColor : TCastleColor) : TCastleTransform;
      procedure PlaceBone(aBone : TCastleTransform; aNominalLength : Single; const aA, aB : TVec3);
      procedure Build;
    public
      constructor Create(AOwner : TComponent); override;

      /// <summary>
      /// Moves the avatar to the pose.
      /// </summary>
      procedure ApplyPose(const aPose : TAvatarPose);
  end;

implementation

const
  SKIN_R  = 0.87; SKIN_G  = 0.69; SKIN_B  = 0.57;
  HAIR_R  = 0.16; HAIR_G  = 0.11; HAIR_B  = 0.08;
  SHIRT_R = 0.22; SHIRT_G = 0.38; SHIRT_B = 0.62;
  PANTS_R = 0.17; PANTS_G = 0.18; PANTS_B = 0.23;
  SHOE_R  = 0.08; SHOE_G  = 0.08; SHOE_B  = 0.09;

function ToVector3(const aV : TVec3) : TVector3;
begin
  Result := Vector3(aV.X, aV.Y, aV.Z);
end;

constructor TMaleAvatar.Create(AOwner : TComponent);
begin
  inherited Create(AOwner);

  Build;
end;

function TMaleAvatar.NewNode(aParent : TCastleTransform) : TCastleTransform;
begin
  Result := TCastleTransform.Create(Self);
  aParent.Add(Result);
end;

function TMaleAvatar.NewEllipsoid(aParent : TCastleTransform; aRx, aRy, aRz : Single;
                                  const aColor : TCastleColor;
                                  aX, aY, aZ : Single) : TCastleSphere;
begin
  Result             := TCastleSphere.Create(Self);
  Result.Radius      := 1;
  Result.Slices      := 20;
  Result.Stacks      := 14;
  Result.Color       := aColor;
  Result.Scale       := Vector3(aRx, aRy, aRz);
  Result.Translation := Vector3(aX, aY, aZ);
  aParent.Add(Result);
end;

function TMaleAvatar.NewBone(aRadius, aLength : Single; const aColor : TCastleColor) : TCastleTransform;
var
  TempCylinder : TCastleCylinder;
begin
  Result := NewNode(self);

  TempCylinder        := TCastleCylinder.Create(Self);
  TempCylinder.Radius := aRadius;
  TempCylinder.Height := aLength;
  TempCylinder.Slices := 18;
  TempCylinder.Color  := aColor;
  Result.Add(TempCylinder);
end;

function TMaleAvatar.NewJoint(aRadius : Single; const aColor : TCastleColor) : TCastleTransform;
begin
  Result := NewNode(self);
  NewEllipsoid(Result, aRadius, aRadius, aRadius, aColor);
end;

procedure TMaleAvatar.PlaceBone(aBone : TCastleTransform; aNominalLength : Single; const aA, aB : TVec3);
var
  TempDir, TempAxis : TVec3;
  TempAngle, TempLen : Single;
begin
  TempDir := VecSub(aB, aA);
  TempLen := VecLength(TempDir);

  if (TempLen < 0.001) then exit;

  AlignYAxis(TempDir, TempAxis, TempAngle);

  aBone.Translation := Vector3((aA.X + aB.X) / 2, (aA.Y + aB.Y) / 2, (aA.Z + aB.Z) / 2);
  aBone.Rotation    := Vector4(TempAxis.X, TempAxis.Y, TempAxis.Z, TempAngle);
  // The bone is a little longer or shorter when the measured joints move apart.
  aBone.Scale       := Vector3(1, TempLen / aNominalLength, 1);
end;

procedure TMaleAvatar.Build;
var
  TempSkin, TempHair, TempShirt, TempPants, TempShoe : TCastleColor;
  TempGround : TCastleBox;
  TempFoot : TCastleBox;
begin
  TempSkin  := Vector4(SKIN_R, SKIN_G, SKIN_B, 1);
  TempHair  := Vector4(HAIR_R, HAIR_G, HAIR_B, 1);
  TempShirt := Vector4(SHIRT_R, SHIRT_G, SHIRT_B, 1);
  TempPants := Vector4(PANTS_R, PANTS_G, PANTS_B, 1);
  TempShoe  := Vector4(SHOE_R, SHOE_G, SHOE_B, 1);

  // Ground
  TempGround             := TCastleBox.Create(Self);
  TempGround.Size        := Vector3(6, 0.02, 6);
  TempGround.Translation := Vector3(0, -0.01, 0);
  TempGround.Color       := Vector4(0.30, 0.33, 0.30, 1);
  Add(TempGround);

  // Pelvis (pants) : ellipsoid at the pelvis joint.
  FPelvis := NewNode(self);
  NewEllipsoid(FPelvis, 0.175, 0.115, 0.115, TempPants, 0, -0.02, 0);

  // Torso (shirt) : an ellipsoid between the pelvis and the shoulders.
  // Chest width 0.36, depth 0.23 (a bit broad : 30s male).
  FTorso    := NewNode(self);
  FTorsoYaw := NewNode(FTorso);
  NewEllipsoid(FTorsoYaw, 0.185, 0.30, 0.115, TempShirt);

  // Neck and head
  FNeck := NewBone(0.050, HEAD_DISTANCE, TempSkin);

  FHead     := NewNode(self);
  FHeadRoll := NewNode(FHead);
  FHeadYaw  := NewNode(FHeadRoll);
  NewEllipsoid(FHeadYaw, 0.088, 0.118, 0.103, TempSkin);                 // head
  NewEllipsoid(FHeadYaw, 0.092, 0.080, 0.106, TempHair, 0, 0.050, -0.006); // hair
  NewEllipsoid(FHeadYaw, 0.015, 0.020, 0.020, TempSkin, 0, -0.012, 0.100); // nose
  NewEllipsoid(FHeadYaw, 0.010, 0.010, 0.008, TempHair, 0.036, 0.020, 0.090);  // eyes
  NewEllipsoid(FHeadYaw, 0.010, 0.010, 0.008, TempHair, -0.036, 0.020, 0.090);
  NewEllipsoid(FHeadYaw, 0.014, 0.028, 0.020, TempSkin, 0.088, 0.000, -0.005); // ears
  NewEllipsoid(FHeadYaw, 0.014, 0.028, 0.020, TempSkin, -0.088, 0.000, -0.005);

  // Arms : sleeves (shirt) on the upper arms, skin on the forearms.
  FUpperArmL := NewBone(0.048, UPPER_ARM_LEN, TempShirt);
  FUpperArmR := NewBone(0.048, UPPER_ARM_LEN, TempShirt);
  FForearmL  := NewBone(0.037, FOREARM_LEN, TempSkin);
  FForearmR  := NewBone(0.037, FOREARM_LEN, TempSkin);
  FShoulderL := NewJoint(0.062, TempShirt);
  FShoulderR := NewJoint(0.062, TempShirt);
  FElbowL    := NewJoint(0.042, TempSkin);
  FElbowR    := NewJoint(0.042, TempSkin);
  FHandL     := NewNode(self);
  FHandR     := NewNode(self);
  NewEllipsoid(FHandL, 0.040, 0.055, 0.025, TempSkin);
  NewEllipsoid(FHandR, 0.040, 0.055, 0.025, TempSkin);

  // Legs
  FThighL := NewBone(0.078, THIGH_LEN, TempPants);
  FThighR := NewBone(0.078, THIGH_LEN, TempPants);
  FShinL  := NewBone(0.055, SHIN_LEN, TempPants);
  FShinR  := NewBone(0.055, SHIN_LEN, TempPants);
  FKneeL  := NewJoint(0.066, TempPants);
  FKneeR  := NewJoint(0.066, TempPants);

  FFootL := NewNode(self);
  FFootR := NewNode(self);
  TempFoot             := TCastleBox.Create(Self);
  TempFoot.Size        := Vector3(0.10, 0.07, 0.27);
  TempFoot.Color       := TempShoe;
  FFootL.Add(TempFoot);
  TempFoot             := TCastleBox.Create(Self);
  TempFoot.Size        := Vector3(0.10, 0.07, 0.27);
  TempFoot.Color       := TempShoe;
  FFootR.Add(TempFoot);
end;

procedure TMaleAvatar.ApplyPose(const aPose : TAvatarPose);
var
  TempAxis, TempDir, TempMid, TempHand : TVec3;
  TempAngle, TempLen : Single;
  TempSin, TempCos : Single;

  procedure PlaceHand(aHand : TCastleTransform; const aElbow, aWrist : TVec3);
  begin
    TempDir := VecSub(aWrist, aElbow);
    TempLen := VecLength(TempDir);

    if (TempLen < 0.001) then exit;

    // The hand continues the forearm.
    TempHand := Vec3(aWrist.X + (TempDir.X / TempLen * 0.06),
                     aWrist.Y + (TempDir.Y / TempLen * 0.06),
                     aWrist.Z + (TempDir.Z / TempLen * 0.06));

    AlignYAxis(TempDir, TempAxis, TempAngle);
    aHand.Translation := ToVector3(TempHand);
    aHand.Rotation    := Vector4(TempAxis.X, TempAxis.Y, TempAxis.Z, TempAngle);
  end;

  procedure PlaceFoot(aFoot : TCastleTransform; const aAnkle : TVec3);
  begin
    // The shoe points to the front of the torso.
    aFoot.Translation := Vector3(aAnkle.X + (TempSin * 0.06), aAnkle.Y - 0.045, aAnkle.Z + (TempCos * 0.06));
    aFoot.Rotation    := Vector4(0, 1, 0, aPose.TorsoYaw);
  end;

begin
  if not(aPose.Valid) then exit;

  TempSin := Sin(aPose.TorsoYaw);
  TempCos := Cos(aPose.TorsoYaw);

  // Pelvis
  FPelvis.Translation := ToVector3(aPose.Joints[jPelvis]);
  FPelvis.Rotation    := Vector4(0, 1, 0, aPose.TorsoYaw);

  // Torso : centered between the pelvis and the shoulder line, along the spine.
  TempDir := VecSub(aPose.Joints[jChest], aPose.Joints[jPelvis]);
  AlignYAxis(TempDir, TempAxis, TempAngle);
  TempMid := Vec3(aPose.Joints[jPelvis].X + (TempDir.X * 0.5),
                  aPose.Joints[jPelvis].Y + (TempDir.Y * 0.5),
                  aPose.Joints[jPelvis].Z + (TempDir.Z * 0.5));
  FTorso.Translation  := ToVector3(TempMid);
  FTorso.Rotation     := Vector4(TempAxis.X, TempAxis.Y, TempAxis.Z, TempAngle);
  FTorsoYaw.Rotation  := Vector4(0, 1, 0, aPose.TorsoYaw);

  // Neck and head
  PlaceBone(FNeck, HEAD_DISTANCE, aPose.Joints[jChest], aPose.Joints[jHead]);
  FHead.Translation   := ToVector3(aPose.Joints[jHead]);
  FHeadRoll.Rotation  := Vector4(0, 0, 1, aPose.HeadRoll);
  FHeadYaw.Rotation   := Vector4(0, 1, 0, aPose.HeadYaw);

  // Arms
  FShoulderL.Translation := ToVector3(aPose.Joints[jLShoulder]);
  FShoulderR.Translation := ToVector3(aPose.Joints[jRShoulder]);
  FElbowL.Translation    := ToVector3(aPose.Joints[jLElbow]);
  FElbowR.Translation    := ToVector3(aPose.Joints[jRElbow]);
  PlaceBone(FUpperArmL, UPPER_ARM_LEN, aPose.Joints[jLShoulder], aPose.Joints[jLElbow]);
  PlaceBone(FUpperArmR, UPPER_ARM_LEN, aPose.Joints[jRShoulder], aPose.Joints[jRElbow]);
  PlaceBone(FForearmL, FOREARM_LEN, aPose.Joints[jLElbow], aPose.Joints[jLWrist]);
  PlaceBone(FForearmR, FOREARM_LEN, aPose.Joints[jRElbow], aPose.Joints[jRWrist]);
  PlaceHand(FHandL, aPose.Joints[jLElbow], aPose.Joints[jLWrist]);
  PlaceHand(FHandR, aPose.Joints[jRElbow], aPose.Joints[jRWrist]);

  // Legs
  FKneeL.Translation := ToVector3(aPose.Joints[jLKnee]);
  FKneeR.Translation := ToVector3(aPose.Joints[jRKnee]);
  PlaceBone(FThighL, THIGH_LEN, aPose.Joints[jLHip], aPose.Joints[jLKnee]);
  PlaceBone(FThighR, THIGH_LEN, aPose.Joints[jRHip], aPose.Joints[jRKnee]);
  PlaceBone(FShinL, SHIN_LEN, aPose.Joints[jLKnee], aPose.Joints[jLAnkle]);
  PlaceBone(FShinR, SHIN_LEN, aPose.Joints[jRKnee], aPose.Joints[jRAnkle]);
  PlaceFoot(FFootL, aPose.Joints[jLAnkle]);
  PlaceFoot(FFootR, aPose.Joints[jRAnkle]);
end;

end.

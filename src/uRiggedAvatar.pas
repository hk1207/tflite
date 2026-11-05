unit uRiggedAvatar;

// Rigged (skinned) glTF human model in Castle Game Engine, moved by the pose.
//
// The model is loaded from a .glb file. The bones are the glTF nodes : their
// names and orientations are described by a profile (uPoseRig), so ghwmaq.glb
// and GHWBodyModel.glb work. The skin follows the bones (Castle Game Engine
// TSkinNode), see https://castle-engine.io/skin .
//
// Every frame the rotation of each bone is set (BuildRigPose) and the root
// bones are moved, so the model does what the person does.

interface

uses
  System.Classes, System.SysUtils,
  CastleTransform, CastleScene, CastleVectors, CastleUriUtils, X3DNodes,
  uPoseSolver, uPoseRig;

type
  TRiggedAvatar = class(TCastleTransform)
    protected
      FScene         : TCastleScene;
      FProfile       : TRigProfile;
      FRest          : TRigRestArray;
      FBones         : array of TTransformNode;
      FRootNodes     : array of TTransformNode;
      FRootRest      : array of TVector3;
      FMetersPerUnit : Single;   // size of one unit of the model in meters
      FArmatureScale : Single;   // scale of the parent node of the root bones

      function FindBone(const aName : string) : TTransformNode;
      function MatchesProfile(const aProfile : TRigProfile) : boolean;
      procedure UseProfile(const aProfile : TRigProfile);
    public
      /// <summary>
      /// aModelFile : a .glb / .gltf file with one of the supported rigs.
      /// </summary>
      constructor Create(AOwner : TComponent; const aModelFile : string); reintroduce;

      /// <summary>
      /// Moves the avatar to the pose.
      /// </summary>
      procedure ApplyPose(const aPose : TAvatarPose);

      function ProfileName : string;
  end;

implementation

constructor TRiggedAvatar.Create(AOwner : TComponent; const aModelFile : string);
begin
  inherited Create(AOwner);

  FScene := TCastleScene.Create(Self);
  FScene.Load(FilenameToUriSafe(aModelFile));

  if MatchesProfile(GhwmaqProfile) then
    UseProfile(GhwmaqProfile)
   else
    if MatchesProfile(GhwBodyProfile) then
      UseProfile(GhwBodyProfile)
     else
      raise Exception.CreateFmt('%s : the bones of this model are not known (see the profiles in uPoseRig.pas)',
                                [ExtractFileName(aModelFile)]);

  // The model is some units tall, scale it to the height of the body model.
  FMetersPerUnit := BODY_HEIGHT / FProfile.ModelHeight;
  FScene.Scale   := Vector3(FMetersPerUnit, FMetersPerUnit, FMetersPerUnit);
  Add(FScene);
end;

function TRiggedAvatar.FindBone(const aName : string) : TTransformNode;
begin
  Result := FScene.Node(TTransformNode, aName, [fnNilOnMissing]) as TTransformNode;
end;

function TRiggedAvatar.MatchesProfile(const aProfile : TRigProfile) : boolean;
var
  i : integer;
begin
  Result := True;

  for i := 0 to high(aProfile.Bones) do
    if (FindBone(aProfile.Bones[i].Node) = nil) then
      begin
        Result := False;
        exit;
      end;
end;

procedure TRiggedAvatar.UseProfile(const aProfile : TRigProfile);
var
  i : integer;
  TempArmature : TTransformNode;
  TempRot : TVector4;
  TempAxis : TVec3;
  TempLen : Single;
begin
  FProfile := aProfile;

  SetLength(FBones, length(aProfile.Bones));
  SetLength(FRest, length(aProfile.Bones));

  for i := 0 to high(aProfile.Bones) do
    begin
      FBones[i] := FindBone(aProfile.Bones[i].Node);

      // Rest transformation of the bone node (axis-angle -> quaternion)
      FRest[i].Translation := Vec3(FBones[i].Translation.X, FBones[i].Translation.Y, FBones[i].Translation.Z);

      TempRot  := FBones[i].Rotation;
      TempLen  := Sqrt((TempRot.X * TempRot.X) + (TempRot.Y * TempRot.Y) + (TempRot.Z * TempRot.Z));

      if (TempLen < 0.000001) then
        FRest[i].Rotation := QuatIdentity
       else
        begin
          TempAxis := Vec3(TempRot.X / TempLen, TempRot.Y / TempLen, TempRot.Z / TempLen);
          FRest[i].Rotation := QuatFromAxisAngle(TempAxis, TempRot.W);
        end;
    end;

  SetLength(FRootNodes, length(aProfile.RootNodes));
  SetLength(FRootRest, length(aProfile.RootNodes));

  for i := 0 to high(aProfile.RootNodes) do
    begin
      FRootNodes[i] := FindBone(aProfile.RootNodes[i]);
      FRootRest[i]  := FRootNodes[i].Translation;
    end;

  FArmatureScale := 1;

  if (aProfile.ArmatureNode <> '') then
    begin
      TempArmature := FindBone(aProfile.ArmatureNode);

      if (TempArmature <> nil) and (TempArmature.Scale.X > 0.000001) then
        FArmatureScale := TempArmature.Scale.X;
    end;
end;

function TRiggedAvatar.ProfileName : string;
begin
  Result := FProfile.Name;
end;

procedure TRiggedAvatar.ApplyPose(const aPose : TAvatarPose);
var
  TempRig : TRigPose;
  TempAxis : TVec3;
  TempAngle, TempFactor : Single;
  i : integer;
begin
  if not(aPose.Valid) then exit;

  BuildRigPose(FProfile, FRest, aPose, TempRig);

  for i := 0 to high(FBones) do
    begin
      QuatToAxisAngle(TempRig.Rotation[i], TempAxis, TempAngle);
      FBones[i].Rotation := Vector4(TempAxis.X, TempAxis.Y, TempAxis.Z, TempAngle);
    end;

  // Meters -> units of the translation of the root bones
  TempFactor := 1 / (FMetersPerUnit * FArmatureScale);

  for i := 0 to high(FRootNodes) do
    FRootNodes[i].Translation := FRootRest[i] +
      Vector3(TempRig.RootOffset.X * TempFactor,
              TempRig.RootOffset.Y * TempFactor,
              TempRig.RootOffset.Z * TempFactor);
end;

end.

unit uPoseEstimator;

{$IFDEF FPC}{$MODE Delphi}{$ENDIF}

// Common interface of the pose models (MoveNet, BlazePose). The estimator
// receives the camera frame and returns the 17 keypoints in pixels of that
// frame. Models that measure the depth (BlazePose) also return the 3D positions.

interface

uses
  uPoseSolver;

type
  TPoseResult = record
    Found     : boolean;      // False if no body was found in the frame
    FrameWidth, FrameHeight : Single;   // size of the frame in pixels
    Keypoints : TKeypoints;   // pixels of the frame
    Has3D     : boolean;      // True if World is measured by the model
    World     : TKeypoints3D; // meters, origin at the hips, +X right, +Y up, +Z to the camera
  end;

  TPoseEstimator = class
    public
      /// <summary>
      /// Short name of the model for the user interface.
      /// </summary>
      function Name : string; virtual; abstract;
      /// <summary>
      /// True if the estimator needs the frames of the application camera. False
      /// if it gets the pose from somewhere else (the MediaPipe bridge) : then
      /// Estimate is called with aFrame = nil.
      /// </summary>
      function UsesCamera : boolean; virtual;
      /// <summary>
      /// aFrame : 4 bytes per pixel (BGRA if aBGRA, RGBA if not), aPitch = bytes of a row.
      /// </summary>
      function Estimate(aFrame : Pointer; aW, aH, aPitch : integer; aBGRA : boolean) : TPoseResult; virtual; abstract;
      /// <summary>
      /// Forget the position of the body in the previous frames.
      /// </summary>
      procedure ResetTracking; virtual;
  end;

implementation

function TPoseEstimator.UsesCamera : boolean;
begin
  Result := True;
end;

procedure TPoseEstimator.ResetTracking;
begin
  //
end;

end.

# Pose Motion

Measures the human pose in real time with **TensorFlow Lite (MoveNet)** and
moves a **3D male model (30s, 1.75 m)** rendered with
[Castle Game Engine](https://github.com/hk1207/castle-engine) the same way.

Delphi, FMX, Windows. Webcam input.

```
webcam frame --> crop + resize (uPoseImage) --> MoveNet (uTFLite, uMoveNet)
   --> 17 keypoints --> smoothing + 3D joints (uPoseSolver) --> 3D model (uMaleAvatar)
```

## What is in the folders

| Folder | Content |
| --- | --- |
| `src/uTFLite.pas` | Delphi binding of the TensorFlow Lite C API (DLL loaded at run time) |
| `src/uMoveNet.pas` | MoveNet SinglePose Lightning/Thunder |
| `src/uPoseImage.pas` | Crop to a square and resize the camera frame (BGRA/RGBA -> RGB) |
| `src/uPoseSolver.pas` | One Euro smoothing, scale, 2D keypoints -> 3D joints of the body model |
| `src/uMaleAvatar.pas` | The 3D male model, built in code with Castle Game Engine primitives |
| `app/` | The FMX application (`PoseMotion.dpr`, the form is created in code) |
| `tests/` | Console tests of the pose solver and the image preparation |
| `models/`, `bin/` | Where to put `movenet.tflite` and `tensorflowlite_c.dll` |

## Build and run

1. **Castle Game Engine** : clone https://github.com/hk1207/castle-engine and
   install its Delphi packages (`packages/delphi/AllPackages.groupproj`, install
   all except `castle_engine_window`). This adds the engine units and
   `Fmx.CastleControl` to the Delphi library path.
2. Get **`movenet.tflite`** ([models/README.md](models/README.md)) and
   **`tensorflowlite_c.dll`** ([bin/README.md](bin/README.md)).
3. Open `app/PoseMotion.dpr` in Delphi (13.x tested by the engine, 12.x should work),
   platform **Windows 64-bit**, build and run. Copy the model and the DLL next
   to the executable (or put the model in `models/`).
4. Stand 2-3 m from the camera, so that the whole body is visible, face the
   camera and press **Calibrate again**.

The application needs FMX `TCameraComponent`, so it is an FMX application.

## How the pose is measured

* MoveNet gives 17 2D keypoints (nose, eyes, ears, shoulders, elbows, wrists,
  hips, knees, ankles).
* The keypoints are smoothed with a One Euro filter (low jitter, low lag).
* The scale (meters per pixel) comes from the torso length, so the avatar has
  the same size near or far from the camera. Calibration also sets the
  reference position of the hips.
* The depth of each limb is estimated from its bone length : if a bone looks
  shorter than its real length, the rest points to (or away from) the camera.
  The direction can't be seen in one 2D image, so elbows and knees bend to the
  camera by default. If an arm moves to the wrong side, tick **Flip the depth
  direction**.
* The turn of the body (yaw) comes from the shoulder/hip width and the side of
  the nose; the head yaw and roll come from the ears and the nose.

This is a single-camera estimate : fast and simple, but depth and the turn of
the body are approximations. A model with 3D output (for example BlazePose) can
be added later by filling `TAvatarPose` from its landmarks.

## The 3D model

`TMaleAvatar` builds an adult male (30s, 1.75 m, broad shoulders, shirt, dark
pants, short hair) from ellipsoids, cylinders and boxes. Each bone is a cylinder
stretched between two joints. The proportions are constants at the top of
`uPoseSolver.pas` (`UPPER_ARM_LEN`, `THIGH_LEN`, `SHOULDER_WIDTH` ...) and the
colors are constants in `uMaleAvatar.pas`.

## Tests

The solver and the image code have no Windows dependencies :

```
cd tests
fpc -Mdelphi -Fu../src TestPose.pas
./TestPose
```

The TensorFlow Lite binding, the camera, the Castle Game Engine avatar and the
form need Delphi on Windows and were **not compiled or run** while writing them.

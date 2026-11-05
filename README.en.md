# Pose Motion

[한국어](README.md)

A Delphi application that measures the human pose from a webcam in real time
with **TensorFlow Lite** and makes a **rigged 3D human model (glTF)** do the same
movements. The 3D rendering uses
[Castle Game Engine](https://github.com/hk1207/castle-engine).

* Delphi FMX, Windows, webcam input
* Pose model : **BlazePose (3D)** or **MoveNet (2D)**
* 3D human model : `ghwmaq.glb`, `GHWBodyModel.glb` (the zip can be used as it is)

```
webcam frame --> pose model (BlazePose 3D / MoveNet 2D) --> 17 keypoints (+ 3D positions)
   --> smoothing + 3D joints (uPoseSolver) --> bone rotations (uPoseRig)
   --> rigged glTF model (uRiggedAvatar)
```

## Folders

| Folder/file | Content |
| --- | --- |
| `src/uTFLite.pas` | TensorFlow Lite C API binding (`tensorflowlite_c.dll` is loaded at run time) |
| `src/uPoseEstimator.pas` | Common interface of the pose models |
| `src/uMoveNet.pas` | MoveNet SinglePose (Lightning/Thunder), 2D |
| `src/uBlazePose.pas`, `src/uBlazeDecode.pas` | BlazePose landmark model, 3D world coordinates, body tracking |
| `src/uPoseModels.pas` | Opens a `.tflite` file and detects the kind of model |
| `src/uPoseImage.pas` | Crops the camera frame and converts it to the model input (RGB) |
| `src/uPoseSolver.pas` | Smoothing, scale, 2D/3D keypoints -> 3D joints of the body |
| `src/uPoseRig.pas` | Joints -> rotations of the model bones. Profile of each model |
| `src/uRiggedAvatar.pas` | Loads the rigged glTF model and applies the bone rotations |
| `app/` | The FMX application (`PoseMotion.dpr`, the form is created in code) |
| `models/` | 3D models (`ghwmaq.glb`, `GHWBodyModel.zip`) and the place for the pose models |
| `tests/` | Tests of the pose solver, the rig, BlazePose decoding and image code (Free Pascal) |

## Pose models

| Model | Output | Notes |
| --- | --- | --- |
| **BlazePose** (MediaPipe) | 33 landmarks + **3D world coordinates (meters)** | The depth and the turn of the body are **measured**. Recommended |
| **MoveNet** (Lightning/Thunder) | 17 2D keypoints | Fast and simple. The depth is **estimated** from the bone lengths |

See [models/README.md](models/README.md) to download them. Put the `.tflite` file in
`models/`; the application finds it and you can select it in the left panel.
A MediaPipe `.task` file works as it is.

Other ways to measure a 3D pose (not in this application yet) :

* 2D -> 3D lifting models : VideoPose3D, MotionBERT (PyTorch/ONNX, they need an ONNX Runtime binding)
* Human mesh recovery : HMR2.0 / 4DHumans, ROMP, WHAM (SMPL model, GPU needed)
* Depth cameras : Azure Kinect Body Tracking, Intel RealSense, ZED (hardware needed)
* To add a model, inherit `TPoseEstimator` (`src/uPoseEstimator.pas`) and implement `Estimate`.

## 3D human models

Both models are rigged (skinned). The application recognizes the model by its bone names.

| File | Bones | Notes |
| --- | --- | --- |
| `models/ghwmaq.glb` | `pelvis`, `spine1/2`, `l.arm1/2`, `l.leg/2/3` ... | Simple human model (6.6 MB) |
| `models/GHWBodyModel.zip` | `Spine001..006`, `Upper Arm L`, `Thigh L` ... | Anatomical model with muscles/organs/nerves (a 45 MB `.glb` in the zip) |

`GHWBodyModel.zip` doesn't have to be unzipped : the application extracts the `.glb` to the
temporary folder the first time.

The bone rotations are calculated from the rest pose of the model, so different bone orientations
work. For another rigged model add a profile (bone names, parents, roles) in `src/uPoseRig.pas`.

## Build and run

1. **Castle Game Engine** : get https://github.com/hk1207/castle-engine and install its Delphi packages
   (`packages/delphi/AllPackages.groupproj`, install all except `castle_engine_window`).
2. Get a pose model (`.tflite`) and **`tensorflowlite_c.dll`**
   ([models/README.md](models/README.md), [bin/README.md](bin/README.md)).
3. Open `app/PoseMotion.dpr` in Delphi, build for **Windows 64-bit** and run it.
   Put the DLL next to the executable.
4. Stand 2-3 m from the camera, so that the whole body is visible, face the camera and press
   **Calibrate again**.

Command line : `PoseMotion.exe [pose model .tflite/.task] [3D model .glb/.zip]`

## From pose to 3D

* The keypoints are smoothed with a One Euro filter (low jitter, low lag).
* The scale (meters per pixel) comes from the torso length, so the model has the same size near or
  far from the camera.
* **BlazePose** : the limbs follow the directions of the 3D world positions, the shoulder line gives
  the turn of the body and the nose and ears give the turn of the head.
* **MoveNet** : the missing length of a bone is the depth. The direction can't be seen, so elbows and
  knees bend to the camera by default. If they move the wrong way, tick **Flip the depth direction**.
* For each bone, the rotation "direction at rest -> measured direction" is applied to the model bone.

## Tests

The parts without Windows dependencies (pose solver, rig, BlazePose decoding, image code) are tested
with Free Pascal :

```
cd tests
fpc -Mdelphi -Fu../src TestPose.pas
./TestPose
```

The TensorFlow Lite binding, the camera, the Castle Game Engine model loading and the form need
Delphi on Windows and were **not compiled or run yet**.

## Limits

* The BlazePose pose detector model is not used. The first frame uses the square at the center of the
  image, so the person has to stand in the middle with the whole body visible. Then the body is tracked.
* Fingers, toes and face expressions don't move (the hand follows the forearm).
* One camera only : hidden parts are not accurate.

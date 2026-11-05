# Pose Motion (포즈 모션)

[English](README.en.md)

웹캠으로 사람의 포즈를 **TensorFlow Lite**로 실시간 측정하고, 같은 동작을
**리깅된 3D 인체 모델(glTF)** 이 따라 하게 하는 Delphi 앱입니다.
3D 렌더링은 [Castle Game Engine](https://github.com/hk1207/castle-engine)을 사용합니다.

* Delphi FMX, Windows, 웹캠 입력
* 포즈 모델 선택 : **BlazePose(3D)** 또는 **MoveNet(2D)**
* 3D 인체 모델 선택 : `ghwmaq.glb`, `GHWBodyModel.glb`(zip 그대로 사용 가능)

```
웹캠 프레임 --> 포즈 모델 (BlazePose 3D / MoveNet 2D)  --> 키포인트 17개 (+ 3D 좌표)
   --> 보정/평활화 + 3D 관절 계산 (uPoseSolver) --> 본 회전 계산 (uPoseRig)
   --> 리깅된 glTF 모델 (uRiggedAvatar)
```

## 폴더 구성

| 폴더/파일 | 내용 |
| --- | --- |
| `src/uTFLite.pas` | TensorFlow Lite C API 바인딩 (`tensorflowlite_c.dll`을 실행 중에 로드) |
| `src/uPoseEstimator.pas` | 포즈 모델 공통 인터페이스 |
| `src/uMoveNet.pas` | MoveNet SinglePose (Lightning/Thunder), 2D |
| `src/uBlazePose.pas`, `src/uBlazeDecode.pas` | BlazePose 랜드마크 모델, 3D 월드 좌표, 몸 추적 |
| `src/uPoseModels.pas` | `.tflite` 파일을 열어 모델 종류를 자동으로 판별 |
| `src/uPoseImage.pas` | 카메라 프레임을 잘라서 모델 입력(RGB)으로 변환 |
| `src/uPoseSolver.pas` | 평활화, 크기 보정, 2D/3D 키포인트 -> 몸 관절 3D 위치 |
| `src/uPoseRig.pas` | 관절 위치 -> 모델 본(bone)의 회전. 모델별 프로파일 |
| `src/uRiggedAvatar.pas` | 리깅된 glTF 모델 로드, 본 회전 적용 |
| `app/` | FMX 앱 (`PoseMotion.dpr`, 폼은 코드로 생성) |
| `models/` | 3D 모델 (`ghwmaq.glb`, `GHWBodyModel.zip`), 포즈 모델 넣는 곳 |
| `tests/` | 포즈 계산, 리그, BlazePose 해석, 이미지 처리 테스트 (Free Pascal) |

## 포즈 모델

| 모델 | 출력 | 특징 |
| --- | --- | --- |
| **BlazePose** (MediaPipe) | 랜드마크 33개 + **3D 월드 좌표(미터)** | 깊이와 몸의 회전을 **측정**합니다. 권장 |
| **MoveNet** (Lightning/Thunder) | 2D 키포인트 17개 | 빠르고 단순합니다. 깊이는 뼈 길이로 **추정**합니다. |

받는 방법은 [models/README.md](models/README.md)를 보세요. `.tflite` 파일을 `models/`에 넣으면
앱이 자동으로 찾고, 왼쪽 패널에서 고를 수 있습니다. MediaPipe `.task` 파일도 그대로 쓸 수 있습니다.

그 밖의 3D 포즈 측정 방법 (이 앱에는 아직 없음) :

* 2D -> 3D 변환 모델 : VideoPose3D, MotionBERT (PyTorch/ONNX, ONNX Runtime 연동이 필요)
* 인체 메시 복원 : HMR2.0 / 4DHumans, ROMP, WHAM (SMPL 모델, GPU 필요)
* 깊이 카메라 : Azure Kinect Body Tracking, Intel RealSense, ZED (장치 필요)
* 새 모델을 추가하려면 `TPoseEstimator`(`src/uPoseEstimator.pas`)를 상속해 `Estimate`를 구현하세요.

## 3D 인체 모델

두 모델 모두 리깅(스키닝)되어 있습니다. 앱이 본 이름으로 모델 종류를 알아냅니다.

| 파일 | 본 | 비고 |
| --- | --- | --- |
| `models/ghwmaq.glb` | `pelvis`, `spine1/2`, `l.arm1/2`, `l.leg/2/3` ... | 단순한 인체 모델 (6.6 MB) |
| `models/GHWBodyModel.zip` | `Spine001..006`, `Upper Arm L`, `Thigh L` ... | 근육/장기/신경이 있는 해부학 모델 (zip 안에 45 MB `.glb`) |

`GHWBodyModel.zip`은 풀지 않아도 됩니다. 앱이 처음 실행할 때 임시 폴더에 `.glb`를 풉니다.

본의 회전은 모델의 기본 자세(rest pose)에서 계산하므로 본 방향이 달라도 동작합니다.
다른 리깅 모델을 쓰려면 `src/uPoseRig.pas`에 프로파일(본 이름, 부모, 역할)을 추가하세요.

## 빌드와 실행

1. **Castle Game Engine** : https://github.com/hk1207/castle-engine 을 받아서 Delphi 패키지를
   설치합니다 (`packages/delphi/AllPackages.groupproj`, `castle_engine_window`를 제외하고 모두 Install).
2. 포즈 모델(`.tflite`)과 **`tensorflowlite_c.dll`**을 준비합니다
   ([models/README.md](models/README.md), [bin/README.md](bin/README.md)).
3. Delphi에서 `app/PoseMotion.dpr`을 열고 **Windows 64-bit**로 빌드해서 실행합니다.
   DLL은 실행 파일 옆에 둡니다.
4. 카메라에서 2~3 m 떨어져 전신이 보이게 서서 정면을 보고 **Calibrate again**을 누릅니다.

명령줄 : `PoseMotion.exe [포즈 모델 .tflite/.task] [3D 모델 .glb/.zip]`

## 포즈를 3D로 바꾸는 방법

* 키포인트를 One Euro 필터로 평활화합니다 (떨림은 줄이고 지연은 적게).
* 크기(미터/픽셀)는 몸통 길이로 보정하므로 카메라와의 거리가 달라도 모델 크기가 같습니다.
* **BlazePose** : 3D 월드 좌표의 방향으로 팔다리를 움직이고, 어깨선으로 몸의 회전을,
  코와 귀로 머리의 회전을 계산합니다.
* **MoveNet** : 뼈 길이에서 모자란 길이를 깊이로 봅니다. 앞뒤 방향은 알 수 없어서 팔꿈치와
  무릎은 카메라 쪽으로 굽는 것을 기본으로 합니다. 반대로 움직이면 **Flip the depth direction**을 켜세요.
* 본마다 "기본 자세에서의 방향 -> 측정한 방향" 회전을 구해 모델의 본에 적용합니다.

## 테스트

Windows가 필요 없는 부분(포즈 계산, 리그, BlazePose 해석, 이미지 처리)은 Free Pascal로 테스트합니다.

```
cd tests
fpc -Mdelphi -Fu../src TestPose.pas
./TestPose
```

TensorFlow Lite 바인딩, 카메라, Castle Game Engine 모델 로드, 폼은 Delphi + Windows가 필요하며
**아직 컴파일하거나 실행해 보지 않았습니다.**

## 한계

* BlazePose의 포즈 검출 모델(detector)은 쓰지 않습니다. 첫 프레임은 화면 가운데 정사각형을 쓰므로
  사람이 화면 가운데에 전신이 보이게 서야 합니다. 이후에는 몸을 따라갑니다.
* 손가락, 발가락, 얼굴 표정은 움직이지 않습니다 (손은 팔뚝을 따라갑니다).
* 카메라 한 대로 측정하므로 가려진 부분은 부정확합니다.

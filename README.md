# Pose Motion (포즈 모션)

[English](README.en.md)

웹캠으로 사람의 포즈를 **TensorFlow Lite**로 실시간 측정하고, 같은 동작을
**리깅된 3D 인체 모델(glTF)** 이 따라 하게 하는 Delphi 앱입니다.
3D 렌더링은 [Castle Game Engine](https://github.com/hk1207/castle-engine)을 사용합니다.

* Delphi FMX, Windows, 웹캠 입력
* 포즈 모델 선택 : **BlazePose(3D, MediaPipe 파이프라인을 Delphi에서 직접 처리)**, **MoveNet(2D)**, **YOLO pose(2D)**, **MediaPipe(3D, Python 브리지)**
* 추론 엔진 선택 : **TensorFlow Lite**(`.tflite`) 또는 **ONNX Runtime**(`.onnx`)
* 3D 인체 모델 선택 : `ghwmaq.glb`, `GHWBodyModel.glb`(zip 그대로 사용 가능)

```
웹캠 프레임 --> 포즈 모델 (TFLite / ONNX Runtime)  --> 키포인트 17개 (+ 3D 좌표)
(또는 Python MediaPipe 브리지 --UDP--> 랜드마크 33개 + 3D 좌표)
   --> 보정/평활화 + 3D 관절 계산 (uPoseSolver) --> 본 회전 계산 (uPoseRig)
   --> 리깅된 glTF 모델 (uRiggedAvatar)
```

## 폴더 구성

| 폴더/파일 | 내용 |
| --- | --- |
| `src/uInference.pas` | 추론 엔진 공통 인터페이스 (TFLite와 ONNX Runtime이 같은 모델 코드를 씀) |
| `src/uTFLite.pas` | TensorFlow Lite C API 바인딩 (`tensorflowlite_c.dll`을 실행 중에 로드) |
| `src/uOnnxRuntime.pas` | ONNX Runtime C API 바인딩 (`onnxruntime.dll`을 실행 중에 로드) |
| `src/uPoseEstimator.pas` | 포즈 모델 공통 인터페이스 |
| `src/uMoveNet.pas` | MoveNet SinglePose (Lightning/Thunder), 2D |
| `src/uBlazePose.pas` | MediaPipe Pose 파이프라인 직접 처리 : 검출 -> 회전된 영역 -> 랜드마크 -> 추적 |
| `src/uBlazeDetect.pas`, `src/uBlazeDecode.pas` | 검출 모델(앵커, 해석), 랜드마크 모델 해석, 회전된 영역 계산 |
| `src/uYoloPose.pas`, `src/uYoloDecode.pas` | YOLOv8/11-pose ONNX 모델, 2D |
| `src/uMediaPipeBridge.pas`, `src/uMediaPipeProtocol.pas` | MediaPipe(Python) 브리지 수신 (UDP) |
| `src/uPoseModels.pas` | `.tflite`/`.onnx` 파일을 열어 모델 종류를 자동으로 판별 |
| `tools/mediapipe_bridge.py` | 웹캠에서 MediaPipe Pose Landmarker를 실행해 UDP로 전송하는 Python 프로그램 |
| `src/uPoseImage.pas` | 카메라 프레임을 잘라서 모델 입력(RGB)으로 변환 |
| `src/uPoseSolver.pas` | 평활화, 크기 보정, 2D/3D 키포인트 -> 몸 관절 3D 위치 |
| `src/uPoseRig.pas` | 관절 위치 -> 모델 본(bone)의 회전. 모델별 프로파일 |
| `src/uRiggedAvatar.pas` | 리깅된 glTF 모델 로드, 본 회전 적용 |
| `app/` | FMX 앱 (`PoseMotion.dpr`, 폼은 코드로 생성) |
| `models/` | 3D 모델 (`ghwmaq.glb`, `GHWBodyModel.zip`), 포즈 모델 넣는 곳 |
| `tests/` | 포즈 계산, 리그, BlazePose 해석, 이미지 처리 테스트 (Free Pascal) |

## 포즈 모델

| 모델 | 파일 | 출력 | 특징 |
| --- | --- | --- | --- |
| **BlazePose** (MediaPipe 직접 처리) | `.tflite` 또는 `.onnx` (+ 포즈 검출 모델) | 랜드마크 33개 + **3D 월드 좌표(미터)** | 깊이와 몸의 회전을 **측정**합니다. 브리지 없이 Delphi만으로 동작. 권장 |
| **MediaPipe 브리지** | (Python 프로그램) | 랜드마크 33개 + **3D 월드 좌표** | 공식 MediaPipe 라이브러리를 그대로 사용 |
| **MoveNet** (Lightning/Thunder) | `.tflite` 또는 `.onnx` | 2D 키포인트 17개 | 빠르고 단순합니다. 깊이는 뼈 길이로 **추정**합니다. |
| **YOLO pose** (v8/11) | `.onnx` | 2D 키포인트 17개 | 사람을 찾아서 측정합니다. 깊이는 **추정** |

모델 종류는 출력 모양으로 자동 판별합니다. `.tflite`/`.onnx` 파일을 `models/`에 넣으면 앱이 자동으로
찾고, 왼쪽 패널에서 고를 수 있습니다. 받는 방법은 [models/README.md](models/README.md)를 보세요.
MediaPipe `.task` 파일도 그대로 쓸 수 있습니다.

### MediaPipe 직접 처리 (Python 없이)

MediaPipe Pose의 처리 과정을 Delphi로 옮겼습니다. Python도, 브리지도 필요 없습니다.

1. **포즈 검출 모델**(`pose_detection.tflite`, 입력 224x224)이 전체 화면에서 사람을 찾고,
   몸 중심과 몸을 둘러싼 원 위의 점을 줍니다 (SSD 앵커 2254개를 직접 만들어 해석).
2. 그 두 점으로 몸 주변의 **회전된 정사각형**(1.25배)을 만들어 잘라냅니다.
   몸이 기울거나 누워 있어도 모델에는 똑바로 선 모습이 들어갑니다.
3. **랜드마크 모델**(`pose_landmark_*.tflite`, 입력 256x256)이 랜드마크 33개와 3D 월드 좌표를 줍니다.
   월드 좌표는 영역의 회전만큼 되돌립니다.
4. 다음 프레임의 영역은 이번 랜드마크(33번, 34번)로 계산합니다(추적). 몸을 놓치면 검출 모델을 다시 씁니다.

검출 모델 파일(`pose_detection.tflite` 또는 `pose_detector.tflite`)을 랜드마크 모델 옆에 두면 자동으로 씁니다.
MediaPipe `.task` 파일에는 둘 다 들어 있어서 그대로 쓸 수 있습니다. 검출 모델이 없으면 화면 가운데
정사각형만 쓰므로 사람이 화면 가운데에 서야 합니다.

### ONNX Runtime

`.onnx` 파일을 넣으면 `onnxruntime.dll`(1.14 이상)로 실행합니다. 입력은 `[1,H,W,3]`과 `[1,3,H,W]`
둘 다 지원하고 float32/uint8 입력을 지원합니다. BlazePose, MoveNet을 ONNX로 변환한 모델과
YOLOv8/11-pose 모델이 동작합니다. 출력은 float32만 지원합니다 (float16 모델은 지원하지 않음).
DLL 준비는 [bin/README.md](bin/README.md)를 보세요.

### MediaPipe (Python 브리지)

MediaPipe는 C++/Python 라이브러리라서 Delphi에서 직접 부를 수 없습니다. 그래서 Python 프로그램이
MediaPipe Pose Landmarker를 실행하고, 결과를 UDP(127.0.0.1:5005)로 앱에 보냅니다.

```
pip install -r tools/requirements.txt
python tools/mediapipe_bridge.py --model pose_landmarker_full.task
```

앱의 포즈 모델 목록에서 **MediaPipe (Python bridge ...)** 를 고르면 됩니다.
웹캠은 한 프로그램만 열 수 있어서 이 모드에서는 Python이 카메라를 열고 앱의 카메라는 쓰지 않습니다.
`--video 파일.mp4`, `--image 사진.jpg`, `--preview`(Python 쪽 미리보기)도 있습니다.

그 밖의 3D 포즈 측정 방법 (이 앱에는 아직 없음) :

* 2D -> 3D 변환 모델 : VideoPose3D, MotionBERT (ONNX로 변환하면 `TPoseEstimator`를 새로 만들어 연결할 수 있음)
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
2. 포즈 모델과 추론 엔진 DLL을 준비합니다 : `.tflite` -> **`tensorflowlite_c.dll`**,
   `.onnx` -> **`onnxruntime.dll`** ([models/README.md](models/README.md), [bin/README.md](bin/README.md)).
   MediaPipe 브리지만 쓸 거면 DLL은 필요 없습니다.
3. Delphi에서 `app/PoseMotion.dpr`을 열고 **Windows 64-bit**로 빌드해서 실행합니다.
   DLL은 실행 파일 옆에 둡니다.
4. 카메라에서 2~3 m 떨어져 전신이 보이게 서서 정면을 보고 **Calibrate again**을 누릅니다.

명령줄 : `PoseMotion.exe [포즈 모델 .tflite/.onnx/.task 또는 udp://127.0.0.1:5005] [3D 모델 .glb/.zip]`

## 포즈를 3D로 바꾸는 방법

* 키포인트를 One Euro 필터로 평활화합니다 (떨림은 줄이고 지연은 적게).
* 크기(미터/픽셀)는 몸통 길이로 보정하므로 카메라와의 거리가 달라도 모델 크기가 같습니다.
* **BlazePose** : 3D 월드 좌표의 방향으로 팔다리를 움직이고, 어깨선으로 몸의 회전을,
  코와 귀로 머리의 회전을 계산합니다.
* **MediaPipe 브리지** : BlazePose와 같은 방식으로 3D 월드 좌표를 씁니다.
* **MoveNet / YOLO pose** : 뼈 길이에서 모자란 길이를 깊이로 봅니다. 앞뒤 방향은 알 수 없어서 팔꿈치와
  무릎은 카메라 쪽으로 굽는 것을 기본으로 합니다. 반대로 움직이면 **Flip the depth direction**을 켜세요.
* 본마다 "기본 자세에서의 방향 -> 측정한 방향" 회전을 구해 모델의 본에 적용합니다.

## 테스트

Windows가 필요 없는 부분(포즈 계산, 리그, BlazePose 해석, 이미지 처리)은 Free Pascal로 테스트합니다.

```
cd tests
fpc -Mdelphi -Fu../src TestPose.pas
./TestPose
```

TensorFlow Lite/ONNX Runtime 바인딩, UDP 수신, 카메라, Castle Game Engine 모델 로드, 폼은 Delphi + Windows가
필요하며 **아직 컴파일하거나 실행해 보지 않았습니다.** 포즈 검출 모델 해석(앵커 2254개, 회전된 영역, 회전된 이미지 자르기)은 합성 입력으로 테스트했지만 실제 모델 파일로는 확인하지 못했습니다. `tools/mediapipe_bridge.py`도 MediaPipe로는
실행해 보지 못했고, 전송하는 줄의 형식(`--selftest`)만 Pascal 쪽 해석 코드로 테스트했습니다.

## 한계

* BlazePose를 직접 처리할 때는 한 명만 추적합니다 (MediaPipe의 `num_poses=1`과 같음). 여러 명은 지원하지 않습니다.
* 직접 처리는 MediaPipe의 후처리 필터(랜드마크 평활화)를 쓰지 않고 앱의 One Euro 필터를 씁니다. 첫 프레임은 화면 가운데 정사각형을 쓰므로
  사람이 화면 가운데에 전신이 보이게 서야 합니다. 이후에는 몸을 따라갑니다.
* 손가락, 발가락, 얼굴 표정은 움직이지 않습니다 (손은 팔뚝을 따라갑니다).
* 카메라 한 대로 측정하므로 가려진 부분은 부정확합니다.

# 모델 / Models

## 3D 인체 모델 / 3D human models

* `ghwmaq.glb` : 리깅된 인체 모델 / rigged human model
* `GHWBodyModel.zip` : 리깅된 해부학 모델(`.glb`가 들어 있음). 풀지 않아도 됩니다. /
  rigged anatomical model (has a `.glb`). It doesn't have to be unzipped.

## 포즈 모델 / Pose models

`.tflite` 파일을 이 폴더에 넣으세요. 앱이 자동으로 찾습니다. / Put the `.tflite` file in this folder.
The application finds it.

### BlazePose (3D, 권장 / recommended)

MediaPipe 랜드마크 모델 (입력 256x256) / MediaPipe landmark model (input 256x256) :

* `pose_landmarker_full.task` (또는 lite, heavy) : https://ai.google.dev/edge/mediapipe/solutions/vision/pose_landmarker#models
  — `.task` 파일은 그대로 넣어도 됩니다 (앱이 안의 `pose_landmarks_detector.tflite`를 꺼냅니다). /
  the `.task` file can be used as it is (the application extracts `pose_landmarks_detector.tflite`).
* 또는 `pose_landmark_full.tflite` (MediaPipe 저장소 `mediapipe/modules/pose_landmark/`) /
  or `pose_landmark_full.tflite` (MediaPipe repository)

출력 : 랜드마크 195개 값, 월드 랜드마크 117개 값, 포즈 존재 값 1개 (크기로 구분). /
Outputs : 195 landmark values, 117 world landmark values, 1 pose flag (found by size).

### MoveNet (2D)

| 모델 / Model | 입력 / Input | 비고 / Notes |
| --- | --- | --- |
| MoveNet SinglePose **Lightning** (float16) | 192x192 | 빠름 / fast |
| MoveNet SinglePose **Thunder** (float16) | 256x256 | 더 정확함 / more accurate |

* https://www.kaggle.com/models/google/movenet/tfLite
* https://tfhub.dev/google/movenet/singlepose/lightning/4

모델 입력은 float32 (0..255), uint8, int32를 지원하며 int8 양자화 모델은 지원하지 않습니다. /
The input can be float32 (0..255), uint8 or int32; the int8 quantized variants are not supported.

### ONNX (`.onnx`)

* BlazePose / MoveNet : ONNX 변환 모델 (예: PINTO model zoo) 또는 직접 변환 /
  ONNX versions (for example the PINTO model zoo) or convert them yourself.
* YOLO pose : `yolo export model=yolov8n-pose.pt format=onnx imgsz=640` (Ultralytics).
  출력 `[1, 56, 8400]` / Output `[1, 56, 8400]`.
* 입력 `[1,H,W,3]` 또는 `[1,3,H,W]`, float32/uint8, 고정 크기 / Input `[1,H,W,3]` or `[1,3,H,W]`, float32/uint8, fixed size.

### MediaPipe (Python 브리지 / bridge)

`pose_landmarker_full.task`를 받아 `python tools/mediapipe_bridge.py --model pose_landmarker_full.task`로
실행하세요. / Download `pose_landmarker_full.task` and run the command above.

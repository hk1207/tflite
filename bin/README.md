# DLL : tensorflowlite_c.dll, onnxruntime.dll

`PoseMotion.exe`는 TensorFlow Lite **C API** 라이브러리를 실행 중에 로드합니다.
**`tensorflowlite_c.dll`**(64비트 앱이면 64비트)을 `PoseMotion.exe` 옆에 복사하세요.

Google은 이 라이브러리의 Windows 빌드를 배포하지 않습니다. TensorFlow 소스에서 Bazel로 빌드하거나
믿을 만한 빌드를 사용하세요. 파일 이름은 `tensorflowlite_c.dll`이어야 합니다.

```
bazel build -c opt //tensorflow/lite/c:tensorflowlite_c
```

---

`PoseMotion.exe` loads the TensorFlow Lite **C API** library at run time. Copy
**`tensorflowlite_c.dll`** (64-bit for a 64-bit application) next to `PoseMotion.exe`.

Google doesn't publish a Windows build of this library. Build it from the TensorFlow sources with
Bazel, or use a build that you trust. The file name must be `tensorflowlite_c.dll`.

---

## onnxruntime.dll

`.onnx` 모델을 쓸 때 필요합니다 (ONNX Runtime 1.14 이상, 64비트 앱이면 64비트).
https://github.com/microsoft/onnxruntime/releases 의 `onnxruntime-win-x64-*.zip` 안 `lib\onnxruntime.dll`을
`PoseMotion.exe` 옆에 복사하세요. / Needed for `.onnx` models (ONNX Runtime 1.14 or newer, 64-bit for a 64-bit
application). Copy `lib\onnxruntime.dll` from `onnxruntime-win-x64-*.zip` of the releases page next to `PoseMotion.exe`.

Windows에는 `System32`에 오래된 `onnxruntime.dll`이 있을 수 있어서 실행 파일 옆의 DLL을 쓰는 것이 안전합니다. /
Windows may have an old `onnxruntime.dll` in `System32`, so the DLL next to the executable is safer.

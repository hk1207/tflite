# MoveNet model

Put the MoveNet SinglePose model here and name it **`movenet.tflite`**.
The application also looks for it next to `PoseMotion.exe` and in the parent
folders.

Download one of these (Google, Apache 2.0):

| Model | Input | Notes |
| --- | --- | --- |
| MoveNet SinglePose **Lightning** (float16) | 192x192 | Fast, recommended for a webcam |
| MoveNet SinglePose **Thunder** (float16) | 256x256 | More accurate, slower |

* https://www.kaggle.com/models/google/movenet/tfLite (variations `singlepose-lightning-tflite-float16` and `singlepose-thunder-tflite-float16`)
* or the TensorFlow Hub page https://tfhub.dev/google/movenet/singlepose/lightning/4

The input size is read from the model, so both models work without changes.
The model input can be float32 (0..255), uint8 or int32; the int8 quantized
variants are not supported.

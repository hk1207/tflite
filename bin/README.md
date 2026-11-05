# tensorflowlite_c.dll

`PoseMotion.exe` loads the TensorFlow Lite **C API** library at run time.
Copy **`tensorflowlite_c.dll`** (64-bit if you build the 64-bit application)
next to `PoseMotion.exe`.

Google doesn't publish a Windows build of this library. Build it from the
TensorFlow sources with Bazel :

```
bazel build -c opt //tensorflow/lite/c:tensorflowlite_c
```

or use a prebuilt one that you trust. The file name must be
`tensorflowlite_c.dll`.

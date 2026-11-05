unit uInference;

{$IFDEF FPC}{$MODE Delphi}{$ENDIF}

// Common interface of the inference engines (TensorFlow Lite, ONNX Runtime).
// The pose models (MoveNet, BlazePose, YOLO pose) only use this interface, so
// the same model can come from a .tflite or from an .onnx file.
//
// It has no dependencies on Windows, so the models can be tested on any platform.

interface

uses
  SysUtils;

type
  EInferenceError = class(Exception);

  TSingleArray = array of Single;

  TInferenceEngine = class
    public
      /// <summary>
      /// Input size in pixels and number of channels of the first input.
      /// </summary>
      function InputWidth : integer; virtual; abstract;
      function InputHeight : integer; virtual; abstract;
      /// <summary>
      /// True if the input is [1, 3, H, W] (ONNX), False if it is [1, H, W, 3] (TensorFlow Lite).
      /// </summary>
      function InputChannelsFirst : boolean; virtual; abstract;

      /// <summary>
      /// Copies RGB bytes (aWidth x aHeight x 3, row by row) to the input
      /// tensor. The size must be the size of the model input. Float inputs get
      /// the values 0..255 * aFloatScale + aFloatOffset (1/255 and 0 for 0..1,
      /// 1/127.5 and -1 for -1..1), byte inputs get the bytes. The layout (HWC / CHW) is converted when needed.
      /// </summary>
      procedure SetInputRGB(aRGB : PByte; aWidth, aHeight : integer; aFloatScale : Single = 1; aFloatOffset : Single = 0); virtual; abstract;
      procedure Invoke; virtual; abstract;

      /// <summary>
      /// Output tensors : count, number of values, dimensions. The values are read as float32.
      /// </summary>
      function  OutputCount : integer; virtual; abstract;
      function  OutputValueCount(aIndex : integer) : integer; virtual; abstract;
      function  OutputDimCount(aIndex : integer) : integer; virtual; abstract;
      function  OutputDim(aIndex, aDim : integer) : integer; virtual; abstract;
      procedure ReadOutput(aIndex : integer; out aData : TSingleArray); virtual; abstract;
  end;

implementation

end.

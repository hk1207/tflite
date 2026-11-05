unit uTFLite;

// Minimal Delphi binding of the TensorFlow Lite C API (tensorflowlite_c.dll).
// The DLL is loaded at run time, so the application starts without it and
// shows a clear error message when it isn't found.
//
// C API : https://github.com/tensorflow/tensorflow/blob/master/tensorflow/lite/core/c/c_api.h

interface

uses
  Winapi.Windows, System.SysUtils, uInference;

const
  TFLITE_DLL = 'tensorflowlite_c.dll';

  // TfLiteType
  kTfLiteFloat32 = 1;
  kTfLiteInt32   = 2;
  kTfLiteUInt8   = 3;
  kTfLiteInt8    = 9;

  kTfLiteOk = 0;

type
  ETFLiteError = class(EInferenceError);

  /// <summary>
  /// A loaded model and its interpreter.
  /// </summary>
  TTFLiteInterpreter = class(TInferenceEngine)
    protected
      FModel       : Pointer;
      FOptions     : Pointer;
      FInterpreter : Pointer;
      FInputType   : integer;
      FInputDims   : array of integer;

      procedure CheckStatus(aStatus : integer; const aWhat : string);
    public
      /// <summary>
      /// aDllPath : full path of tensorflowlite_c.dll, empty to search it next
      /// to the executable and in the PATH.
      /// </summary>
      constructor Create(const aModelPath : string; aThreads : integer = 2; const aDllPath : string = '');
      destructor  Destroy; override;

      /// <summary>
      /// Copies RGB bytes (aWidth x aHeight x 3) to the input tensor. The size
      /// must be the size of the model input. float32 models get the values
      /// 0..255 multiplied by aFloatScale (1/255 for BlazePose), uint8 models
      /// the bytes and int32 models the integers.
      /// </summary>
      procedure SetInputRGB(aRGB : PByte; aWidth, aHeight : integer; aFloatScale : Single = 1); override;
      procedure Invoke; override;
      procedure ReadOutput(aIndex : integer; out aData : TSingleArray); override;
      function  OutputCount : integer; override;
      function  OutputValueCount(aIndex : integer) : integer; override;
      function  OutputDimCount(aIndex : integer) : integer; override;
      function  OutputDim(aIndex, aDim : integer) : integer; override;

      function  InputWidth : integer; override;
      function  InputHeight : integer; override;
      function  InputChannelsFirst : boolean; override;

      property InputType : integer read FInputType;
      function InputDim(aIndex : integer) : integer;
      function InputDimCount : integer;
  end;

implementation

type
  TModelCreateFromFile   = function(aPath : PAnsiChar) : Pointer; cdecl;
  TModelDelete           = procedure(aModel : Pointer); cdecl;
  TOptionsCreate         = function : Pointer; cdecl;
  TOptionsDelete         = procedure(aOptions : Pointer); cdecl;
  TOptionsSetNumThreads  = procedure(aOptions : Pointer; aThreads : Int32); cdecl;
  TInterpreterCreate     = function(aModel, aOptions : Pointer) : Pointer; cdecl;
  TInterpreterDelete     = procedure(aInterpreter : Pointer); cdecl;
  TAllocateTensors       = function(aInterpreter : Pointer) : Int32; cdecl;
  TGetInputTensor        = function(aInterpreter : Pointer; aIndex : Int32) : Pointer; cdecl;
  TGetOutputTensor       = function(aInterpreter : Pointer; aIndex : Int32) : Pointer; cdecl;
  TGetOutputCount        = function(aInterpreter : Pointer) : Int32; cdecl;
  TInvoke                = function(aInterpreter : Pointer) : Int32; cdecl;
  TTensorType            = function(aTensor : Pointer) : Int32; cdecl;
  TTensorNumDims         = function(aTensor : Pointer) : Int32; cdecl;
  TTensorDim             = function(aTensor : Pointer; aIndex : Int32) : Int32; cdecl;
  TTensorByteSize        = function(aTensor : Pointer) : NativeUInt; cdecl;
  TTensorCopyFromBuffer  = function(aTensor : Pointer; aData : Pointer; aSize : NativeUInt) : Int32; cdecl;
  TTensorCopyToBuffer    = function(aTensor : Pointer; aData : Pointer; aSize : NativeUInt) : Int32; cdecl;

var
  GLib : HMODULE = 0;
  ModelCreateFromFile  : TModelCreateFromFile;
  ModelDelete          : TModelDelete;
  OptionsCreate        : TOptionsCreate;
  OptionsDelete        : TOptionsDelete;
  OptionsSetNumThreads : TOptionsSetNumThreads;
  InterpreterCreate    : TInterpreterCreate;
  InterpreterDelete    : TInterpreterDelete;
  AllocateTensors      : TAllocateTensors;
  GetInputTensor       : TGetInputTensor;
  GetOutputTensor      : TGetOutputTensor;
  GetOutputCount       : TGetOutputCount;
  InvokeInterpreter    : TInvoke;
  TensorType           : TTensorType;
  TensorNumDims        : TTensorNumDims;
  TensorDim            : TTensorDim;
  TensorByteSize       : TTensorByteSize;
  TensorCopyFromBuffer : TTensorCopyFromBuffer;
  TensorCopyToBuffer   : TTensorCopyToBuffer;

function GetProc(const aName : AnsiString) : Pointer;
begin
  Result := GetProcAddress(GLib, PAnsiChar(aName));

  if (Result = nil) then
    raise ETFLiteError.CreateFmt('%s was not found in %s', [string(aName), TFLITE_DLL]);
end;

procedure LoadLibraryOnce(const aDllPath : string);
var
  TempPath : string;
begin
  if (GLib <> 0) then exit;

  if (aDllPath <> '') then
    TempPath := aDllPath
   else
    TempPath := TFLITE_DLL;

  GLib := LoadLibrary(PChar(TempPath));

  if (GLib = 0) then
    raise ETFLiteError.CreateFmt('%s could not be loaded (%s). Copy it next to the executable.',
                                 [TempPath, SysErrorMessage(GetLastError)]);

  @ModelCreateFromFile  := GetProc('TfLiteModelCreateFromFile');
  @ModelDelete          := GetProc('TfLiteModelDelete');
  @OptionsCreate        := GetProc('TfLiteInterpreterOptionsCreate');
  @OptionsDelete        := GetProc('TfLiteInterpreterOptionsDelete');
  @OptionsSetNumThreads := GetProc('TfLiteInterpreterOptionsSetNumThreads');
  @InterpreterCreate    := GetProc('TfLiteInterpreterCreate');
  @InterpreterDelete    := GetProc('TfLiteInterpreterDelete');
  @AllocateTensors      := GetProc('TfLiteInterpreterAllocateTensors');
  @GetInputTensor       := GetProc('TfLiteInterpreterGetInputTensor');
  @GetOutputTensor      := GetProc('TfLiteInterpreterGetOutputTensor');
  @GetOutputCount       := GetProc('TfLiteInterpreterGetOutputTensorCount');
  @InvokeInterpreter    := GetProc('TfLiteInterpreterInvoke');
  @TensorType           := GetProc('TfLiteTensorType');
  @TensorNumDims        := GetProc('TfLiteTensorNumDims');
  @TensorDim            := GetProc('TfLiteTensorDim');
  @TensorByteSize       := GetProc('TfLiteTensorByteSize');
  @TensorCopyFromBuffer := GetProc('TfLiteTensorCopyFromBuffer');
  @TensorCopyToBuffer   := GetProc('TfLiteTensorCopyToBuffer');
end;

{ TTFLiteInterpreter }

constructor TTFLiteInterpreter.Create(const aModelPath : string; aThreads : integer; const aDllPath : string);
var
  TempTensor : Pointer;
  i : integer;
begin
  inherited Create;

  FModel       := nil;
  FOptions     := nil;
  FInterpreter := nil;

  if not(FileExists(aModelPath)) then
    raise ETFLiteError.CreateFmt('The model file %s was not found', [aModelPath]);

  LoadLibraryOnce(aDllPath);

  FModel := ModelCreateFromFile(PAnsiChar(AnsiString(aModelPath)));
  if (FModel = nil) then
    raise ETFLiteError.CreateFmt('The model %s could not be loaded', [aModelPath]);

  FOptions := OptionsCreate;
  OptionsSetNumThreads(FOptions, aThreads);

  FInterpreter := InterpreterCreate(FModel, FOptions);
  if (FInterpreter = nil) then
    raise ETFLiteError.Create('The interpreter could not be created');

  CheckStatus(AllocateTensors(FInterpreter), 'AllocateTensors');

  TempTensor := GetInputTensor(FInterpreter, 0);
  if (TempTensor = nil) then
    raise ETFLiteError.Create('The model has no input tensor');

  FInputType := TensorType(TempTensor);
  SetLength(FInputDims, TensorNumDims(TempTensor));

  for i := 0 to high(FInputDims) do
    FInputDims[i] := TensorDim(TempTensor, i);
end;

destructor TTFLiteInterpreter.Destroy;
begin
  if (FInterpreter <> nil) then InterpreterDelete(FInterpreter);
  if (FOptions <> nil)     then OptionsDelete(FOptions);
  if (FModel <> nil)       then ModelDelete(FModel);

  inherited Destroy;
end;

procedure TTFLiteInterpreter.CheckStatus(aStatus : integer; const aWhat : string);
begin
  if (aStatus <> kTfLiteOk) then
    raise ETFLiteError.CreateFmt('%s failed (status %d)', [aWhat, aStatus]);
end;

function TTFLiteInterpreter.InputDim(aIndex : integer) : integer;
begin
  Result := FInputDims[aIndex];
end;

function TTFLiteInterpreter.InputWidth : integer;
begin
  // [1, height, width, 3]
  if (length(FInputDims) = 4) then
    Result := FInputDims[2]
   else
    Result := 0;
end;

function TTFLiteInterpreter.InputHeight : integer;
begin
  if (length(FInputDims) = 4) then
    Result := FInputDims[1]
   else
    Result := 0;
end;

function TTFLiteInterpreter.InputChannelsFirst : boolean;
begin
  Result := False;
end;

function TTFLiteInterpreter.OutputDimCount(aIndex : integer) : integer;
var
  TempTensor : Pointer;
begin
  TempTensor := GetOutputTensor(FInterpreter, aIndex);

  if (TempTensor = nil) then
    Result := 0
   else
    Result := TensorNumDims(TempTensor);
end;

function TTFLiteInterpreter.OutputDim(aIndex, aDim : integer) : integer;
var
  TempTensor : Pointer;
begin
  TempTensor := GetOutputTensor(FInterpreter, aIndex);

  if (TempTensor = nil) then
    Result := 0
   else
    Result := TensorDim(TempTensor, aDim);
end;

function TTFLiteInterpreter.InputDimCount : integer;
begin
  Result := length(FInputDims);
end;

procedure TTFLiteInterpreter.SetInputRGB(aRGB : PByte; aWidth, aHeight : integer; aFloatScale : Single);
var
  TempTensor : Pointer;
  TempCount, i : integer;
  TempFloats : TSingleArray;
  TempInts : TArray<Int32>;
begin
  TempTensor := GetInputTensor(FInterpreter, 0);
  TempCount  := aWidth * aHeight * 3;

  case FInputType of
    kTfLiteFloat32 :
      begin
        SetLength(TempFloats, TempCount);
        for i := 0 to pred(TempCount) do
          TempFloats[i] := PByte(NativeUInt(aRGB) + NativeUInt(i))^ * aFloatScale;

        CheckStatus(TensorCopyFromBuffer(TempTensor, @TempFloats[0], TempCount * SizeOf(Single)), 'CopyFromBuffer');
      end;

    kTfLiteUInt8 :
      CheckStatus(TensorCopyFromBuffer(TempTensor, aRGB, TempCount), 'CopyFromBuffer');

    kTfLiteInt32 :
      begin
        SetLength(TempInts, TempCount);
        for i := 0 to pred(TempCount) do
          TempInts[i] := PByte(NativeUInt(aRGB) + NativeUInt(i))^;

        CheckStatus(TensorCopyFromBuffer(TempTensor, @TempInts[0], TempCount * SizeOf(Int32)), 'CopyFromBuffer');
      end;

    else
      raise ETFLiteError.CreateFmt('The input tensor type %d is not supported', [FInputType]);
  end;
end;

procedure TTFLiteInterpreter.Invoke;
begin
  CheckStatus(InvokeInterpreter(FInterpreter), 'Invoke');
end;

function TTFLiteInterpreter.OutputCount : integer;
begin
  Result := GetOutputCount(FInterpreter);
end;

function TTFLiteInterpreter.OutputValueCount(aIndex : integer) : integer;
var
  TempTensor : Pointer;
begin
  TempTensor := GetOutputTensor(FInterpreter, aIndex);

  if (TempTensor = nil) then
    Result := 0
   else
    Result := TensorByteSize(TempTensor) div SizeOf(Single);
end;

procedure TTFLiteInterpreter.ReadOutput(aIndex : integer; out aData : TSingleArray);
var
  TempTensor : Pointer;
  TempBytes : NativeUInt;
begin
  TempTensor := GetOutputTensor(FInterpreter, aIndex);

  if (TempTensor = nil) then
    raise ETFLiteError.CreateFmt('The model has no output tensor %d', [aIndex]);

  if (TensorType(TempTensor) <> kTfLiteFloat32) then
    raise ETFLiteError.Create('Only float32 outputs are supported');

  TempBytes := TensorByteSize(TempTensor);
  SetLength(aData, TempBytes div SizeOf(Single));

  if (length(aData) > 0) then
    CheckStatus(TensorCopyToBuffer(TempTensor, @aData[0], TempBytes), 'CopyToBuffer');
end;

end.

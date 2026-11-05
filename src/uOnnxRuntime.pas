unit uOnnxRuntime;

// Minimal Delphi binding of the ONNX Runtime C API (onnxruntime.dll), as an
// inference engine for the pose models. The DLL is loaded at run time.
//
// The C API is a table of function pointers (OrtApi). The indexes of the
// functions in the table are fixed since ONNX Runtime 1.0 : they come from
// include/onnxruntime/core/session/onnxruntime_c_api.h (struct OrtApi).
// The calling convention is stdcall (ORT_API_CALL).

interface

uses
  Winapi.Windows, System.SysUtils, uInference;

const
  ONNXRUNTIME_DLL = 'onnxruntime.dll';

type
  EOnnxError = class(EInferenceError);

  TOnnxEngine = class(TInferenceEngine)
    protected
      FEnv           : Pointer;
      FOptions       : Pointer;
      FSession       : Pointer;
      FMemoryInfo    : Pointer;
      FInputName     : AnsiString;
      FOutputNames   : array of AnsiString;
      FInputDims     : array of Int64;
      FInputType     : integer;
      FChannelsFirst : boolean;
      FOutputDims    : array of array of Int64;
      FOutputs       : array of Pointer;
      FInputFloats   : TSingleArray;
      FInputBytes    : TBytes;

      procedure CheckStatus(aStatus : Pointer);
      procedure ReleaseOutputs;
      procedure ReadDims(aTypeInfo : Pointer; out aDims : TArray<Int64>; out aElementType : integer);
    public
      /// <summary>
      /// aDllPath : full path of onnxruntime.dll, empty to search it next to the
      /// executable and in the PATH.
      /// </summary>
      constructor Create(const aModelPath : string; aThreads : integer = 2; const aDllPath : string = '');
      destructor  Destroy; override;

      function  InputWidth : integer; override;
      function  InputHeight : integer; override;
      function  InputChannelsFirst : boolean; override;
      procedure SetInputRGB(aRGB : PByte; aWidth, aHeight : integer; aFloatScale : Single = 1); override;
      procedure Invoke; override;
      function  OutputCount : integer; override;
      function  OutputValueCount(aIndex : integer) : integer; override;
      function  OutputDimCount(aIndex : integer) : integer; override;
      function  OutputDim(aIndex, aDim : integer) : integer; override;
      procedure ReadOutput(aIndex : integer; out aData : TSingleArray); override;
  end;

implementation

const
  // The API version that is asked to the DLL. The functions that are used here
  // exist since version 1, 14 = ONNX Runtime 1.14 (2023) or newer.
  ORT_API_VERSION_USED = 14;

  // Indexes in the OrtApi table
  API_GET_ERROR_MESSAGE     = 2;
  API_CREATE_ENV            = 3;
  API_CREATE_SESSION        = 7;
  API_RUN                   = 9;
  API_CREATE_SESSION_OPTIONS = 10;
  API_SET_GRAPH_OPT_LEVEL   = 23;
  API_SET_INTRA_OP_THREADS  = 24;
  API_SESSION_GET_INPUT_COUNT  = 30;
  API_SESSION_GET_OUTPUT_COUNT = 31;
  API_SESSION_GET_INPUT_TYPE_INFO  = 33;
  API_SESSION_GET_OUTPUT_TYPE_INFO = 34;
  API_SESSION_GET_INPUT_NAME   = 36;
  API_SESSION_GET_OUTPUT_NAME  = 37;
  API_CREATE_TENSOR_WITH_DATA  = 49;
  API_GET_TENSOR_MUTABLE_DATA  = 51;
  API_CAST_TYPE_INFO_TO_TENSOR_INFO = 55;
  API_GET_TENSOR_ELEMENT_TYPE  = 60;
  API_GET_DIMENSIONS_COUNT     = 61;
  API_GET_DIMENSIONS           = 62;
  API_GET_TENSOR_ELEMENT_COUNT = 64;
  API_GET_TENSOR_TYPE_AND_SHAPE = 65;
  API_CREATE_CPU_MEMORY_INFO   = 69;
  API_ALLOCATOR_FREE           = 76;
  API_GET_ALLOCATOR_DEFAULT    = 78;
  API_RELEASE_ENV              = 92;
  API_RELEASE_STATUS           = 93;
  API_RELEASE_MEMORY_INFO      = 94;
  API_RELEASE_SESSION          = 95;
  API_RELEASE_VALUE            = 96;
  API_RELEASE_TYPE_INFO        = 98;
  API_RELEASE_TENSOR_TYPE_AND_SHAPE_INFO = 99;
  API_RELEASE_SESSION_OPTIONS  = 100;

  // ONNXTensorElementDataType
  ONNX_FLOAT = 1;
  ONNX_UINT8 = 2;

  ORT_LOGGING_LEVEL_WARNING = 2;
  ORT_ENABLE_ALL = 99;
  ORT_ARENA_ALLOCATOR = 1;
  ORT_MEM_TYPE_DEFAULT = 0;

type
  TOrtGetApiBase = function : Pointer; stdcall;
  TOrtGetApi = function(aVersion : Cardinal) : Pointer; stdcall;

  TOrtCreateEnv          = function(aLevel : Integer; aLogId : PAnsiChar; out aEnv : Pointer) : Pointer; stdcall;
  TOrtCreateSessionOptions = function(out aOptions : Pointer) : Pointer; stdcall;
  TOrtSetInt             = function(aOptions : Pointer; aValue : Integer) : Pointer; stdcall;
  TOrtCreateSession      = function(aEnv : Pointer; aPath : PWideChar; aOptions : Pointer; out aSession : Pointer) : Pointer; stdcall;
  TOrtSessionGetCount    = function(aSession : Pointer; out aCount : NativeUInt) : Pointer; stdcall;
  TOrtSessionGetName     = function(aSession : Pointer; aIndex : NativeUInt; aAllocator : Pointer; out aName : PAnsiChar) : Pointer; stdcall;
  TOrtSessionGetTypeInfo = function(aSession : Pointer; aIndex : NativeUInt; out aInfo : Pointer) : Pointer; stdcall;
  TOrtCastTypeInfo       = function(aTypeInfo : Pointer; out aTensorInfo : Pointer) : Pointer; stdcall;
  TOrtGetElementType     = function(aInfo : Pointer; out aType : Integer) : Pointer; stdcall;
  TOrtGetDimensionsCount = function(aInfo : Pointer; out aCount : NativeUInt) : Pointer; stdcall;
  TOrtGetDimensions      = function(aInfo : Pointer; aDims : PInt64; aCount : NativeUInt) : Pointer; stdcall;
  TOrtGetAllocator       = function(out aAllocator : Pointer) : Pointer; stdcall;
  TOrtAllocatorFree      = function(aAllocator : Pointer; aPointer : Pointer) : Pointer; stdcall;
  TOrtCreateCpuMemoryInfo = function(aAllocatorType, aMemType : Integer; out aInfo : Pointer) : Pointer; stdcall;
  TOrtCreateTensorWithData = function(aInfo : Pointer; aData : Pointer; aLength : NativeUInt;
                                      aShape : PInt64; aShapeLength : NativeUInt; aType : Integer;
                                      out aValue : Pointer) : Pointer; stdcall;
  TOrtRun                = function(aSession, aRunOptions : Pointer; aInputNames : PPAnsiChar; aInputs : PPointer;
                                    aInputCount : NativeUInt; aOutputNames : PPAnsiChar; aOutputCount : NativeUInt;
                                    aOutputs : PPointer) : Pointer; stdcall;
  TOrtGetTensorMutableData = function(aValue : Pointer; out aData : Pointer) : Pointer; stdcall;
  TOrtGetTensorTypeAndShape = function(aValue : Pointer; out aInfo : Pointer) : Pointer; stdcall;
  TOrtGetElementCount    = function(aInfo : Pointer; out aCount : NativeUInt) : Pointer; stdcall;
  TOrtRelease            = procedure(aObject : Pointer); stdcall;
  TOrtGetErrorMessage    = function(aStatus : Pointer) : PAnsiChar; stdcall;

var
  GLib : HMODULE = 0;
  GApi : Pointer = nil;

// Function number aIndex of the OrtApi table
function OrtFunction(aIndex : integer) : Pointer;
begin
  Result := PPointer(NativeUInt(GApi) + (NativeUInt(aIndex) * SizeOf(Pointer)))^;
end;

procedure LoadOnnxRuntime(const aDllPath : string);
var
  TempPath : string;
  TempGetApiBase : TOrtGetApiBase;
  TempBase : Pointer;
  TempGetApi : TOrtGetApi;
begin
  if (GApi <> nil) then exit;

  if (aDllPath <> '') then
    TempPath := aDllPath
   else
    TempPath := ONNXRUNTIME_DLL;

  GLib := LoadLibrary(PChar(TempPath));

  if (GLib = 0) then
    raise EOnnxError.CreateFmt('%s could not be loaded (%s). Copy it next to the executable.',
                               [TempPath, SysErrorMessage(GetLastError)]);

  @TempGetApiBase := GetProcAddress(GLib, 'OrtGetApiBase');

  if not(assigned(TempGetApiBase)) then
    raise EOnnxError.CreateFmt('OrtGetApiBase was not found in %s', [TempPath]);

  // OrtApiBase : the first field is GetApi
  TempBase := TempGetApiBase();
  @TempGetApi := PPointer(TempBase)^;
  GApi := TempGetApi(ORT_API_VERSION_USED);

  if (GApi = nil) then
    raise EOnnxError.CreateFmt('%s is too old (ONNX Runtime 1.14 or newer is needed)', [TempPath]);
end;

{ TOnnxEngine }

procedure TOnnxEngine.CheckStatus(aStatus : Pointer);
var
  TempMessage : string;
begin
  if (aStatus = nil) then exit;

  TempMessage := string(AnsiString(TOrtGetErrorMessage(OrtFunction(API_GET_ERROR_MESSAGE))(aStatus)));
  TOrtRelease(OrtFunction(API_RELEASE_STATUS))(aStatus);

  raise EOnnxError.Create('ONNX Runtime : ' + TempMessage);
end;

// Dimensions and element type of a tensor type info (not owned)
procedure TOnnxEngine.ReadDims(aTypeInfo : Pointer; out aDims : TArray<Int64>; out aElementType : integer);
var
  TempInfo : Pointer;
  TempCount : NativeUInt;
begin
  CheckStatus(TOrtCastTypeInfo(OrtFunction(API_CAST_TYPE_INFO_TO_TENSOR_INFO))(aTypeInfo, TempInfo));
  CheckStatus(TOrtGetElementType(OrtFunction(API_GET_TENSOR_ELEMENT_TYPE))(TempInfo, aElementType));
  CheckStatus(TOrtGetDimensionsCount(OrtFunction(API_GET_DIMENSIONS_COUNT))(TempInfo, TempCount));

  SetLength(aDims, TempCount);

  if (TempCount > 0) then
    CheckStatus(TOrtGetDimensions(OrtFunction(API_GET_DIMENSIONS))(TempInfo, @aDims[0], TempCount));
end;

constructor TOnnxEngine.Create(const aModelPath : string; aThreads : integer; const aDllPath : string);
var
  TempAllocator, TempTypeInfo : Pointer;
  TempCount : NativeUInt;
  TempName : PAnsiChar;
  TempDims : TArray<Int64>;
  TempType, i, j : integer;
begin
  inherited Create;

  FEnv        := nil;
  FOptions    := nil;
  FSession    := nil;
  FMemoryInfo := nil;

  if not(FileExists(aModelPath)) then
    raise EOnnxError.CreateFmt('The model file %s was not found', [aModelPath]);

  LoadOnnxRuntime(aDllPath);

  CheckStatus(TOrtCreateEnv(OrtFunction(API_CREATE_ENV))(ORT_LOGGING_LEVEL_WARNING, 'PoseMotion', FEnv));
  CheckStatus(TOrtCreateSessionOptions(OrtFunction(API_CREATE_SESSION_OPTIONS))(FOptions));
  CheckStatus(TOrtSetInt(OrtFunction(API_SET_INTRA_OP_THREADS))(FOptions, aThreads));
  CheckStatus(TOrtSetInt(OrtFunction(API_SET_GRAPH_OPT_LEVEL))(FOptions, ORT_ENABLE_ALL));
  CheckStatus(TOrtCreateSession(OrtFunction(API_CREATE_SESSION))(FEnv, PWideChar(aModelPath), FOptions, FSession));
  CheckStatus(TOrtCreateCpuMemoryInfo(OrtFunction(API_CREATE_CPU_MEMORY_INFO))(ORT_ARENA_ALLOCATOR, ORT_MEM_TYPE_DEFAULT, FMemoryInfo));
  CheckStatus(TOrtGetAllocator(OrtFunction(API_GET_ALLOCATOR_DEFAULT))(TempAllocator));

  // First input : name, type and dimensions
  CheckStatus(TOrtSessionGetCount(OrtFunction(API_SESSION_GET_INPUT_COUNT))(FSession, TempCount));

  if (TempCount < 1) then
    raise EOnnxError.Create('The model has no input');

  CheckStatus(TOrtSessionGetName(OrtFunction(API_SESSION_GET_INPUT_NAME))(FSession, 0, TempAllocator, TempName));
  FInputName := AnsiString(TempName);
  TOrtAllocatorFree(OrtFunction(API_ALLOCATOR_FREE))(TempAllocator, TempName);

  CheckStatus(TOrtSessionGetTypeInfo(OrtFunction(API_SESSION_GET_INPUT_TYPE_INFO))(FSession, 0, TempTypeInfo));
  try
    ReadDims(TempTypeInfo, TempDims, FInputType);
  finally
    TOrtRelease(OrtFunction(API_RELEASE_TYPE_INFO))(TempTypeInfo);
  end;

  if (length(TempDims) <> 4) then
    raise EOnnxError.Create('The input of the model must be an image [1, H, W, 3] or [1, 3, H, W]');

  SetLength(FInputDims, 4);
  for i := 0 to 3 do
    FInputDims[i] := TempDims[i];

  // A dynamic batch size is 1.
  if (FInputDims[0] < 1) then FInputDims[0] := 1;

  FChannelsFirst := (FInputDims[1] = 3) and (FInputDims[3] <> 3);

  if (FInputDims[1] < 1) or (FInputDims[2] < 1) or (FInputDims[3] < 1) then
    raise EOnnxError.Create('The model has a dynamic input size : use a model with a fixed input size');

  if (FInputType <> ONNX_FLOAT) and (FInputType <> ONNX_UINT8) then
    raise EOnnxError.CreateFmt('The input type %d is not supported (float32 and uint8 are)', [FInputType]);

  // Outputs : names and dimensions
  CheckStatus(TOrtSessionGetCount(OrtFunction(API_SESSION_GET_OUTPUT_COUNT))(FSession, TempCount));
  SetLength(FOutputNames, TempCount);
  SetLength(FOutputDims, TempCount);
  SetLength(FOutputs, TempCount);

  for i := 0 to pred(integer(TempCount)) do
    begin
      FOutputs[i] := nil;

      CheckStatus(TOrtSessionGetName(OrtFunction(API_SESSION_GET_OUTPUT_NAME))(FSession, i, TempAllocator, TempName));
      FOutputNames[i] := AnsiString(TempName);
      TOrtAllocatorFree(OrtFunction(API_ALLOCATOR_FREE))(TempAllocator, TempName);

      CheckStatus(TOrtSessionGetTypeInfo(OrtFunction(API_SESSION_GET_OUTPUT_TYPE_INFO))(FSession, i, TempTypeInfo));
      try
        ReadDims(TempTypeInfo, TempDims, TempType);
      finally
        TOrtRelease(OrtFunction(API_RELEASE_TYPE_INFO))(TempTypeInfo);
      end;

      SetLength(FOutputDims[i], length(TempDims));
      for j := 0 to high(TempDims) do
        begin
          FOutputDims[i][j] := TempDims[j];
          if (FOutputDims[i][j] < 1) then FOutputDims[i][j] := 1;  // dynamic dimension
        end;
    end;

  if FChannelsFirst then
    SetLength(FInputFloats, FInputDims[1] * FInputDims[2] * FInputDims[3])
   else
    SetLength(FInputFloats, FInputDims[1] * FInputDims[2] * FInputDims[3]);

  SetLength(FInputBytes, FInputDims[1] * FInputDims[2] * FInputDims[3]);
end;

destructor TOnnxEngine.Destroy;
begin
  ReleaseOutputs;

  if (FMemoryInfo <> nil) then TOrtRelease(OrtFunction(API_RELEASE_MEMORY_INFO))(FMemoryInfo);
  if (FSession <> nil)    then TOrtRelease(OrtFunction(API_RELEASE_SESSION))(FSession);
  if (FOptions <> nil)    then TOrtRelease(OrtFunction(API_RELEASE_SESSION_OPTIONS))(FOptions);
  if (FEnv <> nil)        then TOrtRelease(OrtFunction(API_RELEASE_ENV))(FEnv);

  inherited Destroy;
end;

procedure TOnnxEngine.ReleaseOutputs;
var
  i : integer;
begin
  for i := 0 to high(FOutputs) do
    if (FOutputs[i] <> nil) then
      begin
        TOrtRelease(OrtFunction(API_RELEASE_VALUE))(FOutputs[i]);
        FOutputs[i] := nil;
      end;
end;

function TOnnxEngine.InputWidth : integer;
begin
  if FChannelsFirst then
    Result := FInputDims[3]
   else
    Result := FInputDims[2];
end;

function TOnnxEngine.InputHeight : integer;
begin
  if FChannelsFirst then
    Result := FInputDims[2]
   else
    Result := FInputDims[1];
end;

function TOnnxEngine.InputChannelsFirst : boolean;
begin
  Result := FChannelsFirst;
end;

procedure TOnnxEngine.SetInputRGB(aRGB : PByte; aWidth, aHeight : integer; aFloatScale : Single);
var
  TempPixels, i, c : integer;
  TempValue : Byte;
begin
  if (aWidth <> InputWidth) or (aHeight <> InputHeight) then
    raise EOnnxError.CreateFmt('The image must be %dx%d', [InputWidth, InputHeight]);

  TempPixels := aWidth * aHeight;

  for i := 0 to pred(TempPixels) do
    for c := 0 to 2 do
      begin
        TempValue := PByte(NativeUInt(aRGB) + NativeUInt((i * 3) + c))^;

        if (FInputType = ONNX_FLOAT) then
          begin
            if FChannelsFirst then
              FInputFloats[(c * TempPixels) + i] := TempValue * aFloatScale
             else
              FInputFloats[(i * 3) + c] := TempValue * aFloatScale;
          end
         else
          begin
            if FChannelsFirst then
              FInputBytes[(c * TempPixels) + i] := TempValue
             else
              FInputBytes[(i * 3) + c] := TempValue;
          end;
      end;
end;

procedure TOnnxEngine.Invoke;
var
  TempInput : Pointer;
  TempInputName : PAnsiChar;
  TempOutputNames : array of PAnsiChar;
  TempData : Pointer;
  TempBytes : NativeUInt;
  TempType, i : integer;
begin
  ReleaseOutputs;

  if (FInputType = ONNX_FLOAT) then
    begin
      TempData  := @FInputFloats[0];
      TempBytes := length(FInputFloats) * SizeOf(Single);
      TempType  := ONNX_FLOAT;
    end
   else
    begin
      TempData  := @FInputBytes[0];
      TempBytes := length(FInputBytes);
      TempType  := ONNX_UINT8;
    end;

  CheckStatus(TOrtCreateTensorWithData(OrtFunction(API_CREATE_TENSOR_WITH_DATA))(
                FMemoryInfo, TempData, TempBytes, @FInputDims[0], 4, TempType, TempInput));
  try
    TempInputName := PAnsiChar(FInputName);

    SetLength(TempOutputNames, length(FOutputNames));
    for i := 0 to high(FOutputNames) do
      TempOutputNames[i] := PAnsiChar(FOutputNames[i]);

    CheckStatus(TOrtRun(OrtFunction(API_RUN))(FSession, nil, @TempInputName, @TempInput, 1,
                                              @TempOutputNames[0], length(TempOutputNames), @FOutputs[0]));
  finally
    TOrtRelease(OrtFunction(API_RELEASE_VALUE))(TempInput);
  end;
end;

function TOnnxEngine.OutputCount : integer;
begin
  Result := length(FOutputNames);
end;

function TOnnxEngine.OutputDimCount(aIndex : integer) : integer;
begin
  Result := length(FOutputDims[aIndex]);
end;

function TOnnxEngine.OutputDim(aIndex, aDim : integer) : integer;
begin
  Result := FOutputDims[aIndex][aDim];
end;

function TOnnxEngine.OutputValueCount(aIndex : integer) : integer;
var
  i : integer;
begin
  Result := 1;

  for i := 0 to high(FOutputDims[aIndex]) do
    Result := Result * FOutputDims[aIndex][i];
end;

procedure TOnnxEngine.ReadOutput(aIndex : integer; out aData : TSingleArray);
var
  TempInfo, TempData : Pointer;
  TempCount : NativeUInt;
  TempType : Integer;
begin
  if (FOutputs[aIndex] = nil) then
    raise EOnnxError.Create('Invoke has to be called before ReadOutput');

  CheckStatus(TOrtGetTensorTypeAndShape(OrtFunction(API_GET_TENSOR_TYPE_AND_SHAPE))(FOutputs[aIndex], TempInfo));
  try
    CheckStatus(TOrtGetElementType(OrtFunction(API_GET_TENSOR_ELEMENT_TYPE))(TempInfo, TempType));
    CheckStatus(TOrtGetElementCount(OrtFunction(API_GET_TENSOR_ELEMENT_COUNT))(TempInfo, TempCount));
  finally
    TOrtRelease(OrtFunction(API_RELEASE_TENSOR_TYPE_AND_SHAPE_INFO))(TempInfo);
  end;

  if (TempType <> ONNX_FLOAT) then
    raise EOnnxError.Create('Only float32 outputs are supported');

  SetLength(aData, TempCount);

  if (TempCount > 0) then
    begin
      CheckStatus(TOrtGetTensorMutableData(OrtFunction(API_GET_TENSOR_MUTABLE_DATA))(FOutputs[aIndex], TempData));
      Move(TempData^, aData[0], TempCount * SizeOf(Single));
    end;
end;

end.

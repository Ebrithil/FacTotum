unit U_Functions;

interface

uses
  Windows,
  ShellAPI,
  Forms,
  StrUtils,
  Classes,
  SysUtils;

type
  WinIsWow64 = function( Handle: THandle; var Iret: BOOL ): Windows.BOOL; stdcall;

  procedure ExecuteCommandAndWait(cmd: String);

  function GetExBits: Integer;
  function GetFmtFileVersion(const FileName: String = '';
    const Fmt: String = '%d.%d.%d.%d'): String;
  function BuildPBText(product: String; index, max: Integer): String;
  function Split(StrBuf, Delimiter: String): TStringList;
  function ExtractVersion(SWString: String): String;

implementation

/// <summary>
///   This function reads the file resource of "FileName" and returns
///   the version number as formatted text.</summary>
/// <example>
///   Sto_GetFmtFileVersion() = '4.13.128.0'
///   Sto_GetFmtFileVersion('', '%.2d-%.2d-%.2d') = '04-13-128'
/// </example>
/// <remarks>If "Fmt" is invalid, the function may raise an
///   EConvertError exception.</remarks>
/// <param name="FileName">Full path to exe or dll. If an empty
///   string is passed, the function uses the filename of the
///   running exe or dll.</param>
/// <param name="Fmt">Format string, you can use at most four integer
///   values.</param>
/// <returns>Formatted version number of file, '' if no version
///   resource found.</returns>
function GetFmtFileVersion(const FileName: String = '';
  const Fmt: String = '%d.%d.%d.%d'): String;
var
  sFileName: String;
  iBufferSize: DWORD;
  iDummy: DWORD;
  pBuffer: Pointer;
  pFileInfo: Pointer;
  iVer: array[1..4] of Word;
begin
  // set default value
  Result := '';
  // get filename of exe/dll if no filename is specified
  sFileName := FileName;
  if (sFileName = '') then
  begin
    // prepare buffer for path and terminating #0
    SetLength(sFileName, MAX_PATH + 1);
    SetLength(sFileName,
      GetModuleFileName(hInstance, PChar(sFileName), MAX_PATH + 1));
  end;
  // get size of version info (0 if no version info exists)
  iBufferSize := GetFileVersionInfoSize(PChar(sFileName), iDummy);
  if (iBufferSize > 0) then
  begin
    GetMem(pBuffer, iBufferSize);
    try
    // get fixed file info (language independent)
    GetFileVersionInfo(PChar(sFileName), 0, iBufferSize, pBuffer);
    VerQueryValue(pBuffer, '\', pFileInfo, iDummy);
    // read version blocks
    iVer[1] := HiWord(PVSFixedFileInfo(pFileInfo)^.dwFileVersionMS);
    iVer[2] := LoWord(PVSFixedFileInfo(pFileInfo)^.dwFileVersionMS);
    iVer[3] := HiWord(PVSFixedFileInfo(pFileInfo)^.dwFileVersionLS);
    iVer[4] := LoWord(PVSFixedFileInfo(pFileInfo)^.dwFileVersionLS);
    finally
      FreeMem(pBuffer);
    end;
    // format result string
    Result := Format(Fmt, [iVer[1], iVer[2], iVer[3], iVer[4]]);
  end;
end;

// Check if the OS is x86 or x64
function GetExBits: Integer;
var
  HandleTo64BitsProcess: WinIsWow64;
  Iret                 : Windows.BOOL;
begin
  Result := 1; //x86
  HandleTo64BitsProcess := GetProcAddress(GetModuleHandle('kernel32.dll'), 'IsWow64Process');
  if Assigned(HandleTo64BitsProcess) then
  begin
    if not HandleTo64BitsProcess(GetCurrentProcess, Iret) then
      Raise Exception.Create('Invalid handle');
    if Iret then
      Result := 2; //x64
  end;
end;

procedure ExecuteCommandAndWait(cmd: String);
var
  SEInfo: TShellExecuteInfo;
  ExitCode: DWORD;
  ExecuteFile: string;
begin
  ExecuteFile := cmd;
  FillChar(SEInfo, SizeOf(SEInfo), 0);
  SEInfo.cbSize := SizeOf(TShellExecuteInfo);
  with SEInfo do
  begin
    fMask := SEE_MASK_NOCLOSEPROCESS;
    Wnd := Application.Handle;
    lpFile := PChar(ExecuteFile);
    nShow := SW_NORMAL;
  end;
  if ShellExecuteEx(@SEInfo) then
  begin
    repeat
      Application.ProcessMessages;
      GetExitCodeProcess(SEInfo.hProcess, ExitCode);
    until (ExitCode <> STILL_ACTIVE) or Application.Terminated;
  end;
end;

function BuildPBText(product: String; index, max: Integer): String;
begin
  Result := 'Installing ' + product + ' (' + index.ToString() + ' di ' + max.ToString() + ')';
end;

// Porting of VB Split function
function Split(StrBuf, Delimiter: String): TStringList;
var
  MyStrList: TStringList;
  TmpBuf:    String;
  LoopCount: Integer;
begin
  MyStrList := TStringList.Create;
  LoopCount := 1;

  repeat
    if StrBuf[LoopCount] = Delimiter then
    begin
      MyStrList.Add(Trim(TmpBuf));
      TmpBuf := '';
    end;

    TmpBuf := TmpBuf + StrBuf[LoopCount];
    inc(LoopCount);
  until LoopCount > Length(StrBuf);
  MyStrList.Add(Trim(TmpBuf));

  Result := MyStrList;
end;

function ExtractVersion(SWString: String): String;
var
  i:          Byte;
  SL:         TStringList;
  CheckVer:   Boolean;
  TestString: String;
begin
  SL:= TStringList.Create;
  SL:= Split(SWString, ' ');

  for TestString in SL do
    begin
      CheckVer:= True;
      for i := 1 to Length(TestString) do
        if not( (TestString[i] in ['0'..'9']) or (TestString[i] = '.') ) then
          begin
            CheckVer:= False;
            Break;
          end;

      if CheckVer then
        begin
          if AnsiContainsText(TestString, '.') then
          begin
            Result:= TestString;
            Exit;
          end;
        end;
    end;
  Result := 'N/D';
end;

end.

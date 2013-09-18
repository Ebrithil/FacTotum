unit U_Functions;

interface

uses
    windows, system.strUtils, system.classes, system.sysUtils;

type
    a = string;
    function getFmtFileVersion(const fileName: string = ''; const fmt: string = '%d.%d.%d.%d'): string;
    function split(const strBuf: string; const delimiter: string): tStringList;

implementation

function getFmtFileVersion(const fileName: string = ''; const fmt: string = '%d.%d.%d.%d'): string;
var
    iDummy,
    iBufferSize: DWORD;
    pBuffer,
    pFileInfo:   pointer;
    sFileName:   string;
    iVer:        array[1..4] of word;
begin
    result    := '';
    sFileName := fileName;

    if (sFileName = '') then
    begin
        setLength(sFileName, MAX_PATH + 1);
        setLength(sFileName, getModuleFileName(hInstance, pChar(sFileName), MAX_PATH + 1));
    end;

    iBufferSize := getFileVersionInfoSize(pChar(sFileName), iDummy);
    if (iBufferSize > 0) then
    begin
        getMem(pBuffer, iBufferSize);
        try
            getFileVersionInfo(pChar(sFileName), 0, iBufferSize, pBuffer);
            verQueryValue(pBuffer, '\', pFileInfo, iDummy);
            iVer[1] := hiWord(PVSFixedFileInfo(pFileInfo)^.dwFileVersionMS);
            iVer[2] := loWord(PVSFixedFileInfo(pFileInfo)^.dwFileVersionMS);
            iVer[3] := hiWord(PVSFixedFileInfo(pFileInfo)^.dwFileVersionLS);
            iVer[4] := loWord(PVSFixedFileInfo(pFileInfo)^.dwFileVersionLS);
        finally
            freeMem(pBuffer);
        end;
        result := format(fmt, [iVer[1], iVer[2], iVer[3], iVer[4]]);
    end;
end;

function split(const strBuf: string; const delimiter: string): tStringList;
var
    tmpBuf:    string;
    loopCount: word;
begin
    result := tStringList.create;

    loopCount := 1;
    repeat
        if strBuf[loopCount] = delimiter then
        begin
            result.add( trim(tmpBuf) );
            tmpBuf := '';
        end;
        tmpBuf := tmpBuf + strBuf[loopCount];

        inc(LoopCount);
    until loopCount > length(strBuf);

    result.add( trim(tmpBuf) );
end;

end.

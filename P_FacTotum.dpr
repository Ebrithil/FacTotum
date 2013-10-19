program P_FacTotum;

uses
    Vcl.Forms,
    SysUtils,
    Classes,
    Windows,
    Vcl.Themes,
    Vcl.Styles,
    U_Main        in 'U_Main.pas' {fFacTotum},
    U_Functions   in 'Units\U_Functions.pas',
    U_DataBase    in 'Units\U_DataBase.pas',
    U_Threads     in 'Units\U_Threads.pas',
    U_InputTasks  in 'Units\U_InputTasks.pas',
    U_Download    in 'Units\U_Download.pas',
    U_Events      in 'Units\U_Events.pas',
    U_OutputTasks in 'Units\U_OutputTasks.pas',
    U_Parser      in 'Units\U_Parser.pas',
    U_Files       in 'Units\U_Files.pas';

{$R *.res}
{$R sqlite.RES}

var
 rStream:  tResourceStream;
 fStream:  tFileStream;
 fname:    string;
 sAppPath: string;
begin
    application.initialize;
    sAppPath:= includeTrailingPathDelimiter(extractFileDir(application.exeName));
    if not fileExists(sAppPath + 'resources\' + 'sqlite3.dll') then
    begin
        if not directoryExists('resources') then
            if not createDir('resources') then
                exit;

        fname:= sAppPath + 'resources\' + 'sqlite3.dll';
        rStream := tResourceStream.create(hInstance, 'dSqlite', RT_RCDATA);
        try
            fStream := tFileStream.create(fname, fmCreate);
            try
                fStream.copyFrom(rStream, 0);
            finally
                fStream.free;
            end;
            finally
                rStream.free;
        end;
    end;

    application.mainFormOnTaskbar := true;
    tStyleManager.trySetStyle('Metropolis UI Dark');
    application.createForm(tfFacTotum, fFacTotum);
    application.run;
end.

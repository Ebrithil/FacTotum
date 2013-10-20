program P_FacTotum;

uses
    Vcl.Forms,
    SysUtils,
    Classes,
    Windows,
    Vcl.Dialogs,
    Vcl.Themes,
    Vcl.Styles,
    System.UITypes,
    Winapi.ShellAPI,
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
{$R resources.res}

var
    rStream:  tResourceStream;
    fStream:  tFileStream;
    fName:    string;
begin
    application.initialize;

    sEventHdlr         := eventHandler.create;
    sTaskMgr           := taskManager.create;
    sUpdateParser      := updateParser.create;
    sDownloadMgr       := downloadManager.create;
    sFileMgr           := tFileManager.create;

    if not directoryExists('resources') then
    begin
        createEvent('Cartella resources non trovata. ', eiAlert);
        createEvent('La cartella resources verra'' ricreata. ', eiAlert);
        if not createDir('resources') then
        begin
            messageDlg('Impossibile ricreare la cartella resources.' + #13 + #13
                     + 'Il programma verra'' terminato.', mtError, [mbOK], 0);
            exit;
        end;
    end;

    fname := 'resources\' + 'sqlite3.dll';
    if not fileExists(fName) and
       not sFileMgr.fileExistsInPath('sqlite3.dll') then
    begin
        createEvent('Libreria sqlite3.dll non trovata. ', eiAlert);
        createEvent('La libreria verra'' riestratta. ', eiAlert);

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

        if not fileExists(fName) then
        begin
            messageDlg('Impossibile caricare la libreria sqlite3.dll.' + #13 + #13
                     + 'Il programma verra'' terminato.', mtError, [mbOK], 0);
            exit;
        end;
    end;
    sdbMgr := dbManager.create;

    fName := 'resources\' + 'erasmd.ttf';
    if not fileExists(fName)                                                    and
       not fileExists( getEnvironmentVariable('WINDIR') + '\fonts\erasmd.ttf' ) then
    begin
        rStream := tResourceStream.create(hInstance, 'dErasMD', RT_RCDATA);
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

        if fileExists(fName) then
            if (addFontResource( pchar(fName) ) = 0) then
                createEvent('Impossibile caricare il font erasmd.ttf.', eiAlert)
            else
                createEvent('Font erasmd.ttf caricato correttamente.', eiInfo)
        else
            createEvent('Impossibile caricare il font erasmd.ttf.', eiAlert);
    end;

    application.mainFormOnTaskbar := true;
    tStyleManager.trySetStyle('Metropolis UI Dark');
    application.createForm(tfFacTotum, fFacTotum);
    application.run;
end.

unit U_Files;

interface

uses
    IdHash, System.Classes, System.SysUtils, IdHashSHA, IdHashMessageDigest, ShellAPI, Winapi.Windows,

    U_Events, U_DataBase, U_Threads, U_InputTasks;

type
    fileManager = class
       protected
           m_hasher:    tIdHash;
           m_stpFolder: string;
           function     getFileHash(fileName: string): string;
           function     getArchivePathFor(cmdGuid: integer): string;
           function     isArchived(cmdGuid: integer): boolean; overload;
           function     isArchived(fileHash: string): boolean; overload;
       public
           constructor create(useSha1: boolean = false; stpFolder: string = '.\Setup\');
           destructor  Destroy; override;
           procedure   saveDataStreamToFile(fileName: string; dataStream: tMemoryStream);
           procedure   runCommand(cmd: string);
           procedure   addSetupToArchive(handle: tHandle; cmdRec: cmdRecord; fileName: string; folderName: string = ''); overload;
           procedure   removeSetupFromArchive(archivedName: string);
    end;

    tTaskFlush = class(tTask) // Task per scrivere il MemoryStream su file
        public
            fileName:   string;
            dataStream: tMemoryStream;

            procedure exec; override;
    end;

var
    sFileMgr: fileManager;

implementation

    constructor fileManager.create(useSha1: boolean = false; stpFolder: string = '.\Setup\');
    begin
        self.m_stpFolder := stpFolder;
        if not( directoryExists(self.m_stpFolder) ) then
        begin
            sEventHdlr.pushEventToList( 'Cartella d''installazione non esistente.', eiAlert );
            sEventHdlr.pushEventToList( 'La cartella verrà ricreata.', eiAlert );
            if not( createDir(self.m_stpFolder) ) then
                sEventHdlr.pushEventToList( 'Impossibile creare la cartella d''installazione.', eiError )
        end;

        if useSha1 then
            m_hasher := tIdHashSHA1.create
        else
            m_hasher := tIdHashMessageDigest5.create;
    end;

    destructor fileManager.Destroy;
    begin
        m_hasher.free;
    end;

    function fileManager.getFileHash(fileName: string): string;
    var
        msFile: tMemoryStream;
    begin
        msFile := tMemoryStream.create;
        msFile.loadFromFile(fileName);

        result := ansiLowerCase( self.m_hasher.hashStreamAsHex(msFile) );

        msFile.free;
    end;

    procedure fileManager.saveDataStreamToFile(fileName: string; dataStream: tMemoryStream);
    begin
        dataStream.saveToFile(fileName)
    end;

    procedure fileManager.runCommand(cmd: string);
    begin
        // TODO
    end;

    procedure fileManager.addSetupToArchive(handle: tHandle; cmdRec: cmdRecord; fileName: string; folderName: string = '');
    var
      soFileOperation: tSHFileOpStruct;
      taskUpdate:      tTaskRecordUpdate;
      errorCode:       integer;
      tempHash:        string;
    begin
        // usas FillChar
        fillChar( soFileOperation, sizeOf(soFileOperation), #0 );
        tempHash := self.getFileHash(fileName);
        with soFileOperation do
        begin
            Wnd    := handle;
            wFunc  := FO_COPY;
            fFlags := FOF_NOCONFIRMATION or FOF_NOCONFIRMMKDIR or FOF_SIMPLEPROGRESS;

            if folderName = '' then
                pFrom := pchar(fileName + #0)
            else
                pFrom := pchar(folderName + #0);

            pTo := pchar(self.m_stpFolder + tempHash + #0);
        end;
        errorCode := SHFileOperation(soFileOperation);

        if ( (errorCode <> 0) or soFileOperation.fAnyOperationsAborted ) then
            sEventHdlr.pushEventToList('Errore durante la copia del percorso 0x' + intToHex(errorCode, 8) + '.', eiError)
        else
        begin
            taskUpdate         := tTaskRecordUpdate.create;
            taskUpdate.field   := dbFieldCmdHash;
            taskUpdate.value   := tempHash;
            taskUpdate.tRecord := recordCommand;
            taskUpdate.pRecord := cmdRec;

            sTaskMgr.pushTaskToInput(taskUpdate);
        end;
    end;

    procedure fileManager.removeSetupFromArchive(archivedName: string);
    begin
        if not( removeDir(self.m_stpFolder + archivedName) ) then
            sEventHdlr.pushEventToList( 'Impossibile eliminare la cartella d''installazione ' + archivedName + '.', eiError )
    end;

    function fileManager.getArchivePathFor(cmdGuid: integer): string;
    begin
        result := self.m_stpFolder + cmdRecord( sDBMgr.getCommandRec(cmdGuid) ).hash;
    end;

    function fileManager.isArchived(cmdGuid: integer): boolean;
    begin
        result := directoryExists( self.getArchivePathFor(cmdGuid) );
    end;

    function fileManager.isArchived(fileHash: string): boolean;
    var
        i, j:   byte;
        swList: tList;
    begin
        result := false;
        swList := sdbMgr.getSoftwareList;
        for i := 0 to pred(swList.count) do
            for j := 0 to pred( swRecord(swList.items[i]).commands.count ) do
                if cmdRecord( swRecord(swList.items[i]).commands.items[j] ).hash = fileHash then
                begin
                    result := true;
                    exit;
                end;
    end;

    procedure tTaskFlush.exec;
    begin
        //sFileMgr.saveDataStreamToFile(self.fileName, self.dataStream)
    end;

end.

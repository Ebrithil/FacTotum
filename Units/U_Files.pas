unit U_Files;

interface

uses
    IdHash, System.Classes, System.SysUtils, IdHashSHA, IdHashMessageDigest, ShellAPI, Winapi.Windows,
    vcl.extCtrls, System.StrUtils,

    U_Events, U_DataBase, U_Threads, U_InputTasks, U_OutputTasks;

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
           constructor create(useSha1: boolean = false; stpFolder: string = 'Setup\');
           destructor  Destroy; override;
           procedure   saveDataStreamToFile(fileName: string; dataStream: tMemoryStream);
           procedure   runCommand(cmd: string);
           procedure   addSetupToArchive(handle: tHandle; cmdRec: cmdRecord; fileName: string; folderName: string = ''); overload;
           procedure   removeSetupFromArchive(handle: tHandle; folderName: string);
    end;

    tTaskAddToArchive = class(tTask)
        public
            formHandle: tHandle;
            cmdRec:     cmdRecord;
            fileName:   string;
            folderName: string;
            pReturn:    tLabeledEdit;

            procedure exec; override;
    end;

    tTaskAddedToArchive = class(tTaskOutput)
        public
            selectedFile:   string;
            selectedFolder: string;
            pReturn:        tLabeledEdit;

            procedure exec; override;
    end;

var
    sFileMgr: fileManager;

implementation

    constructor fileManager.create(useSha1: boolean = false; stpFolder: string = 'Setup\');
    begin
        self.m_stpFolder := stpFolder;
        if not( directoryExists(self.m_stpFolder) ) then
        begin
            sEventHdlr.pushEventToList('Cartella d''installazione non trovata.', eiAlert);
            sEventHdlr.pushEventToList('La cartella verra'' ricreata.', eiAlert);
            if not( createDir(self.m_stpFolder) ) then
                sEventHdlr.pushEventToList('Impossibile creare la cartella d''installazione.', eiError)
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
            wnd    := handle;
            wFunc  := FO_COPY;

            if folderName = '' then
                pFrom := pchar(fileName + #0)
            else
                pFrom := pchar(folderName + #0);

            pTo := pchar(self.m_stpFolder + tempHash + #0);
            fFlags := FOF_NOCONFIRMATION or FOF_NOCONFIRMMKDIR or FOF_SIMPLEPROGRESS;
        end;
        errorCode := SHFileOperation(soFileOperation);

        if ( (errorCode <> 0) or soFileOperation.fAnyOperationsAborted ) then
            sEventHdlr.pushEventToList('Errore 0x' + intToHex(errorCode, 8) + ': impossibile copiare [' + soFileOperation.pFrom + ']', eiError)
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

    procedure fileManager.removeSetupFromArchive(handle: tHandle; folderName: string);
    var
        soFileOperation: tSHFileOpStruct;
        errorCode:       integer;
    begin
        // usas FillChar
        fillChar( soFileOperation, sizeOf(soFileOperation), #0 );
        with soFileOperation do
        begin
            wnd    := handle;
            wFunc  := FO_COPY;
            pFrom := pchar(folderName + #0);
            fFlags := FOF_NOCONFIRMATION or FOF_SIMPLEPROGRESS;
        end;
        errorCode := SHFileOperation(soFileOperation);

        if ( (errorCode <> 0) or soFileOperation.fAnyOperationsAborted ) then
            sEventHdlr.pushEventToList('Errore 0x' + intToHex(errorCode, 8) + ': impossibile eliminare [' + soFileOperation.pFrom + ']', eiError);
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

    procedure tTaskAddToArchive.exec;
    var
        taskAdded: tTaskAddedToArchive;
    begin
        sFileMgr.addSetupToArchive(self.formHandle, self.cmdRec, self.fileName, self.folderName);

        taskAdded                := tTaskAddedToArchive.create;
        taskAdded.selectedFile   := self.fileName;
        taskAdded.selectedFolder := self.folderName;
        taskAdded.pReturn        := self.pReturn;
    end;

    procedure tTaskAddedToArchive.exec;
    begin
        if self.selectedFolder <> '' then
            self.pReturn.text := ansiReplaceStr(self.selectedFile, self.selectedFolder + '\', '')
        else
            self.pReturn.text := extractFileName(selectedFile);
    end;

end.

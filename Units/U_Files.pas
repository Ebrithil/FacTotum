unit U_Files;

interface

uses
    IdHash, System.Classes, System.SysUtils, IdHashSHA, IdHashMessageDigest, ShellAPI, Winapi.Windows,
    vcl.extCtrls, Vcl.StdCtrls, System.StrUtils, System.UITypes, Vcl.forms, vcl.comCtrls, IdComponent, IdURI,

    U_Events, U_DataBase, U_Threads, U_InputTasks, U_OutputTasks, U_Download, U_Parser;

type
    fileManager = class
       protected
           m_hasher:    tIdHash;
           m_stpFolder: string;
           function     getFileHash(fileName: string): string; overload;
           function     getFileHash(fileData: tMemoryStream): string; overload;
           function     getArchivePathFor(cmdGuid: integer): string;
           function     isArchived(cmdGuid: integer): boolean; overload;
           function     isArchived(fileHash: string): boolean; overload;
           function     executeFileOperation(handle: tHandle; op: short; pathFrom: string; pathTo: string = ''): boolean;
       public
           constructor create(useSha1: boolean = false; stpFolder: string = 'Setup\');
           destructor  Destroy; override;
           function    addSetupToArchive(handle: tHandle; cmdRec: cmdRecord; fileName: string; folderName: string = ''): boolean;
           function    updateSetupInArchive(handle: tHandle; cmdRec: cmdRecord; data: tMemoryStream; fileName:string): boolean;
           procedure   runCommand(cmd: string);
           procedure   removeSetupFromArchive(handle: tHandle; folderName: string);
    end;

    tTaskDownload = class(tTask)
        protected
            dlmax,
            dlcur,
            dlchunk:    int64;
            fileName:   string;
            procedure   onDownload(aSender: tObject; aWorkMode: tWorkMode; aWorkCount: Int64);
            procedure   onDownloadBegin(aSender: tObject; aWorkMode: tWorkMode; aWorkCountMax: Int64);
            procedure   onRedirect(sender: tObject; var dest: string; var numRedirect: integer; var handled: boolean; var vMethod: string);
        public
            cmdRec:     cmdRecord;
            formHandle: tHandle;
            dataStream: tMemoryStream;
            procedure   exec; override;
    end;

    tTaskDownloadReport = class(tTaskOutput)
        public
            dlPct:    byte;
            procedure exec; override;
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
            createEvent('Cartella d''installazione non trovata.', eiAlert);
            createEvent('La cartella verra'' ricreata.', eiAlert);
            if not( createDir(self.m_stpFolder) ) then
                createEvent('Impossibile creare la cartella d''installazione.', eiError)
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

    function fileManager.getFileHash(fileData: tMemoryStream): string;
    begin
        result := ansiLowerCase( self.m_hasher.hashStreamAsHex(fileData) );
    end;

    procedure fileManager.runCommand(cmd: string);
    begin
        // TODO
    end;

    function fileManager.addSetupToArchive(handle: tHandle; cmdRec: cmdRecord; fileName: string; folderName: string = ''): boolean;
    var
        tmpTo,
        tmpFrom,
        tempHash: string;
    begin
        result := false;

        tempHash := self.getFileHash(fileName);
        tmpTo    := getCurrentDir + self.m_stpFolder + tempHash;
        if folderName = '' then
        begin
            tmpFrom := fileName;
            tmpTo   := tmpTo + '\' + extractFileName(fileName);
        end
        else
            tmpFrom := folderName;

        if sFileMgr.executeFileOperation(handle, FO_COPY, tmpFrom, tmpTo) then
        begin
            cmdRec.hash := tempHash;
            cmdRec := sdbMgr.updatedbRecord(cmdRec) as cmdRecord;
            result := true;
        end;
    end;

    function fileManager.updateSetupInArchive(handle: tHandle; cmdRec: cmdRecord; data: tMemoryStream; fileName:string): boolean;
    var
        testFile,
        newHash:         string;
    begin
        result  := false;
        newHash := self.getFileHash(data);

        if cmdRec.hash <> '' then
        begin
            // Rinomino il vecchio eseguibile del comando
            testFile := m_stpFolder + cmdRec.hash + '\' + cmdRec.Cmmd;
            while not fileExists(testFile) and (testFile <> '') do
                delete(testFile, length(testFile), 1);

            if (testFile = '') or not sFileMgr.executeFileOperation(handle, FO_RENAME, testFile, testFile + '.old') then
                exit;

            // Salvo il file scaricato in temp per lo spostamento
            data.saveToFile(getEnvironmentVariable('TEMP') + '\' + fileName);

            if not sFileMgr.executeFileOperation(handle, FO_MOVE, getEnvironmentVariable('TEMP') + '\' + fileName, m_stpFolder + cmdRec.hash + '\' + fileName) then
                exit;

            // Rinomino la vecchia cartella con il nuovo hash
            if not sFileMgr.executeFileOperation(handle, FO_RENAME, m_stpFolder + cmdRec.hash, m_stpFolder + newHash) then
                exit;

            // Aggiorno il database con le nuove informazioni
            testFile    := copy(testFile, lastDelimiter('\', testFile) + 1, testFile.length);
            cmdRec.cmmd := ansiReplaceStr(cmdRec.cmmd, testFile, fileName);
        end
        else
        begin
            // Salvo il file scaricato in temp per lo spostamento
            data.saveToFile(getEnvironmentVariable('TEMP') + '\' + fileName);

            if not sFileMgr.executeFileOperation(handle, FO_MOVE, getEnvironmentVariable('TEMP') + '\' + fileName, m_stpFolder + newHash + '\' + fileName) then
                exit;

            // Aggiorno il database con le nuove informazioni
            cmdRec.name := fileName;
        end;
        cmdRec.hash := newHash;
        cmdRec := sdbMgr.updatedbRecord(cmdRec) as cmdRecord;

        result := true;
    end;

    procedure fileManager.removeSetupFromArchive(handle: tHandle; folderName: string);
    begin
        // usas FillChar
        sFileMgr.executeFileOperation(handle, FO_DELETE, folderName);
    end;

    function fileManager.getArchivePathFor(cmdGuid: integer): string;
    begin
        result := self.m_stpFolder + cmdRecord( sdbMgr.getCommandRec(cmdGuid) ).hash;
    end;

    function fileManager.isArchived(cmdGuid: integer): boolean;
    begin
        result := directoryExists( self.getArchivePathFor(cmdGuid) );
    end;

    function fileManager.isArchived(fileHash: string): boolean;
    begin
        result := directoryExists(fileHash);
    end;

    function fileManager.executeFileOperation(handle: tHandle; op: short; pathFrom: string; pathTo: string = ''): boolean;
    var
        soFileOperation: tSHFileOpStruct;
        errorCode:       integer;
    begin
        fillChar( soFileOperation, sizeOf(soFileOperation), #0 );

        with soFileOperation do
        begin
            wnd    := handle;
            wFunc  := op;
            pFrom  := pchar(pathFrom + #0);
            pTo    := pchar(pathTo + #0);
            fFlags := FOF_NOCONFIRMATION or FOF_NOCONFIRMMKDIR or FOF_SIMPLEPROGRESS or FOF_NOERRORUI;
        end;

        errorCode := shFileOperation(soFileOperation);

        if ( (errorCode <> 0) or soFileOperation.fAnyOperationsAborted ) then
        begin
            createEvent('Errore 0x' + intToHex(errorCode, 8) + ': impossibile eseguire l''operazione ' + intToStr(op) + ' [' + soFileOperation.pFrom + '] in [' + soFileOperation.pTo + ']', eiError);
            result := false;
        end
        else
            result := true;
    end;

    procedure tTaskAddToArchive.exec;
    var
        taskAdded: tTaskAddedToArchive;
    begin
        if (not sFileMgr.addSetupToArchive(self.formHandle, self.cmdRec, self.fileName, self.folderName)) then
            exit;

        taskAdded                 := tTaskAddedToArchive.create;
        taskAdded.selectedFile    := self.fileName;
        taskAdded.selectedFolder  := self.folderName;
        setLength(taskAdded.dummyTargets, 1);
        taskAdded.dummyTargets[0] := self.pReturn;

        sTaskMgr.pushTaskToOutput(taskAdded);
    end;

    procedure tTaskAddedToArchive.exec;
    var
        targetLe: tLabeledEdit;
    begin
        if not (self.dummyTargets[0] is tLabeledEdit) then
            exit;

        targetLe := self.dummyTargets[0] as tLabeledEdit;

        if self.selectedFolder <> '' then
            targetLe.text := ansiReplaceStr(self.selectedFile, self.selectedFolder + '\', '')
        else
            targetLe.text := extractFileName(selectedFile);
    end;

    procedure tTaskDownload.onDownload(aSender: tObject; aWorkMode: tWorkMode; aWorkCount: Int64);
    var
        reportTask: tTaskDownloadReport;
    begin
        if aWorkCount >= ( self.dlchunk * succ(self.dlcur) ) then
        begin
            self.dlcur                 := aWorkCount div self.dlchunk;

            reportTask                 := tTaskDownloadReport.create;
            reportTask.dlPct           := self.dlcur;

            setLength(reportTask.dummyTargets, 2);
            reportTask.dummyTargets[0] := self.dummyTargets[0];
            reportTask.dummyTargets[1] := self.dummyTargets[1];

            sTaskMgr.pushTaskToOutput(reportTask);
        end
        else if aWorkCount = self.dlmax then
        begin
            self.dlcur       := 100;

            reportTask       := tTaskDownloadReport.create;
            reportTask.dlPct := self.dlcur;

            setLength(reportTask.dummyTargets, 2);
            reportTask.dummyTargets[0] := self.dummyTargets[0];
            reportTask.dummyTargets[1] := self.dummyTargets[1];

            sTaskMgr.pushTaskToOutput(reportTask);
        end;
    end;

    procedure tTaskDownload.onDownloadBegin(aSender: tObject; aWorkMode: tWorkMode; aWorkCountMax: Int64);
    begin
        self.dlcur   := 0;
        self.dlmax   := aWorkCountMax;
        self.dlchunk := self.dlmax div 100;
    end;

    procedure tTaskDownload.exec;
    begin
        if not (self.dummyTargets[0] is tProgressBar) or
           not (self.dummyTargets[1] is tListItem) then
            exit;

        self.dataStream := sDownloadMgr.downloadLastStableVersion( sUpdateParser.getLastStableLink(self.cmdRec.uURL), self.onDownload, self.onDownloadBegin, self.onRedirect );
        self.dataStream.seek(0, soBeginning);
        sFileMgr.updateSetupInArchive(self.formHandle, self.cmdRec, self.dataStream, self.fileName);
    end;

    procedure tTaskDownload.onRedirect(sender: tObject; var dest: string; var numRedirect: integer; var handled: boolean; var vMethod: string);
    begin
        self.fileName := copy(dest, lastDelimiter('/', dest) + 1, dest.length);
        dest := tIdURI.urlEncode(dest);
    end;

    procedure tTaskDownloadReport.exec;
    var
        targetLI: tListItem;
        targetPB: tProgressBar;
    begin
        if not (self.dummyTargets[0] is tProgressBar) or
           not (self.dummyTargets[1] is tListItem) then
             exit;

        targetLI                                        := self.dummyTargets[1] as tListItem;
        targetPB                                        := self.dummyTargets[0] as tProgressBar;
        targetLI.subItems[pred( integer(lvColStatus) )] := intToStr(self.dlPct) + '%';
        targetPb.position                               := self.dlPct;

        if self.dlPct = 100 then
            targetLI.stateIndex := tImageIndex(eiDotGreen);
            // Bisogna far chiamare un task specifico per il refresh di questa singola riga...
    end;

end.

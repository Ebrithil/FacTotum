unit U_Files;

interface

uses
    IdHash, System.Classes, System.SysUtils, IdHashSHA, IdHashMessageDigest, ShellAPI, Winapi.Windows,
    vcl.extCtrls, Vcl.StdCtrls, System.StrUtils, System.UITypes, Vcl.forms, vcl.comCtrls, IdComponent, IdURI,

    U_Events, U_DataBase, U_Threads, U_InputTasks, U_OutputTasks, U_Download, U_Parser, U_Functions;

type
    tFileManager = class
       protected
            m_hasher:    tIdHash;
            m_stpFolder: string;
            function     isArchived(cmdGuid: integer): boolean; overload;
            function     isArchived(fileHash: string): boolean; overload;
            function     getFileHash(fileName: string): string; overload;
            function     getFileHash(fileData: tMemoryStream): string; overload;
            function     getArchivePathFor(cmdGuid: integer):  string;
            function     getCmdRecordsByHash(const hash: string): tList;
       public
            constructor  create(useMD5: boolean = false; stpFolder: string = 'Setup');
            destructor   Destroy; override;
            function     isAvailable(const fileName, fileHash: string): boolean;
            function     fileExistsInPath(fileName: string): boolean;
            procedure    runCommand(handle: tHandle; cmd: tCmdRecord);
            function     insertArchiveSetup(handle: tHandle; cmdRec: tCmdRecord; fileName: string; folderName: string = ''): boolean;
            function     updateArchiveSetup(handle: tHandle; cmdRec: tCmdRecord; fileName: string; data: tMemoryStream): boolean;
            function     removeArchiveSetup(handle: tHandle; hash: string): boolean;
            function     executeFileOperation(handle: tHandle; fileOP: short; pathFrom: string; pathTo: string = ''): boolean;
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
            pRecord:    tCmdRecord;
            formHandle: tHandle;
            dataStream: tMemoryStream;
            procedure   exec; override;
    end;

    tTaskDownloadReport = class(tTaskOutput)
        public
            pRecord:  tCmdRecord;
            dlPct:    byte;
            procedure exec; override;
    end;

    tTaskAddToArchive = class(tTask)
        public
            formHandle: tHandle;
            cmdRec:     tCmdRecord;
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

    tTaskRunCommands = class(tTask)
        public
            lSoftware: tList;
            handle:    tHandle;
            procedure  exec; override;
    end;

var
    sFileMgr: tFileManager;

implementation

    constructor tFileManager.create(useMD5: boolean = false; stpFolder: string = 'Setup');
    begin
        self.m_stpFolder := includeTrailingPathDelimiter(stpFolder);
        if not( directoryExists(self.m_stpFolder) ) then
        begin
            createEvent('Cartella d''installazione non trovata.', eiAlert);
            createEvent('La cartella verra'' ricreata.', eiAlert);
            if not( createDir(self.m_stpFolder) ) then
                createEvent('Impossibile creare la cartella d''installazione.', eiError)
        end;

        if useMD5 then
            m_hasher := tIdHashMessageDigest5.create
        else
            m_hasher := tIdHashSHA1.create;
    end;

    destructor tFileManager.Destroy;
    begin
        m_hasher.free;
    end;

    function tFileManager.fileExistsInPath(fileName: string): boolean;
    var
        filePartPtr:   pWideChar;
        filePart,
        fullFilePath:  array[0..255] of char;
    begin
        filePartPtr := @filePart;
        result := ( searchPath(nil, pWideChar(fileName), nil, 255, fullFilePath, filePartPtr) > 0 );
    end;

    function tFileManager.getFileHash(fileName: string): string;
    var
        msFile: tMemoryStream;
    begin
        msFile := tMemoryStream.create;
        msFile.loadFromFile(fileName);

        result := ansiLowerCase( self.m_hasher.hashStreamAsHex(msFile) );

        msFile.free;
    end;

    function tFileManager.getFileHash(fileData: tMemoryStream): string;
    begin
        result := ansiLowerCase( self.m_hasher.hashStreamAsHex(fileData) );
    end;

    procedure tFileManager.runCommand(handle: tHandle; cmd: tCmdRecord);
    var
        exInfo:     tShellExecuteInfo;
        ph:         DWORD;
    begin
        fillChar(exInfo, sizeOf(exInfo), 0);
        with exInfo do
        begin
            cbSize              := sizeOf(exInfo);
            fMask               := SEE_MASK_NOCLOSEPROCESS or SEE_MASK_FLAG_DDEWAIT or SEE_MASK_NOASYNC;
            wnd                 := getActiveWindow();
            exInfo.lpVerb       := 'open';
            exInfo.lpParameters := pchar(cmd.swch);
            lpFile              := pchar(cmd.cmmd);
            nShow               := SW_SHOWNORMAL;
        end;
        if not shellExecuteEx(@exInfo) then
        begin
            createEvent( sysErrorMessage(getLastError), eiError );
            exit;
        end;
        ph := exInfo.hProcess;
        waitForSingleObject(exInfo.hProcess, infinite);
        closeHandle(ph);
    end;

    function tFileManager.insertArchiveSetup(handle: tHandle; cmdRec: tCmdRecord; fileName: string; folderName: string = ''): boolean;
    var
        tmpTo,
        tmpFrom,
        tempHash: string;
        opResult: boolean;
    begin
        result := false;

        opResult := false;
        tempHash := self.getFileHash(fileName);
        if not isArchived(tempHash) then
        begin
            tmpTo    := getCurrentDir + self.m_stpFolder + tempHash;
            if folderName = '' then
            begin
                tmpFrom := fileName;
                tmpTo   := tmpTo + '\' + extractFileName(fileName);
            end
            else
                tmpFrom := folderName;

            opResult := sFileMgr.executeFileOperation(handle, FO_COPY, tmpFrom, tmpTo);
        end;

        if opResult or isArchived(tempHash) then
        begin
            cmdRec.hash := tempHash;
            if folderName <> '' then
                cmdRec.cmmd := ansiReplaceStr(fileName, folderName + '\', '')
            else
                cmdRec.cmmd := extractFileName(fileName);
            sdbMgr.updatedbRecord( tDBRecord(cmdRec) );
            result := true;
        end;
    end;

    function tFileManager.updateArchiveSetup(handle: tHandle; cmdRec: tCmdRecord; fileName: string; data: tMemoryStream): boolean;
    var
        i:          integer;
        tmpRec:     tDBRecord;
        newHash,
        testFile:   string;
        cmdRecList: tList;
    begin
        result   := true;
        newHash  := self.getFileHash(data);
        testFile := '';

        // Nome di default
        if fileName = '' then
            fileName := 'Setup.exe';

        // Salvo il file scaricato in temp per lo spostamento
        data.saveToFile(getEnvironmentVariable('TEMP') + '\' + fileName);
        data.free;

        if cmdRec.hash <> '' then
        begin
            // Rinomino il vecchio eseguibile del comando
            testFile := m_stpFolder + cmdRec.hash + '\' + cmdRec.Cmmd;
            while not fileExists(testFile) and (testFile <> '') do
                delete(testFile, length(testFile), 1);

            if (testFile = '') or not sFileMgr.executeFileOperation(handle, FO_RENAME, testFile, testFile + '.old') then
                exit;

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
            if not sFileMgr.executeFileOperation(handle, FO_MOVE, getEnvironmentVariable('TEMP') + '\' + fileName, m_stpFolder + newHash + '\' + fileName) then
                exit;

            // Aggiorno il database con le nuove informazioni
            cmdRec.cmmd := fileName;
        end;
        cmdRec.hash := newHash;
        sdbMgr.updatedbRecord( tDBRecord(cmdRec) );

        // Aggiorno allo stesso modo tutti gli altri comandi con lo stesso hash (preservando gli switch se possibile)
        cmdRecList := sFileMgr.getCmdRecordsByHash(newHash);
        for i := 0 to pred( cmdRecList.count ) do
        begin
            tCmdRecord(cmdRecList[i]).hash := cmdRec.hash;
            tCmdRecord(cmdRecList[i]).vers := cmdRec.vers;
            if testFile <> '' then
                tCmdRecord(cmdRecList[i]).cmmd := ansiReplaceStr( tCmdRecord(cmdRecList[i]).cmmd, testFile, fileName)
            else
                tCmdRecord(cmdRecList[i]).cmmd := fileName;

            tmpRec := tDBRecord(cmdRecList[i]);
            sdbMgr.updatedbRecord( tmpRec );
        end;

        cmdRecList.free;
        result := true;
    end;

    function tFileManager.removeArchiveSetup(handle: tHandle; hash: string): boolean;
    begin
        result := sFileMgr.executeFileOperation(handle, FO_DELETE, hash);
    end;

    function tFileManager.getArchivePathFor(cmdGuid: integer): string;
    begin
        result := self.m_stpFolder + tCmdRecord( sdbMgr.getCmdRecordByGUID(cmdGuid) ).hash;
    end;

    function tFileManager.isArchived(cmdGuid: integer): boolean;
    begin
        result := directoryExists( self.getArchivePathFor(cmdGuid) );
    end;

    function tFileManager.isArchived(fileHash: string): boolean;
    begin
        result := directoryExists(fileHash);
    end;

    function tFileManager.isAvailable(const fileName, fileHash: string): boolean;
    begin
        result := fileExists(self.m_stpFolder + fileHash + '\' + fileName) or
                  fileExistsInPath(fileName);
    end;

    function tFileManager.getCmdRecordsByHash(const hash: string): tList;
    var
        i,
        j:       integer;
        swList:  tList;
    begin
       result := tList.create;
       swList := sdbMgr.getSoftwareList;

       for i := 0 to pred(swList.count) do
          for j := 0 to pred( tSwRecord(swList[i]).commands.count ) do
              if tCmdRecord( tSwRecord(swList[i]).commands[j] ).hash = hash then
                  result.add( tCmdRecord( tSwRecord(swList[i]).commands[j] ) );
    end;

    function tFileManager.executeFileOperation(handle: tHandle; fileOP: short; pathFrom: string; pathTo: string = ''): boolean;
    var
        soFileOperation: tSHFileOpStruct;
        errorCode:       integer;
    begin
        fillChar( soFileOperation, sizeOf(soFileOperation), #0 );

        with soFileOperation do
        begin
            wnd    := handle;
            wFunc  := fileOP;
            pFrom  := pchar(pathFrom + #0);
            pTo    := pchar(pathTo + #0);
            fFlags := FOF_NOCONFIRMATION or FOF_NOCONFIRMMKDIR or FOF_SIMPLEPROGRESS or FOF_NOERRORUI;
        end;

        errorCode := shFileOperation(soFileOperation);

        if ( (errorCode <> 0) or soFileOperation.fAnyOperationsAborted ) then
        begin
            createEvent('Errore 0x' + intToHex(errorCode, 8) + ': impossibile eseguire l''operazione ' + intToStr(fileOP) + ' [' + soFileOperation.pFrom + '] in [' + soFileOperation.pTo + ']', eiError);
            result := false;
        end
        else
            result := true;
    end;

    procedure tTaskAddToArchive.exec;
    var
        taskAdded: tTaskAddedToArchive;
    begin
        if (not sFileMgr.insertArchiveSetup(self.formHandle, self.cmdRec, self.fileName, self.folderName)) then
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
        if ( aWorkCount >= (self.dlchunk * succ(self.dlcur)) ) and
           (self.dlchunk > 0) then
        begin
            self.dlcur                 := aWorkCount div self.dlchunk;

            reportTask                 := tTaskDownloadReport.create;
            reportTask.dlPct           := self.dlcur;

            setLength(reportTask.dummyTargets, 2);
            reportTask.dummyTargets[0] := self.dummyTargets[0];
            reportTask.dummyTargets[1] := self.dummyTargets[1];

            reportTask.pRecord := self.pRecord;

            sTaskMgr.pushTaskToOutput(reportTask);
        end
    end;

    procedure tTaskRunCommands.exec;
    var
        i,
        j:         integer;
        pSoftware: tSwRecord;
    begin
        for i := 0 to pred(self.lSoftware.count) do
        begin
            pSoftware := tSwRecord(self.lSoftware[i]);
            createEvent('Installazione di ' + pSoftware.name + ' iniziata', eiInfo);
            for j := 0 to pred(pSoftware.commands.count) do
            begin
                createEvent( 'Esecuzione comando ' + tCmdRecord(pSoftware.commands[j]).name, eiInfo );
                sFileMgr.runCommand(self.handle, pSoftware.commands[j]);
            end;
            createEvent('Installazione di ' + pSoftware.name + ' completata', eiInfo);
        end;
        self.lSoftware.free;
    end;

    procedure tTaskDownload.onDownloadBegin(aSender: tObject; aWorkMode: tWorkMode; aWorkCountMax: Int64);
    begin
        self.dlcur   := 0;
        self.dlmax   := aWorkCountMax;
        self.dlchunk := self.dlmax div 100;
    end;

    procedure tTaskDownload.exec;
    var
        reportTask: tTaskDownloadReport;
    begin
        if not (self.dummyTargets[0] is tProgressBar) or
           not (self.dummyTargets[1] is tListItem) then
            exit;

        self.dataStream := sDownloadMgr.downloadLastStableVersion( self.pRecord.cURL, self.onDownload, self.onDownloadBegin, self.onRedirect );

        if self.dataStream.size = 0 then
        begin
            createEvent('Impossibile aggiornare ' + self.pRecord.name + '. Ricevuto file vuoto.', eiError);
            exit;
        end;

        self.dataStream.seek(0, soBeginning);
        if (sFileMgr.updateArchiveSetup(self.formHandle, self.pRecord, self.fileName, self.dataStream)) then
        begin
            reportTask       := tTaskDownloadReport.create;
            reportTask.dlPct := 255;

            reportTask.pRecord := self.pRecord;

            setLength(reportTask.dummyTargets, 2);
            reportTask.dummyTargets[0] := self.dummyTargets[0];
            reportTask.dummyTargets[1] := self.dummyTargets[1];

            sTaskMgr.pushTaskToOutput(reportTask);
        end;
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
        refresh:  tTaskGetVer;
    begin
        if not (self.dummyTargets[0] is tProgressBar) or
           not (self.dummyTargets[1] is tListItem) then
             exit;

        targetLI                                        := self.dummyTargets[1] as tListItem;
        targetPB                                        := self.dummyTargets[0] as tProgressBar;

        if self.dlPct = 255 then
        begin
            targetPB.position                               := 0;
            targetLI.subitems[pred( integer(lvColStatus) )] := '';
            targetLI.subItems[pred( integer(lvColVA) )]     := self.pRecord.vers;

            refresh := tTaskGetVer.create;
            refresh.cmdRec := self.pRecord;

            setLength(refresh.dummyTargets, 1);
            refresh.dummyTargets[0] := targetLI;

            sTaskMgr.pushTaskToInput(refresh);
        end
        else
        begin
            targetLI.subItems[pred( integer(lvColStatus) )] := intToStr(self.dlPct) + '%';
            targetPB.position                               := self.dlPct;
        end;
    end;

end.

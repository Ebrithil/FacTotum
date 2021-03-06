unit U_Files;

interface

uses
    IdHash, System.Classes, System.SysUtils, IdHashSHA, IdHashMessageDigest, ShellAPI, Winapi.Windows,
    vcl.extCtrls, Vcl.StdCtrls, System.StrUtils, System.UITypes, Vcl.forms, vcl.comCtrls, IdComponent, IdURI,
    vcl.checklst, Dialogs, Messages,

    U_Events, U_DataBase, U_Threads, U_InputTasks, U_OutputTasks, U_Download, U_Parser, U_Functions;

type
    tFileManager = class
       protected
            m_hasher:    tIdHash;
            m_stpFolder: string;
            function     getArchiveDirList: tStringList;
            function     isArchived(hash: string): boolean;
            function     getElemCount(const path: string): word;
            function     getFileHash(fileName: string): string; overload;
            function     getFileHash(fileData: tMemoryStream): string; overload;
            function     getCmdRecordsByHash(const hash: string): tList;
       public
            constructor  create(useMD5: boolean = false; stpFolder: string = 'setup');
            destructor   Destroy; override;
            procedure    cleanupArchive(handle: tHandle);
            procedure    runCommand(handle: tHandle; cmd: tCmdRecord);
            function     isAvailable(const fileName, fileHash: string): boolean;
            function     fileExistsInPath(fileName: string): boolean;
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

    tTaskInsertArchiveSetup = class(tTask)
        public
            formHandle: tHandle;
            cmdRec:     tCmdRecord;
            fileName,
            folderName: string;
            pReturn:    tLabeledEdit;

            procedure exec; override;
    end;

    tTaskInsertArchiveSetupReport = class(tTaskOutput)
        public
            selectedFile,
            selectedFolder: string;

            procedure exec; override;
    end;

    tTaskRunCommands = class(tTask)
        public
            lSoftware: tList;
            handle:    tHandle;
            procedure  exec; override;
    end;

    tTaskProgressRun = class(tTaskOutput)
        public
            pct:      integer;
            procedure exec; override;
    end;

    tTaskRanCommands = class(tTaskOutput)
        public
            procedure exec; override;
    end;

    tTaskCheckStuck = class(tTaskOutput)
        public
            class var window: tForm;
            process:  integer;
            procedure exec; override;
    end;

const
    seconds = 1000;
    minutes = 60 * seconds;
    defaultWaitCommandWarningTime = 30 * minutes;

var
    sFileMgr: tFileManager;

implementation

    constructor tFileManager.create(useMD5: boolean = false; stpFolder: string = 'setup');
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

    function tFileManager.getArchiveDirList: tStringList;
    var
        sr : tSearchRec;
    begin
        result := tStringList.create;
        if findFirst(self.m_stpFolder + '*.*', faDirectory, sr) = 0 then
        begin
            repeat
                if ( (sr.attr and faDirectory <> 0) and
                     (sr.name <> '.')               and
                     (sr.Name <> '..') )
                then
                    result.add(sr.name);
            until findNext(sr) <> 0;
            system.sysUtils.findClose(sr);
        end;
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
        tmpCmd:     string;
        ph,
        waitSt:     DWORD;
        taskSt:     tTaskCheckStuck;
    begin
        tmpCmd := self.m_stpFolder + cmd.hash + '\' + cmd.cmmd;
        if not fileExists(tmpCmd) then
            tmpCmd := cmd.cmmd;  // Se non � in archivio, dev'essere nella path

        fillChar(exInfo, sizeOf(exInfo), 0);
        with exInfo do
        begin
            cbSize              := sizeOf(exInfo);
            fMask               := SEE_MASK_NOCLOSEPROCESS or SEE_MASK_FLAG_DDEWAIT or SEE_MASK_NOASYNC;
            wnd                 := getActiveWindow();
            exInfo.lpVerb       := 'open';
            exInfo.lpParameters := pChar(cmd.swch);
            lpFile              := pChar(tmpCmd);
            nShow               := SW_SHOWNORMAL;
        end;
        if not shellExecuteEx(@exInfo) then
        begin
            createEvent( sysErrorMessage(getLastError), eiError );
            exit;
        end;
        ph := exInfo.hProcess;

        waitSt := WAIT_TIMEOUT;
        
        while (waitSt = WAIT_TIMEOUT) do
        begin
            waitSt := waitForSingleObject(exInfo.hProcess, defaultWaitCommandWarningTime);

            if waitSt = WAIT_OBJECT_0 then
                break;

            taskSt         := tTaskCheckStuck.create;
            taskSt.process := ph;
            sTaskMgr.pushTaskToOutput(taskSt);            
        end;

        taskSt         := tTaskCheckStuck.create;
        taskSt.process := 0;
        sTaskMgr.pushTaskToOutput(taskSt);                    
        
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
            tmpTo    := includeTrailingPathDelimiter(getCurrentDir) + self.m_stpFolder + tempHash;
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

            result := sdbMgr.updatedbRecord( tDBRecord(cmdRec) );
        end;
    end;

    function tFileManager.updateArchiveSetup(handle: tHandle; cmdRec: tCmdRecord; fileName: string; data: tMemoryStream): boolean;
    var
        i:          integer;
        tmpRec:     tDBRecord;
        newHash,
        tmpFile:    string;
        cmdRecList: tList;
    begin
        result   := false;
        newHash  := self.getFileHash(data);

        // Nome di default
        if fileName = '' then
            fileName := 'setup.exe';

        // Salvo il file scaricato in temp per lo spostamento
        tmpFile := includeTrailingPathDelimiter( getEnvironmentVariable('TEMP') ) + fileName;
        data.saveToFile(tmpFile);
        data.free;

        // Se e' impossibile trovare il vecchio file, o se � nella path,
        // allora procedo con un nuovo inserimento
        if ( (cmdRec.hash <> '') and not self.isArchived(cmdRec.hash) ) or
              self.fileExistsInPath(cmdRec.cmmd) or (cmdRec.hash = '')
        then
        begin
            result:= self.insertArchiveSetup(handle, cmdRec, tmpFile);
            exit;
        end
        // Altrimenti procedo con l'aggiornamento
        else
        begin
            // Svuoto la cartella dai vecchi backup
            if not self.executeFileOperation(
                handle, FO_DELETE,
                m_stpFolder + cmdRec.hash + '\*.old'
            )
            then
                exit;
            if directoryExists(m_stpFolder + cmdRec.hash + '\old') then
                if not self.executeFileOperation(
                    handle, FO_DELETE,
                    m_stpFolder + cmdRec.hash + '\old'
                )
                then
                    exit;

            // Archivio i vecchi files per avere un backup
            if self.getElemCount(m_stpFolder + cmdRec.hash) <= 1 then
                // Se e' un singolo file lo rinomino
                if not self.executeFileOperation(
                    handle, FO_RENAME,
                    m_stpFolder + cmdRec.hash + '\' + cmdRec.cmmd,
                    m_stpFolder + cmdRec.hash + '\' + cmdRec.cmmd + '.old'
                )
                then
                    exit
                else
            else
                // Altrimenti sposto il contenuto nella cartella \old
                if not self.executeFileOperation(
                    handle, FO_MOVE,
                    m_stpFolder + cmdRec.hash + '\*',
                    m_stpFolder + cmdRec.hash + '\old'
                )
                then
                    exit;

            // Sposto il nuovo eseguibile nella vecchia cartella
            if not self.executeFileOperation(
                handle, FO_MOVE,
                getEnvironmentVariable('TEMP') + '\' + fileName,
                m_stpFolder + cmdRec.hash + '\' + fileName
            )
            then
                exit;

            // Rinomino la vecchia cartella con il nuovo hash
            if not self.executeFileOperation(
                handle, FO_RENAME,
                m_stpFolder + cmdRec.hash,
                m_stpFolder + newHash
            )
            then
                exit;
        end;

        // Aggiorno in database tutti i comandi con lo stesso hash
        cmdRecList := self.getCmdRecordsByHash(cmdRec.hash);
        for i := 0 to pred( cmdRecList.count ) do
        begin
            tCmdRecord(cmdRecList[i]).hash := newHash;
            tCmdRecord(cmdRecList[i]).vers := cmdRec.vers;
            tCmdRecord(cmdRecList[i]).cmmd := fileName;

            tmpRec := tDBRecord(cmdRecList[i]);
            if not sdbMgr.updatedbRecord( tmpRec ) then
            begin
                cmdRecList.free;
                exit;
            end;
        end;
        cmdRecList.free;

        result := true;
    end;

    function tFileManager.removeArchiveSetup(handle: tHandle; hash: string): boolean;
    begin
        result := false;
        if hash <> '' then
        begin
            result := self.executeFileOperation(handle, FO_DELETE,
                                                self.m_stpFolder + hash);
            if not result then
                createEvent('Archivio: impossibile eliminare la cartella'
                          + '[' + hash + '].', eiError);
        end;
    end;

    function tFileManager.isArchived(hash: string): boolean;
    begin
        result := directoryExists(self.m_stpFolder + hash);
    end;

    function tFileManager.getElemCount(const path: string): word;
    var
      sr: tSearchRec;
    begin
        result := 0;

        if findFirst(
            includeTrailingPathDelimiter(path) + '*.*',
            faAnyFile,
            sr
        ) = 0
        then
        begin
            repeat
                if (sr.name <> '.') and (sr.Name <> '..') then
                    inc(result);
            until findNext(sr) <> 0;
            system.sysUtils.findClose(sr);
        end;
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
        errorStr:        string;
    begin
        fillChar( soFileOperation, sizeOf(soFileOperation), #0 );

        with soFileOperation do
        begin
            wnd    := handle;
            wFunc  := fileOP;
            pFrom  := pchar(pathFrom + #0);
            pTo    := pchar(pathTo + #0);
            fFlags := FOF_NOCONFIRMATION or FOF_NOCONFIRMMKDIR or
                      FOF_SIMPLEPROGRESS or FOF_NOERRORUI;
        end;

        errorCode := shFileOperation(soFileOperation);
        if errorCode = 118 then
            errorCode := 0;  // Bruttissimo hack da capire e sistemare ASAP
        errorStr  := intToHex(errorCode, 8);
        if errorCode <> 0 then
            while errorStr[1] = '0' do
                delete(errorStr, 1, 1);

        if ( (errorCode <> 0) or soFileOperation.fAnyOperationsAborted ) then
        begin
            createEvent('Errore 0x' + errorStr + ': impossibile eseguire l''operazione ' + intToStr(fileOP) + ' [' + soFileOperation.pFrom + '] in [' + soFileOperation.pTo + ']', eiError);
            result := false;
        end
        else
            result := true;
    end;

    procedure tFileManager.cleanupArchive(handle: tHandle);
    var
        i,
        counter:  integer;
        dirList,
        hashList: tStringList;
    begin
        createEvent('Archivio: manutenzione iniziata.',
                    eiInfo);

        counter  := 0;
        dirList  := self.getArchiveDirList;
        hashList := sdbMgr.getStoredHashList;
        for i := 0 to pred(dirList.count) do
            if hashList.indexOf(dirList[i]) = -1 then
                if self.removeArchiveSetup(handle, dirList[i]) then
                    inc(counter);

        dirList.free;
        hashList.free;
        createEvent('Archivio: manutenzione completata, rimossi '
                   + intToStr(counter) + ' archivi inutilizzati.', eiInfo);
    end;

    procedure tTaskInsertArchiveSetup.exec;
    var
        taskAdded: tTaskInsertArchiveSetupReport;
    begin
        if not sFileMgr.insertArchiveSetup(self.formHandle, self.cmdRec,
                                           self.fileName,   self.folderName)
        then
            exit;

        taskAdded                 := tTaskInsertArchiveSetupReport.create;
        taskAdded.selectedFile    := self.fileName;
        taskAdded.selectedFolder  := self.folderName;
        setLength(taskAdded.dummyTargets, 1);
        taskAdded.dummyTargets[0] := self.pReturn;

        sTaskMgr.pushTaskToOutput(taskAdded);
    end;

    procedure tTaskInsertArchiveSetupReport.exec;
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
        j:          integer;
        pSoftware:  tSwRecord;
        taskPrg:    tTaskProgressRun;
        taskRan:    tTaskRanCommands;
    begin
        for i := 0 to pred(self.lSoftware.count) do
        begin
            pSoftware := tSwRecord(self.lSoftware[i]);
            createEvent('Installazione di ' + pSoftware.name + ' iniziata', eiInfo);
            for j := 0 to pred(pSoftware.commands.count) do
            begin
                createEvent( 'Esecuzione comando ' + tCmdRecord(pSoftware.commands[j]).name, eiInfo );
                sFileMgr.runCommand(self.handle, pSoftware.commands[j]);

                taskPrg     := tTaskProgressRun.create;
                taskPrg.pct := trunc( (succ(j) / pSoftware.commands.count) * 100 );
                setLength(taskPrg.dummyTargets, 2);
                taskPrg.dummyTargets[0] := self.dummyTargets[3];
                taskPrg.dummyTargets[1] := self.dummyTargets[5];
                sTaskMgr.pushTaskToOutput(taskPrg);
            end;
            createEvent('Installazione di ' + pSoftware.name + ' completata', eiInfo);

            taskPrg     := tTaskProgressRun.create;
            taskPrg.pct := trunc( (succ(i) / self.lSoftware.count) * 100 );
            setLength(taskPrg.dummyTargets, 2);
            taskPrg.dummyTargets[0] := self.dummyTargets[2];
            taskPrg.dummyTargets[1] := self.dummyTargets[4];
            sTaskMgr.pushTaskToOutput(taskPrg);
        end;
        sleep(500);
        taskRan := tTaskRanCommands.create;
        setLength( taskRan.dummyTargets, length(self.dummyTargets) );
        for i := 0 to pred( length(self.dummyTargets) ) do
            taskRan.dummyTargets[i] := self.dummyTargets[i];
        sTaskMgr.pushTaskToOutput(taskRan);
        self.lSoftware.clear;
    end;

    procedure tTaskProgressRun.exec;
    begin
        if not (self.dummyTargets[0] is tProgressBar) or
           not (self.dummyTargets[1] is tLabel)       then
            exit;

        (self.dummyTargets[0] as tProgressBar).position := self.pct;
        (self.dummyTargets[1] as tLabel).caption        := intToStr(self.pct) + '%';
    end;

    procedure tTaskRanCommands.exec;
    begin
        if not (self.dummyTargets[0] is tButton)       or
           not (self.dummyTargets[1] is tCheckListBox) or
           not (self.dummyTargets[2] is tProgressBar)  or
           not (self.dummyTargets[3] is tProgressBar)  or
           not (self.dummyTargets[4] is tLabel)        or
           not (self.dummyTargets[5] is tLabel)        then
            exit;

        (self.dummyTargets[0] as tButton).enabled       := true;
        (self.dummyTargets[1] as tCheckListBox).enabled := true;
        (self.dummyTargets[2] as tProgressBar).position := 0;
        (self.dummyTargets[3] as tProgressBar).position := 0;
        (self.dummyTargets[4] as tLabel).caption        := '0%';
        (self.dummyTargets[5] as tLabel).caption        := '0%';
    end;

    procedure tTaskCheckStuck.exec;
    begin
        if (self.process = 0) then
        begin
            if assigned(self.window) then
                self.window.close;

            exit;
        end;
                
        self.window := createMessageDialog('L''esecuzione del comando st� impiegando molto tempo. Interromperla?', mtWarning, mbYesNo);         
        if self.window.showModal = mrYes then
           closeHandle(self.process);
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

        self.dataStream := sDownloadMgr.downloadLastStableVersion(self.pRecord.cURL, self.onDownload, self.onDownloadBegin, self.onRedirect);

        if self.dataStream.size = 0 then
        begin
            createEvent('Impossibile aggiornare ' + self.pRecord.name + '. Ricevuto file vuoto.', eiError);
            exit;
        end;

        self.dataStream.seek(0, soBeginning);
        if ( sFileMgr.updateArchiveSetup(self.formHandle, self.pRecord, self.fileName, self.dataStream) ) then
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

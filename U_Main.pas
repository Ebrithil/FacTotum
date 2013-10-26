unit U_Main;

{$HINTS ON}
{$WARNINGS ON}
{$WARN UNIT_PLATFORM OFF}
{$WARN SYMBOL_PLATFORM OFF}

interface

uses
    Dialogs,
    FileCtrl,
    ShellAPI,
    VCL.Forms,
    VCL.Menus,
    VCL.ImgList,
    VCL.ComCtrls,
    VCL.ExtCtrls,
    VCL.StdCtrls,
    VCL.CheckLst,
    VCL.Controls,
    VCL.Graphics,
    System.Types,
    System.UiTypes,
    System.Classes,
    System.SysUtils,
    System.StrUtils,

    U_Files,
    U_Parser,
    U_Events,
    U_Threads,
    U_DataBase,
    U_Download,
    U_Functions,
    U_OutputTasks;

type
    tfFacTotum = class(tForm)
            lUpdate:        tLabel;
            lEvents:        tLabel;
            lInstall:       tLabel;
            lUpdateProg:    tLabel;
            lSwInstProg:    tLabel;
            lEventsProg:    tLabel;
            lCmdInstProg:   tLabel;
            tRefresh:       tTimer;
            bEmpty:         tButton;
            bUpdate:        tButton;
            bBrowse:        tButton;
            bInstall:       tButton;
            tLog:           tTabSheet;
            tUpdate:        tTabSheet;
            tInstaller:     tTabSheet;
            tConfiguration: tTabSheet;
            tvConfig:       tTreeView;
            lvUpdate:       tListView;
            lvEvents:       tListView;
            miInsert:       tMenuItem;
            miUpdate:       tMenuItem;
            miDelete:       tMenuItem;
            miSetMainCmd:   tMenuItem;
            ilTasks:        tImageList;
            ilFacTotum:     tImageList;
            pmUpdate:       tPopupMenu;
            pmSoftware:     tPopupMenu;
            rgArchInfo:     tRadioGroup;
            pcTabs:         tPageControl;
            pbUpdate:       tProgressBar;
            pbEvents:       tProgressBar;
            pbSwInst:       tProgressBar;
            pbCmdInst:      tProgressBar;
            leCmmdInfo:     tLabeledEdit;
            leSwchInfo:     tLabeledEdit;
            leVersInfo:     tLabeledEdit;
            leuUrlInfo:     tLabeledEdit;
            clbInstall:     tCheckListBox;

            procedure applicationIdleEvents(sender: tObject; var done: boolean);
            procedure tRefreshTimer(sender: tObject);
            procedure formCreate(sender: tObject);
            procedure bEmptyClick(sender: tObject);
            procedure bBrowseClick(sender: tObject);
            procedure bUpdateClick(sender: tObject);
            procedure bInstallClick(sender: tObject);
            procedure miInsertClick(sender: tObject);
            procedure miUpdateClick(sender: tObject);
            procedure miDeleteClick(sender: tObject);
            procedure pmUpdatePopup(sender: tObject);
            procedure pmSoftwarePopup(sender: tObject);
            procedure leCmmdInfoExit(sender: tObject);
            procedure leVersInfoExit(sender: tObject);
            procedure leuUrlInfoExit(sender: tObject);
            procedure leSwchInfoExit(Sender: TObject);
            procedure rgArchInfoExit(sender: tObject);
            procedure ctrlInfoKeyPress(sender: tObject; var key: char);
            procedure tvConfigChange(sender: tObject; node: tTreeNode);
            procedure tvConfigEdited(sender: tObject; node: tTreeNode; var s: string);
            procedure tvConfigMouseDown(sender: tObject; button: tMouseButton; shift: tShiftState; x, y: integer);
            procedure leVersInfoKeyDown(sender: tObject; var key: word; shift: tShiftState);
            procedure leVersInfoKeyPress(sender: tObject; var key: char);
            procedure leVersInfoContextPopup(sender: tObject; mousePos: tPoint; var handled: boolean);
            procedure formClose(sender: tObject; var action: tCloseAction);
            procedure lvUpdateMouseDown(sender: tObject; button: tMouseButton; shift: tShiftState; x, y: integer);

        protected
            lastNode: tTreeNode;
            procedure fillConfigureSoftwareList;
            procedure fillUpdateSoftwareList;
            procedure sendUpdateSoftwareList;
    end;

var
    fFacTotum: tfFacTotum;

implementation

{$R *.dfm}

// Start implementation of internal procedures
//------------------------------------------------------------------------------

    procedure tfFacTotum.fillConfigureSoftwareList;
    var
        software: tList;
        j,
        i:        integer;
        node:     tTreeNode;
        swRec:    tSwRecord;
    begin
        tvConfig.items.clear;

        software := sdbMgr.getSoftwareList;

        for i := 0 to pred(software.count) do
        begin
            swRec := tSwRecord(software.items[i]);

            if swRec.hasValidCommands then
                clbInstall.items.addObject(swRec.name, software.items[i]);

            node      := tvConfig.items.add(nil, swRec.name);
            node.data := swRec;

            if not assigned(swRec.commands) then
                continue;

            for j := 0 to pred(swRec.commands.count) do
                tvConfig.items.addChild( node, tCmdRecord( swRec.commands[j]).name ).data := tCmdRecord(swRec.commands[j]);

            node.expand(true);
        end;
    end;

    procedure tfFactotum.fillUpdateSoftwareList;
    var
      sList,
      cList:   tList;
      swRec:   tSwRecord;
      cmdRec:  tCmdRecord;
      i,
      j,
      k:       integer;
      progBar: tProgressBar;
      progRec: tRect;
    begin
        lvUpdate.clear;

        sList := sdbMgr.getSoftwareList;
        for i := 0 to pred(sList.count) do
        begin
            swRec := tSwRecord( sList.items[i] );
            cList := swRec.commands;
            for j := 0 to pred(cList.count) do
            begin
                cmdRec  := cList.items[j];

                if (cmdRec.uURL = '') or (cmdRec.vers = '') then // TODO: Da rimuovere quando sarà previsto l'update manuale
                    continue;

                with lvUpdate.items.add do
                begin
                    data    := cmdRec;
                    caption := '';
                    subItems.add( swRec.name + ' [' + intToStr(cmdRec.guid) + ']' );
                    subItems.add(cmdRec.vers);
                    subItems.add('');
                    subItems.add('');
                    subItems.add('');

                    progBar               := tProgressBar.create(nil);
                    progBar.parent        := lvUpdate;
                    progBar.max           := 100;
                    progBar.min           := 0;
                    progBar.position      := 0;
                    progBar.barColor      := clLime;
                    progBar.styleElements := [seFont, seBorder];
                    progRec               := displayRect(drBounds);

                    for k := 0 to pred( integer(lvColProgress) ) do
                        progRec.left := progRec.left + lvUpdate.columns[k].width;

                    progRec.right      := progRec.left + lvUpdate.columns[ integer(lvColProgress) ].width;
                    progBar.boundsRect := progRec;

                    stateIndex := tImageIndex(eiDotYellow);
                end;
            end;
        end;
    end;

    procedure tfFactotum.sendUpdateSoftwareList;
    var
        taskVer: tTaskGetVer;
        i:       integer;
    begin
        for i := 0 to pred(lvUpdate.items.count) do
        begin
            // TODO: Da rimuovere quando sarà previsto l'update manuale
            if ( tCmdRecord(lvUpdate.items[i].data).uURL = '' ) or
               ( tCmdRecord(lvUpdate.items[i].data).vers = '' ) then
                continue;

            taskVer        := tTaskGetVer.create;
            taskVer.cmdRec := tCmdRecord(lvUpdate.items[i].data);

            setLength(taskVer.dummyTargets, 2);
            taskVer.dummyTargets[0] := lvUpdate.items[i];
            taskVer.dummyTargets[1] := tUpdate;

            sTaskMgr.pushTaskToInput(taskVer);
        end;
    end;

//------------------------------------------------------------------------------
// End implementation of internal procedures

// Start implementation of idle operations
//------------------------------------------------------------------------------

    procedure tfFacTotum.applicationIdleEvents(sender: tObject; var done: boolean);
    var
        i,
        updComp: integer;
        chkJobs: boolean;
        taskOut: tTaskOutput;
    begin
        // Visualizza il carico di lavoro della ThreadPool
        pbEvents.position := round(sTaskMgr.getBusyThreadsCount * (pbEvents.max / sTaskMgr.getThreadsCount));
        lEventsProg.caption := intToStr(pbEvents.position) + '%';

        // Visualizza l'avanzamento della ricerca aggiornamenti
        updComp := 0;
        if lvUpdate.items.count > 0 then
        begin
            for i := 0 to pred(lvUpdate.items.count) do
                if trim(lvUpdate.items[i].subItems[ pred( integer(lvColUV) ) ]) <> '' then
                    inc(updComp);

            pbUpdate.max        := lvUpdate.items.count;
            pbUpdate.position   := updComp;
            lUpdateProg.caption := floatToStr( trunc( (pbUpdate.position / pbUpdate.max) * 100 ) ) + '%';
        end;

        if not bUpdate.enabled then
        begin
            chkJobs := true;
            for i := 0 to pred(lvUpdate.items.count) do
                if lvUpdate.items[i].stateIndex = tImageIndex(eiDotYellow) then
                begin
                    chkJobs := false;
                    break;
                end;
            bUpdate.enabled := chkJobs;
        end;

        // Processa la coda di output
        taskOut := sTaskMgr.pullTaskFromOutput;
        if assigned(taskOut) then
        begin
            taskOut.exec;
            taskOut.free;

            if not sTaskMgr.isTaskOutputEmpty then
                done := false;
        end;
    end;

    procedure tfFacTotum.tRefreshTimer(sender: tObject);
    var
        jobStatus: boolean;
    begin
        jobStatus := false;
        self.applicationIdleEvents(sender, jobStatus);
    end;

//------------------------------------------------------------------------------
// End implementation of idle operations

// Start implementation of GUI related procedures
//------------------------------------------------------------------------------

    procedure tfFacTotum.formCreate(sender: tObject);
    begin
        // Inizializzo l'event handler
        sEventHdlr.initialize(lvEvents, tLog);

        // Eseguo la manutenzione dell'archivio
        sFileMgr.cleanupArchive(self.handle);

        // Centro la GUI nello schermo
        fFacTotum.left     := (Screen.Width - Width)   div 2;
        fFacTotum.top      := (Screen.Height - Height) div 2;

        // Visualizzo la versione attuale ed inizio le procedure in background
        fFacTotum.caption  := fFacTotum.caption + ' v' + getFmtFileVersion;
        application.onIdle := applicationIdleEvents;
        tRefresh.enabled   := true;

        // Popolo le liste di software e controllo gli aggiornamenti
        self.fillConfigureSoftwareList;
        self.fillUpdateSoftwareList;
        self.sendUpdateSoftwareList;
    end;

    procedure tfFacTotum.bEmptyClick(sender: tObject);
    begin
        lvEvents.items.clear;
        tLog.imageIndex := tImageIndex(tiEvents);
    end;

    procedure tfFacTotum.bBrowseClick(sender: tObject);
    var
        odSelectFile:   tOpenDialog;
        odSelectCombo:  tFileOpenDialog;
        selectedFolder,
        selectedFile:   string;
        taskAdd:        tTaskInsertArchiveSetup;
   begin
        selectedFile   := '';
        selectedFolder := '';

        // Chiedo all'utente di selezionare il file, ed eventualmente la
        // cartella del file che desidera importare

        // Componenti utilizzabili solo da Windows Vista in poi
        if tOSVersion.major >= 6 then
        begin
            odSelectCombo                   := tFileOpenDialog.create(self);
            odSelectCombo.title             := 'Seleziona il file d''installazione';
            odSelectCombo.options           := [fdoAllNonStorageItems, fdoFileMustExist];
            odSelectCombo.defaultFolder     := getCurrentDir;
            odSelectCombo.okButtonLabel     := 'Seleziona';
            with odSelectCombo.fileTypes.add do
            begin
               displayName := 'File eseguibili';
               fileMask    := '*.exe; *.msi';
            end;
            with odSelectCombo.fileTypes.add do
            begin
               displayName := 'Tutti i file';
               fileMask    := '*.*';
            end;

            if odSelectCombo.execute then
                selectedFile                := odSelectCombo.fileName;

            if messageDlg('Vuoi aggiungere una cartella d''installazione?', mtConfirmation, mbYesNo, 0) = mrYes then
            begin
                odSelectCombo.title         := 'Seleziona la cartella d''installazione';
                odSelectCombo.options       := [fdoPickFolders, fdoPathMustExist];
                odSelectCombo.defaultFolder := extractFileDir(selectedFile);
                odSelectCombo.fileTypes.clear;

                if odSelectCombo.execute then
                   selectedFolder           := odSelectCombo.fileName;
            end;

            odSelectCombo.free;
        end
        else  // Altrimenti, rollback a componenti compatibili con XP
        begin
            odSelectFile            := tOpenDialog.create(self);
            odSelectFile.title      := 'Seleziona il file d''installazione';
            odSelectFile.filter     := 'File eseguibili|*.exe; *.msi|Tutti i file|*.*';
            odSelectFile.options    := [ofFileMustExist];
            odSelectFile.initialDir := getCurrentDir;

            if odSelectFile.execute then
               selectedFile         := odSelectFile.fileName;

            if messageDlg('Vuoi aggiungere una cartella d''installazione?', mtConfirmation, mbYesNo, 0) = mrYes then
                selectDirectory('Seleziona la cartella d''installazione', getEnvironmentVariable('SYSTEMDRIVE') + '\', selectedFolder);

            odSelectFile.free;
        end;

        // Verifico che l'utente non abbia chiuso la finestra senza selezionare
        if selectedFile <> '' then
        begin
            // Se il file esiste nella path, la cartella non puo' essere
            // importata, ed e' sufficiente aggiornare il campo del comando
            if sFileMgr.fileExistsInPath( extractFileName(selectedFile) ) then
            begin
                selectedFolder  := '';
                tCmdRecord(tvConfig.selected.data).hash := '';
                leCmmdInfo.text := extractFileName(selectedFile);
                leCmmdInfoExit(sender);
                leCmmdInfo.setFocus;
                exit;
            end;

            // La cartella deve contenere il file, oppure non verrà considerata
            if selectedFolder <> '' then
                if not ansiContainsText(selectedFile, selectedFolder) then
                    selectedFolder := '';

            taskAdd            := tTaskInsertArchiveSetup.create;
            taskAdd.formHandle := handle;
            taskAdd.cmdRec     := tvConfig.selected.data;
            taskAdd.fileName   := selectedFile;
            taskAdd.folderName := selectedFolder;

            sTaskMgr.pushTaskToInput(taskAdd);
        end;
    end;

    procedure tfFacTotum.bUpdateClick(sender: tObject);
    begin
        lvUpdate.clear;
        pbUpdate.position   := 0;
        lUpdateProg.caption := '0%';
        bUpdate.enabled     := false;

        while lvUpdate.controlCount > 0 do
            lvUpdate.controls[0].free;

        tUpdate.imageIndex := tImageIndex(tiUpdate);
        self.fillUpdateSoftwareList;
        self.sendUpdateSoftwareList;
    end;

    procedure tfFacTotum.bInstallClick(sender: tObject);
    var
        i:         integer;
        task:      tTaskRunCommands;
        lSoftware: tList;
    begin
        pbSwInst.max       := 100;
        pbCmdInst.max      := 100;
        lSoftware          := tList.create;
        for i := 0 to pred(clbInstall.items.count) do
        begin
            if not clbInstall.checked[i] then
                continue;

            clbInstall.enabled := false;
            bInstall.enabled   := false;

            lSoftware.add(clbInstall.items.objects[i]);

            task           := tTaskRunCommands.create;
            task.handle    := handle;
            task.lSoftware := lSoftware;

            setLength(task.dummyTargets, 6);
            task.dummyTargets[0] := bInstall;
            task.dummyTargets[1] := clbInstall;
            task.dummyTargets[2] := pbSwInst;
            task.dummyTargets[3] := pbCmdInst;
            task.dummyTargets[4] := lSwInstProg;
            task.dummyTargets[5] := lCmdInstProg;

            sTaskMgr.pushTaskToInput(task);
        end;
    end;

    procedure tfFacTotum.miInsertClick(sender: tObject);
    var
        taskInsert: tTaskRecordOP;
        command:    tCmdRecord;
    begin
        taskInsert   := tTaskRecordOP.create;
        command      := tCmdRecord.create;

        if assigned(tvConfig.selected) and assigned(tvConfig.selected.parent) then
        begin
            taskInsert.pRecord    := command;
            taskInsert.tOperation := DOR_INSERT;
            command.swid          := tSwRecord(tvConfig.selected.parent.data).guid;
            command.prty          := tSwRecord(tvConfig.selected.parent.data).commands.count;
        end
        else
        begin
            taskInsert.pRecord                     := tSwRecord.create;
            taskInsert.tOperation                  := DOR_INSERT;
            tSwRecord(taskInsert.pRecord).name     := '<Nuovo Software>';
            tSwRecord(taskInsert.pRecord).commands := tList.create;
            command.prty                           := 0;
            tSwRecord(taskInsert.pRecord).commands.add(command);
        end;

        command.arch := byte(archNone);
        command.name := '<Nuovo Comando>';
        command.vers := '';
        command.cmmd := '<Comando>';
        command.uURL := '';
        command.hash := '';

        setLength(taskInsert.dummyTargets, 1);
        taskInsert.dummyTargets[0] := tvConfig;

        sTaskMgr.pushTaskToInput(taskInsert);
    end;

    procedure tfFacTotum.miUpdateClick(sender: tObject);
    var
        curRow:       integer;
        taskDownload: tTaskDownload;
    begin
        lvUpdate.selected.stateIndex := tImageIndex(eiDotYellow);

        taskDownload              := tTaskDownload.create;
        taskDownload.formHandle   := handle;
        taskDownload.pRecord      := lvUpdate.selected.data;
        taskDownload.pRecord.vers := lvUpdate.selected.subItems[pred( integer(lvColUV) )];

        curRow := lvUpdate.selected.index;
        setLength(taskDownload.dummyTargets, 2);
        taskDownload.dummyTargets[0] := tProgressBar( lvUpdate.controls[curRow] );
        taskDownload.dummyTargets[1] := lvUpdate.selected;

        sTaskMgr.pushTaskToInput(taskDownload);

        lvUpdate.selected.subitems[pred( integer(lvColStatus) )] := '0%';
    end;

    procedure tfFacTotum.miDeleteClick(sender: tObject);
    var
        taskDelete: tTaskRecordOP;
    begin
        taskDelete := tTaskRecordOP.create;

        taskDelete.tOperation := DOR_DELETE;

        if assigned(tvConfig.selected.parent)and
            (tvConfig.selected.parent.count = 1) then
        begin
            taskDelete.pRecord := tvConfig.selected.parent.data;
            tvConfig.items.delete(tvConfig.selected.parent);
        end
        else
        begin
            taskDelete.pRecord := tvConfig.selected.data;
            tvConfig.items.delete(tvConfig.selected);
        end;

        setLength(taskDelete.dummyTargets, 1);
        taskDelete.dummyTargets[0] := tvConfig;

        sTaskMgr.pushTaskToInput(taskDelete);
    end;

    procedure tfFacTotum.pmUpdatePopup(sender: tObject);
    begin
        if assigned(lvUpdate.selected) then
            miUpdate.enabled := lvUpdate.selected.stateIndex = tImageIndex(eiDotRed)
        else
            miUpdate.enabled := false;
    end;

    procedure tfFacTotum.pmSoftwarePopup(sender: tObject);
    begin
        miDelete.enabled := false;

        if assigned(tvConfig.selected) then
        begin
            if assigned(tvConfig.selected.parent) then
            begin
                miInsert.caption := 'Inserisci comando';
                miDelete.caption := 'Elimina comando';
            end
            else
            begin
                miInsert.caption := 'Inserisci software';
                miDelete.caption := 'Elimina software';
            end;
            miDelete.enabled := true;
        end;
    end;

    procedure tfFacTotum.leCmmdInfoExit(sender: tObject);
    var
        tmpNode:    tTreeNode;
        taskUpdate: tTaskRecordOP;
    begin
        if assigned(self.lastNode) then
            tmpNode := self.lastNode
        else
            tmpNode := tvConfig.selected;

        leCmmdInfo.text := trim(leCmmdInfo.text);
        if tCmdRecord(tmpNode.data).cmmd <> leCmmdInfo.text then
            if sFileMgr.isAvailable(leCmmdInfo.text, tCmdRecord(tmpNode.data).hash) or
               (leCmmdInfo.text = '')                                              then
            begin
                taskUpdate := tTaskRecordOP.create;

                tCmdRecord(tmpNode.data).cmmd := leCmmdInfo.text;
                taskUpdate.pRecord            := tmpNode.data;
                taskUpdate.tOperation         := DOR_UPDATE;

                setLength(taskUpdate.dummyTargets, 2);
                taskUpdate.dummyTargets[0] := tvConfig;

                if leCmmdInfo.text = '' then
                    leCmmdInfo.color := $0080FFFF  // Giallo
                else
                    taskUpdate.dummyTargets[1] := leCmmdInfo;

                sTaskMgr.pushTaskToInput(taskUpdate);
                self.lastNode := nil;
            end
            else
                leCmmdInfo.color := $008080FF      // Rosso
        else
            leCmmdInfo.color := clWhite;
    end;

    procedure tfFacTotum.leVersInfoExit(sender: tObject);
    var
        tmpNode:    tTreeNode;
        taskUpdate: tTaskRecordOP;
    begin
        if assigned(self.lastNode) then
            tmpNode := self.lastNode
        else
            tmpNode := tvConfig.selected;

        leVersInfo.text := trim( leVersInfo.text );
        if tCmdRecord(tmpNode.data).vers <> leVersInfo.text then
            if leVersInfo.text[length(leVersInfo.text)] <> '.' then
            begin
                taskUpdate := tTaskRecordOP.create;

                tCmdRecord(tmpNode.data).vers := leVersInfo.text;
                taskUpdate.pRecord            := tmpNode.data;
                taskUpdate.tOperation         := DOR_UPDATE;

                setLength(taskUpdate.dummyTargets, 2);
                taskUpdate.dummyTargets[0] := tvConfig;

                if leVersInfo.text = '' then
                    leVersInfo.color := $0080FFFF  // Giallo
                else
                    taskUpdate.dummyTargets[1] := leVersInfo;

                sTaskMgr.pushTaskToInput(taskUpdate);
                self.lastNode := nil;
            end
            else
                leVersInfo.color := $008080FF      // Rosso
        else
            leVersInfo.color := clWhite;
    end;

    procedure tfFacTotum.leuUrlInfoExit(sender: tObject);
    var
        tmpNode:    tTreeNode;
        taskUpdate: tTaskRecordOP;
    begin
        if assigned(self.lastNode) then
            tmpNode := self.lastNode
        else
            tmpNode := tvConfig.selected;

        leuUrlInfo.text := trim(leuUrlInfo.text);
        if tCmdRecord(tmpNode.data).uURL <> leuUrlInfo.text then
        begin
            taskUpdate := tTaskRecordOP.create;

            tCmdRecord(tmpNode.data).uURL := leuUrlInfo.text;
            taskUpdate.pRecord            := tmpNode.data;
            taskUpdate.tOperation         := DOR_UPDATE;

            setLength(taskUpdate.dummyTargets, 2);
            taskUpdate.dummyTargets[0] := tvConfig;

            if leuUrlInfo.text = '' then
                leuUrlInfo.color := $0080FFFF  // Giallo
            else
                taskUpdate.dummyTargets[1] := leuUrlInfo;

            sTaskMgr.pushTaskToInput(taskUpdate);
            self.lastNode := nil;
        end
        else
            leuUrlInfo.color := clWhite;
    end;

    procedure tfFacTotum.leSwchInfoExit(sender: tObject);
    var
        tmpNode:    tTreeNode;
        taskUpdate: tTaskRecordOP;
    begin
        if assigned(self.lastNode) then
            tmpNode := self.lastNode
        else
            tmpNode := tvConfig.selected;

        leSwchInfo.text := trim(leSwchInfo.text);
        if tCmdRecord(tmpNode.data).swch <> leSwchInfo.text then
        begin
            taskUpdate := tTaskRecordOP.create;

            tCmdRecord(tmpNode.data).swch := leSwchInfo.text;
            taskUpdate.pRecord            := tmpNode.data;
            taskUpdate.tOperation         := DOR_UPDATE;

            setLength(taskUpdate.dummyTargets, 2);
            taskUpdate.dummyTargets[0] := tvConfig;

            if leSwchInfo.text = '' then
                leSwchInfo.color := $0080FFFF  // Giallo
            else
                taskUpdate.dummyTargets[1] := leSwchInfo;

            sTaskMgr.pushTaskToInput(taskUpdate);
            self.lastNode := nil;
        end
        else
            leSwchInfo.color := clWhite;
    end;

    procedure tfFacTotum.rgArchInfoExit(sender: tObject);
    var
        tmpNode:    tTreeNode;
        taskUpdate: tTaskRecordOP;
    begin
        if assigned(self.lastNode) then
            tmpNode := self.lastNode
        else
            tmpNode := tvConfig.selected;

        if tCmdRecord(tmpNode.data).arch <> rgArchInfo.itemIndex then
        begin
            tCmdRecord(tmpNode.data).arch := abs(rgArchInfo.itemIndex);
            taskUpdate                    := tTaskRecordOP.create;
            taskUpdate.pRecord            := tmpNode.data;
            taskUpdate.tOperation         := DOR_UPDATE;

            setLength(taskUpdate.dummyTargets, 2);
            taskUpdate.dummyTargets[0] := tvConfig;
            taskUpdate.dummyTargets[1] := rgArchInfo;

            sTaskMgr.pushTaskToInput(taskUpdate);
            self.lastNode := nil;
        end;
    end;

    procedure tfFacTotum.ctrlInfoKeyPress(sender: tObject; var key: char);
    begin
        if key = #13 then
        begin
            selectNext(sender as tWinControl, true, true);
            key := #0
        end;
    end;

    procedure tfFacTotum.tvConfigChange(sender: tObject; node: tTreeNode);
    var
        isChild: boolean;
        cmdRec:  tCmdRecord;
    begin
        isChild            := assigned(node.parent);
        bBrowse.enabled    := isChild;
        leCmmdInfo.enabled := isChild;
        leSwchInfo.enabled := isChild;
        leVersInfo.enabled := isChild;
        leuUrlInfo.enabled := isChild;
        rgArchInfo.enabled := isChild;

        leCmmdInfo.color   := clWhite;
        leSwchInfo.color   := clWhite;
        leVersInfo.color   := clWhite;
        leuUrlInfo.color   := clWhite;

        if isChild then
        begin
            cmdRec               := node.data;
            leCmmdInfo.text      := cmdRec.cmmd;
            leSwchInfo.text      := cmdRec.swch;
            leVersInfo.text      := cmdRec.vers;
            leuUrlInfo.text      := cmdRec.uURL;
            rgArchInfo.itemIndex := cmdRec.arch;
        end
        else
        begin
            leuUrlInfo.text      := '';
            leCmmdInfo.text      := '';
            leSwchInfo.text      := '';
            leVersInfo.text      := '';
            rgArchInfo.itemIndex := -1;
        end;
    end;

    procedure tfFacTotum.tvConfigEdited(sender: tObject; node: tTreeNode; var s: string);
    var
        taskUpdate: tTaskRecordOP;
    begin
        taskUpdate := tTaskRecordOP.create;

        if node.hasChildren then  // E' un software
            tSwRecord(tvConfig.selected.data).name  := trim(s)
        else                      // E' un comando
            tCmdRecord(tvConfig.selected.data).name := trim(s);

        taskUpdate.pRecord    := tvConfig.selected.data;
        taskUpdate.tOperation := DOR_UPDATE;

        setLength(taskUpdate.dummyTargets, 1);
        taskUpdate.dummyTargets[0] := tvConfig;

        sTaskMgr.pushTaskToInput(taskUpdate);
    end;

    procedure tfFacTotum.tvConfigMouseDown(sender: tObject; button: tMouseButton; shift: tShiftState; x, y: integer);
    var
        node: tTreeNode;
    begin
        node := tvConfig.getNodeAt(x, y);

        if assigned(node) then
        begin
            self.lastNode     := tvConfig.selected;
            tvConfig.selected := node;
        end;
    end;

    procedure tfFacTotum.leVersInfoKeyDown(sender: tObject; var key: word; shift: tShiftState);
    begin
        // Disabilito l'utilizzo di alcuni tasti
        if key in [46] then
            key := 0;
    end;

    procedure tfFacTotum.leVersInfoKeyPress(sender: tObject; var key: char);
    var
        chrBef, chrAft: char;
    begin
        // Alla pressione del tastio Invio si attiva il tasto Tab
        if key = #13 then
        begin
            selectNext(sender as tWinControl, true, true);
            key := #0;
            exit;
        end;
        // Limito i tasti utilizzabili
        if not( charInSet(key, ['0'..'9', '.', #8]) ) then
        begin
            key := #0;
            exit;
        end;

        chrBef := #0;
        chrAft := #0;
        // Se possibile, ricavo i caratteri all'inizio e alla fine della selezione
        if (leVersInfo.selStart > 0) then
            chrBef := leVersInfo.text[leVersInfo.selStart];
        if (leVersInfo.selStart + leVersInfo.selLength) < length(leVersInfo.text) then
            chrAft := leVersInfo.text[succ(leVersInfo.selStart + leVersInfo.selLength)];

        // Il primo carattere non può essere un punto
        if ( (leVersInfo.selStart = 0)  and (key = '.') )             or
           ( (leVersInfo.selStart = 0)  and (leVersInfo.selLength > 0) and (chrAft = '.') and (key = #8) ) or
           ( (leVersInfo.selStart <= 1) and (leVersInfo.selLength = 0) and (chrAft = '.') and (key = #8) ) then
        begin
            key := #0;
            exit;
        end;
        // Non possono esserci due punti attaccati
        if ( ( (chrBef = '.') or (chrAft = '.') ) and (key = '.') ) then
        begin
            key := #0;
            exit;
        end;
        // Cancellando una selezione, non posso unire due punti
        if ( (chrBef = '.') and (chrAft = '.') and (key = #8) ) then
        begin
            key := #0;
            exit;
        end;
        // Cancellando, non posso unire due punti
        if ( (key = #8) and (pred(leVersInfo.selStart) > 0) ) then
            if ( (leVersInfo.text[pred(leVersInfo.selStart)] = '.') and (chrAft = '.') ) then
            begin
                key := #0;
                exit;
            end;
    end;

    procedure tfFacTotum.lvUpdateMouseDown(sender: tObject; button: tMouseButton; shift: tShiftState; x, y: integer);
    begin
        lvUpdate.selected := lvUpdate.getItemAt(x, y);
    end;

    procedure tfFacTotum.leVersInfoContextPopup(sender: tObject; mousePos: TPoint; var handled: boolean);
    begin
        handled := true;
    end;

    procedure tfFacTotum.formClose(sender: tObject; var action: tCloseAction);
    begin
        if sTaskMgr.getBusyThreadsCount > 0 then
            if messageDlg('Ci sono ancora dei processi in esecuzione.'
                        + #13 + #13
                        + 'Vuoi interromperli subito?', mtWarning, mbYesNo, 0) = mrYes then
                sTaskMgr.Destroy(true)
            else
                sTaskMgr.Destroy
        else
            sTaskMgr.Destroy;
    end;

//------------------------------------------------------------------------------
// End implementation of GUI related procedures

    end.


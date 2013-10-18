unit U_Main;

{$HINTS ON}
{$WARNINGS ON}
{$WARN UNIT_PLATFORM OFF}
{$WARN SYMBOL_PLATFORM OFF}

interface

uses
    vcl.controls, vcl.forms, vcl.comCtrls, vcl.stdCtrls, vcl.checkLst, vcl.imgList,
    vcl.extCtrls, vcl.menus, system.sysutils, system.classes, system.uiTypes, dialogs,
    system.types, ShellAPI, FileCtrl, Vcl.Graphics, System.StrUtils,

    U_DataBase, U_Functions, U_Threads, U_OutputTasks, U_Events, U_Parser, U_Download, U_Files;

type
    tfFacTotum = class(tForm)
            pcTabs:         tPageControl;
            tInstaller:     tTabSheet;
            tConfiguration: tTabSheet;
            tUpdate:        tTabSheet;
            pbCmdInst:      tProgressBar;
            lInstall:       tLabel;
            clbInstall:     tCheckListBox;
            ilFacTotum:     tImageList;
            tvConfig:       ttreeView;
            rgArchInfo:     tRadioGroup;
            leCmdInfo:      tLabeledEdit;
            pmSoftware:     tPopupMenu;
            miInsert:       tMenuItem;
            miDelete:       tMenuItem;
            lUpdate:        tLabel;
            pbUpdate:       tProgressBar;
            leVerInfo:      tLabeledEdit;
            leUrlInfo:      tLabeledEdit;
            miSetMainCmd:   tMenuItem;
            lUpdateProg:    tLabel;
            tLog:           tTabSheet;
            lCmdInstProg:   tLabel;
            bInstall:       tButton;
            bUpdate:        tButton;
            lvEvents:       tListView;
            bEmpty:         tButton;
            ilTasks:        tImageList;
            bBrowse:        tButton;
            lvUpdate:       tListView;
            pbSwInst:       tProgressBar;
            lSwInstProg:    tLabel;
            pbEvents:       tProgressBar;
            lEventsProg:    tLabel;
            lEvents:        tLabel;
            pmUpdate:       tPopupMenu;
            miUpdate:       tMenuItem;

            procedure formCreate(sender: tObject);
            procedure applicationIdleEvents(sender: tObject; var done: boolean);
            procedure bEmptyClick(sender: tObject);
            procedure configureUpdateOnTreeSelect(sender: tObject; node: tTreeNode);
            procedure formClose(sender: tObject; var action: tCloseAction);
            procedure miInsertClick(sender: tObject);
            procedure tvConfigMouseDown(sender: tObject; button: tMouseButton; shift: tShiftState; x, y: integer);
            procedure pmSoftwarePopup(sender: tObject);
            procedure miDeleteClick(sender: tObject);
            procedure leCmdInfoExit(sender: tObject);
            procedure leVerInfoExit(sender: tObject);
            procedure leVerInfoKeyPress(sender: tObject; var key: char);
            procedure leUrlInfoExit(sender: tObject);
            procedure leCmdInfoKeyPress(sender: tObject; var key: char);
            procedure leUrlInfoKeyPress(sender: tObject; var key: char);
            procedure bBrowseClick(sender: tObject);
            procedure leVerInfoKeyDown(sender: tObject; var key: word; shift: tShiftState);
            procedure leVerInfoContextPopup(sender: tObject; mousePos: tPoint; var handled: boolean);
            procedure tvConfigEdited(sender: tObject; node: tTreeNode; var s: string);
            procedure bUpdateClick(sender: tObject);
            procedure pmUpdatePopup(sender: tObject);
            procedure miUpdateClick(sender: tObject);
            procedure rgArchInfoExit(sender: tObject);

            procedure fillConfigureSoftwareList;
            procedure sendUpdateSoftwareList;
            procedure fillUpdateSoftwareList;

        protected
            lastNode: tTreeNode;
    end;

var
    fFacTotum: tfFacTotum;

implementation

{$R *.dfm}

    procedure tfFacTotum.configureUpdateOnTreeSelect(sender: tObject; node: tTreeNode);
    var
        isChild: boolean;
        cmdRec:  tCmdRecord;
    begin
        isChild            := assigned(node.parent);
        bBrowse.enabled    := isChild;
        leCmdInfo.enabled  := isChild;
        leVerInfo.enabled  := isChild;
        leUrlInfo.enabled  := isChild;
        rgArchInfo.enabled := isChild;

        leCmdInfo.color    := clWhite;
        leVerInfo.color    := clWhite;
        leUrlInfo.color    := clWhite;

        if isChild then
        begin
            cmdRec               := node.data;
            leCmdInfo.text       := cmdRec.cmmd;
            leVerInfo.text       := cmdRec.vers;
            leUrlInfo.text       := cmdRec.uURL;
            rgArchInfo.itemIndex := cmdRec.arch;
        end
        else
        begin
            leUrlInfo.text       := '';
            leCmdInfo.text       := '';
            leVerInfo.text       := '';
            rgArchInfo.itemIndex := -1;
        end;
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
                clbInstall.items.add(swRec.name);

            node      := tvConfig.items.add(nil, swRec.name);
            node.data := swRec;

            if not assigned(swRec.commands) then
                continue;

            for j := 0 to pred(swRec.commands.count) do
                tvConfig.items.addChild( node, tCmdRecord( swRec.commands[j]).name ).data := tCmdRecord(swRec.commands[j]);

            node.expand(true);
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

    procedure tfFacTotum.tvConfigMouseDown(sender: tObject; button: tMouseButton; shift: tShiftState; X, Y: integer);
    var
        node: tTreeNode;
    begin
        node := tvConfig.getNodeAt(X, Y);

        if assigned(node) then
        begin
            self.lastNode     := tvConfig.selected;
            tvConfig.selected := node;
        end;
    end;

    procedure tfFacTotum.applicationIdleEvents(sender: tObject; var done: boolean);
    var
        i,
        updComp: word;
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

    procedure tfFacTotum.formCreate(sender: tObject);
    begin
        sEventHdlr         := eventHandler.create(lvEvents, tLog);
        sTaskMgr           := taskManager.create;
        sUpdateParser      := updateParser.create;
        sDownloadMgr       := downloadManager.create;
        sFileMgr           := fileManager.create;
        sdbMgr             := dbManager.create;

        fFacTotum.left     := (Screen.Width - Width)   div 2;
        fFacTotum.top      := (Screen.Height - Height) div 2;

        fFacTotum.caption  := fFacTotum.caption + ' v' + getFmtFileVersion(application.exeName);

        application.onIdle := applicationIdleEvents;

        self.fillConfigureSoftwareList;
        self.fillUpdateSoftwareList;
        self.sendUpdateSoftwareList;
    end;

    procedure tfFacTotum.leCmdInfoExit(sender: tObject);
    var
        tmpNode:    tTreeNode;
        taskUpdate: tTaskRecordOP;
    begin
        if assigned(self.lastNode) then
            tmpNode := self.lastNode
        else
            tmpNode := tvConfig.selected;

        leCmdInfo.text := trim(leCmdInfo.text);
        if tCmdRecord(tmpNode.data).cmmd <> leCmdInfo.text then
        begin
            taskUpdate := tTaskRecordOP.create;

            tCmdRecord(tmpNode.data).cmmd := leCmdInfo.text;
            taskUpdate.pRecord            := tmpNode.data;
            taskUpdate.tOperation         := DOR_UPDATE;

            setLength(taskUpdate.dummyTargets, 2);
            taskUpdate.dummyTargets[0] := tvConfig;
            taskUpdate.dummyTargets[1] := leCmdInfo;

            sTaskMgr.pushTaskToInput(taskUpdate);
            self.lastNode := nil;

            if length(leCmdInfo.text) > 0 then
                leCmdInfo.color := $0080FFFF  // Giallo
        end
        else
            leCmdInfo.color := clWhite;
    end;

    procedure tfFacTotum.leCmdInfoKeyPress(Sender: TObject; var Key: Char);
    begin
        if key = #13 then
        begin
            selectNext(sender as tWinControl, true, true);
            key := #0
        end;
    end;

    procedure tfFacTotum.leUrlInfoExit(Sender: TObject);
    var
        tmpNode:    tTreeNode;
        taskUpdate: tTaskRecordOP;
    begin
        if assigned(self.lastNode) then
            tmpNode := self.lastNode
        else
            tmpNode := tvConfig.selected;

        leUrlInfo.text := trim(leUrlInfo.text);
        if tCmdRecord(tmpNode.data).uURL <> leUrlInfo.text then
        begin
            taskUpdate := tTaskRecordOP.create;

            tCmdRecord(tmpNode.data).uURL := leUrlInfo.text;
            taskUpdate.pRecord            := tmpNode.data;
            taskUpdate.tOperation         := DOR_UPDATE;

            setLength(taskUpdate.dummyTargets, 2);
            taskUpdate.dummyTargets[0] := tvConfig;
            taskUpdate.dummyTargets[1] := leUrlInfo;

            sTaskMgr.pushTaskToInput(taskUpdate);
            self.lastNode := nil;

            if length(leUrlInfo.text) = 0 then
                leUrlInfo.color := $0080FFFF  // Giallo
        end
        else
            leUrlInfo.color := clWhite;
    end;

    procedure tfFacTotum.leUrlInfoKeyPress(Sender: TObject; var Key: Char);
    begin
        if key = #13 then
        begin
            selectNext(sender as tWinControl, true, true);
            key := #0
        end;
    end;

    procedure tfFacTotum.leVerInfoContextPopup(Sender: TObject; MousePos: TPoint; var Handled: Boolean);
    begin
        handled := true;
    end;

    procedure tfFacTotum.leVerInfoExit(sender: tObject);
    var
        tmpNode:    tTreeNode;
        taskUpdate: tTaskRecordOP;
    begin
        if assigned(self.lastNode) then
            tmpNode := self.lastNode
        else
            tmpNode := tvConfig.selected;

        leVerInfo.text := trim( leVerInfo.text );
        if tCmdRecord(tmpNode.data).vers <> leVerInfo.text then
        begin
            if ( leVerInfo.text[length(leVerInfo.text)] <> '.' ) then
            begin
                taskUpdate := tTaskRecordOP.create;

                tCmdRecord(tmpNode.data).vers := leVerInfo.text;
                taskUpdate.pRecord            := tmpNode.data;
                taskUpdate.tOperation         := DOR_UPDATE;

                setLength(taskUpdate.dummyTargets, 2);
                taskUpdate.dummyTargets[0] := tvConfig;
                taskUpdate.dummyTargets[1] := leVerInfo;

                sTaskMgr.pushTaskToInput(taskUpdate);
                self.lastNode := nil;
            end;

            if ( length(leVerInfo.text) > 0 ) then
                leVerInfo.color := $0080FFFF  // Giallo
        end
        else
            leVerInfo.color := clWhite;
    end;

    procedure tfFacTotum.leVerInfoKeyDown(Sender: TObject; var Key: Word;
      Shift: TShiftState);
    begin
        // Disabilito l'utilizzo di alcuni tasti
        if key in [46] then
            key := 0;
    end;

    procedure tfFacTotum.leVerInfoKeyPress(sender: tObject; var key: char);
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
        if (leVerInfo.selStart > 0) then
            chrBef := leVerInfo.text[leVerInfo.selStart];
        if (leVerInfo.selStart + leVerInfo.selLength) < length(leVerInfo.text) then
            chrAft := leVerInfo.text[succ(leVerInfo.selStart + leVerInfo.selLength)];

        // Il primo carattere non può essere un punto
        if ( (leVerInfo.selStart = 0)  and (key = '.') )             or
           ( (leVerInfo.selStart = 0)  and (leVerInfo.selLength > 0) and (chrAft = '.') and (key = #8) ) or
           ( (leVerInfo.selStart <= 1) and (leVerInfo.selLength = 0) and (chrAft = '.') and (key = #8) ) then
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
        if ( (key = #8) and (pred(leVerInfo.selStart) > 0) ) then
            if ( (leVerInfo.text[pred(leVerInfo.selStart)] = '.') and (chrAft = '.') ) then
            begin
                key := #0;
                exit;
            end;
    end;

    procedure tfFacTotum.miInsertClick(Sender: TObject);
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

    procedure tfFacTotum.miUpdateClick(Sender: TObject);
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

    procedure tfFacTotum.pmSoftwarePopup(Sender: TObject);
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

    procedure tfFacTotum.pmUpdatePopup(Sender: TObject);
    begin
        miUpdate.enabled := lvUpdate.selected.stateIndex = tImageIndex(eiDotRed);
    end;

    procedure tfFacTotum.rgArchInfoExit(Sender: TObject);
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

    procedure tfFacTotum.bBrowseClick(sender: tObject);
    var
        odSelectFile:   tOpenDialog;
        odSelectCombo:  tFileOpenDialog;
        selectedFolder,
        selectedFile:   string;
        taskAdd:        tTaskAddToArchive;
   begin
        selectedFile   := '';
        selectedFolder := '';

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
                odSelectCombo.defaultFolder := extractFileName(selectedFile);
                odSelectCombo.fileTypes.clear;

                if odSelectCombo.execute then
                   selectedFolder           := odSelectCombo.fileName;
            end;

            odSelectCombo.free;
        end
        else
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

        if selectedFile <> '' then
        begin
            taskAdd            := tTaskAddToArchive.create;
            taskAdd.formHandle := handle;
            taskAdd.cmdRec     := tvConfig.selected.data;
            taskAdd.fileName   := selectedFile;
            taskAdd.folderName := selectedFolder;

            sTaskMgr.pushTaskToInput(taskAdd);

            // Da controllare, se il task fallisce la parte sotto non deve avvenire!
            if selectedFolder <> '' then
                leCmdInfo.text := ansiReplaceStr(selectedFile, selectedFolder + '\', '')
            else
                leCmdInfo.text := extractFileName(selectedFile);

            leCmdInfo.setFocus;
        end;
    end;

    procedure tfFacTotum.bEmptyClick(sender: tObject);
    begin
        lvEvents.items.clear;
        tLog.imageIndex := tImageIndex(tiEvents);
    end;

    procedure tfFacTotum.bUpdateClick(Sender: TObject);
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

    end.


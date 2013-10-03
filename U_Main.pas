unit U_Main;

interface

uses
    vcl.controls, vcl.forms, vcl.comCtrls, vcl.stdCtrls, vcl.checkLst, vcl.imgList,
    vcl.extCtrls, vcl.menus, system.sysutils, system.classes, system.uiTypes, dialogs,

    U_DataBase, U_Functions, U_Classes;

type
    tfFacTotum = class(tForm)
        pcTabs: TPageControl;
        tInstaller: TTabSheet;
        tConfiguration: TTabSheet;
        tUpdate: TTabSheet;
        pbProgress: TProgressBar;
        lInstallInfo: TLabel;
        clbSoftware: TCheckListBox;
        ilFacTotum: TImageList;
        tvSoftware: TTreeView;
        rgCompConfig: TRadioGroup;
        leCmdInfo: TLabeledEdit;
        pmSoftware: TPopupMenu;
        pmInsert: TMenuItem;
        pmDelete: TMenuItem;
        clbDownload: TCheckListBox;
        lDownloadInfo: TLabel;
        pbDownload: TProgressBar;
        leVersion: TLabeledEdit;
        leUrl: TLabeledEdit;
        pmSetMainCmd: TMenuItem;
        lUpdateProg: TLabel;
        tLog: TTabSheet;
        lSetupProg: TLabel;
        bInstall: TButton;
        bUpdate: TButton;
        lvEvents: TListView;
        bClear: TButton;
        ilEvents: TImageList;

        procedure formCreate(sender: tObject);
        procedure applicationIdleEvents(sender: tObject; var done: boolean);
        procedure bClearClick(sender: tObject);
        procedure refreshSoftwareList;
        procedure configureUpdateOnTreeSelect(sender: tObject; node: tTreeNode);
        procedure formClose(sender: tObject; var action: tCloseAction);
        procedure pmInsertClick(Sender: TObject);
        procedure tvSoftwareMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
        procedure pmSoftwarePopup(Sender: TObject);
        procedure pmDeleteClick(Sender: TObject);
    end;

const
    FH_URL = 'http://www.filehippo.com/';

var
    fFacTotum: tfFacTotum;

implementation

{$R *.dfm}

    procedure tfFacTotum.configureUpdateOnTreeSelect(sender: tObject; node: tTreeNode);
    var
        isChild: boolean;
        cmdRec:  cmdRecord;
    begin
        isChild              := assigned(node.parent);
        leCmdInfo.enabled    := isChild;
        leVersion.enabled    := isChild;
        leUrl.enabled        := isChild;
        rgCompConfig.enabled := isChild;

        if isChild then
        begin
            cmdRec                 := cmdRecord( swRecord(sDBMgr.getSoftwareList.items[node.parent.index]).commands[node.index] );
            leCmdInfo.text         := cmdRec.cmmd;
            leVersion.text         := cmdRec.vers;
            leUrl.text             := cmdRec.uURL;
            rgCompConfig.itemIndex := cmdRec.arch;
        end
        else
        begin
            leUrl.text             := '';
            leCmdInfo.text         := '';
            leVersion.text         := '';
            rgCompConfig.itemIndex := -1;
        end;
    end;

    procedure tfFacTotum.formClose(sender: tObject; var action: tCloseAction);
    begin
        sTaskMgr.free;
    end;

    procedure tfFacTotum.refreshSoftwareList;
    var
        software: tList;
        j,
        i:        integer;
        node:     tTreeNode;
        swRec:    swRecord;
    begin
        if not sDBMgr.wasUpdated then
            exit;

        tvSoftware.items.clear;

        software := sDBMgr.getSoftwareList;

        for i := 0 to pred(software.count) do
        begin
            swRec := swRecord(software.items[i]);

            if swRec.hasValidCommands then
                clbSoftware.items.add(swRec.name);

            node := tvSoftware.items.add(nil, swRec.name);

            if not assigned(swRec.commands) then
                continue;

            for j := 0 to pred(swRec.commands.count) do
                tvSoftware.items.addChild( node, cmdRecord(swRec.commands[j]).name );
        end;
    end;

    procedure tfFacTotum.tvSoftwareMouseDown(sender: tObject; button: tMouseButton; shift: tShiftState; X, Y: integer);
    var
        node: tTreeNode;
    begin
        node := tvSoftware.getNodeAt(X, Y);

        if assigned(node) then
            node.selected := true;
    end;

    procedure tfFacTotum.applicationIdleEvents(sender: tObject; var done: boolean);
    var
        event:  tEvent;
    begin
        if (sEventHdlr.getErrorCache) then
            tLog.imageIndex := tImageIndex(tiEvtErr);

        if not(sEventHdlr.isEventListEmpty) then
            while not(sEventHdlr.isEventListEmpty) do
                with lvEvents.items.add do
                begin
                    event      := sEventHdlr.pullEventFromList;

                    stateIndex := event.eventType;
                    subItems.add(event.eventTime);
                    subItems.add(event.eventDesc);

                    event.free;
                end;

        self.refreshSoftwareList;
    end;

    procedure tfFacTotum.formCreate(sender: tObject);
    begin
        sEventHdlr          := eventHandler.create;
        sTaskMgr            := taskManager.create;
        sUpdateParser       := updateParser.create;
        sDownloadMgr        := downloadManager.create;
        sFileMgr            := fileManager.create;
        sDBMgr              := dbManager.create;

        fFacTotum.left      := (Screen.Width - Width)   div 2;
        fFacTotum.top       := (Screen.Height - Height) div 2;

        fFacTotum.caption   := fFacTotum.caption + ' v' + getFmtFileVersion(application.exeName);

        application.onIdle  := applicationIdleEvents;

        self.refreshSoftwareList;
    end;

    procedure tfFacTotum.pmInsertClick(Sender: TObject);
    var
        taskInsert: tTaskRecordInsert;
        command:    cmdRecord;
    begin
        taskInsert   := tTaskRecordInsert.create;

        command      := cmdRecord.create;

        if assigned(tvSoftware.selected) and assigned(tvSoftware.selected.parent) then
        begin
            taskInsert.tRecord := recordCommand;
            taskInsert.pRecord := command;
            command.swid       := swRecord(sDBMgr.getSoftwareList.items[tvSoftware.selected.parent.index]).guid;
            command.prty       := swRecord(sDBMgr.getSoftwareList.items[tvSoftware.selected.parent.index]).commands.count;
        end
        else
        begin
            taskInsert.tRecord                    := recordSoftware;
            taskInsert.pRecord                    := swRecord.create;
            swRecord(taskInsert.pRecord).name     := '<Nuovo Software>';
            swRecord(taskInsert.pRecord).commands := tList.create;
            command.prty                          := 0;
            swRecord(taskInsert.pRecord).commands.add(command);
        end;

        command.arch := byte(archNone);
        command.name := '<Nuovo Comando>';
        command.vers := '';
        command.cmmd := '<Comando>';
        command.uURL := '';

        sTaskMgr.pushTaskToInput(taskInsert);
    end;

    procedure tfFacTotum.pmSoftwarePopup(Sender: TObject);
    begin
        pmDelete.enabled := false;

        if assigned(tvSoftware.selected) then
        begin
            if assigned(tvSoftware.selected.parent) then
            begin
                pmInsert.caption := 'Inserisci comando';
                pmDelete.caption := 'Elimina comando';
            end
            else
            begin
                pmInsert.caption := 'Inserisci software';
                pmDelete.caption := 'Elimina software';
            end;
            pmDelete.enabled := true;
        end;
    end;

    procedure tfFacTotum.pmDeleteClick(sender: tObject);
    var
        taskDelete: tTaskRecordDelete;
    begin
        taskDelete := tTaskRecordDelete.create;

        if assigned(tvSoftware.selected.parent) then
        begin
            taskDelete.tRecord := recordCommand;
            taskDelete.pRecord := swRecord(sDBMgr.getSoftwareList.items[tvSoftware.selected.parent.index]).commands.items[tvSoftware.selected.Index];
        end
        else
        begin
            taskDelete.tRecord := recordSoftware;
            taskDelete.pRecord := DBRecord(sDBMgr.getSoftwareList.items[tvSoftware.selected.index]);
        end;

        sTaskMgr.pushTaskToInput(taskDelete);
    end;

    procedure tfFacTotum.bClearClick(sender: tObject);
    begin
        lvEvents.items.clear;
        sEventHdlr.clearErrorCache;
        tLog.imageIndex := tImageIndex(tiEvents);
    end;
end.


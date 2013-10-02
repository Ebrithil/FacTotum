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
        pmSwDelete: TMenuItem;
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
    var
        tasku: tTaskRecordUpdate;
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

        tasku := tTaskRecordUpdate.create;
        tasku.field := dbFieldSwName;
        tasku.value := 'Prova2';
        tasku.pRecord := swRecord(sDBMgr.getSoftwareList.First);
        tasku.tRecord := recordSoftware;
        sTaskMgr.pushTaskToInput(tasku);
    end;

    procedure tfFacTotum.pmInsertClick(Sender: TObject);
    var
        taskInsert: tTaskRecordInsert;
    begin
        taskInsert         := tTaskRecordInsert.create;
        taskInsert.tRecord := recordSoftware;
        taskInsert.pRecord := swRecord.create;
        sTaskMgr.pushTaskToInput(taskInsert);
    end;

    procedure tfFacTotum.pmSoftwarePopup(Sender: TObject);
    begin
        if assigned(tvSoftware.selected.parent) then
            pmInsert.caption := 'Inserisci Comando'
        else
            pmInsert.caption := 'Inserisci Software'
    end;

    procedure tfFacTotum.bClearClick(sender: tObject);
    begin
        lvEvents.items.clear;
        sEventHdlr.clearErrorCache;
        tLog.imageIndex := tImageIndex(tiEvents);
    end;
end.


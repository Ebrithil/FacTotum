unit U_Main;

interface

uses
    vcl.controls, vcl.forms, vcl.comCtrls, vcl.stdCtrls, vcl.checkLst, vcl.imgList,
    vcl.extCtrls, vcl.menus, system.sysutils, system.classes, system.uiTypes,

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
        pmSwInsert: TMenuItem;
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

        procedure formCreate(Sender: TObject);
        procedure applicationIdleEvents(Sender: TObject; var Done: Boolean);
        procedure bClearClick(Sender: TObject);
        procedure refreshSoftwareList;
    end;

const
    FH_URL = 'http://www.filehippo.com/';

var
    fFacTotum: tfFacTotum;

implementation

{$R *.dfm}

    procedure tfFacTotum.refreshSoftwareList;
    var
        software: tList;
        j,
        i:        integer;
        node:     tTreeNode;
        swRec:    swRecord;
    begin
        software := sDBMgr.getSoftwareList;

        for i := 0 to pred(software.count) do
        begin
            swRec := swRecord(software.items[i]);

            if swRec.hasValidCommands then
                clbSoftware.items.add(swRec.name);

            node := tvSoftware.items.add(nil, swRec.name);

            for j := 0 to pred(swRec.commands.count) do
                tvSoftware.items.addChild( node, cmdRecord(swRec.commands[j]).name );
        end;
    end;

    procedure tfFacTotum.applicationIdleEvents(Sender: TObject; var Done: Boolean);
    var
          event:  tEvent;
    begin
        if (sEventHdlr.getErrorCache) then
            tLog.imageIndex := tImageIndex(tiEvtErr);

        if not(sEventHdlr.isEventListEmpty) then
            while not(sEventHdlr.isEventListEmpty) do
                with lvEvents.items.add do
                begin
                    event := sEventHdlr.pullEventFromList;

                    stateIndex := event.eventType;
                    subItems.add(event.eventTime);
                    subItems.add(event.eventDesc);

                    event.free;
                end;
    end;

    procedure tfFacTotum.formCreate(sender: tObject);
    begin
        sEventHdlr    := eventHandler.create;
        sTaskMgr      := taskManager.create;
        sUpdateParser := updateParser.create;
        sDownloadMgr  := downloadManager.create;
        sFileMgr      := fileManager.create;
        sDBMgr        := dbManager.create;

        fFacTotum.Left := (Screen.Width - Width)   div 2;
        fFacTotum.Top  := (Screen.Height - Height) div 2;

        fFacTotum.Caption:= fFacTotum.caption + ' v' + getFmtFileVersion(application.exeName);

        application.OnIdle := applicationIdleEvents;

        self.refreshSoftwareList;
    end;

    procedure tfFacTotum.bClearClick(Sender: TObject);
    begin
        lvEvents.items.clear;
        sEventHdlr.clearErrorCache;
        tLog.imageIndex := tImageIndex(tiEvents);
    end;
end.


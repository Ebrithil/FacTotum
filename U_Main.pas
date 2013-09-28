unit U_Main;

interface

uses
    vcl.controls, vcl.forms, vcl.comCtrls, vcl.stdCtrls, vcl.checkLst, vcl.imgList,
    vcl.extCtrls, vcl.menus, system.sysutils, system.classes, system.uiTypes,

    U_DataBase, U_Functions, U_Classes;

type
    TF_FacTotum = class(tForm)
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

    end;

const
    FH_URL = 'http://www.filehippo.com/';

var
    F_FacTotum: tF_FacTotum;

implementation

{$R *.dfm}

    procedure TF_FacTotum.applicationIdleEvents(Sender: TObject; var Done: Boolean);
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

    procedure TF_FacTotum.formCreate(sender: tObject);
    begin
        sEventHdlr      :=  eventHandler.create;
        sTaskMgr        :=  taskManager.create;
        sDbManager      :=  dbManager.create;
        sUpdateParser   :=  updateParser.create;

        F_FacTotum.Left := (Screen.Width - Width)   div 2;
        F_FacTotum.Top  := (Screen.Height - Height) div 2;

        F_FacTotum.Caption:= F_FacTotum.Caption + ' v' + GetFmtFileVersion(Application.ExeName);

        Application.OnIdle := ApplicationIdleEvents;
    end;

    procedure TF_FacTotum.bClearClick(Sender: TObject);
    begin
        lvEvents.items.clear;
        sEventHdlr.clearErrorCache;
        tLog.imageIndex := tImageIndex(tiEvents);
    end;
end.


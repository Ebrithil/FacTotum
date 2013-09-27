unit U_Main;

interface

uses
    vcl.controls, vcl.forms, vcl.comCtrls, vcl.stdCtrls, vcl.checkLst,
    vcl.extCtrls, vcl.menus, system.sysutils,

    U_DataBase, U_Functions, U_Classes, Vcl.ImgList, System.Classes, System.UITypes;

type
    TF_FacTotum = class(tForm)
        TABs: TPageControl;
        tInstaller: TTabSheet;
        tConfiguration: TTabSheet;
        tUpdate: TTabSheet;
        PB_Progress: TProgressBar;
        L_InstallInfo: TLabel;
        CLB_Software: TCheckListBox;
        IL_FacTotum: TImageList;
        TV_Software: TTreeView;
        RG_CompatibilityConfig: TRadioGroup;
        LE_CmdInfo: TLabeledEdit;
        PM_Software: TPopupMenu;
        PM_Software_Insert: TMenuItem;
        PM_Software_Delete: TMenuItem;
        CLB_Download: TCheckListBox;
        L_DownloadInfo: TLabel;
        PB_Download: TProgressBar;
        LE_Versione: TLabeledEdit;
        LE_Url: TLabeledEdit;
        PM_Set_Main_Command: TMenuItem;
        L_Progress: TLabel;
        tLog: TTabSheet;
        lSetupPercentage: TLabel;
        bInstall: TButton;
        bUpdate: TButton;
        lvEvents: TListView;
        bClear: TButton;

        procedure formCreate(Sender: TObject);
        procedure applicationIdleEvents(Sender: TObject; var Done: Boolean);
        procedure bClearClick(Sender: TObject);

    end;

const
    FH_URL         = 'http://www.filehippo.com/';

var
    F_FacTotum: tF_FacTotum;

implementation

{$R *.dfm}

    procedure TF_FacTotum.applicationIdleEvents(Sender: TObject; var Done: Boolean);
    var
          event:  tEvent;
          iEvent: tListItem;
    begin
        if (sEventHdlr.getErrorCache) then
            tLog.imageIndex := tImageIndex(EvtErr);

        if not(sEventHdlr.isEventListEmpty) then
            while not(sEventHdlr.isEventListEmpty) do
            begin
                iEvent := lvEvents.items.add;
                event := sEventHdlr.pullEventFromList;
                iEvent.stateIndex := event.imageType;
                iEvent.subItems.add(event.value);
                event.free;
            end;
    end;

    procedure TF_FacTotum.formCreate(sender: tObject);
    begin
        sEventHdlr      :=  eventHandler.create;
        sTaskMgr        :=  taskManager.create;
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
        tLog.imageIndex := tImageIndex(Events);
    end;

end.


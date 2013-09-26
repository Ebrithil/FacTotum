unit U_Main;

interface

uses
    vcl.controls, vcl.forms, vcl.comCtrls, vcl.stdCtrls, vcl.checkLst,
    vcl.extCtrls, vcl.menus, system.sysutils,

    U_DataBase, U_Functions, U_Classes, Vcl.ImgList, System.Classes;

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
        procedure ApplicationIdleEvents(Sender: TObject; var Done: Boolean);
    procedure bClearClick(Sender: TObject);

    end;

const
    FH_URL  = 'http://www.filehippo.com/';

var
    F_FacTotum: tF_FacTotum;

implementation

{$R *.dfm}

    procedure TF_FacTotum.ApplicationIdleEvents(Sender: TObject; var Done: Boolean);
    var
          error:  exception;
          iEvent: tListItem;
    begin
          if not(sErrorHdlr.isErrorListEmpty) then
          begin
              tLog.imageIndex := 4;
              while not(sErrorHdlr.isErrorListEmpty) do
              begin
                  iEvent := lvEvents.items.add;
                  error := sErrorHdlr.pullErrorFromList;
                  iEvent.subItems.add( error.className + ': ' + error.message );
                  //iEvent.ImageIndex :=
              end;
          end;
    end;

    procedure TF_FacTotum.formCreate(sender: tObject);
    begin
        sErrorHdlr      :=  errorHandler.create;
        sUpdateParser   :=  updateParser.create;

        F_FacTotum.Left := (Screen.Width - Width)   div 2;
        F_FacTotum.Top  := (Screen.Height - Height) div 2;

        F_FacTotum.Caption:= F_FacTotum.Caption + ' v' + GetFmtFileVersion(Application.ExeName);

        Application.OnIdle := ApplicationIdleEvents;
    end;

    procedure TF_FacTotum.bClearClick(Sender: TObject);
    begin
        lvEvents.items.clear;
    end;

end.


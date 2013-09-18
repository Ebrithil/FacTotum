unit U_Main;

interface

uses
    vcl.controls, vcl.forms, vcl.comCtrls, vcl.stdCtrls, vcl.checkLst,
    vcl.extCtrls, vcl.menus,

    U_DataBase, U_Functions, U_Classes, U_Events, Vcl.ImgList, System.Classes;

type
    TF_FacTotum = class(tForm)
        TABs: TPageControl;
        TS_Installer: TTabSheet;
        TS_Configuration: TTabSheet;
        TS_Update: TTabSheet;
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
        BTN_Install: TButton;
        CLB_Download: TCheckListBox;
        L_DownloadInfo: TLabel;
        PB_Download: TProgressBar;
        BTN_Update: TButton;
        LE_Versione: TLabeledEdit;
        LE_Url: TLabeledEdit;
        PM_Set_Main_Command: TMenuItem;
        L_Progress: TLabel;
        BTN_Check: TButton;

        procedure formCreate(Sender: TObject);

    end;

const
    FH_URL  = 'http://www.filehippo.com/';

var
    F_FacTotum: tF_FacTotum;

implementation

{$R *.dfm}

procedure TF_FacTotum.formCreate(sender: tObject);
begin
    sErrorHdlr      :=  errorHandler.create;
    sUpdateParser   :=  updateParser.create;

    F_FacTotum.Left := (Screen.Width - Width)   div 2;
    F_FacTotum.Top  := (Screen.Height - Height) div 2;

    fEvents         :=  TfEvents.create(self);
    fEvents.show;

    F_FacTotum.Caption:= F_FacTotum.Caption + ' v' + GetFmtFileVersion(Application.ExeName);
end;

end.


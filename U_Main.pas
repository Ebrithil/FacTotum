unit U_Main;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.ComCtrls, Vcl.StdCtrls,
  Vcl.ImgList, Vcl.CheckLst, Vcl.ExtCtrls, Vcl.Menus, Data.DbxSqlite, Data.DB,
  Data.SqlExpr, Data.FMTBcd, MSHTML, IdURI, IdBaseComponent, IdComponent,
  IdTCPConnection, IdTCPClient, IdHTTP, ActiveX, StrUtils, System.SyncObjs,

  U_DataBase, U_Functions, U_Classes, U_Events;

type
  TF_FacTotum = class(TForm)
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
    SQL_Connection: TSQLConnection;
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
    IdHTTP: TIdHTTP;

    procedure FormCreate(Sender: TObject);
    procedure trvSoftwareCreateNode(Sender: TCustomTreeView; var NodeClass: TTreeNodeClass);
    procedure BTN_InstallClick(Sender: TObject);
    procedure TABsChanging(Sender: TObject; var AllowChange: Boolean);
    procedure TV_SoftwareChanging(Sender: TObject; Node: TTreeNode;
      var AllowChange: Boolean);
    procedure LoadDataBase;
    procedure LoadSoftwares;
    procedure LoadInstall;
    procedure LoadConfig;
    procedure ReloadConfig;
    procedure AnalyzeSelectedNode;
    procedure ConfigCheck;
    procedure TABsChange(Sender: TObject);
    procedure PM_Software_DeleteClick(Sender: TObject);
    procedure PM_Software_InsertClick(Sender: TObject);
    procedure TV_SoftwareChange(Sender: TObject; Node: TTreeNode);
    procedure TV_SoftwareDragDrop(Sender, Source: TObject; X, Y: Integer);
    procedure TV_SoftwareDragOver(Sender, Source: TObject; X, Y: Integer;
      State: TDragState; var Accept: Boolean);
    procedure ChangeOn;
    procedure ChangeOff;
    procedure PM_Set_Main_CommandClick(Sender: TObject);
    procedure CheckForUpdates;
    procedure IdHTTPRedirect(Sender: TObject; var dest: string;
      var NumRedirect: Integer; var Handled: Boolean; var VMethod: string);
    procedure IdHTTPWork(ASender: TObject; AWorkMode: TWorkMode;
      AWorkCount: Int64);
    procedure IdHTTPWorkBegin(ASender: TObject; AWorkMode: TWorkMode;
      AWorkCountMax: Int64);
    procedure IdHTTPWorkEnd(ASender: TObject; AWorkMode: TWorkMode);
    procedure BTN_UpdateClick(Sender: TObject);
    procedure DownloadFile(prg, url: String; DLLink: Boolean);

    function ParseUrl(lbl, url: String): ArrayReturn;
    procedure BTN_CheckClick(Sender: TObject);

    procedure fillEvents(Sender: TObject; var Done: Boolean);
  public

  end;

const
  FH_URL  = 'http://www.filehippo.com/';
  Retries = 3;

var
  F_FacTotum:           TF_FacTotum;

  StartingPoint:        TPoint;
  database:             TDatabase;
  resSoftware:          TDataSet;
  resSoftwareFilter:    TDataSet;
  softwareCountFilter:  Integer;
  resInstall:           TDataSet;
  resComandi:           TDataSet;
  trnMain:              TTreeNode;
  trnChild:             TTreeNode;
  trnOrder:             TTreeNode;
  vetInstall:           Array of Array of String;
  vetUpdate:            Array of Array of String;
  SelectedNode:         TSoftwareTreeNode;
  architecture:         Integer;
  lastInsert:           Integer;

implementation

{$R *.dfm}

procedure TF_FacTotum.fillEvents(Sender: TObject; var Done: Boolean);
var
    error:  Exception;
    iError: TListItem;
begin
    while not(sErrorHdlr.isErrorListEmpty) do
    begin
        error := sErrorHdlr.pullErrorFromList;
        iError := fEvents.lvEvents.items.add;
        iError.subItems.add( error.ClassName + ': ' + error.Message );
    end;
end;

procedure TF_FacTotum.FormCreate(Sender: TObject);
begin
  sErrorHdlr := errorHandler.create;

  F_FacTotum.Left := (Screen.Width - Width)   div 2;
  F_FacTotum.Top  := (Screen.Height - Height) div 2;

  sUpdateParser := updateParser.create;

  fEvents := TfEvents.create(self);
  fEvents.show;

  Application.OnIdle := self.fillEvents;

  ShowMessage(sUpdateParser.getLastStableLink('http://www.filehippo.com/it/download_google_chrome/'));

  {lastInsert := -1;

  sTaskMgr := taskManager.create;

  //architettura: 1 := x86 / 2 := x64
  architecture:=GetExBits;

  //database
  LoadDataBase;

  //dataset software
  LoadSoftwares;

  //installazione
  LoadInstall;

  //configurazione
  LoadConfig;
  ChangeOn;

  //check items number
  ConfigCheck;

  TABs.ActivePageIndex := 0;
  SelectedNode := nil;
  }

  F_FacTotum.Caption:= F_FacTotum.Caption + ' v' + GetFmtFileVersion(Application.ExeName);
end;

procedure TF_FacTotum.LoadDataBase;
begin
  database := TDatabase.Create(SQL_Connection);
  database.Connect(SQL_Connection.Params.Values['Database']);
end;

procedure TF_FacTotum.LoadSoftwares;
var
resCount: TDataSet;
begin
  resSoftware := database.QueryRes('SELECT * FROM software');

  resSoftwareFilter := database.QueryRes('SELECT * FROM software WHERE ID IN (SELECT DISTINCT software FROM commands WHERE compatibility IN (0, ' + architecture.ToString + '))');
  resCount := database.QueryRes('SELECT COUNT(*) FROM software WHERE ID IN (SELECT DISTINCT software FROM commands WHERE compatibility IN (0, ' + architecture.ToString + '))');
  resCount.First;
  softwareCountFilter := resCount.Fields[0].AsInteger;
end;

procedure TF_FacTotum.LoadInstall;
var
i, j: Integer;
begin
  CLB_Software.Items.Clear;
  L_InstallInfo.Caption := 'Loading Softwares';
  resSoftwareFilter.First;
  PB_Progress.Max := softwareCountFilter;
  SetLength(vetInstall, softwareCountFilter);
  for i := 1 to softwareCountFilter do
  begin
    resInstall := database.QueryRes('SELECT command FROM commands WHERE software='+resSoftwareFilter.Fields[0].AsString + ' AND compatibility IN (0, ' + architecture.ToString + ') ORDER BY [order]');
    if resInstall.RecordCount <> 0 then
    begin
      CLB_Software.Items.Add(resSoftwareFilter.Fields[1].AsString);
      resInstall.First;
      SetLength(vetInstall[i - 1], resInstall.RecordCount);
      for j := 1 to resInstall.RecordCount do
      begin
        vetInstall[i - 1, j - 1] := resInstall.Fields[0].AsString;
        resInstall.Next;
      end;
    end;

    PB_Progress.Position := i;
    resSoftwareFilter.Next;
  end;
  L_InstallInfo.Caption := 'Loading Completed';
end;

procedure TF_FacTotum.LoadConfig;
var
i, j: Integer;
begin
  TV_Software.Items.Clear;
  resSoftware.First;
  for i := 1 to resSoftware.RecordCount do
  begin
    trnMain:=TV_Software.Items.Add(nil, resSoftware.Fields[1].AsString);
    resComandi := database.QueryRes('SELECT * FROM commands WHERE software=' + resSoftware.Fields[0].AsString + ' ORDER BY [order]');
    TSoftwareTreeNode(trnMain).SoftwareID:=resSoftware.Fields[0].AsInteger;
    TSoftwareTreeNode(trnMain).CommandID:=-1;
    TSoftwareTreeNode(trnMain).Software:=resSoftware.Fields[1].AsString;
    TSoftwareTreeNode(trnMain).version:=database.GetSWVersion(resSoftware.Fields[0].AsInteger);
    TSoftwareTreeNode(trnMain).Command:='';
    TSoftwareTreeNode(trnMain).MainCommand:=resSoftware.Fields[2].AsInteger;
    resComandi.First;
    for j := 1 to resComandi.RecordCount do
    begin
      trnChild := TV_Software.Items.Add(nil, resComandi.Fields[3].AsString);
      TSoftwareTreeNode(trnChild).CommandID:=resComandi.Fields[0].AsInteger;
      TSoftwareTreeNode(trnChild).SoftwareID:=resComandi.Fields[1].AsInteger;
      TSoftwareTreeNode(trnChild).Order:=resComandi.Fields[2].AsInteger;
      TSoftwareTreeNode(trnChild).description:=resComandi.Fields[3].AsString;
      TSoftwareTreeNode(trnChild).Command:=resComandi.Fields[4].AsString;
      TSoftwareTreeNode(trnChild).version:=resComandi.Fields[5].AsString;
      TSoftwareTreeNode(trnChild).Compatibility:=resComandi.Fields[6].AsInteger;
      TSoftwareTreeNode(trnChild).URL:=resComandi.Fields[7].AsString;
      trnChild.MoveTo(trnMain, naAddChild);
      resComandi.Next;
    end;

    if TSoftwareTreeNode(trnMain).SoftwareID = lastInsert then
      begin
        trnMain.Expand(False);
      end
    else
      begin
        trnMain.Collapse(False);
      end;
    resSoftware.Next;
  end;
end;

procedure TF_FacTotum.ReloadConfig;
begin
  ChangeOff;
  LoadSoftwares;
  LoadConfig;
  ChangeOn;
end;

procedure TF_FacTotum.BTN_InstallClick(Sender: TObject);
var
  i, j: Integer;
begin
  BTN_Install.Enabled := False;
  for i := 1 to CLB_Software.Count do
  begin
    if CLB_Software.Checked[i - 1] then
    begin
      PB_Progress.Max := Length(vetInstall[i - 1]);
      PB_Progress.Position := 0;
      for j := 1 to Length(vetInstall[i - 1]) do
      begin
        L_InstallInfo.Caption := BuildPBText(CLB_Software.Items[i - 1], j, Length(vetInstall[i - 1]));
        ExecuteCommandAndWait(vetInstall[i - 1, j - 1]);
        PB_Progress.Position := j;
      end;
    end;
  end;
  L_InstallInfo.Caption := 'Installation Completed';
  BTN_Install.Enabled := True;
end;

procedure TF_FacTotum.trvSoftwareCreateNode(Sender: TCustomTreeView; var NodeClass: TTreeNodeClass);
begin
  NodeClass := TSoftwareTreeNode;
end;

procedure TF_FacTotum.TABsChange(Sender: TObject);
begin
  if (Sender as TPageControl).ActivePage = TS_Installer then
  begin
    LoadSoftwares;
    LoadInstall;
  end;

  if (Sender as TPageControl).ActivePage = TS_Configuration then
    ReloadConfig;
end;

procedure TF_FacTotum.TABsChanging(Sender: TObject; var AllowChange: Boolean);
begin
  if (Sender as TPageControl).ActivePage = TS_Configuration then
  begin
    AnalyzeSelectedNode;
    SelectedNode := nil;
  end;
end;

procedure TF_FacTotum.TV_SoftwareChange(Sender: TObject; Node: TTreeNode);
begin
  SelectedNode := TSoftwareTreeNode(Node);
  LE_Versione.Visible := True;
  case SelectedNode.Level of
    0:
    begin
      LE_CmdInfo.Visible := False;
      LE_Versione.Text := SelectedNode.version;
      LE_Url.Visible := False;
      RG_CompatibilityConfig.Visible := False;
      RG_CompatibilityConfig.ItemIndex := -1;
      PM_Software_Insert.Caption := 'Inserisci Software';
      PM_Software_Delete.Caption := 'Elimina Software';
      PM_Set_Main_Command.Visible := False;
    end;
    1:
    begin
      LE_CmdInfo.Visible := True;
      LE_CmdInfo.Text := SelectedNode.Command;
      LE_Versione.Text := SelectedNode.version;
      LE_Url.Visible := True;
      LE_Url.Text := SelectedNode.URL;
      RG_CompatibilityConfig.Visible := True;
      RG_CompatibilityConfig.ItemIndex := SelectedNode.Compatibility;
      PM_Software_Insert.Caption := 'Inserisci Comando';
      PM_Software_Delete.Caption := 'Elimina Comando';
      PM_Set_Main_Command.Visible := True;
      if SelectedNode.CommandID = TSoftwareTreeNode(SelectedNode.Parent).MainCommand then
        PM_Set_Main_Command.Enabled := False
      else
        PM_Set_Main_Command.Enabled := True;
    end;
  end;
end;

procedure TF_FacTotum.TV_SoftwareChanging(Sender: TObject; Node: TTreeNode;
  var AllowChange: Boolean);
begin
  if SelectedNode <> nil then
    AnalyzeSelectedNode;
end;

procedure TF_FacTotum.AnalyzeSelectedNode;
begin
  if SelectedNode <> nil then
  begin
    case SelectedNode.Level of
      0:
      begin
        if SelectedNode.Software <> SelectedNode.Text then
        begin
          SelectedNode.Software := SelectedNode.Text;
          database.UpdateSoftwareByNode(SelectedNode);
        end;
      end;
      1:
      begin
        if (SelectedNode.Command <> LE_CmdInfo.Text) OR (SelectedNode.Compatibility <> RG_CompatibilityConfig.ItemIndex) OR (SelectedNode.description <> SelectedNode.Text) OR (SelectedNode.URL <> LE_Url.Text) then
        begin
          SelectedNode.Command := LE_CmdInfo.Text;
          SelectedNode.Compatibility := RG_CompatibilityConfig.ItemIndex;
          SelectedNode.description := SelectedNode.Text;
          SelectedNode.URL := LE_Url.Text;
          database.UpdateCommandByNode(SelectedNode);
        end;
      end;
    end;
  end;
end;

procedure TF_FacTotum.PM_Software_InsertClick(Sender: TObject);
var
  swId: Integer;
  resS: TDataSet;
begin
  if (TV_Software.Items.Count = 0) OR (SelectedNode = nil) then
    begin
      database.AddSoftware('new software', 0);
      swId := database.GetLastId('software');
      database.AddCommand(swId, 1, 0, 'new command', 'command', '0.0', FH_URL);
      database.UpdateSoftware(swId, 'new software', database.GetLastId('commands'));
      lastInsert := swId;
    end
  else
    begin
      case SelectedNode.Level of
        0:
        begin
          database.AddSoftware('new software', 0);
          swId := database.GetLastId('software');
          database.AddCommand(swId, 1, 0, 'new command', 'command', '0.0', FH_URL);
          database.UpdateSoftware(swId, 'new software', database.GetLastId('commands'));
          lastInsert := swId;
        end;
        1:
        begin
          resS := database.QueryRes('SELECT MAX([order]) FROM commands WHERE software = ' + SelectedNode.SoftwareID.ToString());
          resS.First;
          database.AddCommand(SelectedNode.SoftwareID, resS.Fields[0].AsInteger + 1, 0, 'new command', 'command', '0.0', FH_URL);
          lastInsert := SelectedNode.SoftwareID;
        end;
      end;
    end;

  ReloadConfig;
  ConfigCheck;
end;

procedure TF_FacTotum.PM_Software_DeleteClick(Sender: TObject);
var
  i, index: Integer;
  res:  String;
begin
ChangeOff;
if SelectedNode <> nil then
begin
  case SelectedNode.Level of
    0:
    begin
      index := SelectedNode.SoftwareID;
      for i := 0 to TV_Software.Items.Count - 1 do
      begin
        if TSoftwareTreeNode(TV_Software.Items[i]).SoftwareID = index then
        begin
          TV_Software.Items[i].Delete;
          Break;
        end;
      end;
      database.DeleteSoftware(index);
    end;
    1:
    begin
      index := SelectedNode.CommandID;
      res := database.DeleteCommand(index, SelectedNode.SoftwareID);
      for i := 0 to TV_Software.Items.Count - 1 do
      begin
        if TSoftwareTreeNode(TV_Software.Items[i]).CommandID = index then
        begin
          if res = 'DEL' then
            begin
              TV_Software.Items.Delete(TV_Software.Items[i].Parent);
            end
          else
            begin
              TV_Software.Items[i].Delete;
            end;

          Break;
        end;
      end;
    end;
  end;
end;

LoadSoftwares;
LoadConfig;
ChangeOn;

SelectedNode := TSoftwareTreeNode(TV_Software.Selected);
ConfigCheck;
end;

procedure TF_FacTotum.PM_Set_Main_CommandClick(Sender: TObject);
begin
  database.UpdateSoftware(SelectedNode.SoftwareID, TSoftwareTreeNode(SelectedNode.Parent).Software, SelectedNode.CommandID);
  TSoftwareTreeNode(SelectedNode.Parent).version := SelectedNode.version;
  TSoftwareTreeNode(SelectedNode.Parent).MainCommand := SelectedNode.CommandID;
end;

procedure TF_FacTotum.ConfigCheck;
begin
  if TV_Software.Items.Count = 0 then
    PM_Software_Delete.Enabled := False
  else
    PM_Software_Delete.Enabled := True;
end;

procedure TF_FacTotum.TV_SoftwareDragOver(Sender, Source: TObject; X,
  Y: Integer; State: TDragState; var Accept: Boolean);
var
  Moving, Target: TTreeNode;
begin
  Accept := False;
  Moving := TV_Software.Selected;
  Target := TV_Software.GetNodeAt(X, Y);

  if Moving.Level = Target.Level then
    Accept := True;

end;

procedure TF_FacTotum.TV_SoftwareDragDrop(Sender, Source: TObject; X,
  Y: Integer);
var
  Moving, Target: TTreeNode;
begin
  Moving := TV_Software.Selected;
  Target := TV_Software.GetNodeAt(X, Y);
  TSoftwareTreeNode(Moving).Order := TSoftwareTreeNode(Target).Order;
  TSoftwareTreeNode(Moving).SoftwareID := TSoftwareTreeNode(Target).SoftwareID;
  database.MoveCommandsForward(TSoftwareTreeNode(Moving).SoftwareID, TSoftwareTreeNode(Moving).Order);
  database.UpdateCommandByNode(TSoftwareTreeNode(Moving));

  Moving.MoveTo(Target, naInsert);
end;

procedure TF_FacTotum.ChangeOn;
begin
  TV_Software.OnChange := TV_SoftwareChange;
  TV_Software.OnChanging := TV_SoftwareChanging;
end;

procedure TF_FacTotum.ChangeOff;
begin
  TV_Software.OnChange := nil;
  TV_Software.OnChanging := nil;
end;

procedure TF_FacTotum.CheckForUpdates;
var
  res: TDataSet;
  i, count: Integer;
  s: ArrayReturn;
  temp: String;
begin
  CLB_Download.Items.Clear;
  BTN_Update.Enabled := False;
  count := 0;
  res := database.QueryRes('SELECT software, label, version, updateurl, ID FROM commands ORDER BY commands.software, commands.[order]');
  res.First;
  for i := 0 to res.RecordCount - 1 do
  begin
    temp := database.GetSWNameById(res.Fields[0].AsInteger) + ': ' + res.Fields[1].AsString;
    L_DownloadInfo.Caption := 'Controllo Aggiornamenti ' + temp;
    s := ParseUrl(res.Fields[1].AsString, res.Fields[3].AsString);
    if ExtractVersion(s[0]) > res.Fields[2].AsString then
    begin
      SetLength(vetUpdate, count + 1);
      SetLength(vetUpdate[count], 5);
      vetUpdate[count, 0] := temp;
      vetUpdate[count, 1] := s[1];
      vetUpdate[count, 2] := s[2];
      vetUpdate[count, 3] := res.Fields[4].AsString;
      vetUpdate[count, 4] := ExtractVersion(s[0]);
      CLB_Download.Items.Add(temp);
      count := count + 1;
    end;
    res.Next;
  end;

  if CLB_Download.Items.Count = 0 then
  begin
    L_DownloadInfo.Caption := 'Nessun Nuovo Aggiornamento';
    BTN_Check.Enabled := True;
  end
  else
  begin
    L_DownloadInfo.Caption := 'Nuovi Aggiornamenti Disponibili';
    BTN_Check.Enabled := False;
    BTN_Update.Enabled := True;
  end;

end;

procedure TF_FacTotum.BTN_CheckClick(Sender: TObject);
begin
  CheckForUpdates;
end;

procedure TF_FacTotum.BTN_UpdateClick(Sender: TObject);
var
  i: Integer;
begin
  BTN_Update.Enabled := False;

  for i := 0 to CLB_Download.Count - 1 do
  begin
    if CLB_Download.Checked[i] then
    begin
      L_DownloadInfo.Caption := 'Download Aggiornamento ' + CLB_Download.Items[i];
      if vetUpdate[i, 2] = '0' then
      begin
        DownloadFile(CLB_Download.Items[i], vetUpdate[i, 1], True);
      end
      else
      begin
        DownloadFile(CLB_Download.Items[i], vetUpdate[i, 1], False);
      end;
      database.UpdateCmdVersion(vetUpdate[i, 3], vetUpdate[i, 4].Trim);
    end;
  end;

  CheckForUpdates;
end;

procedure TF_FacTotum.IdHTTPRedirect(Sender: TObject; var dest: string;
  var NumRedirect: Integer; var Handled: Boolean; var VMethod: string);
begin
  dest:= TIdURI.URLEncode(dest);
end;

procedure TF_FacTotum.IdHTTPWork(ASender: TObject; AWorkMode: TWorkMode;
  AWorkCount: Int64);
begin
  PB_Download.Position:= AWorkCount;
  L_Progress.Caption:= IntToStr(Trunc( (PB_Download.Position / PB_Download.Max) * 100)) + '%';
  Application.ProcessMessages;
end;

procedure TF_FacTotum.IdHTTPWorkBegin(ASender: TObject; AWorkMode: TWorkMode;
  AWorkCountMax: Int64);
begin
  PB_Download.Max:= AWorkCountMax;
end;

procedure TF_FacTotum.IdHTTPWorkEnd(ASender: TObject; AWorkMode: TWorkMode);
begin
  PB_Download.Position:= PB_Download.Max;
end;

function TF_FacTotum.ParseUrl(lbl, url: String): ArrayReturn;
var
  FHSource:     IHTMLDocument2;
  i, k:         Word;
  Cache:        String;
  V, FHTags,
  FHVerTable:   OleVariant;
  DlVerLinks:   array of array of String;
  vet:          ArrayReturn;
begin
  // Store HTMl Source into IHTMLDocument2
  Cache:= IdHTTP.Get(url);
  IdHTTP.Disconnect;
  FHSource:= coHTMLDocument.Create as IHTMLDocument2;
  V:= VarArrayCreate([0,0], varVariant);
  V[0]:= Cache;
  FHSource.Write(PSafeArray(TVarData(v).VArray));
  FHSource.Close;

  // Find FileHippo DL Table
  FHTags:= FHSource.all.tags('div');
  for i := 0 to FHTags.Length - 1 do
    begin
      if FHTags.Item(i).ID = 'dlbox' then
        begin
          FHVerTable:= FHTags.Item(i);
          Break;
        end;
    end;

  // Prepare to parse table
  Cache:= FHVerTable.innerHTML;
  FHSource:= coHTMLDocument.Create as IHTMLDocument2;
  V:= VarArrayCreate([0,0], varVariant);
  V[0]:= Cache;
  FHSource.Write(PSafeArray(TVarData(v).VArray));
  FHSource.Close;

  // Reset links array
  SetLength(DlVerLinks, 0, 0);

  // Find download links and names
  FHTags:= FHSource.all.tags('a');
  for i := 0 to FHTags.Length - 1 do
    if not( AnsiContainsText(FHTags.Item(i).innerText, 'Ultima Versione') ) and
       not( AnsiContainsText(FHTags.Item(i).innerText, 'Vedi di') ) then
      begin
        SetLength(DlVerLinks, Length(DlVerLinks) + 1, 2);

        DlVerLinks[Length(DlVerLinks) - 1, 0]:= Trim(FHTags.Item(i).href);
        DlVerLinks[Length(DlVerLinks) - 1, 1]:= Trim(FHTags.Item(i).innerText);
      end;
  FHTags:= FHSource.all.tags('b');
  for i := 0 to FHTags.Length - 1 do
    if not( AnsiEndsStr('MB', Trim(FHTags.Item(i).innerText)) ) and
       not( AnsiEndsStr('KB', Trim(FHTags.Item(i).innerText)) ) and
       not( AnsiContainsText(FHTags.Item(i).innerText, 'Ultima Versione') ) then
      begin
        for k := 0 to Length(DlVerLinks) - 1 do
          if DlVerLinks[k, 1] = '' then
            begin
              DlVerLinks[k, 1]:= Trim(FHTags.Item(i).innerText);
              Break;
            end;
        Break;
      end;

  // Get Last Non-Beta Version
  for i := 0 to Length(DlVerLinks) - 1 do
    begin
      if NOT AnsiContainsText(DlVerLinks[i,1],'BETA') OR
         NOT AnsiContainsText(DlVerLinks[i,1],'DEV') OR
         NOT AnsiContainsText(DlVerLinks[i,1],'ALPHA') then
      begin
        vet[0] := DlVerLinks[i,1].Trim;
        vet[1] := AnsiReplaceStr(DlVerLinks[i,0], 'about:/', FH_URL);
        vet[2] := i.ToString();
        Result := vet;
        Break;
      end;
    end;
end;

procedure TF_FacTotum.DownloadFile(prg, url: string; DLLink: Boolean);
var
  FHSource:     IHTMLDocument2;
  i:            Word;
  Cache:        String;
  MS:           TMemoryStream;
  V, FHTags,
  FHVerTable:   OleVariant;
  saveDialog:   TSaveDialog;
begin
  // Store HTMl Source into IHTMLDocument2
  Cache:= IdHTTP.Get(url);
  IdHTTP.Disconnect;
  FHSource:= coHTMLDocument.Create as IHTMLDocument2;
  V:= VarArrayCreate([0,0], varVariant);
  V[0]:= Cache;
  FHSource.Write(PSafeArray(TVarData(v).VArray));
  FHSource.Close;

  // Catch redirect URL and download file
  if DLLink then
    begin
      FHTags:= FHSource.all.tags('meta');
      for i := 0 to FHTags.Length - 1 do
        if AnsiContainsText(FHTags.Item(i).content, 'url') then
          begin
            Cache:= Trim(FHTags.Item(i).content);
            Delete( Cache, 1, AnsiPos('=', Cache) );
            Cache:= FH_URL + Cache;
          end;

      saveDialog := TSaveDialog.Create(Self);
      saveDialog.Title := 'Salvataggio File ' + prg;
      saveDialog.Filter := 'Eseguibile|*.exe';
      saveDialog.DefaultExt := 'exe';
      saveDialog.FilterIndex := 1;

      if saveDialog.Execute then
      begin
        MS:= TMemoryStream.Create;
        IdHTTP.Get(Cache, MS);
        IdHTTP.Disconnect;
        MS.SaveToFile(saveDialog.FileName);
        MS.Free;
      end
      else
      begin
        ShowMessage('Download annullato per ' + prg);
      end;

    end
  // Find correct download link
  else
    begin
      // Recover download links table
      FHTags:= FHSource.all.tags('div');
      for i := 0 to FHTags.Length - 1 do
        begin
          if FHTags.Item(i).ID = 'dlbox' then
            begin
              FHVerTable:= FHTags.Item(i);
              Break;
            end;
        end;

      // Prepare to parse table
      Cache:= FHVerTable.innerHTML;
      FHSource:= coHTMLDocument.Create as IHTMLDocument2;
      V:= VarArrayCreate([0,0], varVariant);
      V[0]:= Cache;
      FHSource.Write(PSafeArray(TVarData(v).VArray));
      FHSource.Close;

      // Find download links and names
      FHTags:= FHSource.all.tags('a');
      for i := 0 to FHTags.Length - 1 do
        if AnsiContainsText(FHTags.Item(i).innerText, 'Questa Versione') then
          DownloadFile( prg, Trim(FHTags.Item(i).href), True );
    end;
end;

end.

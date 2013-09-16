unit U_DataBase;

interface

uses
  Windows, System.SysUtils, System.UITypes, Vcl.Dialogs, Data.DB, Data.SqlExpr, U_Classes;

type
  TDatabase = class
  private
    Connector: TSQLConnection;
    function IsNumeric(Value: string; const AllowFloat: Boolean;
                       const TrimWhiteSpace: Boolean = True): Boolean;
  public
    Constructor Create(DBConn : TSQLConnection);

    procedure Disconnect;
    procedure RebuildStructure;

    function Connect(DBFile: String): Boolean;
    function CheckStructure: Boolean;
    function Query(QString: String): Boolean;
    function QueryRes(QString: String): TDataSet;
    function FieldValueExists(Table, Field, Value: String): Boolean;

    function AddSoftware(name: String; maincommand: Integer): Boolean;
    function AddCommand(software, order, compatibility: Integer; clabel, command, version, url: String): Boolean;

    function UpdateSoftware(id: Integer; name: String; maincommand: Integer): Boolean;
    function UpdateSoftwareByNode(node: TSoftwareTreeNode): Boolean;
    function UpdateCommand(id, software, order, compatibility: Integer; clabel, command, url: String): Boolean;
    function UpdateCommandByNode(node: TSoftwareTreeNode): Boolean;

    function DeleteSoftware(id: Integer): Boolean;
    function DeleteCommand(id, softwareId: Integer): String;

    function GetLastId(table: String): Integer;
    function MoveCommandsForward(software, order: Integer): Boolean;
    function GetSWVersion(id: Integer): String;
    function GetSWNameById(id: Integer): String;
    function UpdateCmdVersion(id, version: String): Boolean;
  end;

implementation

// Start Implementation of TDatabase Class
//------------------------------------------------------------------------------

function TDatabase.IsNumeric(Value: string; const AllowFloat: Boolean;
                             const TrimWhiteSpace: Boolean = True): Boolean;
var
  ValueInt: Int64;      // dummy integer value
  ValueFloat: Extended; // dummy float value
begin
  if TrimWhiteSpace then
    Value := Trim(Value);

  // Check for valid integer
  Result := TryStrToInt64(Value, ValueInt);

  if not Result and AllowFloat then
    // Wasn't valid as integer, try float
    Result := TryStrToFloat(Value, ValueFloat);
end;

function TDatabase.Query(QString: String): Boolean;
begin
  try
    Self.Connector.ExecuteDirect(QString);
    Result:= True;
  except
    on E: Exception do
      begin
        MessageDlg('Impossibile eseguire la Query (' + E.Message +')', mtError, [mbOK], 0);
        Result:= False;
      end;
  end;
end;

function TDatabase.QueryRes(QString: String): TDataSet;
begin
  try
    Self.Connector.Execute(QString, nil, Result);
  except
    on E: Exception do
      MessageDlg('Impossibile eseguire la Query (' + E.Message +')', mtError, [mbOK], 0);
  end;
end;

function TDatabase.CheckStructure: Boolean;
var
  Query:    String;
  QueryRes: TDataSet;
begin
  Query:= 'SELECT COUNT(*) FROM sqlite_master WHERE type=''table'' AND (name = ''software'' OR name = ''commands'');';
  QueryRes:= Self.QueryRes(Query);

  Result:= (QueryRes.Fields[0].AsInteger >= 2);
end;

function TDatabase.FieldValueExists(Table, Field, Value: String): Boolean;
var
  Query:    String;
  QueryRes: TDataSet;
begin
  if not( IsNumeric(Value, False, True) ) then
    Query:= 'SELECT COUNT(*) FROM ' + Table + ' WHERE ' + Field +  ' = ''' + Value + ''';'
  else
    Query:= 'SELECT COUNT(*) FROM ' + Table + ' WHERE ' + Field +  ' = ' + Value + ';';

  QueryRes:= Self.QueryRes(Query);

  if (QueryRes.Fields[0].AsInteger >= 1) then
    Result:= True
  else
    Result:= False;
end;

constructor TDatabase.Create(DBConn : TSQLConnection);
begin
  Self.Connector := DBConn;
end;

procedure TDatabase.Disconnect;
begin
  Self.Connector.Connected:= False;
end;

procedure TDatabase.RebuildStructure;
var
  Query : String;
begin
  // Eventually rebuild Software Table
  Query:= 'CREATE TABLE IF NOT EXISTS software ( '
  + 'id INTEGER PRIMARY KEY AUTOINCREMENT, '
  + 'name VARCHAR(50) NOT NULL, '
  + 'maincommand INTEGER NOT NULL, '
  + 'FOREIGN KEY(maincommand) REFERENCES commands(id) '
  + ');';
  Self.Query(Query);

  // Eventually rebuild Commands History Table
  Query:= 'CREATE TABLE IF NOT EXISTS commands ( '
  + 'id INTEGER PRIMARY KEY AUTOINCREMENT, '
  + 'software INTEGER NOT NULL, '
  + '[order] INT(3) NOT NULL, '
  + 'label VARCHAR(25) NOT NULL, '
  + 'command TEXT NOT NULL, '
  + 'version VARCHAR(25) NULL, '
  + 'compatibility INT(1) NOT NULL DEFAULT 0, '
  + 'updateurl TEXT NULL, '
  + 'CONSTRAINT u_command UNIQUE(software, [order], label, compatibility), '
  + 'FOREIGN KEY(software) REFERENCES software(ID) ON DELETE CASCADE ON UPDATE CASCADE '
  + ');';
  Self.Query(Query);
end;

function TDatabase.Connect(DBFile: String): Boolean;
begin
  if not( FileExists(DBFile) ) then
    if MessageDlg('Impossibile trovare il Database, ricrearlo?', mtWarning, [mbYes, mbNo], 0) <> mrYes then
      begin
        MessageDlg('FacTotum non può continuare senza il supporto database.' + #13 +
                   'L''applicazione verrà terminata', mtError, [mbOK], 0);
        Result:= False;
        Exit;
      end
    else
      begin
        CopyFile('FacTotum_Clean.db', 'FacTotum.db', True);
      end;

    try
      Self.Connector.Connected := True;
      if not(Self.CheckStructure) then
        begin
          MessageDlg('Impossibile trovare le tabelle necessarie nel Database, verranno ricreate', mtWarning, [mbOK], 0);
          Self.RebuildStructure;
        end;
      Result:= True;
    except
      on E: EDatabaseError do
        begin
          MessageDlg('Impossibile aprire il Database (' + E.Message +').' + #13 +
                     'L''applicazione verrà terminata', mtError, [mbOK], 0);
          Result:= False;
          Exit;
        end;
  end
end;

function TDatabase.AddSoftware(name : String; maincommand: Integer): Boolean;
var
  Query : String;
begin
  // Insert new Software
  Query:= 'INSERT INTO software ( name, maincommand ) '
  + 'VALUES ( '
  + '''' + Trim(name) + ''', '
  + '' + maincommand.ToString + ' '
  + ' );';
  Result:= Self.Query(Query);
end;

function TDatabase.AddCommand(software, order, compatibility: Integer; clabel, command, version, url: String): Boolean;
var
  Query : String;
begin

  //Sposta in avanti i comandi per un inserimento nel mezzo
  MoveCommandsForward(software, order);

  // Insert new Software
  Query:= 'INSERT INTO commands ( software, [order], label, command, version, compatibility, updateurl ) '
  + 'VALUES ( '
  + '' + IntToStr(software) + ', '
  + '' + IntToStr(order) + ', '
  + '''' + Trim(clabel) + ''', '
  + '''' + Trim(command) + ''', '
  + '''' + Trim(version) + ''', '
  + '' + IntToStr(compatibility) + ', '
  + '''' + Trim(url) + ''' '
  + ' );';
  Result:= Self.Query(Query);
end;

function TDatabase.UpdateSoftware(id: Integer; name: String; maincommand: Integer): Boolean;
var
  Query : String;
begin
  Query := 'UPDATE software ' +
           'SET name = ''' + name + ''', ' +
               'maincommand = ''' + maincommand.ToString + ''' ' +
           'WHERE ID = ' + IntToStr(id);
  Result:=Self.Query(Query);
end;

function TDatabase.UpdateSoftwareByNode(node: TSoftwareTreeNode): Boolean;
begin
  Result := UpdateSoftware(node.SoftwareID, node.Software, node.MainCommand);
end;

function TDatabase.UpdateCommand(id, software, order, compatibility: Integer; clabel, command, url: String): Boolean;
var
  Query : String;
begin
  Query := 'UPDATE commands ' +
           'SET software = ' + software.ToString() + ', ' +
               '[order] = ' + IntToStr(order) + ', ' +
               'label = ''' + Trim(clabel) + ''', ' +
               'command = ''' + Trim(command) + ''', ' +
               'compatibility = ' + IntToStr(compatibility) + ', ' +
               'updateurl = ''' + Trim(url) + ''' ' +
           'WHERE ID = ' + IntToStr(id);
  Result := Self.Query(Query);
end;

function TDatabase.UpdateCommandByNode(node: TSoftwareTreeNode): Boolean;
begin
  Result := UpdateCommand(node.CommandID, node.SoftwareID, node.Order, node.Compatibility, node.description, node.Command, node.URL);
end;

function TDatabase.DeleteSoftware(id: Integer): Boolean;
var
software, commands: Boolean;
begin
  software := Self.Query('DELETE FROM software WHERE ID = ' + id.ToString());
  commands := Self.Query('DELETE FROM commands WHERE software = ' + id.ToString());
  Result := software AND commands;
end;

function TDatabase.DeleteCommand(id, softwareId: Integer): String;
var
  res:  TDataSet;
  software, command:  Boolean;
begin
  software := False;
  command := Self.Query('DELETE FROM commands WHERE ID = ' + id.ToString());

  res := Self.QueryRes('SELECT * FROM commands WHERE software = ' + softwareId.ToString());
  if res.RecordCount = 0 then
    begin
      software := Self.Query('DELETE FROM software WHERE ID = ' + softwareId.ToString());
    end;

  Result := 'NO';
  if command then
    begin
      if software then
        begin
          Result := 'DEL';
        end
      else
        begin
          Result := 'YES';
        end;
    end;
end;

function TDataBase.GetLastId(table: String): Integer;
var
  res: TDataSet;
  I: Integer;
begin
  Result := -1;

  res := Self.QueryRes('SELECT * FROM SQLITE_SEQUENCE');
  res.First;

  for I := 0 to res.RecordCount - 1 do
  begin
    if res.Fields[0].AsString = table then
    begin
      Result := res.Fields[1].AsInteger;
      Break;
    end;
    res.Next;
  end;
end;

function TDatabase.MoveCommandsForward(software, order: Integer): Boolean;
begin
  Result := Self.Query('UPDATE commands SET [order] = [order] + 1 WHERE software = ' + software.ToString + ' AND [order] >= ' + order.ToString);
end;

function TDataBase.GetSWVersion(id: Integer): String;
var
res: TDataSet;
begin
  res := Self.QueryRes('SELECT version FROM commands, software WHERE commands.software=software.id AND commands.ID=software.maincommand AND software.ID=' + id.ToString());
  res.First;
  Result := res.Fields[0].AsString;
end;

function TDataBase.GetSWNameById(id: Integer): String;
var
res: TDataSet;
begin
  res := Self.QueryRes('SELECT name FROM software WHERE ID=' + id.ToString());
  res.First;
  Result := res.Fields[0].AsString;
end;

function TDataBase.UpdateCmdVersion(id: string; version: string): Boolean;
begin
  Result := Self.Query('UPDATE commands SET version=''' + version + ''' WHERE ID=' + id);
end;

//------------------------------------------------------------------------------
// End Implementation of TDatabase Class

end.

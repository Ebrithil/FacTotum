unit U_DataBase;

interface

uses
    System.SysUtils, System.UITypes, Vcl.Dialogs, Data.DB, Data.SqlExpr, Data.DBXSqlite,
    System.Classes, winapi.windows,

    U_Classes;

type
    swRecord = class
        id:       integer;
        name:     string;
        commands: tList;
    end;

    cmdRecord = class
        id:            integer;
        order:         byte;
        compatibility: shortInt;
        name,
        exeCmd,
        version,
        updateURL:     string;
    end;

    DBManager = class
        protected
            m_connector: tSQLConnection;
            procedure    connect;
            procedure    disconnect;
            procedure    rebuildDBStructure;
            function     query(qString: string): boolean;
            function     queryRes(qString: string): tDataSet;
            function     getCommandList(const swID: integer): tList;
        public
            constructor create;
            destructor  Destroy; override;
            function    getSoftwareList: tList;
            //function loadRecordsFromDB(): tList;
            //function writeSoftwareRecordToDB(data: softwareRecord): integer;
            //function writeCommandRecordToDB(data: commandRecord): integer;
    end;

const
    DBNamePath = 'FacTotum.db';

var
    sDBMgr: DBManager;

implementation

// Start Implementation of TDatabase Class
//------------------------------------------------------------------------------

    constructor DBManager.create;
    begin
        m_connector := tSQLConnection.create(nil);

        m_connector.connectionName := 'SQLITECONNECTION';
        m_connector.driverName     := 'Sqlite';
        m_connector.loginPrompt    := false;

        m_connector.params.clear;
        m_connector.params.add('DriverName=Sqlite');
        m_connector.params.add('Database=' + DBNamePath);
        m_connector.params.add('FailIfMissing=False');

        self.connect;
    end;

    destructor DBManager.destroy;
    begin
        self.disconnect;
        inherited;
    end;

    procedure DBManager.connect;
    begin
        if not( fileExists(DBNamePath) ) then
        begin
             sEventHdlr.pushEventToList( tEvent.create('DataBase non trovato.', eiAlert) );
             sEventHdlr.pushEventToList( tEvent.create('Il DataBase verr� ricreato.', eiAlert) );
        end;

        //setDllDirectory('.\dll');
        try
            try
                m_connector.open;
                sEventHdlr.pushEventToList( tEvent.create('Effettuata connessione al DataBase.', eiInfo) );
                self.rebuildDBStructure;
            except
                on e: exception do
                    sEventHdlr.pushEventToList( tEvent.create(e.ClassName + ': ' + e.Message, eiError) );
            end;
        finally
            //setDllDirectory('');
        end;
    end;

    procedure DBManager.disconnect;
    begin
        try
            m_connector.close;
            sEventHdlr.pushEventToList( tEvent.create('Terminata connessione al DataBase.', eiInfo) );
        except
            on e: exception do
                sEventHdlr.pushEventToList( tEvent.create(e.className + ': ' + e.message, eiError) );
        end;
    end;

    function DBManager.query(qString: string): boolean;
    begin
        result := false;
        try
            self.m_connector.executeDirect(qString);
            result:= true;
        except
            on e: exception do
                sEventHdlr.pushEventToList( tEvent.create(e.className + ': ' + e.message, eiError) );
        end;
    end;

    function DBManager.QueryRes(qString: string): TDataSet;
    begin
        result := nil;
        try
            self.m_connector.execute(qString, nil, result);
        except
            on e: exception do
                sEventHdlr.pushEventToList( tEvent.create(e.className + ': ' + e.message, eiError) );
        end;
    end;

    procedure DBManager.rebuildDBStructure;
    var
        query: string;
    begin
        // Eventually rebuild Software Table
        query:=
        'CREATE TABLE IF NOT EXISTS software ( '
        + 'id INTEGER PRIMARY KEY AUTOINCREMENT, '
        + 'name VARCHAR(50) NOT NULL '
        + ');';
        self.query(query);

        // Eventually rebuild Commands History Table
        query:=
        'CREATE TABLE IF NOT EXISTS commands ( '
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
        self.query(query);
    end;

    function DBManager.getCommandList(const swID: integer): tList;
    var
        cmdRec:  cmdRecord;
        sqlData: tDataSet;
    begin
        sqlData := self.queryRes('SELECT * FROM commands WHERE software = ' + intToStr(swID) + ' ORDER BY [order];');
        cmdRec  := cmdRecord.create;
        result  := tList.create;

        sqlData.first;
        while not( sqlData.eof ) do
        begin
            with cmdRec do
            begin
                id            := sqlData.fieldByName('id').asInteger;
                name          := sqlData.fieldByName('label').toString;
                order         := sqlData.fieldByName('order').asLongWord;
                exeCmd        := sqlData.fieldByName('command').toString;
                version       := sqlData.fieldByName('version').toString;
                updateURL     := sqlData.fieldByName('updateurl').toString;
                compatibility := sqlData.fieldByName('compatibility').asInteger;
            end;
            sqlData.next;
            result.add(cmdRec);
        end;

        sqlData.free;
    end;

    function DBManager.getSoftwareList: tList;
    var
        swRec:   swRecord;
        sqlData: tDataSet;
    begin
        sqlData := self.queryRes('SELECT * FROM software;');
        swRec   := swRecord.create;
        result  := tList.create;

        sqlData.first;
        while not(sqlData.eof) do
        begin
            with swRec do
            begin
                id       := sqlData.fieldByName('id').asInteger;
                name     := sqlData.fieldByName('name').toString;
                commands := self.getCommandList(id);
            end;

            sqlData.next;
            result.add(swRec);
        end;

        sqlData.free;
    end;

//------------------------------------------------------------------------------
// End Implementation of TDatabase Class

end.

unit U_DataBase;

interface

uses
    System.SysUtils, System.UITypes, Vcl.Dialogs, Data.DB, Data.SqlExpr, Data.DbxSqlite,
    System.Classes, winapi.windows,

    U_Classes;

type
    swRecord = record
        id:       integer;
        name:     string;
        commands: tList;
    end;

    cmdRecord = record
        id:            integer;
        order:         byte;
        compatibility: shortInt;
        name,
        exeCmd,
        version,
        updateURL:     string;
    end;

    dbManager = class
        protected
            m_connector: tSQLConnection;
            procedure    connect;
            procedure    disconnect;
            procedure    rebuildDbStructure;
            function     query(qString: string): boolean;
            function     queryRes(qString: string): tDataSet;
            function     getCommandList(const swID: integer): tList;
        public
            constructor create;
            destructor  destroy; override;
            function    getSoftwareList: tList;
            //function loadRecordsFromDB(): tList;
            //function writeSoftwareRecordToDB(data: softwareRecord): integer;
            //function writeCommandRecordToDB(data: commandRecord): integer;
    end;

const
    dbNamePath = 'FacTotum.db';

var
    sDbManager:    dbManager;

implementation

// Start Implementation of TDatabase Class
//------------------------------------------------------------------------------

    constructor dbManager.create;
    begin
        m_connector := tSQLConnection.create(nil);

        m_connector.connectionName := 'SQLITECONNECTION';
        m_connector.driverName := 'Sqlite';
        m_connector.loginPrompt := false;

        m_connector.params.clear;
        m_connector.params.add('DriverName=Sqlite');
        m_connector.params.add('Database=' + dbNamePath);
        m_connector.params.add('FailIfMissing=False');

        self.connect;
    end;

    destructor  dbManager.destroy;
    begin
        self.disconnect;
        inherited;
    end;

    procedure dbManager.connect;
    begin
        if not( fileExists(dbNamePath) ) then
        begin
             sEventHdlr.pushEventToList( tEvent.create('DataBase non trovato.', eiAlert) );
             sEventHdlr.pushEventToList( tEvent.create('Il DataBase verrà ricreato.', eiAlert) );
        end;

        //setDllDirectory('.\dll');
        try
            try
                m_connector.open;
                sEventHdlr.pushEventToList( tEvent.create('Effettuata connessione al DataBase.', eiInfo) );
                self.rebuildDbStructure;
            except
                on e: exception do
                    sEventHdlr.pushEventToList( tEvent.create(e.ClassName + ': ' + e.Message, eiError) );
            end;
        finally
            //setDllDirectory('');
        end;
    end;

    procedure dbManager.disconnect;
    begin
        try
            m_connector.close;
            sEventHdlr.pushEventToList( tEvent.create('Terminata connessione al DataBase.', eiInfo) );
        except
            on e: exception do
                sEventHdlr.pushEventToList( tEvent.create(e.className + ': ' + e.message, eiError) );
        end;
    end;

    function dbManager.query(qString: string): boolean;
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

    function dbManager.QueryRes(qString: string): TDataSet;
    begin
        result := nil;
        try
            self.m_connector.execute(qString, nil, result);
        except
            on e: exception do
                sEventHdlr.pushEventToList( tEvent.create(e.className + ': ' + e.message, eiError) );
        end;
    end;

    procedure dbManager.rebuildDbStructure;
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

    function dbManager.getCommandList(const swID: integer): tList;
    var
        cmdRec:  cmdRecord;
        sqlData: tDataSet;
    begin
        sqlData := self.queryRes('SELECT * FROM commands WHERE software = ' + intToStr(swID) + ' ORDER BY [order];');

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
            //result.add(cmdRec);
        end;

        sqlData.free;
    end;

    function dbManager.getSoftwareList: tList;
    var
        swRec:   swRecord;
        sqlData: tDataSet;
    begin
        sqlData := self.queryRes('SELECT * FROM software;');

        sqlData.first;
        while not( sqlData.eof ) do
        begin
            with swRec do
            begin
                id       := sqlData.fieldByName('id').asInteger;
                name     := sqlData.fieldByName('name').toString;
                commands := self.getCommandList(id);
            end;
            sqlData.next;
            //result.add(swRec);
        end;

        sqlData.free;
    end;

//------------------------------------------------------------------------------
// End Implementation of TDatabase Class

end.

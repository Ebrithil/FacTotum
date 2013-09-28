unit U_DataBase;

interface

uses
    System.SysUtils, System.UITypes, Vcl.Dialogs, Data.DB, Data.SqlExpr, Data.DbxSqlite,
    System.Classes, winapi.windows,

    U_Classes;

type
    softwareRecord = record
        commands: tList;
    end;

    commandRecord = record

    end;

    dbManager = class
        protected
            m_connector: tSQLConnection;
            procedure    connect;
            procedure    disconnect;
            procedure    rebuildDbStructure;
            function     query(qString: string): boolean;
            function     queryRes(qString: string): tDataSet;
        public
            constructor create;
            destructor  destroy; override;
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
        m_connector.close;
        sEventHdlr.pushEventToList( tEvent.create('Terminata connessione al DataBase.', eiInfo) );
    end;

    function dbManager.Query(QString: String): Boolean;
    begin
        try
            self.m_connector.executeDirect(qString);
            result:= true;
        except
            on e: exception do
                sEventHdlr.pushEventToList( tEvent.create(e.ClassName + ': ' + e.Message, eiError) );
        end;
    end;

    function dbManager.QueryRes(QString: String): TDataSet;
    begin
        result := nil;
        try
            self.m_connector.execute(qString, nil, result);
        except
            on e: exception do
                sEventHdlr.pushEventToList( tEvent.create(e.ClassName + ': ' + e.Message, eiError) );
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

//------------------------------------------------------------------------------
// End Implementation of TDatabase Class

end.

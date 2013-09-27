unit U_DataBase;

interface

uses
    Windows, System.SysUtils, System.UITypes, Vcl.Dialogs, Data.DB, Data.SqlExpr, System.Classes,

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

    m_connector.params.add('Database=' + dbNamePath);
    m_connector.params.add('DriverUnit=Data.DbxSqlite');
    m_connector.params.add('DriverPackageLoader=TDBXSqliteDriverLoader,DBXSqliteDriver170.bpl');
    m_connector.params.add('MetaDataPackageLoader=TDBXSqliteMetaDataCommandFactory,DbxSqliteDriver170.bpl');
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

    try
        m_connector.connected := true;
        sEventHdlr.pushEventToList( tEvent.create('Effettuata connessione al DataBase.', eiInfo) );
    except
        sEventHdlr.pushEventToList( tEvent.create('Impossibile connettersi al DataBase.', eiError) );
    end;
end;

procedure dbManager.disconnect;
begin
    m_connector.connected := false;
    sEventHdlr.pushEventToList( tEvent.create('Terminata connessione al DataBase.', eiInfo) );
end;

//------------------------------------------------------------------------------
// End Implementation of TDatabase Class

end.

unit U_DataBase;

interface

uses
    System.SysUtils, System.UITypes, Vcl.Dialogs, Data.DB, Data.SqlExpr, Data.DBXSqlite,
    System.Classes, winapi.windows,

    U_Classes;

type
    compatibilityMask = ( archNone, archx86, archx64 );

    DBRecord = class
        rType: string;
    end;

    swRecord = class(DBRecord)
        id:       integer;
        name:     string;
        commands: tList;

        function hasValidCommands: boolean;
    end;

    cmdRecord = class(DBRecord)
        id:            integer;
        order,
        compatibility: byte;
        name,
        exeCmd,
        version,
        updateURL:     string;
    end;

    fieldUpdate = class
        rType: string;
        rID:   integer;
        field: string;
        value: variant;

        constructor create(rType: string; rID: integer; field: string; value:variant);
    end;

    updateWrapper = class
        recordInfo: DBRecord;
        data:       tList;
    end;

    DBManager = class
        protected
            m_connector: tSQLConnection;
            m_updates,
            m_software:  tList;
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
            procedure   addModificationToUpdateList(update: updateWrapper);
            procedure   flushModificationsToDB;
    end;

const
    DBNamePath = 'FacTotum.db';

var
    sDBMgr: DBManager;

implementation

    function swRecord.hasValidCommands: boolean;
    var
        i: integer;
    begin
        for i := 0 to pred(commands.count) do
            // Confronto il mask di compatibility con la mask generata dall'architettura del SO, usando la Magia Nera
            if ( (cmdRecord(commands.items[i]).compatibility and (1 shl byte(tOSVersion.architecture))) > 0 ) then
            begin
                result := true;
                exit
            end;

        result := false;
    end;

// Start Implementation of TDatabase Class
//------------------------------------------------------------------------------

    constructor DBManager.create;
    begin
        m_connector := tSQLConnection.create(nil);

        m_connector.connectionName := 'SQLITECONNECTION';
        m_connector.driverName     := 'Sqlite';
        m_connector.loginPrompt    := false;
        m_updates                  := tList.create;

        m_connector.params.clear;
        m_connector.params.add('DriverName=Sqlite');
        m_connector.params.add('Database=' + DBNamePath);
        m_connector.params.add('FailIfMissing=False');

        self.connect;
    end;

    destructor DBManager.Destroy;
    begin
        self.disconnect;
        inherited;
    end;

    procedure DBManager.connect;
    begin
        if not( fileExists(DBNamePath) ) then
        begin
             sEventHdlr.pushEventToList( tEvent.create('DataBase non trovato.', eiAlert) );
             sEventHdlr.pushEventToList( tEvent.create('Il DataBase verrà ricreato.', eiAlert) );
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

    function DBManager.queryRes(qString: string): tDataSet;
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
        result  := tList.create;

        sqlData.first;
        while not( sqlData.eof ) do
        begin
            cmdRec  := cmdRecord.create;
            with cmdRec do
            begin
                id            := sqlData.fieldByName('id').value;
                name          := sqlData.fieldByName('label').value;
                order         := sqlData.fieldByName('order').value;
                exeCmd        := sqlData.fieldByName('command').value;
                version       := sqlData.fieldByName('version').value;
                updateURL     := sqlData.fieldByName('updateurl').value;
                compatibility := sqlData.fieldByName('compatibility').value;
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
        if assigned(m_software) then
        begin
            result := m_software;
            exit;
        end;

        sqlData     := self.queryRes('SELECT * FROM software;');
        swRec       := swRecord.create;
        m_software  := tList.create;

        sqlData.first;
        while not(sqlData.eof) do
        begin
            with swRec do
            begin
                id       := sqlData.fieldByName('id').value;
                name     := sqlData.fieldByName('name').value;
                commands := self.getCommandList(id);
            end;

            sqlData.next;
            m_software.add(swRec);
        end;

        sqlData.free;
        result := m_software;
    end;

    procedure DBManager.addModificationToUpdateList(update: updateWrapper);
    var
        i:   integer;
        add: boolean;
    begin
        add := true;

        for i := 0 to m_updates.count do
            if updateWrapper(m_updates.items[i]).recordInfo = update.recordInfo  then
            begin
                add := false;
                break;
            end;

        if add then
            m_updates.add(update)
        else
            updateWrapper(m_updates.items[i]).data.add(fieldUpdate(update.data.items[0]))
    end;

//------------------------------------------------------------------------------
// End Implementation of TDatabase Class

    constructor fieldUpdate.create(rType: string; rID: integer; field: string; value: variant);
    begin
        self.rType := rType;
        self.rID   := rID;
        self.field := field;
        self.value := value;
    end;

end.

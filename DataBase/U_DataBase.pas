unit U_DataBase;

interface

uses
    System.SysUtils, System.UITypes, Vcl.Dialogs, Data.DB, Data.SqlExpr, Data.DBXSqlite,
    System.Classes, winapi.windows, System.SyncObjs,

    U_Classes;

type
    compatibilityMask = ( archNone, archx86, archx64 );
    recordType        = ( recordSoftware, recordCommand );
    modificationType  = ( modInsert, modUpdate, modDelete );

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

    tTaskRecordOP = class(tTask)
        public
            tRecord: recordType;
            pRecord: DBRecord;
    end;

    tTaskRecordInsert = class(tTaskRecordOP)
        public
            procedure exec; override;
    end;

    tTaskRecordUpdate = class(tTaskRecordOP)
        public
            field: string;
            value: variant;

            procedure exec; override;
    end;

    tTaskRecordDelete = class(tTaskRecordOP)
        public
            procedure exec; override;
    end;

    tTaskDBUpdate = class(tTask)
        public
            procedure exec; override;
    end;

    recordModification = class
        public
            modType: modificationType;
            pRecord: DBRecord;
            field:   string;
            value:   variant;

            constructor create(modType: modificationType; pRecord: DBRecord); overload;
            constructor create(modType: modificationType; pRecord: DBRecord; field: string; value: variant); overload;
    end;

    DBManager = class
        protected
            m_connector:   tSQLConnection;
            m_updates,
            m_software:    tList;
            m_updateMutex: tMutex;
            m_updated:     boolean;
            procedure      connect;
            procedure      disconnect;
            procedure      rebuildDBStructure;
            function       query(qString: string): boolean;
            function       queryRes(qString: string): tDataSet;
            function       getCommandList(const swID: integer): tList;
        public
            constructor create;
            destructor  Destroy; override;
            function    getSoftwareList: tList;
            function    wasUpdated: boolean;
            procedure   enqueueModification(data: recordModification);
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
        result := false;

        if not assigned(commands) then
            exit;

        for i := 0 to pred(commands.count) do
            // Confronto il mask di compatibility con la mask generata dall'architettura del SO, usando la Magia Nera
            if ( (cmdRecord(commands.items[i]).compatibility and (1 shl byte(tOSVersion.architecture))) > 0 ) then
            begin
                result := true;
                exit
            end;
    end;

// Start Implementation of TDatabase Class
//------------------------------------------------------------------------------

    constructor DBManager.create;
    begin
        m_connector   := tSQLConnection.create(nil);
        m_updateMutex := tMutex.create;
        m_updates     := tList.create;
        m_updated     := true;

        m_connector.connectionName := 'SQLITECONNECTION';
        m_connector.driverName     := 'Sqlite';
        m_connector.loginPrompt    := false;

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
        query :=
        'CREATE TABLE IF NOT EXISTS software ( '
        + 'id INTEGER PRIMARY KEY AUTOINCREMENT, '
        + 'name VARCHAR(50) NOT NULL '
        + ');';
        self.query(query);

        // Eventually rebuild Commands History Table
        query :=
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

    procedure DBManager.flushModificationsToDB;
    var
        query: string;
    begin
        query := ''; // TODO PER MATTIA :P
        self.query(query);
    end;

    procedure DBManager.enqueueModification(data: recordModification);
    begin
        self.m_updateMutex.acquire;
        self.m_updates.add(data);
        self.m_updateMutex.release;
        m_updated := true;
    end;

    function DBManager.wasUpdated: boolean;
    begin
        if m_updated then
        begin
            m_updated := false;
            result    := true;
        end
        else
            result := false;
    end;

//------------------------------------------------------------------------------
// End Implementation of TDatabase Class

    constructor recordModification.create(modType: modificationType; pRecord: DBRecord);
    begin
        self.create(modType, pRecord, '', 0);
    end;

    constructor recordModification.create(modType: modificationType; pRecord: DBRecord; field: string; value: variant);
    begin
        self.modType := modType;
        self.pRecord := pRecord;
        self.field   := field;
        self.value   := value;
    end;

    procedure tTaskRecordInsert.exec;
    var
        pList: tList;
    begin
        sDBMgr.enqueueModification(recordModification.create(modInsert, self.pRecord));
        pList := sDBMgr.getSoftwareList;

        case self.tRecord of
            recordSoftware : pList.add(self.pRecord);
            recordCommand  : swRecord(pList.items[pList.indexOf(self.pRecord)]).commands.add(self.pRecord);
        end;
    end;

    procedure tTaskRecordUpdate.exec;
    begin

    end;

    procedure tTaskRecordDelete.exec;
    begin
        sDBMgr.enqueueModification(recordModification.create(modDelete, self.pRecord));
    end;

    procedure tTaskDBUpdate.exec;
    begin
        sDBMgr.flushModificationsToDB;
    end;

end.

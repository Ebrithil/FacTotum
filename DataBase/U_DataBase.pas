unit U_DataBase;

interface

uses
    System.SysUtils, System.UITypes, Vcl.Dialogs, Data.DB, Data.SqlExpr, Data.DBXSqlite,
    System.Classes, winapi.windows, System.SyncObjs,

    U_Classes;

type
    compatibilityMask = ( archNone, archx86, archx64 );
    recordType        = ( recordSoftware, recordCommand );

    DBRecord = class
        rType: string;
    end;

    swRecord = class(DBRecord)
        guid:     integer;
        name:     string;
        commands: tList;

        function hasValidCommands: boolean;
    end;

    cmdRecord = class(DBRecord)
        guid,
        swid: integer;
        prty,
        arch: byte;
        name,
        cmmd,
        vers,
        uURL: string;
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

    DBManager = class
        protected
            m_connector: tSQLConnection;
            m_software:  tList;
            m_updated:   boolean;
            procedure    connect;
            procedure    disconnect;
            procedure    rebuildDBStructure;
            procedure    insertRecordInDB(software: swRecord); overload;
            procedure    insertRecordInDB(command: cmdRecord); overload;
            procedure    updateRecordInDB(software: swRecord; field: string; value: variant); overload;
            procedure    updateRecordInDB(command: cmdRecord; field: string; value: variant); overload;
            procedure    deleteRecordFromDB(software: swRecord); overload;
            procedure    deleteRecordFromDB(command: cmdRecord); overload;
            function     query(qString: string): boolean;
            function     queryRes(qString: string): tDataSet;
            function     getCommandList(const swID: integer): tList;
        public
            constructor create;
            destructor  Destroy; override;
            procedure   insertDBRecord(tRecord: recordType; pRecord: DBRecord);
            procedure   deleteDBRecord(tRecord: recordType; pRecord: DBRecord);
            procedure   updateDBRecord(tRecord: recordType; pRecord: DBRecord; field: string; value: variant);
            function    wasUpdated: boolean;
            function    getSoftwareList: tList;
    end;

const
    DBNamePath = 'FacTotum.db';
    // Database related strings
    dbTableCommands = 'commands';
    dbTableSoftware = 'software';
    dbFieldSwGUID   = 'guid';
    dbFieldSwName   = 'name';
    dbFieldCmdGUID  = 'guid';
    dbFieldCmdSwID  = 'swid';
    dbFieldCmdPrty  = 'prty';
    dbFieldCmdName  = 'name';
    dbFieldCmdCmmd  = 'cmmd';
    dbFieldCmdVers  = 'vers';
    dbFieldCmdArch  = 'arch';
    dbFieldCmduURL  = 'uurl';

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
            if ( (cmdRecord(commands.items[i]).arch and (1 shl byte(tOSVersion.architecture))) > 0 ) then
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
        query := format(
          'CREATE TABLE IF NOT EXISTS %s ( '
          + '%s INTEGER PRIMARY KEY AUTOINCREMENT, '
          + '%s VARCHAR(50) NOT NULL '
          + ');',
          [
          // Table name
          dbTableSoftware,
          // Table columns
          dbFieldSwGUID, dbFieldSwName
          ]
        );
        self.query(query);

        // Eventually rebuild Commands History Table
        query := format(
          'CREATE TABLE IF NOT EXISTS %s ( '
          + '%s INTEGER PRIMARY KEY AUTOINCREMENT, '
          + '%s INTEGER NOT NULL, '
          + '%s INT(3) NOT NULL, '
          + '%s INT(1) NOT NULL DEFAULT 0, '
          + '%s VARCHAR(25) NOT NULL, '
          + '%s VARCHAR(25) NULL, '
          + '%s TEXT NOT NULL, '
          + '%s TEXT NULL, '
          + 'CONSTRAINT u_command UNIQUE(%s, %s, %s, %s), '
          + 'FOREIGN KEY(%s) REFERENCES %s(%s) ON DELETE CASCADE ON UPDATE CASCADE '
          + ');',
          [
          // Table name
          dbTableCommands,
          // Table columns
          dbFieldCmdGUID, dbFieldCmdSwID, dbFieldCmdPrty, dbFieldCmdArch,
          dbFieldCmdName, dbFieldCmdVers, dbFieldCmdCmmd, dbFieldCmduURL,
          // Table constraints
          dbFieldCmdGUID, dbFieldCmdPrty, dbFieldCmdArch, dbFieldCmdName,
          // Table foreign keys
          dbFieldCmdSwID, dbTableSoftware, dbFieldSwGUID
          ]
        );
        self.query(query);
    end;

    function DBManager.getCommandList(const swID: integer): tList;
    var
        query:   string;
        cmdRec:  cmdRecord;
        sqlData: tDataSet;
    begin
        result  := tList.create;

        query := format(
          'SELECT * '
        + 'FROM %s '
        + 'WHERE %s = %d '
        + 'ORDER BY %s;',
          [
          // Select
          dbTableCommands,
          // Where
          dbFieldCmdSwID, swID,
          // Order
          dbFieldCmdPrty
          ]
        );
        sqlData := self.queryRes(query);

        sqlData.first;
        while not( sqlData.eof ) do
        begin
            cmdRec  := cmdRecord.create;
            with cmdRec do
            begin
                guid := sqlData.fieldByName(dbFieldCmdGUID).value;
                swid := sqlData.fieldByName(dbFieldCmdSwID).value;
                prty := sqlData.fieldByName(dbFieldCmdPrty).value;
                arch := sqlData.fieldByName(dbFieldCmdArch).value;
                name := sqlData.fieldByName(dbFieldCmdName).value;
                cmmd := sqlData.fieldByName(dbFieldCmdCmmd).value;
                vers := sqlData.fieldByName(dbFieldCmdVers).value;
                uURL := sqlData.fieldByName(dbFieldCmduURL).value;
            end;
            sqlData.next;
            result.add(cmdRec);
        end;

        sqlData.free;
    end;

    function DBManager.getSoftwareList: tList;
    var
        query:   string;
        swRec:   swRecord;
        sqlData: tDataSet;
    begin
        if assigned(m_software) then
        begin
            result := m_software;
            exit;
        end;

        query := format(
          'SELECT * '
        + 'FROM %s;',
          [
          // Tables
          dbTableSoftware
          ]
        );
        sqlData     := self.queryRes( query );
        swRec       := swRecord.create;
        m_software  := tList.create;

        sqlData.first;
        while not(sqlData.eof) do
        begin
            with swRec do
            begin
                guid     := sqlData.fieldByName(dbFieldSwGUID).value;
                name     := sqlData.fieldByName(dbFieldSwName).value;
                commands := self.getCommandList(guid);
            end;

            sqlData.next;
            m_software.add(swRec);
        end;

        sqlData.free;
        result := m_software;
    end;

    procedure DBManager.insertRecordInDB(software: swRecord);
    var
        query: string;
    begin
        query := format(
          'INSERT INTO %s (%s)'
        + 'VALUES (%s);',
          [
          // Table
          dbTableSoftware,
          // Columns
          dbFieldSwName,
          // Values
          software.name
          ]
        );
        self.query(query);
    end;

    procedure DBManager.insertRecordInDB(command: cmdRecord);
    var
        query: string;
    begin
        query := format(
          'INSERT INTO %s (%s, %s, %s, %s, %s, %s, %s)'
        + 'VALUES (%d, %u, %s, %s, %s, %u, %s);',
          [
          // Table
          dbTableCommands,
          // Columns
          dbFieldCmdSwID, dbFieldCmdPrty, dbFieldCmdName, dbFieldCmdCmmd,
          dbFieldCmdVers, dbFieldCmdArch, dbFieldCmduURL,
          // Values
          command.swid, command.prty, command.name, command.cmmd,
          command.vers, command.arch, command.uURL
          ]
        );
        self.query(query);
    end;

    procedure DBManager.updateRecordInDB(software: swRecord; field: string; value: variant);
    var
        query: string;
    begin
        query := format(
          'UPDATE %s '
        + 'SET %s = %s'
        + 'WHERE %s = %s;',
          [
          // Update
          dbTableSoftware,
          // Set
          field, string(value),
          // Where
          dbFieldSwGUID, software.guid
          ]
        );
        self.query(query);
    end;

    procedure DBManager.updateRecordInDB(command: cmdRecord; field: string; value: variant);
    var
        query: string;
    begin
        query := format(
          'UPDATE %s '
        + 'SET %s = %s'
        + 'WHERE %s = %s;',
          [
          // Update
          dbTableCommands,
          // Set
          field, string(value),
          // Where
          dbFieldCmdGUID, command.guid
          ]
        );
        self.query(query);
    end;

    procedure DBManager.deleteRecordFromDB(software: swRecord);
    var
        query: string;
    begin
        query := format(
          'DELETE '
        + 'FROM %s'
        + 'WHERE %s = %s;',
          [
          // From
          dbTableSoftware,
          // Where
          dbFieldSwGUID, software.guid
          ]
        );
        self.query(query);
    end;

    procedure DBManager.deleteRecordFromDB(command: cmdRecord);
    var
        query: string;
    begin
        query := format(
          'DELETE '
        + 'FROM %s'
        + 'WHERE %s = %s;',
          [
          // From
          dbTableSoftware,
          // Where
          dbFieldCmdGUID, command.guid
          ]
        );
        self.query(query);
    end;

    procedure DBManager.insertDBRecord(tRecord: recordType; pRecord: DBRecord);
    begin
        case tRecord of
            recordSoftware: self.insertRecordInDB( swRecord(pRecord) );
            recordCommand:  self.insertRecordInDB( cmdRecord(pRecord) );
        end
    end;

    procedure DBManager.deleteDBRecord(tRecord: recordType; pRecord: DBRecord);
    begin
        case tRecord of
            recordSoftware: self.deleteRecordFromDB( swRecord(pRecord) );
            recordCommand:  self.deleteRecordFromDB( cmdRecord(pRecord) );
        end
    end;

    procedure DBManager.updateDBRecord(tRecord: recordType; pRecord: DBRecord; field: string; value: variant);
    begin
        case tRecord of
            recordSoftware: self.updateRecordInDB( swRecord(pRecord), field, value );
            recordCommand:  self.updateRecordInDB( cmdRecord(pRecord), field, value );
        end
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

    procedure tTaskRecordInsert.exec;
    var
        pList: tList;
    begin
        pList := sDBMgr.getSoftwareList;

        case self.tRecord of
            recordSoftware:
            begin
                pList.add(self.pRecord);
                sDBMgr.InsertRecordInDB(swRecord(self.pRecord));
            end;
            recordCommand:
            begin
                swRecord(pList.items[pList.indexOf(self.pRecord)]).commands.add(self.pRecord);
                sDBMgr.insertRecordInDB(cmdRecord(self.pRecord));
            end;
        end;
    end;

    procedure tTaskRecordUpdate.exec;
    begin

    end;

    procedure tTaskRecordDelete.exec;
    begin

    end;

end.

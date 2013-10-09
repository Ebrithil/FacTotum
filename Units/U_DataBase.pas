unit U_DataBase;

interface

uses
    System.SysUtils, System.UITypes, Vcl.Dialogs, Data.DB, Data.SqlExpr, Data.DBXSqlite,
    System.Classes, winapi.windows, System.SyncObjs, System.Types,
    IdGlobal, IdHash, IdHashSHA, IdHashMessageDigest, ShellAPI, vcl.comCtrls, System.StrUtils,

    U_InputTasks, U_OutputTasks, U_Parser, U_Events, U_Threads;

type
    compatibilityMask = ( archNone, archx86, archx64 );
    recordType        = ( recordSoftware, recordCommand );
    dbStringsIndex    = ( dbTableCommands, dbTableSoftware,
                          dbFieldSwGUID,   dbFieldSwName,
                          dbFieldCmdGUID,  dbFieldCmdSwID, dbFieldCmdPrty, dbFieldCmdName,
                          dbFieldCmdCmmd,  dbFieldCmdVers, dbFieldCmdArch, dbFieldCmduURL,
                          dbFieldCmdHash );

    DBRecord = class
    end;

    swRecord = class(DBRecord)
        guid:     integer;
        name:     string;
        commands: tList;
        function  hasValidCommands: boolean;
    end;

    cmdRecord = class(DBRecord)
        guid,
        swid: integer;
        prty,
        arch: byte;
        name,
        cmmd,
        vers,
        uURL,
        hash: string;
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
            field: dbStringsIndex;
            value: string;

            procedure exec; override;
    end;

    tTaskRecordDelete = class(tTaskRecordOP)
        public
            procedure exec; override;
    end;

    tTaskGetVer = class(tTask)
        public
            cmdRec:      cmdRecord;
            returnValue: string;

            procedure exec; override;
    end;

    tTaskSetVer = class(tTaskOutput)
        public
            cmdRec:      cmdRecord;
            new_version: string;

            procedure exec(); override;
    end;

    DBManager = class
        protected
            m_connector:  tSQLConnection;
            m_software:   tList;
            m_updated:    boolean;
            m_DBNamePath: string;
            procedure     connect;
            procedure     disconnect;
            procedure     rebuildDBStructure;
            procedure     insertRecordInDB(software: swRecord); overload;
            procedure     insertRecordInDB(command: cmdRecord); overload;
            procedure     updateRecordInDB(software: swRecord; field: dbStringsIndex; value: string); overload;
            procedure     updateRecordInDB(command: cmdRecord; field: dbStringsIndex; value: string); overload;
            procedure     deleteRecordFromDB(software: swRecord); overload;
            procedure     deleteRecordFromDB(command: cmdRecord); overload;
            function      query(qString: string): boolean;
            function      queryRes(qString: string): tDataSet;
            function      getLastInsertedRecordID: integer;
            function      getCommandList(const swID: integer): tList;
        public
            constructor create(DBNamePath: string = 'FacTotum.db');
            destructor  Destroy; override;
            procedure   insertDBRecord(tRecord: recordType; pRecord: DBRecord);
            procedure   deleteDBRecord(tRecord: recordType; pRecord: DBRecord);
            procedure   updateDBRecord(tRecord: recordType; pRecord: DBRecord; field: dbStringsIndex; value: string);
            function    wasUpdated: boolean;
            function    getSoftwareList: tList;
            function    getSoftwareRec(guid: integer): swRecord;
            function    getCommandRec(guid: integer):  cmdRecord;
    end;

const
    dbStrings: array[dbStringsIndex] of string = (
        // Database related strings
        'commands',
        'software',
        'guid',
        'name',
        'guid',
        'swid',
        'prty',
        'name',
        'cmmd',
        'vers',
        'arch',
        'uurl',
        'hash' );

var
    sDBMgr: DBManager;
    sLvUpdate: tListView;

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

    constructor DBManager.create(DBNamePath: string = 'FacTotum.db');
    begin
        m_connector   := tSQLConnection.create(nil);
        m_updated     := true;
        m_DBNamePath  := DBNamePath;

        m_connector.connectionName := 'SQLITECONNECTION';
        m_connector.driverName     := 'Sqlite';
        m_connector.loginPrompt    := false;

        m_connector.params.clear;
        m_connector.params.add('DriverName=Sqlite');
        m_connector.params.add('Database=' + m_DBNamePath);
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
        if not( fileExists(m_DBNamePath) ) then
        begin
             sEventHdlr.pushEventToList('DataBase non trovato.', eiAlert);
             sEventHdlr.pushEventToList('Il DataBase verra'' ricreato.', eiAlert);
        end;

        //setDllDirectory('.\dll');
        try
            try
                m_connector.open;
                sEventHdlr.pushEventToList('Stabilita connessione al DataBase.', eiInfo);
                self.rebuildDBStructure;
            except
                on e: exception do
                    sEventHdlr.pushEventToList('Impossibile connettersi al DataBase: ' + e.Message, eiError);
            end;
        finally
            //setDllDirectory('');
        end;
    end;

    procedure DBManager.disconnect;
    begin
        try
            m_connector.close;
            sEventHdlr.pushEventToList('Terminata connessione al DataBase.', eiInfo);
        except
            on e: exception do
                sEventHdlr.pushEventToList('Impossibile disconnettersi dal DataBase: ' + e.message, eiError);
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
                sEventHdlr.pushEventToList('Impossibile eseguire la Query: ' + e.message, eiError);
        end;
    end;

    function DBManager.queryRes(qString: string): tDataSet;
    begin
        result := nil;
        try
            self.m_connector.execute(qString, nil, result);
        except
            on e: exception do
                sEventHdlr.pushEventToList('Impossibile eseguire la Query: ' + e.message, eiError);
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
          dbStrings[dbTableSoftware],
          // Table columns
          dbStrings[dbFieldSwGUID], dbStrings[dbFieldSwName]
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
          + '%s VARCHAR(40) NULL, '
          + 'CONSTRAINT u_command UNIQUE(%s, %s, %s, %s), '
          + 'FOREIGN KEY(%s) REFERENCES %s(%s) ON DELETE CASCADE ON UPDATE CASCADE '
          + ');',
          [
          // Table name
          dbStrings[dbTableCommands],
          // Table columns
          dbStrings[dbFieldCmdGUID], dbStrings[dbFieldCmdSwID], dbStrings[dbFieldCmdPrty], dbStrings[dbFieldCmdArch],
          dbStrings[dbFieldCmdName], dbStrings[dbFieldCmdVers], dbStrings[dbFieldCmdCmmd], dbStrings[dbFieldCmduURL],
          dbStrings[dbFieldCmdHash],
          // Table constraints
          dbStrings[dbFieldCmdGUID], dbStrings[dbFieldCmdPrty], dbStrings[dbFieldCmdArch], dbStrings[dbFieldCmdName],
          // Table foreign keys
          dbStrings[dbFieldCmdSwID], dbStrings[dbTableSoftware], dbStrings[dbFieldSwGUID]
          ]
        );
        self.query(query);
    end;

    function DBManager.getCommandList(const swID: integer): tList;
    var
        query:   string;
        cmdRec:  cmdRecord;
        sqlData: tDataSet;
        i:       byte;
    begin
        if assigned(m_software) then
        begin
            result := nil;
            for i := 0 to m_software.count do
                if swRecord( m_software.items[i] ).guid = swID then
                begin
                    result := swRecord(self.getSoftwareList.items[i]).commands;
                    break;
                end;
            exit;
        end;

        result  := tList.create;

        query := format(
          'SELECT * '
        + 'FROM %s '
        + 'WHERE %s = %d '
        + 'ORDER BY %s;',
          [
          // Select
          dbStrings[dbTableCommands],
          // Where
          dbStrings[dbFieldCmdSwID], swID,
          // Order
          dbStrings[dbFieldCmdPrty]
          ]
        );
        sqlData := self.queryRes(query);

        sqlData.first;
        while not(sqlData.eof) do
        begin
            cmdRec  := cmdRecord.create;
            with cmdRec do
            begin
                guid := sqlData.fieldByName( dbStrings[dbFieldCmdGUID] ).value;
                swid := sqlData.fieldByName( dbStrings[dbFieldCmdSwID] ).value;
                prty := sqlData.fieldByName( dbStrings[dbFieldCmdPrty] ).value;
                arch := sqlData.fieldByName( dbStrings[dbFieldCmdArch] ).value;
                name := sqlData.fieldByName( dbStrings[dbFieldCmdName] ).value;
                cmmd := sqlData.fieldByName( dbStrings[dbFieldCmdCmmd] ).value;
                vers := sqlData.fieldByName( dbStrings[dbFieldCmdVers] ).value;
                uURL := sqlData.fieldByName( dbStrings[dbFieldCmduURL] ).value;
                hash := sqlData.fieldByName( dbStrings[dbFieldCmdHash] ).value;
            end;
            sqlData.next;
            result.add(cmdRec);
        end;

        sqlData.free;
    end;

    function DBManager.getCommandRec(guid: integer): cmdRecord;
    var
        i,j:    word;
        swList: tList;
    begin
        result:= nil;

        swList := self.getSoftwareList;
        for i := 0 to pred(swList.count) do
            for j := 0 to pred( swRecord(swList.items[i]).commands.count ) do
            begin
                result := cmdRecord( swRecord(swList.items[i]).commands.items[j] );
                if result.guid = guid then
                    exit;
            end;
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
          dbStrings[dbTableSoftware]
          ]
        );
        sqlData := self.queryRes(query);
        result  := tList.create;

        sqlData.first;
        while not(sqlData.eof) do
        begin
            swRec := swRecord.create;

            with swRec do
            begin
                guid     := sqlData.fieldByName( dbStrings[dbFieldSwGUID] ).value;
                name     := sqlData.fieldByName( dbStrings[dbFieldSwName] ).value;
                commands := self.getCommandList(guid);
            end;

            sqlData.next;
            result.add(swRec);
        end;

        sqlData.free;
        m_software := result;
    end;

    function DBManager.getSoftwareRec(guid: integer): swRecord;
    var
        i:      word;
        swList: tList;
    begin
        result:= nil;

        swList := self.getSoftwareList;
        for i := 0 to pred(swList.count) do
            begin
                result := swList.items[i];
                if result.guid = guid then
                    exit;
            end;
    end;

    procedure DBManager.insertRecordInDB(software: swRecord);
    var
        query: string;
    begin
        query := format(
          'INSERT INTO %s (%s) '
        + 'VALUES (''%s'');',
          [
          // Table
          dbStrings[dbTableSoftware],
          // Columns
          dbStrings[dbFieldSwName],
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
          'INSERT INTO %s (%s, %s, %s, %s, %s, %s, %s, %s) '
        + 'VALUES (''%d'', ''%u'', ''%s'', ''%s'', ''%s'', ''%u'', ''%s'', ''%s'');',
          [
          // Table
          dbStrings[dbTableCommands],
          // Columns
          dbStrings[dbFieldCmdSwID], dbStrings[dbFieldCmdPrty], dbStrings[dbFieldCmdName], dbStrings[dbFieldCmdCmmd],
          dbStrings[dbFieldCmdVers], dbStrings[dbFieldCmdArch], dbStrings[dbFieldCmduURL], dbStrings[dbFieldCmdHash],
          // Values
          command.swid, command.prty, command.name, command.cmmd,
          command.vers, command.arch, command.uURL, command.hash
          ]
        );
        self.query(query);
    end;

    procedure DBManager.updateRecordInDB(software: swRecord; field: dbStringsIndex; value: string);
    var
        query: string;
    begin
        query := format(
          'UPDATE %s '
        + 'SET %s = ''%s'' '
        + 'WHERE %s = ''%d'';',
          [
          // Update
          dbStrings[dbTableSoftware],
          // Set
          dbStrings[field], value,
          // Where
          dbStrings[dbFieldSwGUID], software.guid
          ]
        );
        self.query(query);
    end;

    procedure DBManager.updateRecordInDB(command: cmdRecord; field: dbStringsIndex; value: string);
    var
        query: string;
    begin
        query := format(
          'UPDATE %s '
        + 'SET %s = ''%s'' '
        + 'WHERE %s = ''%d'';',
          [
          // Update
          dbStrings[dbTableCommands],
          // Set
          dbStrings[field], value,
          // Where
          dbStrings[dbFieldCmdGUID], command.guid
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
        + 'FROM %s '
        + 'WHERE %s = ''%d'';',
          [
          // From
          dbStrings[dbTableSoftware],
          // Where
          dbStrings[dbFieldSwGUID], software.guid
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
        + 'FROM %s '
        + 'WHERE %s = ''%d'';',
          [
          // From
          dbStrings[dbTableCommands],
          // Where
          dbStrings[dbFieldCmdGUID], command.guid
          ]
        );
        self.query(query);
    end;

    procedure DBManager.insertDBRecord(tRecord: recordType; pRecord: DBRecord);
    var
        i: byte;
    begin
        case tRecord of
            recordSoftware:
            begin
                self.insertRecordInDB( swRecord(pRecord) );
                for i := 0 to pred( swRecord(pRecord).commands.count ) do
                begin
                    swRecord(pRecord).guid := self.getLastInsertedRecordID;
                    cmdRecord(swRecord(pRecord).commands[i]).swid := self.getLastInsertedRecordID;
                    self.insertRecordInDB( cmdRecord(swRecord(pRecord).commands[i]) );
                    cmdRecord(swRecord(pRecord).commands[i]).guid := self.getLastInsertedRecordID;
                end;
            end;
            recordCommand:
            begin
                self.insertRecordInDB( cmdRecord(pRecord) );
                cmdRecord(pRecord).guid := self.getLastInsertedRecordID;
            end;
        end;

        m_updated := true;
    end;

    procedure DBManager.deleteDBRecord(tRecord: recordType; pRecord: DBRecord);
    begin
        case tRecord of
            recordSoftware: self.deleteRecordFromDB( swRecord(pRecord) );
            recordCommand:  self.deleteRecordFromDB( cmdRecord(pRecord) );
        end;

        m_updated := true;
    end;

    procedure DBManager.updateDBRecord(tRecord: recordType; pRecord: DBRecord; field: dbStringsIndex; value: string);
    begin
        case tRecord of
            recordSoftware: self.updateRecordInDB( swRecord(pRecord), field, value );
            recordCommand:  self.updateRecordInDB( cmdRecord(pRecord), field, value );
        end;

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

    function DBManager.getLastInsertedRecordID: integer;
    var
        query:   string;
        sqlData: tDataSet;
    begin
        query := 'SELECT LAST_INSERT_ROWID();';
        sqlData := self.queryRes(query);

        sqlData.first;
        result := sqlData.fields[0].value;
    end;

//------------------------------------------------------------------------------
// End Implementation of TDatabase Class

    // TODO: Controlla di aver rimosso tutta la PARANOIA.
    procedure tTaskRecordInsert.exec;
    var
        pList: tList;
        i:     integer;
    begin
        pList := sDBMgr.getSoftwareList;

        case self.tRecord of
            recordSoftware:
            begin
                pList.add(self.pRecord);
                sDBMgr.insertDBRecord(self.tRecord, self.pRecord);
            end;
            recordCommand:
            begin
                for i := 0 to pred(pList.count) do
                    if swRecord(pList.items[i]).guid = cmdRecord(self.pRecord).swid then
                    begin
                        swRecord(pList.items[i]).commands.add(self.pRecord);
                        break;
                    end;

                sDBMgr.insertDBRecord(self.tRecord, self.pRecord);
            end;
        end;
    end;

    procedure tTaskRecordUpdate.exec;
    begin
        case self.tRecord of
            recordSoftware:
                case self.field of
                    dbFieldSwName: swRecord(self.pRecord).name := self.value;
                end;
            recordCommand:
                case self.field of
                    dbFieldCmdPrty: cmdRecord(self.pRecord).prty := strToInt(self.value);
                    dbFieldCmdName: cmdRecord(self.pRecord).name := self.value;
                    dbFieldCmdCmmd: cmdRecord(self.pRecord).cmmd := self.value;
                    dbFieldCmdVers: cmdRecord(self.pRecord).vers := self.value;
                    dbFieldCmdArch: cmdRecord(self.pRecord).arch := strToInt(self.value);
                    dbFieldCmduURL: cmdRecord(self.pRecord).uURL := self.value;
                end;
        end;
        sDBMgr.updateDBRecord(self.tRecord, self.pRecord, self.field, self.value);
    end;

    // TODO: Controlla di aver rimosso tutta la PARANOIA.
    procedure tTaskRecordDelete.exec;
    var
        pList: tList;
        i:     integer;
     begin
        pList := sDBMgr.getSoftwareList;

        if self.tRecord = recordCommand then
        begin
            for i := 0 to pred(pList.count) do
                if swRecord( pList.items[i] ).guid = cmdRecord(self.pRecord).swid then
                begin
                    swRecord( pList.items[i] ).commands.remove(self.pRecord);
                    break;
                end;

            if swRecord( pList.items[i] ).commands.count = 0 then
            begin
                sDBMgr.deleteDBRecord( recordSoftware, pList.items[i] );
                swRecord( pList.items[i] ).free;
                pList.delete(i);
            end;
        end
        else
        begin
            for i := 0 to pred( swRecord(self.pRecord).commands.count ) do
            begin
                sDBMgr.deleteDBRecord( recordCommand, swRecord(self.pRecord).commands.first );
                cmdRecord( swRecord(self.pRecord).commands.first ).free;
                swRecord(self.pRecord).commands.remove( swRecord(self.pRecord).commands.first );
            end;
            pList.remove(self.pRecord);
        end;

        sDBMgr.deleteDBRecord(self.tRecord, self.pRecord);
        freeAndNil(self.pRecord);
    end;

    procedure tTaskGetVer.exec;
    var
        new_version: string;
        returnTask:  tTaskSetVer;
    begin
        new_version := sUpdateParser.getLastStableVerFromURL(self.cmdRec.uURL);

        returnTask             := tTaskSetVer.create;
        returnTask.cmdRec      := self.cmdRec;
        returnTask.new_version := new_version;

        sTaskMgr.pushTaskToOutput(returnTask);
    end;

    procedure tTaskSetVer.exec();
    var
        i: integer;
    begin
        for i := 0 to pred(sLvUpdate.items.count) do
            if ( sLvUpdate.items[i].data = self.cmdRec ) then
            begin
                if sLvUpdate.items[i].subItems[1] = self.new_version then
                    sLvUpdate.items[i].imageIndex := tImageIndex(eiDotGreen)
                else
                    sLvUpdate.items[i].imageIndex := tImageIndex(eiDotRed);
                sLvUpdate.items[i].subItems.add(self.new_version);
            end;
    end;

end.

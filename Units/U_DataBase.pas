unit U_DataBase;

interface

uses
    System.SysUtils, System.UITypes, Vcl.Dialogs, Data.db, Data.SqlExpr, Data.dbXSqlite,
    System.Classes, winapi.windows, System.SyncObjs, System.Types,
    IdGlobal, IdHash, IdHashSHA, IdHashMessageDigest, ShellAPI, vcl.comCtrls, System.StrUtils,

    U_InputTasks, U_OutputTasks, U_Parser, U_Events, U_Threads;

type
    compatibilityMask = ( archNone, archx86, archx64 );
    dbOperation       = ( DOR_INSERT, DOR_UPDATE, DOR_DELETE );
    dbStringsIndex    = ( dbTableCommands, dbTableSoftware,
                          dbFieldSwGUID,   dbFieldSwName,
                          dbFieldCmdGUID,  dbFieldCmdSwID, dbFieldCmdPrty, dbFieldCmdName,
                          dbFieldCmdCmmd,  dbFieldCmdVers, dbFieldCmdArch, dbFieldCmduURL,
                          dbFieldCmdHash );
    lvUpdateColIndex  = ( lvColSoftCmd = 1, lvColVA, lvColUV, lvColProgress, lvColStatus );

    dbRecord = class
    end;

    swRecord = class(dbRecord)
        guid:     integer;
        name:     string;
        commands: tList;
        function  hasValidCommands: boolean;
    end;

    cmdRecord = class(dbRecord)
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

    dbManager = class
        protected
            m_connector:  tSQLConnection;
            m_software:   tList;
            m_dbNamePath: string;
            procedure     connect;
            procedure     disconnect;
            procedure     rebuilddbStructure;
            function      query(qString: string): boolean;
            function      queryRes(qString: string): tDataSet;
            function      getLastInsertedRecordID: integer;
            function      getCommandList(const swid: integer): tList;
        public
            constructor   create(dbNamePath: string = 'FacTotum.db');
            destructor    Destroy; override;
            procedure     insertDBRecord(pRecord: dbRecord);
            procedure     deleteDBRecord(pRecord: dbRecord);
            procedure     updateDBRecord(pRecord: dbRecord);
            function      getSoftwareList: tList;
            function      getSwRecordByGUID(const guid: integer; const searchInDB: boolean = false):  swRecord;
            function      getCmdRecordByGUID(const guid: integer; const searchInDB: boolean = false): cmdRecord;
    end;

    tTaskRecordOP = class(tTask)
        public
            pRecord:        dbRecord;
            tOperation:     dbOperation;
            procedure exec; override;
    end;

    tTaskGetVer = class(tTask)
        public
            cmdRec:   cmdRecord;
            procedure exec; override;
    end;

    tTaskSetVer = class(tTaskOutput)
        public
            cmdRec:         cmdRecord;
            new_version:    string;
            procedure exec; override;
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
    sdbMgr: dbManager;

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

    constructor dbManager.create(dbNamePath: string = 'FacTotum.db');
    begin
        m_connector   := tSQLConnection.create(nil);
        m_dbNamePath  := dbNamePath;

        m_connector.connectionName := 'SQLITECONNECTION';
        m_connector.driverName     := 'Sqlite';
        m_connector.loginPrompt    := false;

        m_connector.params.clear;
        m_connector.params.add('DriverName=Sqlite');
        m_connector.params.add('Database=' + m_dbNamePath);
        m_connector.params.add('FailIfMissing=False');

        self.connect;
    end;

    destructor dbManager.Destroy;
    begin
        self.disconnect;
        inherited;
    end;

    procedure dbManager.connect;
    begin
        if not( fileExists(m_dbNamePath) ) then
        begin
             createEvent('DataBase non trovato.', eiAlert);
             createEvent('Il DataBase verra'' ricreato.', eiAlert);
        end;

        //setDllDirectory('.\dll');
        try
            try
                m_connector.open;
                createEvent('Stabilita connessione al DataBase.', eiInfo);
                self.rebuilddbStructure;
            except
                on e: exception do
                    createEvent('Impossibile connettersi al DataBase: ' + e.Message, eiError);
            end;
        finally
            //setDllDirectory('');
        end;
    end;

    procedure dbManager.disconnect;
    begin
        try
            m_connector.close;
            createEvent('Terminata connessione al DataBase.', eiInfo);
        except
            on e: exception do
                createEvent('Impossibile disconnettersi dal DataBase: ' + e.message, eiError);
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
                createEvent('Impossibile eseguire la Query: ' + e.message, eiError);
        end;
    end;

    function dbManager.queryRes(qString: string): tDataSet;
    begin
        result := nil;
        try
            self.m_connector.execute(qString, nil, result);
        except
            on e: exception do
                createEvent('Impossibile eseguire la Query: ' + e.message, eiError);
        end;
    end;

    procedure dbManager.rebuilddbStructure;
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

    procedure dbManager.insertDBRecord(pRecord: dbRecord);
    var
        i:     integer;
        query: string;
    begin
        if pRecord is swRecord then
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
              (pRecord as swRecord).name
              ]
            );
            if self.query(query) then
            begin
                (pRecord as swRecord).guid := self.getLastInsertedRecordID;
                for i := 0 to pred( (pRecord as swRecord).commands.count ) do
                begin
                    cmdRecord( (pRecord as swRecord).commands[i] ).swid := (pRecord as swRecord).guid;
                    self.insertDBRecord( cmdRecord( (pRecord as swRecord).commands[i] ) );
                end;
            end;
        end
        else if pRecord is cmdRecord then
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
              (pRecord as cmdRecord).swid, (pRecord as cmdRecord).prty, (pRecord as cmdRecord).name, (pRecord as cmdRecord).cmmd,
              (pRecord as cmdRecord).vers, (pRecord as cmdRecord).arch, (pRecord as cmdRecord).uURL, (pRecord as cmdRecord).hash
              ]
            );
            if self.query(query) then
                (pRecord as cmdRecord).guid := self.getLastInsertedRecordID;
        end;
    end;

    procedure dbManager.updateDBRecord(pRecord: dbRecord);
    var
        query: string;
    begin
        if pRecord is swRecord then
        begin
            query := format(
              'UPDATE %s '
            + 'SET %s = ''%s'' '
            + 'WHERE %s = ''%d'';',
              [
              // Update
              dbStrings[dbTableSoftware],
              // Set
              dbStrings[dbFieldSwName], (pRecord as swRecord).name,
              // Where
              dbStrings[dbFieldSwGUID], (pRecord as swRecord).guid
              ]
            );
            if not self.query(query) then
            begin
                pRecord.free;
                pRecord := self.getSwRecordByGUID( (pRecord as swRecord).guid, true );
            end;
        end
        else if pRecord is cmdRecord then
        begin
            query := format(
              'UPDATE %s '
            + 'SET %s = ''%u'', '
            + '%s = ''%u'', '
            + '%s = ''%s'', '
            + '%s = ''%s'', '
            + '%s = ''%s'', '
            + '%s = ''%s'', '
            + '%s = ''%s'' '
            + 'WHERE %s = ''%d'';',
              [
              // Update
              dbStrings[dbTableCommands],
              // Set
              dbStrings[dbFieldCmdPrty], (pRecord as cmdRecord).prty,
              dbStrings[dbFieldCmdArch], (pRecord as cmdRecord).arch,
              dbStrings[dbFieldCmdName], (pRecord as cmdRecord).name,
              dbStrings[dbFieldCmdCmmd], (pRecord as cmdRecord).cmmd,
              dbStrings[dbFieldCmdVers], (pRecord as cmdRecord).vers,
              dbStrings[dbFieldCmduURL], (pRecord as cmdRecord).uURL,
              dbStrings[dbFieldCmdHash], (pRecord as cmdRecord).hash,
              // Where
              dbStrings[dbFieldCmdGUID], (pRecord as cmdRecord).guid
              ]
            );
            if not self.query(query) then
            begin
                pRecord.free;
                pRecord := self.getCmdRecordByGUID( (pRecord as swRecord).guid, true );
            end;
        end;
    end;

    procedure dbManager.deletedbRecord(pRecord: dbRecord);
    var
        i,
        varValue: integer;
        query,
        varTable,
        varField: string;
    begin
        varValue := -1;

        if pRecord is swRecord then
        begin
            varTable := dbStrings[dbTableSoftware];
            varField := dbStrings[dbFieldSwGUID];
            varValue := (pRecord as swRecord).guid;
            for i := 0 to pred( (pRecord as swRecord).commands.count ) do
                self.deleteDBRecord( (pRecord as swRecord).commands[i] );
        end
        else if pRecord is cmdRecord then
        begin
            varTable := dbStrings[dbTableCommands];
            varField := dbStrings[dbFieldCmdGUID];
            varValue := (pRecord as cmdRecord).guid;
        end;

        query := format(
          'DELETE '
        + 'FROM %s '
        + 'WHERE %s = ''%d'';',
          [
          // From
          varTable,
          // Where
          varField, varValue
          ]
        );
        if self.query(query) then
            freeAndNil(pRecord);
    end;

    function dbManager.getLastInsertedRecordID: integer;
    var
        query:   string;
        sqlData: tDataSet;
    begin
        query := 'SELECT LAST_INSERT_ROWID();';
        sqlData := self.queryRes(query);

        sqlData.first;
        result := sqlData.fields[0].value;
    end;

    function dbManager.getSwRecordByGUID(const guid: integer; const searchInDB: boolean = false): swRecord;
    var
        i,
        j:       integer;
        query:   string;
        sqlData: tDataSet;
    begin
        if not searchInDB and assigned(self.m_software) then
        begin
            result := nil;
            for i := 0 to pred(self.m_software.count) do
                if swRecord(self.m_software[i]).guid = guid then
                begin
                    result := swRecord(self.m_software[i]);
                    exit;
                end;
            exit;
        end;

        query := format(
          'SELECT * '
        + 'FROM %s '
        + 'WHERE %s = %d;',
          [
          // Select
          dbStrings[dbTableSoftware],
          // Where
          dbStrings[dbFieldSwGUID], guid
          ]
        );
        sqlData := self.queryRes(query);

        result := nil;
        if not sqlData.isEmpty then
        begin
            result := swRecord.create;
            sqlData.first;
            with result do
            begin
                guid     := sqlData.fieldByName( dbStrings[dbFieldSwGUID] ).value;
                name     := sqlData.fieldByName( dbStrings[dbFieldSwName] ).value;
                commands := self.getCommandList( guid );
            end;
        end
        else
            sqlData.free;
    end;

    function dbManager.getCmdRecordByGUID(const guid: integer; const searchInDB: boolean = false): cmdRecord;
    var
        i,
        j:       integer;
        query:   string;
        sqlData: tDataSet;
    begin
        if not searchInDB and assigned(self.m_software) then
        begin
            result := nil;
            for i := 0 to pred(self.m_software.count) do
                for j := 0 to pred( swRecord(self.m_software[i]).commands.count ) do
                    if cmdRecord( swRecord(self.m_software[i]).commands.items[j] ).guid = guid then
                    begin
                        result := cmdRecord( swRecord(self.m_software[i]).commands.items[j] );
                        exit;
                    end;
            exit;
        end;

        query := format(
          'SELECT * '
        + 'FROM %s '
        + 'WHERE %s = %d;',
          [
          // Select
          dbStrings[dbTableCommands],
          // Where
          dbStrings[dbFieldCmdGUID], guid
          ]
        );
        sqlData := self.queryRes(query);

        result := nil;
        if not sqlData.isEmpty then
        begin
            result := cmdRecord.create;
            sqlData.first;
            with result do
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
        end
        else
            sqlData.free;
    end;

    function dbManager.getSoftwareList: tList;
    var
        query:   string;
        swRec:   swRecord;
        sqlData: tDataSet;
    begin
        if assigned(self.m_software) then
        begin
            result := self.m_software;
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

        result := nil;
        if not sqlData.isEmpty then
        begin
            result := tList.create;
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
            self.m_software := result;
        end
        else
            sqlData.free;
    end;

    function dbManager.getCommandList(const swid: integer): tList;
    var
        i:       integer;
        query:   string;
        cmdRec:  cmdRecord;
        sqlData: tDataSet;
    begin
        if assigned(self.m_software) then
        begin
            result := nil;
            for i := 0 to pred(self.m_software.count) do
                if swRecord(self.m_software.items[i]).guid = swid then
                begin
                    result := swRecord(self.m_software.items[i]).commands;
                    break;
                end;
            exit;
        end;

        query := format(
          'SELECT * '
        + 'FROM %s '
        + 'WHERE %s = %d '
        + 'ORDER BY %s;',
          [
          // Select
          dbStrings[dbTableCommands],
          // Where
          dbStrings[dbFieldCmdSwID], swid,
          // Order
          dbStrings[dbFieldCmdPrty]
          ]
        );
        sqlData := self.queryRes(query);

        result := nil;
        if not sqlData.isEmpty then
        begin
            sqlData.first;
            result := tList.create;
            while not sqlData.eof do
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
        end
        else
            sqlData.free;
    end;

//------------------------------------------------------------------------------
// End Implementation of TDatabase Class

    procedure tTaskRecordOP.exec;
    begin
        case self.tOperation of
            DOR_INSERT: sdbMgr.insertdbRecord(self.pRecord);
            DOR_UPDATE: sdbMgr.updateDBRecord(self.pRecord);
            DOR_DELETE: sdbMgr.deleteDBRecord(self.pRecord);
        end;
    end;

    procedure tTaskGetVer.exec;
    var
        new_version: string;
        returnTask:  tTaskSetVer;
    begin
        new_version := sUpdateParser.getLastStableVerFromURL(self.cmdRec.uURL);

        returnTask                 := tTaskSetVer.create;
        returnTask.cmdRec          := self.cmdRec;
        returnTask.new_version     := new_version;
        setLength(returnTask.dummyTargets, 2);
        returnTask.dummyTargets[0] := self.dummyTargets[0];
        returnTask.dummyTargets[1] := self.dummyTargets[1];

        sTaskMgr.pushTaskToOutput(returnTask);
    end;

    procedure tTaskSetVer.exec;
    var
        i:      integer;
        targetLv: tListView;
        targetTs: tTabSheet;
    begin
        if not (self.dummyTargets[0] is tListView) or
           not (self.dummyTargets[1] is tTabSheet) then
            exit;

        targetLv := self.dummyTargets[0] as tListView;
        targetTs := self.dummyTargets[1] as tTabSheet;

        for i := 0 to pred(targetLv.items.count) do
            if ( targetLv.items[i].data = self.cmdRec ) then
            begin
                if targetLv.items[i].subItems[ integer(lvColSoftCmd) ] = self.new_version then
                    targetLv.items[i].stateIndex := tImageIndex(eiDotGreen)
                else if (targetLv.items[i].subItems[ integer(lvColSoftCmd) ] =  RemoteVersionNotAvailable) then
                    targetLv.items[i].stateIndex := tImageIndex(eiDotYellow)
                else
                begin
                    targetLv.items[i].stateIndex := tImageIndex(eiDotRed);
                    targetTs.ImageIndex := tImageIndex(tiUpdateNotif);
                end;

               targetLv.items[i].subItems[ integer(lvColVA) ] := self.new_version;
            end;
    end;

end.

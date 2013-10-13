unit U_DataBase;

interface

uses
    System.SysUtils, System.UITypes, Vcl.Dialogs, Data.db, Data.SqlExpr, Data.dbXSqlite,
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

    tTaskRecordOP = class(tTask)
        public
            tRecord: recordType;
            pRecord: dbRecord;
    end;

    tTaskRecordInsert = class(tTaskRecordOP)
        public
            procedure exec; override;
    end;

    tTaskRecordUpdate = class(tTaskRecordOP)
        public
            procedure exec; override;
    end;

    tTaskRecordDelete = class(tTaskRecordOP)
        public
            procedure exec; override;
    end;

    tTaskGetVer = class(tTask)
        public
            cmdRec:      cmdRecord;

            procedure exec; override;
    end;

    tTaskSetVer = class(tTaskOutput)
        public
            cmdRec:      cmdRecord;
            new_version: string;

            procedure exec; override;
    end;

    dbManager = class
        protected
            m_connector:  tSQLConnection;
            m_software:   tList;
            m_dbNamePath: string;
            procedure     connect;
            procedure     disconnect;
            procedure     rebuilddbStructure;
            procedure     insertRecordIndb(software: swRecord); overload;
            procedure     insertRecordIndb(command: cmdRecord); overload;
            procedure     deleteRecordFromdb(software: swRecord); overload;
            procedure     deleteRecordFromdb(command: cmdRecord); overload;
            function      query(qString: string): boolean;
            function      queryRes(qString: string): tDataSet;
            function      getLastInsertedRecordID: integer;
            function      getCommandList(const swID: integer): tList;
        public
            constructor create(dbNamePath: string = 'FacTotum.db');
            destructor  Destroy; override;
            procedure   insertdbRecord(tRecord: recordType; pRecord: dbRecord);
            procedure   deletedbRecord(tRecord: recordType; pRecord: dbRecord);
            procedure   updatedbRecord(pRecord: dbRecord);
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

    function dbManager.getCommandList(const swID: integer): tList;
    var
        query:   string;
        cmdRec:  cmdRecord;
        sqlData: tDataSet;
        i:       integer;
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

    function dbManager.getCommandRec(guid: integer): cmdRecord;
    var
        i,
        j:      integer;
        swList: tList;
    begin
        result := nil;

        swList := self.getSoftwareList;
        for i := 0 to pred(swList.count) do
            for j := 0 to pred( swRecord(swList.items[i]).commands.count ) do
            begin
                result := cmdRecord( swRecord(swList.items[i]).commands.items[j] );
                if result.guid = guid then
                    exit;
            end;
    end;

    function dbManager.getSoftwareList: tList;
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

    function dbManager.getSoftwareRec(guid: integer): swRecord;
    var
        i:      integer;
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

    procedure dbManager.insertRecordIndb(software: swRecord);
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

    procedure dbManager.insertRecordIndb(command: cmdRecord);
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

    procedure dbManager.deleteRecordFromdb(software: swRecord);
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

    procedure dbManager.deleteRecordFromdb(command: cmdRecord);
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

    procedure dbManager.insertdbRecord(tRecord: recordType; pRecord: dbRecord);
    var
        i: integer;
    begin
        case tRecord of
            recordSoftware:
            begin
                self.insertRecordIndb( swRecord(pRecord) );
                for i := 0 to pred( swRecord(pRecord).commands.count ) do
                begin
                    swRecord(pRecord).guid := self.getLastInsertedRecordID;
                    cmdRecord(swRecord(pRecord).commands[i]).swid := self.getLastInsertedRecordID;
                    self.insertRecordIndb( cmdRecord(swRecord(pRecord).commands[i]) );
                    cmdRecord(swRecord(pRecord).commands[i]).guid := self.getLastInsertedRecordID;
                end;
            end;
            recordCommand:
            begin
                self.insertRecordIndb( cmdRecord(pRecord) );
                cmdRecord(pRecord).guid := self.getLastInsertedRecordID;
            end;
        end;
    end;

    procedure dbManager.deletedbRecord(tRecord: recordType; pRecord: dbRecord);
    begin
        case tRecord of
            recordSoftware: self.deleteRecordFromdb( swRecord(pRecord) );
            recordCommand:  self.deleteRecordFromdb( cmdRecord(pRecord) );
        end;
    end;

    procedure dbManager.updatedbRecord(pRecord: dbRecord);
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
        end;
        self.query(query);
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

//------------------------------------------------------------------------------
// End Implementation of TDatabase Class

    // TODO: Controlla di aver rimosso tutta la PARANOIA.
    procedure tTaskRecordInsert.exec;
    var
        pList: tList;
        i:     integer;
    begin
        pList := sdbMgr.getSoftwareList;

        case self.tRecord of
            recordSoftware:
            begin
                pList.add(self.pRecord);
                sdbMgr.insertdbRecord(self.tRecord, self.pRecord);
            end;
            recordCommand:
            begin
                for i := 0 to pred(pList.count) do
                    if swRecord(pList.items[i]).guid = cmdRecord(self.pRecord).swid then
                    begin
                        swRecord(pList.items[i]).commands.add(self.pRecord);
                        break;
                    end;

                sdbMgr.insertdbRecord(self.tRecord, self.pRecord);
            end;
        end;
    end;

    procedure tTaskRecordUpdate.exec;
    begin
        sdbMgr.updatedbRecord(self.pRecord);
    end;

    // TODO: Controlla di aver rimosso tutta la PARANOIA.
    procedure tTaskRecordDelete.exec;
    var
        pList: tList;
        i:     integer;
     begin
        pList := sdbMgr.getSoftwareList;

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
                sdbMgr.deletedbRecord( recordSoftware, pList.items[i] );
                swRecord( pList.items[i] ).free;
                pList.delete(i);
            end;
        end
        else
        begin
            for i := 0 to pred( swRecord(self.pRecord).commands.count ) do
            begin
                sdbMgr.deletedbRecord( recordCommand, swRecord(self.pRecord).commands.first );
                cmdRecord( swRecord(self.pRecord).commands.first ).free;
                swRecord(self.pRecord).commands.remove( swRecord(self.pRecord).commands.first );
            end;
            pList.remove(self.pRecord);
        end;

        sdbMgr.deletedbRecord(self.tRecord, self.pRecord);
        freeAndNil(self.pRecord);
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

unit U_DataBase;

interface

uses
    System.SysUtils, System.UITypes, Vcl.Dialogs, Data.db, Data.SqlExpr, Data.dbXSqlite,
    System.Classes, winapi.windows, System.SyncObjs, System.Types,
    IdGlobal, IdHash, IdHashSHA, IdHashMessageDigest, ShellAPI, vcl.comCtrls, System.StrUtils,
    vcl.extCtrls,

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

    tDBRecord = class
    end;

    tSwRecord = class(tDBRecord)
        guid:     integer;
        name:     string;
        commands: tList;
        function  hasValidCommands: boolean;
    end;

    tCmdRecord = class(tDBRecord)
        guid,
        swid: integer;
        prty,
        arch: byte;
        name,
        cmmd,
        vers,
        uURL,
        cURL,
        cVER,
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
            function      insertDBRecord(var pRecord: tDBRecord): boolean;
            function      deleteDBRecord(var pRecord: tDBRecord): boolean;
            function      updateDBRecord(var pRecord: tDBRecord): boolean;
            function      getSoftwareList: tList;
            function      getSwRecordByGUID(const guid: integer; const searchInDB: boolean = false):  tSwRecord;
            function      getCmdRecordByGUID(const guid: integer; const searchInDB: boolean = false): tCmdRecord;
    end;

    tTaskRecordOP = class(tTask)
        public
            pRecord:        tDBRecord;
            tOperation:     dbOperation;
            procedure exec; override;
    end;

    tTaskRecordOPFeedBack = class(tTaskOutput)
        public
            pRecord:        tDBRecord;
            tOperation:     dbOperation;
            queryResult:    boolean;
            procedure exec; override;
    end;

    tTaskGetVer = class(tTask)
        public
            cmdRec:   tCmdRecord;
            procedure exec; override;
    end;

    tTaskSetVer = class(tTaskOutput)
        public
            cmdRec:         tCmdRecord;
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

    function tSwRecord.hasValidCommands: boolean;
    var
        i: integer;
    begin
        result := false;

        if not assigned(commands) then
            exit;

        for i := 0 to pred(commands.count) do
            // Confronto il mask di compatibility con la mask generata dall'architettura del SO, usando la Magia Nera
            if ( (tCmdRecord(commands.items[i]).arch and (1 shl byte(tOSVersion.architecture))) > 0 ) then
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

        setDllDirectory('resources');
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
            setDllDirectory('');
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

    function dbManager.insertDBRecord(var pRecord: tDBRecord): boolean;
    var
        i:         integer;
        tmpSwRec:  tSwRecord;
        tmpCmdRec: tCmdRecord;
        query:     string;
    begin
        result := false;
        if pRecord is tSwRecord then
        begin
            tmpSwRec := pRecord as tSwRecord;
            query    := format(
              'INSERT INTO %s (%s) '
            + 'VALUES (''%s'');',
              [
              // Table
              dbStrings[dbTableSoftware],
              // Columns
              dbStrings[dbFieldSwName],
              // Values
              tmpSwRec.name
              ]
            );
            if self.query(query) then
            begin
                result := true;
                tmpSwRec.guid := self.getLastInsertedRecordID;
                for i := 0 to pred( tmpSwRec.commands.count ) do
                begin
                    tmpCmdRec      := tCmdRecord( tmpSwRec.commands[i] );
                    tmpCmdRec.swid := tmpSwRec.guid;

                    self.insertDBRecord( tDBRecord(tmpCmdRec) );
                    if not assigned(tmpCmdRec) then
                    begin
                        while tmpSwRec.commands.count > 0 do
                        begin
                            tmpCmdRec := tCmdRecord(tmpSwRec.commands.first);
                            freeAndNil(tmpCmdRec);
                            tmpSwRec.commands.remove(tmpSwRec.commands.first);
                        end;
                        freeAndNil(tmpSwRec);
                    end;
                end;
            end
            else
                freeAndNil(pRecord);
        end
        else if pRecord is tCmdRecord then
        begin
            tmpCmdRec := pRecord as tCmdRecord;
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
              (pRecord as tCmdRecord).swid, (pRecord as tCmdRecord).prty, (pRecord as tCmdRecord).name, (pRecord as tCmdRecord).cmmd,
              (pRecord as tCmdRecord).vers, (pRecord as tCmdRecord).arch, (pRecord as tCmdRecord).uURL, (pRecord as tCmdRecord).hash
              ]
            );
            if self.query(query) then
            begin
                tmpCmdRec.guid := self.getLastInsertedRecordID;
                result := true;
            end
            else
                freeAndNil(tmpCmdRec);
        end;
    end;

    function dbManager.updateDBRecord(var pRecord: tDBRecord): boolean;
    var
        query:     string;
        tmpRecord: tDBRecord;
    begin
        result := false;
        if pRecord is tSwRecord then
        begin
            query := format(
              'UPDATE %s '
            + 'SET %s = ''%s'' '
            + 'WHERE %s = ''%d'';',
              [
              // Update
              dbStrings[dbTableSoftware],
              // Set
              dbStrings[dbFieldSwName], (pRecord as tSwRecord).name,
              // Where
              dbStrings[dbFieldSwGUID], (pRecord as tSwRecord).guid
              ]
            );
            if not self.query(query) then
            begin
                tmpRecord                   := self.getSwRecordByGUID( (pRecord as tSwRecord).guid, true );
                (pRecord as tSwRecord).name := (tmpRecord as tSwRecord).name;
                tmpRecord.free;
            end
            else
                result := true;
        end
        else if pRecord is tCmdRecord then
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
              dbStrings[dbFieldCmdPrty], (pRecord as tCmdRecord).prty,
              dbStrings[dbFieldCmdArch], (pRecord as tCmdRecord).arch,
              dbStrings[dbFieldCmdName], (pRecord as tCmdRecord).name,
              dbStrings[dbFieldCmdCmmd], (pRecord as tCmdRecord).cmmd,
              dbStrings[dbFieldCmdVers], (pRecord as tCmdRecord).vers,
              dbStrings[dbFieldCmduURL], (pRecord as tCmdRecord).uURL,
              dbStrings[dbFieldCmdHash], (pRecord as tCmdRecord).hash,
              // Where
              dbStrings[dbFieldCmdGUID], (pRecord as tCmdRecord).guid
              ]
            );
            if not self.query(query) then
            begin
                tmpRecord := self.getCmdRecordByGUID( (pRecord as tCmdRecord).guid, true );
                (pRecord as tCmdRecord).prty := (tmpRecord as tCmdRecord).prty;
                (pRecord as tCmdRecord).arch := (tmpRecord as tCmdRecord).arch;
                (pRecord as tCmdRecord).name := (tmpRecord as tCmdRecord).name;
                (pRecord as tCmdRecord).cmmd := (tmpRecord as tCmdRecord).cmmd;
                (pRecord as tCmdRecord).vers := (tmpRecord as tCmdRecord).vers;
                (pRecord as tCmdRecord).uURL := (tmpRecord as tCmdRecord).uURL;
                (pRecord as tCmdRecord).hash := (tmpRecord as tCmdRecord).hash;
                tmpRecord.free;
            end
            else
                result := true;
        end;
    end;

    function dbManager.deleteDBRecord(var pRecord: tDBRecord): boolean;
    var
        varValue: integer;
        query,
        varTable,
        varField:  string;
        tmpSwRec:  tSwRecord;
        tmpCmdRec: tDBRecord;
    begin
        result   := false;
        varValue := -1;

        if pRecord is tSwRecord then
        begin
            tmpSwRec := pRecord as tSwRecord;
            varTable := dbStrings[dbTableSoftware];
            varField := dbStrings[dbFieldSwGUID];
            varValue := (pRecord as tSwRecord).guid;
            while pred(tmpSwRec.commands.count) > -1 do
            begin
                tmpCmdRec := tmpSwRec.commands.first;
                self.deleteDBRecord(tmpCmdRec);
                if assigned(tmpCmdRec) then
                    exit;
                tmpSwRec.commands.remove(tmpSwRec.commands.first);
            end;
        end
        else if pRecord is tCmdRecord then
        begin
            varTable := dbStrings[dbTableCommands];
            varField := dbStrings[dbFieldCmdGUID];
            varValue := (pRecord as tCmdRecord).guid;
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
        begin
            result := true;
            freeAndNil(pRecord);
        end;
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

    function dbManager.getSwRecordByGUID(const guid: integer; const searchInDB: boolean = false): tSwRecord;
    var
        i:       integer;
        query:   string;
        sqlData: tDataSet;
    begin
        if not searchInDB and assigned(self.m_software) then
        begin
            result := nil;
            for i := 0 to pred(self.m_software.count) do
                if tSwRecord(self.m_software[i]).guid = guid then
                begin
                    result := tSwRecord(self.m_software[i]);
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
            result := tSwRecord.create;
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

    function dbManager.getCmdRecordByGUID(const guid: integer; const searchInDB: boolean = false): tCmdRecord;
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
                for j := 0 to pred( tSwRecord(self.m_software[i]).commands.count ) do
                    if tCmdRecord( tSwRecord(self.m_software[i]).commands.items[j] ).guid = guid then
                    begin
                        result := tCmdRecord( tSwRecord(self.m_software[i]).commands.items[j] );
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
            result := tCmdRecord.create;
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
        swRec:   tSwRecord;
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

        result          := tList.create;
        self.m_software := result;
        if not sqlData.isEmpty then
        begin
            sqlData.first;
            while not(sqlData.eof) do
            begin
                swRec := tSwRecord.create;

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
        cmdRec:  tCmdRecord;
        sqlData: tDataSet;
    begin
        if assigned(self.m_software) and
           (self.m_software.count > 0) then
        begin
            result := nil;
            for i := 0 to pred(self.m_software.count) do
                if tSwRecord(self.m_software.items[i]).guid = swid then
                begin
                    result := tSwRecord(self.m_software.items[i]).commands;
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
                cmdRec  := tCmdRecord.create;
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
    var
        i:            integer;
        taskFeedBack: tTaskRecordOPFeedBack;
    begin
        taskFeedBack := tTaskRecordOPFeedBack.create;

        case self.tOperation of
            DOR_INSERT: taskFeedBack.queryResult := sdbMgr.insertDBRecord(self.pRecord);
            DOR_UPDATE: taskFeedBack.queryResult := sdbMgr.updateDBRecord(self.pRecord);
            DOR_DELETE: taskFeedBack.queryResult := sdbMgr.deleteDBRecord(self.pRecord);
        end;

        taskFeedBack.pRecord    := self.pRecord;
        taskFeedBack.tOperation := self.tOperation;
        setLength(taskFeedBack.dummyTargets, length(self.dummyTargets));

        for i := 0 to pred( length(self.dummyTargets) ) do
            taskFeedBack.dummyTargets[i] := self.dummyTargets[i];

        sTaskMgr.pushTaskToOutput(taskFeedBack);
    end;

    procedure tTaskRecordOPFeedBack.exec;
    var
        i:        integer;
        node:     tTreeNode;
        tvConfig: tTreeView;
    begin
        if not (self.dummyTargets[0] is tTreeView) then
            exit;

        tvConfig := self.dummyTargets[0] as tTreeView;

        case self.tOperation of
            DOR_INSERT:
                if assigned(self.pRecord) then
                begin
                    if (self.pRecord is tSwRecord) then
                    begin
                        node      := tvConfig.items.add( nil, tSwRecord(self.pRecord).name );
                        node.data := self.pRecord;
                        tvConfig.items.addChild( node, tCmdRecord(tSwRecord(self.pRecord).commands.first).name ).data := tSwRecord(self.pRecord).commands.first;
                        node.expand(true);
                        exit;
                    end;

                    if (self.pRecord is tCmdRecord) then
                        for i := 0 to pred(tvConfig.items.count) do
                            if tCmdRecord(self.pRecord).swid = tSwRecord(tvConfig.items[i]).guid then
                            begin
                                tvConfig.items.addChild( tvConfig.items[i], tCmdRecord(self.pRecord).name ).data := self.pRecord;
                                exit;
                            end;
                end;
            DOR_UPDATE:
            begin
                for i := 0 to pred(tvConfig.items.count) do
                    if (self.pRecord is tSwRecord) and
                       (tvConfig.items[i].hasChildren) and
                       ( tSwRecord(self.pRecord).guid = tSwRecord(tvConfig.items[i].data).guid ) then
                    begin
                        tvConfig.items[i].text := tSwRecord(self.pRecord).name;
                        break;
                    end
                    else if (self.pRecord is tCmdRecord) and
                            (not tvConfig.items[i].hasChildren) and
                            ( tCmdRecord(self.pRecord).guid = tCmdRecord(tvConfig.items[i].data).guid) then
                            begin
                                tvConfig.items[i].text := tCmdRecord(self.pRecord).name;

                                if ( length(self.dummyTargets) = 2 ) and
                                   (self.dummyTargets[1] is tLabeledEdit) then
                                begin
                                    if ( tCmdRecord(self.pRecord).guid = tCmdRecord(tvConfig.selected.data).guid ) then
                                    begin
                                        if self.queryResult then
                                            (self.dummyTargets[1] as tLabeledEdit).color := $0080FF80 // Verde
                                        else
                                            (self.dummyTargets[1] as tLabeledEdit).color := $008080FF; // Rosso
                                    end
                                    else if not self.queryResult then
                                    begin
                                        tvConfig.selected := tvConfig.items[i];
                                        (self.dummyTargets[1] as tLabeledEdit).color := $008080FF; // Rosso
                                    end;
                                end;
                                break;
                            end;
            end;
            DOR_DELETE:
                if not assigned(self.pRecord) then
                    for i := 0 to pred(tvConfig.items.count) do
                        if not assigned(tvConfig.items[i].data) then
                        begin
                            tvConfig.items[i].delete;
                            exit;
                        end
                        else
                        begin
                            node := tvConfig.items[i].getFirstChild;
                            while( assigned(node) and assigned(node.data) ) do
                                node := tvConfig.items[i].GetNextChild(node);
                            node.free;
                        end;
        end
    end;

    procedure tTaskGetVer.exec;
    var
        versionInfo: lastStableVer;
        returnTask:  tTaskSetVer;
    begin
        versionInfo      := sUpdateParser.getLastStableInfoFromURL(self.cmdRec.uURL);
        self.cmdRec.cVER := versionInfo[ integer(currentVer) ];
        self.cmdRec.cURL := versionInfo[ integer(currentUrl) ];

        returnTask                 := tTaskSetVer.create;
        returnTask.cmdRec          := self.cmdRec;
        returnTask.new_version     := self.cmdRec.cVER;

        setLength(returnTask.dummyTargets, length(self.dummyTargets));
        returnTask.dummyTargets[0] := self.dummyTargets[0];

        if length(self.dummyTargets) = 2 then        
            returnTask.dummyTargets[1] := self.dummyTargets[1];

        sTaskMgr.pushTaskToOutput(returnTask);
    end;

    procedure tTaskSetVer.exec;
    var
        targetIt: tListItem;
    begin
        if not (self.dummyTargets[0] is tListItem) then
            exit;

        targetIt := self.dummyTargets[0] as tListItem;

        if ( targetIt.data = self.cmdRec ) then
        begin
            if targetIt.subItems[pred( integer(lvColVA) )] = self.new_version then
                targetIt.stateIndex := tImageIndex(eiDotGreen)
            else if (targetIt.subItems[pred( integer(lvColVA) )] = RemoteVersionNotAvailable) then
                targetIt.stateIndex := tImageIndex(eiDotYellow)
            else 
            begin
                targetIt.stateIndex := tImageIndex(eiDotRed);

                if ( length(self.dummyTargets) = 2 ) and
                   ( not (self.dummyTargets[1] is tTabSheet) ) then
                    (self.dummyTargets[1] as tTabSheet).ImageIndex := tImageIndex(tiUpdateNotif);
            end;

           targetIt.subItems[ integer(lvColVA) ] := self.new_version;
        end;
    end;

end.

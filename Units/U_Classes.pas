unit U_Classes;

interface

uses
    System.UITypes, System.Classes, System.SyncObjs, System.Variants, System.SysUtils,
    Vcl.ComCtrls, IdHTTP, System.Types, MSHTML, Vcl.Dialogs, ActiveX, System.StrUtils,
    ShellAPI, Windows, Forms,

    U_Functions;

type
    tTabImage   = (tiNoImg = -1, tiInstall, tiConfig, tiUpdate, tiEvents, tiEvtErr);
    tEventImage = (eiNoImg = -1, eiInfo, eiAlert, eiError);

    // Array for Results
    ArrayReturn = Array[0..2] of String;

    // Custom Node for Config
    tSoftwareTreeNode = class(tTreeNode)
        public
            softwareID, commandID, order, compatibility, mainCommand: integer;
            software, version, description, command, URL:             string;
    end;

    thread = class(tThread)
        public
            constructor create; reintroduce;

        protected
            procedure Execute; override;
    end;

    tTask = class // Ogni classe derivata da TTask implementa il metodo virtuale 'exec' che permette l'esecuzione, da parte del thread, del compito assegnatogli
        public
            procedure exec; virtual; abstract;
    end;

    tTaskGetVer = class(tTask) // Task per verificare la versione del programma da scaricare
        public
            URL:     string;
            version: string;

            procedure exec; override;
    end;

    tTaskDownload = class(tTask) // Task per scaricare l'installer
        public
            URL:        string;
            dataStream: tMemoryStream;

            procedure exec; override;
    end;

    tTaskFlush = class(tTask) // Task per scrivere il MemoryStream su file
        public
            fileName:   string;
            dataStream: tMemoryStream;

            procedure exec; override;
    end;

    tStatus = (initializing, processing, completed, failed);

    tTaskReport = class(tTask) // Task per comunicare al thread principale lo stato di un download
        public
            id:     word;
            status: tStatus;
            param:  integer; // Percentuale completamento in caso 'status = processing' o codice errore in caso 'status = failed'
    end;

    tThreads = Array of thread;

    taskManager = class // Wrapper di funzioni ed oggetti relativi alla gestione dei task
        public
            constructor create; overload;
            constructor create(const threadsCount: byte); overload;
            destructor  Destroy; override;

            procedure pushTaskToInput(taskToAdd: tTask);
            function  pullTaskFromInput: tTask;
            procedure pushTaskToOutput(taskToAdd: tTask);
            function  pullTaskFromOutput: tTask;

        protected
            m_threadPool: tThreads;
            m_inputMutex, m_outputMutex: tMutex;
            m_inputTasks, m_outputTasks: tList;

            procedure pushTaskToQueue(taskToAdd: tTask; taskQueue: tList; queueMutex: tMutex);
            function  pullTaskFromQueue(taskQueue: tList; queueMutex: tMutex): tTask;
    end;

    updateParser = class // Wrapper di funzioni ed helper per parsare l'html
        protected
            function getVersionFromFileName(swName: string): string;
            function isAcceptableVersion(version: string): boolean;
            function getDirectDownloadLink(swLink: string): string;
            function srcToIHTMLDocument3(srcCode: string): IHTMLDocument3;
            function getLastStableVerFromSrc(srcCode: IHTMLDocument3): string;

        public
            function getLastStableVerFromURL(baseURL: string): string;
            function getLastStableLink(baseURL: string): string;
    end;

    downloadManager = class // Wrapper di funzioni per gestire i download
        public
            function downloadLastStableVersion(URL: string): tMemoryStream;
            function downloadPageSource(URL: string): string;
    end;

    fileManager = class
        public
            procedure saveDataStreamToFile(fileName: string; dataStream: tMemoryStream);
            procedure startInstallerWithCMD(cmd: string);
    end;

    tEvent = class
        eventDesc,
        eventTime:  string;
        eventType:  tImageIndex;
        constructor create(eDesc: string; eType: tEventImage);
    end;

    eventHandler = class
        public
            constructor create;
            procedure   pushEventToList(event: tEvent);
            function    pullEventFromList: tEvent;
            function    isEventListEmpty:  boolean;
            function    getErrorCache:     boolean;
            procedure   clearErrorCache;
        protected
            m_eventMutex:     tMutex;
            m_eventList:      tList;
            m_containsErrors: boolean;
    end;

const
    softwareUpdateBaseURL       = 'http://www.filehippo.com/';
    defaultMaxConnectionRetries = 3;
    defaultThreadPoolSleepTime  = 50;

var
    sTaskMgr:      taskManager;
    sUpdateParser: updateParser;
    sDownloadMgr:  downloadManager;
    sFileMgr:      fileManager;
    sEventHdlr:    eventHandler;

implementation

// Implementation of
//------------------------------------------------------------------------------

    // thread

    constructor thread.create;
    begin
        inherited create(false);
    end;

    procedure thread.execute;
    var
        task: tTask;
    begin
        while not(self.terminated) do
        begin
            if not( assigned(sTaskMgr) ) then
            begin
                sleep(defaultThreadPoolSleepTime);
                continue;
            end;

            task := sTaskMgr.pullTaskFromInput();

            if not( assigned(task) ) then
            begin
                sleep(defaultThreadPoolSleepTime);
                continue;
            end;

            task.exec; // TODO: Verifica che non faccia crashare qualora exec non fosse overridden
            task.free;
        end;
    end;

    // Implementazioni tTask

    procedure tTaskGetVer.exec;
    var
        returnTask: tTaskGetVer;
    begin
        returnTask := tTaskGetVer.create;
        returnTask.URL := self.URL;
        returnTask.version := sUpdateParser.getLastStableVerFromURL(returnTask.URL);
        sTaskMgr.pushTaskToOutput(returnTask);
    end;

    procedure tTaskDownload.exec;
    begin
        self.dataStream := sDownloadMgr.downloadLastStableVersion(self.URL)
    end;

    procedure tTaskFlush.exec;
    begin
        sFileMgr.saveDataStreamToFile(self.fileName, self.dataStream)
    end;

    // taskManager

    constructor taskManager.create;
    begin
        self.create(CPUCount)
    end;

    destructor taskManager.Destroy;
    var
        i: integer;
    begin
        for i := 0 to pred(length(m_threadPool)) do
            m_threadPool[i].terminate;

        for i := 0 to pred(length(m_threadPool)) do
        begin
            m_threadPool[i].waitFor;
            m_threadPool[i].free;
        end;

        inherited;
    end;

    constructor taskManager.create(const threadsCount: byte);
    var
        i: byte;
    begin
        m_inputMutex  := tMutex.create;
        m_outputMutex := tMutex.create;
        m_inputTasks  := tList.create;
        m_outputTasks := tList.create;

        setLength(m_threadPool, threadsCount);

        sEventHdlr.pushEventToList(tEvent.create('Inizializzazione ThreadPool (' + IntToStr(threadsCount) + ' threads).', eiInfo));

        for i := 0 to threadsCount - 1 do
            m_threadPool[i] := thread.create();
    end;

    procedure taskManager.pushTaskToInput(taskToAdd: tTask);
    begin
        self.pushTaskToQueue(taskToAdd, m_inputTasks, m_inputMutex)
    end;

    function taskManager.pullTaskFromInput(): tTask;
    begin
        result := self.pullTaskFromQueue(m_inputTasks, m_inputMutex)
    end;

    procedure taskManager.pushTaskToOutput(taskToAdd: tTask);
    begin
        self.pushTaskToQueue(taskToAdd, m_outputTasks, m_outputMutex)
    end;

    function taskManager.pullTaskFromOutput(): tTask;
    begin
        result := self.pullTaskFromQueue(m_outputTasks, m_outputMutex)
    end;

    procedure taskManager.pushTaskToQueue(taskToAdd: tTask; taskQueue: tList; queueMutex: tMutex);
    begin
        queueMutex.acquire;
        taskQueue.add(taskToAdd);
        queueMutex.release;
    end;

    function taskManager.pullTaskFromQueue(taskQueue: tList; queueMutex: tMutex): tTask;
    begin
        queueMutex.acquire;

        if taskQueue.count > 0 then
        begin
            result := tTask(taskQueue.first);
            taskQueue.remove(taskQueue.first);
        end
        else
            result := nil;


        queueMutex.release;
    end;

    // updateParser

    function updateParser.getVersionFromFileName(swName: string): string;
    var
      i:          byte;
      swParts:    tStringList;
      chkVer:     boolean;
      testStr:    string;
    begin
        swParts := split(swName, ' ');

        for testStr in swParts do
        begin
            chkVer := true;
            for i := 1 to length(testStr) do
                 if not( charInSet(testStr[i], ['0'..'9']) or (testStr[i] = '.') ) then
                 begin
                    chkVer := False;
                    break;
                 end;

            if chkVer then
                if ansiContainsText(testStr, '.') then
                begin
                    result := testStr;
                    swParts.free;
                    exit;
                end;
        end;
        result := 'N/D';
        sEventHdlr.pushEventToList(tEvent.create('Impossibile ottenere la versione del software: ' + swName, eiError));
        swParts.free;
    end;

    function updateParser.isAcceptableVersion(version: string): boolean;
    begin
        result := true;

        // TODO: Aggiungere un sistema di eccezioni su db?
        if ansiContainsText(version, 'alpha') or
           ansiContainsText(version, 'beta')  or
           ansiContainsText(version, 'rc')    or
           ansiContainsText(version, 'dev')   or
          (self.getVersionFromFileName(version) = 'N/D') then
        begin
            result := false;
            sEventHdlr.pushEventToList(tEvent.create('Versione ' + version + ' non accettabile.', eiInfo));
        end;
    end;

    function updateParser.srcToIHTMLDocument3(srcCode: string): iHTMLDocument3;
    var
        V:       oleVariant;
        srcDoc2: iHTMLDocument2;
    begin
        srcDoc2 := coHTMLDocument.create as iHTMLDocument2;
        V := varArrayCreate([0, 0], varVariant);
        V[0] := srcCode;
        srcDoc2.write( pSafeArray(tVarData(V).vArray) );
        srcDoc2.close;

        try // TODO: Serve questo try?
            result := srcDoc2 as iHTMLDocument3;
        except
            on e: exception do
                sEventHdlr.pushEventToList( tEvent.create(e.className + ': ' + e.message, eiError) );
        end;
    end;

    function updateParser.getDirectDownloadLink(swLink: string): string;
    var
        i:       byte;
        srcTags: iHTMLElementCollection;
        srcTagE: iHTMLElement;
        srcElem: iHTMLElement2;
        srcDoc3: iHTMLDocument3;
    begin
        result := '';
        srcDoc3 := self.srcToIHTMLDocument3( sDownloadMgr.downloadPageSource(swLink) );

        // ricavo il link diretto di download
        srcTags := srcDoc3.getElementsByTagName('meta');
        for i := 0 to pred(srcTags.length) do
        begin
            srcTagE := srcTags.item(i, emptyParam) as iHTMLElement;
            if ansiContainsText(srcTagE.outerHTML, 'refresh') then
            begin
                result := ansiMidStr(srcTagE.outerHTML,
                          ansiPos('url', srcTagE.outerHTML),
                          lastDelimiter('"', srcTagE.outerHTML) - ansiPos('url', srcTagE.outerHTML));
                result := stringReplace(result, 'url=/', softwareUpdateBaseURL, [rfIgnoreCase]);
                break;
            end;
        end;

        if (result = '') then
            begin
                srcElem := srcDoc3.getElementById('dlbox') as iHTMLElement2;
                srcTags := srcElem.getElementsByTagName('a');
                for i := 0 to pred(srcTags.length) do
                begin
                    srcTagE := srcTags.item(i, EmptyParam) as iHTMLElement;
                    if ansiContainsText(srcTagE.innerText, 'scarica') then
                        begin
                            result := srcTagE.getAttribute('href', 0);
                            result := ansiReplaceStr(result, 'about:/', softwareUpdateBaseURL);
                            result := self.getDirectDownloadLink(result);
                            break;
                        end;
                end;
            end;
    end;


    function updateParser.getLastStableVerFromURL(baseURL: string): string;
    var
        srcDoc3: iHTMLDocument3;
    begin
        srcDoc3 := self.srcToIHTMLDocument3(sDownloadMgr.downloadPageSource(baseURL));
        result  := self.getLastStableVerFromSrc(srcDoc3);
    end;

    function updateParser.getLastStableVerFromSrc(srcCode: iHTMLDocument3): string;
    var
        i:       byte;
        srcTags: iHTMLElementCollection;
        srcTagE: iHTMLElement;
        srcElem: iHTMLElement2;
    begin
        result  := '';

        srcElem := srcCode.getElementById('dlboxinner') as iHTMLElement2;

        // verifico se l'ultima versione e' stabile
        srcTags := srcElem.getElementsByTagName('b');
        for i := 0 to pred(srcTags.length) do
        begin
            srcTagE := srcTags.item(i, EmptyParam) as iHTMLElement;
            if self.isAcceptableVersion(srcTagE.innerText) then
            begin
                result := self.getVersionFromFileName( trim(srcTagE.innerText) );
                break;
            end
            else
                sEventHdlr.pushEventToList( tEvent.create('Versione non accettabile: ' + srcTagE.innerText + '.', eiInfo) );
        end;

        // altrimenti passo alle precedenti
        if (result = '') then
        begin
            srcTags := srcElem.getElementsByTagName('a');
            for i := 0 to pred(srcTags.length) do
            begin
                srcTagE := srcTags.item(i, EmptyParam) as iHTMLElement;
                if self.isAcceptableVersion(srcTagE.innerText) then
                begin
                    result := self.getVersionFromFileName( trim(srcTagE.innerText) );
                    break;
                end
                else
                    sEventHdlr.pushEventToList( tEvent.create('Versione non accettabile: ' + srcTagE.innerText + '.', eiInfo) );
            end;
        end;

        if (result = '') then
        begin
            sEventHdlr.pushEventToList( tEvent.create('Nessuna versione accettabile trovata.', eiAlert) );
            result := 'N/D';
        end;
    end;

    function updateParser.getLastStableLink(baseURL: string): string;
    var
        i:       byte;
        targetV: string;
        srcTags: iHTMLElementCollection;
        srcTagE: iHTMLElement;
        srcElem: iHTMLElement2;
        srcDoc3: iHTMLDocument3;
    begin
        result  := '';

        srcDoc3 := self.srcToIHTMLDocument3( sDownloadMgr.downloadPageSource(baseURL) );
        targetV := self.getLastStableVerFromSrc(srcDoc3);
        srcElem := srcDoc3.getElementById('dlbox') as iHTMLElement2;

        // cerco il link alla ultima versione stabile
        srcTags := srcElem.getElementsByTagName('a');
        for i := 0 to pred(srcTags.length) do
        begin
            srcTagE := srcTags.item(i, EmptyParam) as iHTMLElement;
            if ansiContainsText(srcTagE.innerText, 'scarica') then
                result := srcTagE.getAttribute('href', 0)
            else if ansiContainsText( srcTagE.innerText, targetV ) then
                begin
                    result := srcTagE.getAttribute('href', 0);
                    break;
                end;
        end;
        result := ansiReplaceStr(result, 'about:/', softwareUpdateBaseURL);
        result := self.getDirectDownloadLink(result);
    end;

    // downloadManager

    function downloadManager.downloadLastStableVersion(URL: string): tMemoryStream;
    var
        http:  tIdHTTP;
        tries: byte;
    begin
        result := nil;
        tries  := 0;
        http   := tIdHTTP.Create;
        http.handleRedirects := true;
        try
            repeat
                inc(tries);
                try
                    http.get(URL, result);
                    http.disconnect;
                    break;
                except
                    on e: exception do
                        sEventHdlr.pushEventToList( tEvent.create(e.ClassName + ': ' + e.Message, eiError) );
                end;
            until (tries = defaultMaxConnectionRetries);
        finally
            http.free;
        end;
    end;

    function downloadManager.downloadPageSource(URL: string): string;
    var
        http:  tIdHTTP;
        tries: byte;
    begin
        result := '';
        tries  := 0;
        http   := tIdHTTP.Create;
        try
            repeat
                inc(tries);
                try
                    result  := http.get(URL);
                    http.disconnect;
                except
                    on e: exception do
                        sEventHdlr.pushEventToList( tEvent.create(e.ClassName + ': ' + e.Message, eiError) );
                end;
            until (tries = defaultMaxConnectionRetries);
        finally
            http.free;
        end;
    end;

    // fileManager

    procedure fileManager.saveDataStreamToFile(fileName: string; dataStream: tMemoryStream);
    begin
        dataStream.saveToFile(fileName)
    end;

    procedure fileManager.startInstallerWithCMD(cmd: string);
    begin
        // TODO
    end;

    // eventHandler

    constructor tEvent.create(eDesc: string; eType: tEventImage);
    begin
        self.eventType := tImageIndex(eType);
        self.eventTime := FormatDateTime('hh:nn:ss', now);
        self.eventDesc := eDesc;
    end;

    constructor eventHandler.create;
    begin
        m_eventMutex := tMutex.create;
        m_eventList := tList.create;
    end;

    procedure eventHandler.pushEventToList(event: tEvent);
    begin
        m_eventMutex.acquire;
        m_eventList.add(event);
        m_eventMutex.release;

        if event.eventType = tImageIndex(eiError) then
            m_containsErrors := true;
    end;

    function eventHandler.pullEventFromList: tEvent;
    begin
        m_eventMutex.acquire;

        if m_eventList.count = 0 then
        begin
            m_eventMutex.release;
            result := nil;
            exit;
        end;

        result := tEvent(m_eventList.first);
        m_eventList.remove(m_eventList.first);
        m_eventMutex.release;
    end;

    function eventHandler.isEventListEmpty: boolean;
    begin
        m_eventMutex.acquire;
        result := (m_eventList.count = 0);
        m_eventMutex.release;
    end;

    function eventHandler.getErrorCache: boolean;
    begin
        result := m_containsErrors;
    end;

    procedure eventHandler.clearErrorCache;
    begin
        m_containsErrors := false;
    end;
end.


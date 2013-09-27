unit U_Classes;

interface

uses
    System.UITypes, System.Classes, System.SyncObjs, System.Variants, System.SysUtils,
    Vcl.ComCtrls, IdHTTP, System.Types, MSHTML, Vcl.Dialogs, ActiveX, System.StrUtils,
    ShellAPI, Windows, Forms,

    U_Functions;

type
    tImgIndex = (NoImag = -1, Instal, Config, Update, Events, EvtErr, Errors);

    // Array for Results
    ArrayReturn = Array[0..2] of String;

    // Custom Node for Config
    tSoftwareTreeNode = class(tTreeNode)
        public
            softwareID, commandID, order, compatibility, mainCommand:   integer;
            software, version, description, command, URL:               string;
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

            procedure exec; override;
    end;

    tThreads = Array of thread;

    taskManager = class // Wrapper di funzioni ed oggetti relativi alla gestione dei task
        public
            constructor create; overload;
            constructor create(const threadsCount: byte); overload;

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
        imageType: tImageIndex;
        value: string;
    end;

    eventHandler = class
        public
            constructor create;
            procedure pushEventToList(event: tEvent);
            function  pullEventFromList: tEvent;
            function  isEventListEmpty:  boolean;
        protected
            m_eventMutex: tMutex;
            m_eventList:  tList;
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

    // TODO: inizializza tutte le variabili delle classi... T^T

    // thread

    constructor thread.create;
    begin
        inherited create(false);
        freeOnTerminate := true;
    end;

    procedure thread.execute;
    var
        task: tTask;
    begin
        while not(self.Terminated) do
            begin
                task := sTaskMgr.pullTaskFromInput();

                if assigned(task) then
                    begin
                        sleep(defaultThreadPoolSleepTime);
                        continue;
                     end;

                task.exec;
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

    procedure tTaskReport.exec; // Dummy. Il report non ha motivo di essere eseguito (esiste solo in uscita)
    begin
        exit
    end;

    // taskManager

    constructor taskManager.create;
    begin
        self.create(CPUCount)
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
        m_outputMutex.acquire;
        m_outputTasks.add(taskToAdd);
        m_outputMutex.release;
    end;

    function taskManager.pullTaskFromQueue(taskQueue: tList; queueMutex: tMutex): tTask;
    begin
        queueMutex.acquire;

        if taskQueue.Count > 0 then
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
      i:          Byte;
      swParts:    TStringList;
      chkVer:     Boolean;
      testStr:    String;
    begin
        swParts := split(swName, ' ');

        for testStr in swParts do
        begin
            chkVer := True;
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
              result := false;
    end;

    function updateParser.srcToIHTMLDocument3(srcCode: string): IHTMLDocument3;
    var
        V:       OleVariant;
        srcDoc2: IHTMLDocument2;
    begin
        srcDoc2 := coHTMLDocument.Create as IHTMLDocument2;
        V := VarArrayCreate([0, 0], varVariant);
        V[0] := srcCode;
        srcDoc2.Write(PSafeArray(TVarData(V).VArray));
        srcDoc2.Close;

        result := srcDoc2 as IHTMLDocument3;
    end;

    function updateParser.getDirectDownloadLink(swLink: string): string;
    var
        i:       Byte;
        srcTags: IHTMLElementCollection;
        srcTagE: IHTMLElement;
        srcElem: IHTMLElement2;
        srcDoc3: IHTMLDocument3;
    begin
        result := '';
        srcDoc3 := self.srcToIHTMLDocument3(sDownloadMgr.downloadPageSource(swLink));

        // ricavo il link diretto di download
        srcTags := srcDoc3.getElementsByTagName('meta');
        for i := 0 to pred(srcTags.length) do
        begin
            srcTagE := srcTags.item(i, EmptyParam) as IHTMLElement;
            if ansiContainsText(srcTagE.outerHTML, 'refresh') then
            begin
                result := ansiMidStr(srcTagE.outerHTML,
                          ansiPos('url', srcTagE.outerHTML),
                          LastDelimiter('"', srcTagE.outerHTML) - ansiPos('url', srcTagE.outerHTML));
                result := StringReplace(result, 'url=/', softwareUpdateBaseURL, [rfIgnoreCase]);
                break;
            end;
        end;

        if (result = '') then
            begin
                srcElem := srcDoc3.getElementById('dlbox') as IHTMLElement2;
                srcTags := srcElem.getElementsByTagName('a');
                for i := 0 to pred(srcTags.length) do
                begin
                    srcTagE := srcTags.item(i, EmptyParam) as IHTMLElement;
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
        srcDoc3: IHTMLDocument3;
    begin
        srcDoc3 := self.srcToIHTMLDocument3(sDownloadMgr.downloadPageSource(baseURL));
        result := self.getLastStableVerFromSrc(srcDoc3)
    end;

    function updateParser.getLastStableVerFromSrc(srcCode: IHTMLDocument3): string;
    var
        i:       Byte;
        srcTags: IHTMLElementCollection;
        srcTagE: IHTMLElement;
        srcElem: IHTMLElement2;
    begin
        result := '';

        srcElem := srcCode.getElementById('dlboxinner') as IHTMLElement2;

        // verifico se l'ultima versione e' stabile
        srcTags := srcElem.getElementsByTagName('b');
        for i := 0 to pred(srcTags.length) do
        begin
            srcTagE := srcTags.item(i, EmptyParam) as IHTMLElement;
            if self.isAcceptableVersion(srcTagE.innerText) then
            begin
                result := self.getVersionFromFileName( trim(srcTagE.innerText) );
                break;
            end;
        end;

        // altrimenti passo alle precedenti
        if (result = '') then
        begin
            srcTags := srcElem.getElementsByTagName('a');
            for i := 0 to pred(srcTags.length) do
            begin
                srcTagE := srcTags.item(i, EmptyParam) as IHTMLElement;
                if self.isAcceptableVersion(srcTagE.innerText) then
                begin
                    result := self.getVersionFromFileName( trim(srcTagE.innerText) );
                    break;
                end;
            end;
        end;

        if (result = '') then
            result := 'N/D';
    end;

    function updateParser.getLastStableLink(baseURL: string): string;
    var
        i:       Byte;
        targetV: String;
        srcTags: IHTMLElementCollection;
        srcTagE: IHTMLElement;
        srcElem: IHTMLElement2;
        srcDoc3: IHTMLDocument3;
    begin
        result := '';

        srcDoc3 := self.srcToIHTMLDocument3( sDownloadMgr.downloadPageSource(baseURL) );
        targetV := self.getLastStableVerFromSrc(srcDoc3);
        srcElem := srcDoc3.getElementById('dlbox') as IHTMLElement2;

        // cerco il link alla ultima versione stabile
        srcTags := srcElem.getElementsByTagName('a');
        for i := 0 to pred(srcTags.length) do
        begin
            srcTagE := srcTags.item(i, EmptyParam) as IHTMLElement;
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
        event: tEvent;
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
                    on E: exception do
                    begin
                        event := tEvent.create;
                        event.value := E.ClassName + ': ' + E.Message;
                        event.imageType :=  tImageIndex(Errors);
                        sEventHdlr.pushEventToList(event);
                    end;
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
        event: tEvent;
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
                    on E: exception do
                    begin
                        event := tEvent.create;
                        event.value := E.ClassName + ': ' + E.Message;
                        event.imageType := tImageIndex(Errors);
                        sEventHdlr.pushEventToList(event);
                    end;
                end;
            until (tries = defaultMaxConnectionRetries);
        finally
            http.free;
        end;
    end;

    // fileManager

    procedure fileManager.saveDataStreamToFile(fileName: string; dataStream: tMemoryStream);
    begin
        dataStream.SaveToFile(fileName)
    end;

    procedure fileManager.startInstallerWithCMD(cmd: string);
    begin
        // TODO
    end;

    // eventHandler

    constructor eventHandler.create;
    begin
        m_eventMutex := tMutex.create;
        m_eventList := tList.create;
    end;

    procedure eventHandler.pushEventToList(event: tEvent);
    begin
        m_eventMutex.acquire;
        m_eventList.add(event);
        ReleaseExceptionObject;
        m_eventMutex.release;
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
end.


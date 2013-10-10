unit U_Download;

interface

uses
    System.Classes, IdHTTP, System.SysUtils, IdComponent, vcl.comCtrls,

    U_Events, U_Threads, U_InputTasks, U_OutputTasks;

type
    tTaskDownload = class(tTask) // Task per scaricare l'installer
        protected
            dlmax,
            dlcur,
            dlchunk:    int64;
            procedure   onDownload(aSender: tObject; aWorkMode: tWorkMode; aWorkCount: Int64);
            procedure   onDownloadBegin(aSender: tObject; aWorkMode: tWorkMode; aWorkCountMax: Int64);
        public
            URL:        string;
            dummyProgB: tProgressBar;
            dataStream: tMemoryStream;
            procedure   exec; override;
    end;

    tTaskDownloadReport = class(tTaskOutput)
        public
            dlPct:      byte;
            dummyProgB: tProgressBar;
            procedure   exec; override;
    end;

    downloadManager = class // Wrapper di funzioni per gestire i download
        protected
            m_dlmax,
            m_dlchunk: int64;
        public
            function   downloadLastStableVersion(URL: string; eOnWork, eOnWorkBegin: tWorkEvent): tMemoryStream;
            function   downloadPageSource(URL: string): string;
    end;

const
    defaultMaxConnectionRetries = 3;

var
    sDownloadMgr: downloadManager;

implementation

    procedure tTaskDownload.onDownload(aSender: tObject; aWorkMode: tWorkMode; aWorkCount: Int64);
    var
        reportTask: tTaskDownloadReport;
    begin
        if aWorkCount >= (self.dlchunk * self.dlcur) then
        begin
            self.dlcur            := (self.dlchunk * self.dlcur) div aWorkCount;

            reportTask            := tTaskDownloadReport.create;
            reportTask.dlPct      := trunc( (aWorkCount / self.dlmax) * 100 );
            reportTask.dummyProgB := self.dummyProgB;

            sTaskMgr.pushTaskToOutput(reportTask);
        end
        else if aWorkCount = self.dlmax then
        begin
            self.dlcur            := 100;

            reportTask            := tTaskDownloadReport.create;
            reportTask.dlPct      := 100;
            reportTask.dummyProgB := self.dummyProgB;

            sTaskMgr.pushTaskToOutput(reportTask);
        end;
    end;

    procedure tTaskDownload.onDownloadBegin(aSender: tObject; aWorkMode: tWorkMode; aWorkCountMax: Int64);
    begin
        self.dlcur   := 0;
        self.dlmax   := aWorkCountMax;
        self.dlchunk := self.dlmax div 100;
    end;

    procedure tTaskDownloadReport.exec;
    begin
        self.dummyProgB.position := self.dlPct;
    end;

    function downloadManager.downloadLastStableVersion(URL: string; eOnWork, eOnWorkBegin: tWorkEvent): tMemoryStream;
    var
        http:  tIdHTTP;
        tries: byte;
    begin
        result               := nil;
        tries                := 0;
        http                 := tIdHTTP.create;
        http.onWork          := eOnWork;
        http.onWorkBegin     := eOnWorkBegin;
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
                        sEventHdlr.pushEventToList('Impossibile scaricare il file: ' + e.Message, eiError);
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
                        sEventHdlr.pushEventToList('Impossibile caricare la pagina: ' + e.Message, eiError);
                end;
            until (tries = defaultMaxConnectionRetries);
        finally
            http.free;
        end;
    end;

    procedure tTaskDownload.exec;
    begin
        self.dataStream := sDownloadMgr.downloadLastStableVersion(self.URL, self.onDownload, self.onDownloadBegin);
    end;

end.

unit U_Download;

interface

uses
    System.Classes, IdHTTP, System.SysUtils,

    U_Events, U_InputTasks;

type
    tTaskDownload = class(tTask) // Task per scaricare l'installer
        public
            URL:        string;
            dataStream: tMemoryStream;

            procedure exec; override;
    end;

    downloadManager = class // Wrapper di funzioni per gestire i download
        public
            function downloadLastStableVersion(URL: string): tMemoryStream;
            function downloadPageSource(URL: string): string;
    end;

const
    defaultMaxConnectionRetries = 3;

var
    sDownloadMgr: downloadManager;

implementation

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
        self.dataStream := sDownloadMgr.downloadLastStableVersion(self.URL)
    end;

end.

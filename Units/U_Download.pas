unit U_Download;

interface

uses
    System.Classes, IdHTTP, System.SysUtils, IdComponent,

    U_Events, U_Threads, U_InputTasks, U_OutputTasks;

type
    downloadManager = class // Wrapper di funzioni per gestire i download
        protected
            m_dlmax,
            m_dlchunk: int64;
        public
            function   downloadLastStableVersion(URL: string; eOnWork, eOnWorkBegin: tWorkEvent; eOnRedirect: TIdHTTPOnRedirectEvent): tMemoryStream;
            function   downloadPageSource(URL: string): string;
    end;

const
    defaultMaxConnectionRetries = 3;

var
    sDownloadMgr: downloadManager;

implementation
    function downloadManager.downloadLastStableVersion(URL: string; eOnWork, eOnWorkBegin: tWorkEvent; eOnRedirect: TIdHTTPOnRedirectEvent): tMemoryStream;
    var
        http:  tIdHTTP;
        tries: byte;
    begin
        result               := nil;
        tries                := 0;
        http                 := tIdHTTP.create;
        http.onWork          := eOnWork;
        http.onWorkBegin     := eOnWorkBegin;
        http.onRedirect      := eOnRedirect;
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

end.

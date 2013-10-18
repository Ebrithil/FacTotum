unit U_Parser;

interface

uses
    MSHTML, System.Classes, System.SysUtils, System.StrUtils, System.Variants, ActiveX, System.UITypes,

    U_Threads, U_Functions, U_Events, U_Download, U_InputTasks, U_OutputTasks;

type
    lastStableVerIndex = (currentVer, currentURL, maxStableVerIndex);

    lastStableVer = array of string;

    updateParser = class // Wrapper di funzioni ed helper per parsare l'html
        protected
            function getVersionFromFileName(swName: string): string;
            function isAcceptableVersion(version: string): boolean;
            function getDirectDownloadLink(swLink: string): string;
            function srcToIHTMLDocument3(srcCode: string): IHTMLDocument3;
            function getLastStableVerFromSrc(srcCode: IHTMLDocument3): string;
            function getLinkFromSrc(srcCode: IHTMLDocument3; version: string): string;
        public
            function getLastStableInfoFromURL(baseURL: string): lastStableVer;
    end;

const
    softwareUpdateBaseURL     = 'http://www.filehippo.com/';
    remoteVersionNotAvailable = 'N/D';

var
    sUpdateParser: updateParser;

implementation

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
        result := remoteVersionNotAvailable;
        createEvent('Impossibile ricavare la versione: ' + swName, eiAlert);
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
          ( self.getVersionFromFileName(version) = remoteVersionNotAvailable ) then
            result := false;
    end;

    function updateParser.srcToIHTMLDocument3(srcCode: string): iHTMLDocument3;
    var
        V:       oleVariant;
        srcDoc2: iHTMLDocument2;
    begin
        coInitialize(nil);
        srcDoc2 := coHTMLDocument.create as iHTMLDocument2;
        V := varArrayCreate([0, 0], varVariant);
        V[0] := srcCode;
        srcDoc2.write( pSafeArray(tVarData(V).vArray) );
        srcDoc2.close;

        V := Unassigned;

        result := srcDoc2 as iHTMLDocument3;
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


    function updateParser.getLastStableInfoFromURL(baseURL: string): lastStableVer;
    var
        srcDoc3: iHTMLDocument3;
        V:       array of string;
    begin
        setLength( result, integer(maxStableVerIndex) );
        srcDoc3                       := self.srcToIHTMLDocument3(sDownloadMgr.downloadPageSource(baseURL));
        result[ integer(currentVer) ] := self.getLastStableVerFromSrc(srcDoc3);
        result[ integer(currentUrl) ] := self.getLinkFromSrc( srcDoc3, result[integer(currentVer)] );

        setLength(V, 1);
        V[0]    := '';

        (srcDoc3 as iHTMLDocument2).write( pSafeArray(V) );
        (srcDoc3 as iHTMLDocument2).close;

        srcDoc3 := nil;

        CoFreeUnusedLibraries;
    end;

    function updateParser.getLastStableVerFromSrc(srcCode: iHTMLDocument3): string;
    var
        i:       byte;
        srcTags: iHTMLElementCollection;
        srcTagE: iHTMLElement;
        srcElem: iHTMLElement2;
    begin
        srcElem := srcCode.getElementById('dlboxinner') as iHTMLElement2;

        if not assigned(srcElem) then
        begin
            createEvent( 'Errore nella ricerca della versione.', eiError);
            result := RemoteVersionNotAvailable;
            exit;
        end;

        // verifico se l'ultima versione e' stabile
        srcTags := srcElem.getElementsByTagName('b');
        if not assigned(srcTags) then
        begin
            createEvent( 'Errore nella ricerca della versione.', eiAlert);
            result := remoteVersionNotAvailable;
            exit;
        end;

        for i := 0 to pred(srcTags.length) do
        begin
            srcTagE := srcTags.item(i, EmptyParam) as iHTMLElement;
            if self.isAcceptableVersion(srcTagE.innerText) then
            begin
                result := self.getVersionFromFileName( trim(srcTagE.innerText) );
                exit;
            end;
        end;

        // altrimenti passo alle precedenti
        srcTags := srcElem.getElementsByTagName('a');
        if not assigned(srcTags) then
        begin
            createEvent( 'Errore nella ricerca della versione.', eiAlert);
            result := RemoteVersionNotAvailable;
            exit;
        end;

        for i := 0 to pred(srcTags.length) do
        begin
            srcTagE := srcTags.item(i, EmptyParam) as iHTMLElement;
            if self.isAcceptableVersion(srcTagE.innerText) then
            begin
                result := self.getVersionFromFileName( trim(srcTagE.innerText) );
                exit;
            end
            //else
            //    sEventHdlr.pushEventToList('Versione non stabile: ' + srcTagE.innerText + '.', eiAlert);
        end;

        createEvent( 'Nessuna versione stabile trovata: ' + srcTagE.innerText + '.', eiAlert);
        result := remoteVersionNotAvailable;
    end;

    function updateParser.getLinkFromSrc(srcCode: IHTMLDocument3; version: string): string;
    var
        i:       byte;
        srcTags: iHTMLElementCollection;
        srcTagE: iHTMLElement;
        srcElem: iHTMLElement2;
    begin
        result  := '';

        srcElem := srcCode.getElementById('dlbox') as iHTMLElement2;

        // cerco il link alla ultima versione stabile
        srcTags := srcElem.getElementsByTagName('a');
        for i := 0 to pred(srcTags.length) do
        begin
            srcTagE := srcTags.item(i, EmptyParam) as iHTMLElement;
            if ansiContainsText(srcTagE.innerText, 'scarica') then
                result := srcTagE.getAttribute('href', 0)
            else if ansiContainsText( srcTagE.innerText, version ) then
                begin
                    result := srcTagE.getAttribute('href', 0);
                    break;
                end;
        end;
        result := ansiReplaceStr(result, 'about:/', softwareUpdateBaseURL);
        result := self.getDirectDownloadLink(result);
    end;

end.

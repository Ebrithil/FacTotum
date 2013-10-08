unit U_Files;

interface

uses
    IdHash, System.Classes, System.SysUtils, IdHashSHA, IdHashMessageDigest, ShellAPI, Winapi.Windows,

    U_Events, U_DataBase, U_InputTasks;

type
    fileManager = class
       protected
           m_hasher:   tIdHash;
           stpFolder:  string;
           procedure   addSetupToArchive(fileName: string); overload;
           function    getFileHash(fileName: string): string;
           function    getArchivePathFor(cmdGuid: integer): string;
           function    isArchived(cmdGuid: integer): boolean; overload;
           function    isArchived(fileHash: string): boolean; overload;
       public
           constructor create(useSha1: boolean = false; stpFolder: string = '.\Setup\');
           destructor  Destroy; override;
           procedure   saveDataStreamToFile(fileName: string; dataStream: tMemoryStream);
           procedure   runCommand(cmd: string);
           procedure   addSetupToArchive(filename: string; folderName: string = ''); overload;
           procedure   removeSetupFromArchive(archivedName: string);
    end;

    tTaskFlush = class(tTask) // Task per scrivere il MemoryStream su file
        public
            fileName:   string;
            dataStream: tMemoryStream;

            procedure exec; override;
    end;

var
    sFileMgr: fileManager;

implementation

    constructor fileManager.create(useSha1: boolean = false; stpFolder: string = '.\Setup\');
    begin
        self.stpFolder := stpFolder;
        if not( directoryExists(self.stpFolder) ) then
        begin
            sEventHdlr.pushEventToList( tEvent.create('Cartella d''installazione non esistente.', eiAlert) );
            sEventHdlr.pushEventToList( tEvent.create('La cartella verrà ricreata.', eiAlert) );
            if not( createDir(self.stpFolder) ) then
                sEventHdlr.pushEventToList( tEvent.create('Impossibile creare la cartella d''installazione.', eiError) )
        end;

        if useSha1 then
            m_hasher := tIdHashSHA1.create
        else
            m_hasher := tIdHashMessageDigest5.create;
    end;

    destructor fileManager.Destroy;
    begin
        m_hasher.free;
    end;

    function fileManager.getFileHash(fileName: string): string;
    var
        msFile: tMemoryStream;
    begin
        msFile := tMemoryStream.create;
        msFile.loadFromFile(fileName);

        result := ansiLowerCase( self.m_hasher.hashStreamAsHex(msFile) );

        msFile.free;
    end;

    procedure fileManager.saveDataStreamToFile(fileName: string; dataStream: tMemoryStream);
    begin
        dataStream.saveToFile(fileName)
    end;

    procedure fileManager.runCommand(cmd: string);
    begin
        // TODO
    end;

    procedure fileManager.addSetupToArchive(fileName: string);
    var
      soFileOperation: tSHFileOpStruct;
    begin
        // Trovare la unit per usare secureZeroMemory
        zeroMemory( @soFileOperation, sizeOf(soFileOperation) );
        with soFileOperation do
        begin
            wFunc  := FO_COPY;
            fFlags := FOF_FILESONLY;
            pFrom  := pChar(fileName + #0);
            pTo    := pChar( self.stpFolder + self.getFileHash(fileName) );
        end;
    end;

    procedure fileManager.addSetupToArchive(fileName: string; folderName: string = '');
    var
      soFileOperation: tSHFileOpStruct;
    begin
        if folderName = '' then
            self.addSetupToArchive(fileName, '')
        else
        begin
            // Trovare la unit per usare secureZeroMemory
            zeroMemory( @soFileOperation, sizeOf(soFileOperation) );
            with soFileOperation do
            begin
                wFunc  := FO_COPY;
                fFlags := FOF_FILESONLY;
                // SICURAMENTE non funziona, da capire meglio le destinazioni ed i flag giusti
                pFrom  := pChar(folderName + #0);
                pTo    := pChar( self.stpFolder + self.getFileHash(fileName) );
            end;
        end
    end;

    procedure fileManager.removeSetupFromArchive(archivedName: string);
    begin
        if not( removeDir(self.stpFolder + archivedName) ) then
            sEventHdlr.pushEventToList( tEvent.create('Impossibile eliminare la cartella d''installazione ' + archivedName + '.', eiError) )
    end;

    function fileManager.getArchivePathFor(cmdGuid: integer): string;
    begin
        result := self.stpFolder + cmdRecord( sDBMgr.getCommandRec(cmdGuid) ).hash;
    end;

    function fileManager.isArchived(cmdGuid: integer): boolean;
    begin
        result := directoryExists( self.getArchivePathFor(cmdGuid) );
    end;

    function fileManager.isArchived(fileHash: string): boolean;
    var
        i, j:   byte;
        swList: tList;
    begin
        result := false;
        swList := sdbMgr.getSoftwareList;
        for i := 0 to pred(swList.count) do
            for j := 0 to pred( swRecord(swList.items[i]).commands.count ) do
                if cmdRecord( swRecord(swList.items[i]).commands.items[j] ).hash = fileHash then
                begin
                    result := true;
                    exit;
                end;
    end;

    procedure tTaskFlush.exec;
    begin
        //sFileMgr.saveDataStreamToFile(self.fileName, self.dataStream)
    end;

end.

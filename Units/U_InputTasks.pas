unit U_InputTasks;

interface

uses
    System.Classes;

type
    tTask = class // Ogni classe derivata da TTask implementa il metodo virtuale 'exec' che permette l'esecuzione, da parte del thread, del compito assegnatogli
        public
            dummyTargets: array of tObject;

            procedure exec; virtual; abstract;
    end;

implementation

end.

unit U_OutputTasks;

interface

uses
    U_InputTasks;

type
    tStatus     = (initializing, processing, completed, failed);

    tTaskOutput = class(tTask)
    end;

implementation

end.

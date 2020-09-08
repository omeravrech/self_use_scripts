$global:Configuration = $null;
$global:Output = $null;

Try {
    $global:Configuration = Get-Content -Path ".\searcher-configuration.json" | ConvertFrom-Json

    # Data input validation
    if (!($global:Configuration.Computers -is [array])) { throw "Computers isn't a list." }
    if (!($global:Configuration.Files -is [array])) { throw "Files isn't a list." }
    if (  $global:Configuration.Workers -le 0) { thorw "Workers amount can't be negative." }
    if (  $global:Configuration.Workers -gt 10) { thorw "Workers amount can't be greater than 10." }
} catch {
    Write-Host "Can't read configuration file."
    exit 1
}
IF ((Get-Item -Path "./logs" -ErrorAction SilentlyContinue) -eq $null) { New-Item -Path "./logs" -ItemType Directory | Out-Null }
$global:Output = [System.IO.StreamWriter]::new("./logs/searcher-$((Get-Date -Format "yyyyMMdd-hhmmss")).log")
IF ($global:Output) { $global:Output.AutoFlush = $true; }
ELSE { "Can't open log file."; exit 1; }

# ScriptBlock - contain the script per thread have to perform.
$ScriptBlock = {
    param($Machine, $FileList, $Output)
    BEGIN { $Output.WriteLine("[$((Get-Date -Format "yyyy-MM-dd hh:mm:ss"))][$($Machine)] Connecting..."); }
    PROCESS {
        IF (Test-Path \\$Machine\c$) {
            $Output.WriteLine("[$((Get-Date -Format "yyyy-MM-dd hh:mm:ss"))][$($Machine)] Connected to machine.")
            FOREACH($File in $FileList) {
                $Result = Get-ChildItem -Path \\$Machine\c$\ -Filter $File -File -Recurse -Force -ErrorAction SilentlyContinue | Select FullName
                IF ($Result -eq $null) { $Output.WriteLine("[$((Get-Date -Format "yyyy-MM-dd hh:mm:ss"))][$($Machine)] Not found files that match the requirment: $($File)") }
                ELSE { $Result.ForEach({ $Output.WriteLine("[$((Get-Date -Format "yyyy-MM-dd hh:mm:ss"))][$($Machine)] File found: $($_.FullName)") }); }
            }
        } ELSE { $Output.WriteLine("[$((Get-Date -Format "yyyy-MM-dd hh:mm:ss"))][$($Machine)] ERROR: No access to C:\."); }
    }
    END { $Output.WriteLine("[$((Get-Date -Format "yyyy-MM-dd hh:mm:ss"))][$($Machine)] Finish to scan. Disconnected from machine"); }
}

$RunspacePool = [runspacefactory]::CreateRunspacePool(1, $global:Configuration.Workers);
$RunspacePool.Open();
$Jobs = New-Object System.Collections.ArrayList;


$Output.WriteLine("[$((Get-Date -Format "yyyy-MM-dd hh:mm:ss"))][Main Process] Start running over computers list.")
$StartDate=(GET-DATE)

Foreach ($Computer in $global:Configuration.Computers) {
    #Create Thread per computer
    $PowerShell = [powershell]::Create();
    $PowerShell.RunspacePool = $RunspacePool;
    [void]$PowerShell.AddScript($ScriptBlock);
    [void]$PowerShell.AddArgument($Computer).AddArgument($global:Configuration.Files).AddArgument($global:Output);
    [void]$Jobs.Add(($PowerShell.BeginInvoke()));
}

# Wait for all threds to end.
$Total = $Jobs.Count
while ($Jobs.IsCompleted -contains $false) {
    $Remain = @($Jobs | Where { $_.iscompleted -eq ‘Completed’ }).Count
    $progress = [math]::round(($Remain / $Total)*100,0)
    Write-Progress -Activity "Search in Progress..." -Status "Completed $Remain/$Total [$progress%]." -PercentComplete $progress;
    Start-Sleep -Milliseconds 1000
}

# Display the total run time.
$TotalRunTime = (NEW-TIMESPAN –Start $StartDate –End (GET-DATE)).TotalMinutes
$Output.WriteLine("[$((Get-Date -Format "yyyy-MM-dd hh:mm:ss"))][Process] End running over computers list. Total time: $($TotalRunTime) minute(s).")
$global:Output.Close()
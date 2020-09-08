$global:Configuration = $null;
$global:Output = $null;
$global:SourcePath = (Get-Location).path

TRY {
    [System.Reflection.Assembly]::LoadWithPartialName("System.Web.Extensions") | Out-Null
    $json = Get-Content -Path "$($global:SourcePath)\searcher-configuration.json"
    $js = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    $global:Configuration = $js.DeserializeObject($json)

    # Data input validation
    if (!($global:Configuration.Computers -is [array])) { throw "Computers isn't a list." }
    if (!($global:Configuration.Files -is [array])) { throw "Files isn't a list." }
    if (  $global:Configuration.Workers -le 0) { thorw "Workers amount can't be negative." }
    if (  $global:Configuration.Workers -gt 10) { thorw "Workers amount can't be greater than 10." }
} CATCH {
    Write-Host "Can't read configuration file."
    exit 1
}

IF ((Get-Item -Path "$($global:SourcePath)/logs" -ErrorAction SilentlyContinue) -eq $null) { New-Item -Path "$($global:SourcePath)/logs" -ItemType Directory | Out-Null }
$global:Output = New-Object System.IO.StreamWriter "$($global:SourcePath)/logs/searcher-$((Get-Date -Format "yyyyMMdd-hhmmss")).log", $false, ([System.Text.Encoding]::Default)
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
                $Result = Get-ChildItem -Path \\$Machine\c$\ -Filter $File -File -Recurse -Force -ErrorAction SilentlyContinue | % {
                    $Output.WriteLine("[$((Get-Date -Format "yyyy-MM-dd hh:mm:ss"))][$($Machine)] File found: $($_.FullName)");
                    return $_.Name;
                }
                IF ($Result -eq $null) { $Output.WriteLine("[$((Get-Date -Format "yyyy-MM-dd hh:mm:ss"))][$($Machine)] Not found files that match the requirment: $($File)") }
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

FOREACH ($Computer in $global:Configuration.Computers) {
    #Create Thread per computer
    $PowerShell = [powershell]::Create();
    $PowerShell.RunspacePool = $RunspacePool;
    [void]$PowerShell.AddScript($ScriptBlock);
    [void]$PowerShell.AddArgument($Computer).AddArgument($global:Configuration.Files).AddArgument($global:Output);
    [void]$Jobs.Add(($PowerShell.BeginInvoke()));
}

# Wait for all threds to end.
$Total = $Jobs.Count
WHILE ($Jobs.IsCompleted -contains $false) {
    $Remain = @($Jobs | Where { $_.iscompleted -eq ‘Completed’ }).Count
    $progress = [math]::round(($Remain / $Total)*100,0)
    Write-Progress -Activity "Search in Progress..." -Status "Completed $Remain/$Total [$progress%]." -PercentComplete $progress;
    Start-Sleep -Milliseconds 1000
}

# Display the total run time.
$TotalRunTime = (NEW-TIMESPAN –Start $StartDate –End (GET-DATE)).TotalMinutes
$Output.WriteLine("[$((Get-Date -Format "yyyy-MM-dd hh:mm:ss"))][Process] End running over computers list. Total time: $($TotalRunTime) minute(s).")
$global:Output.Close()
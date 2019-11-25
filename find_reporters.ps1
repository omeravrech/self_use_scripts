Function PrintReporters {
    param([string]$user, [int]$dept)

    if ($dept -le 0) { return }
    $reporters = (Get-ADUser $user -Properties * | Select *).directReports;
    ForEach($reporter in $reporters) {
        Write-Host $reporter.Split(",")[0].replace("CN=", "");
        if ($dept -gt 1) {
            PrintReporters -user $reporter -dept ($dept-1);
        }
    }
    
    PrintReporters -user '[user]' -dept '[number]'

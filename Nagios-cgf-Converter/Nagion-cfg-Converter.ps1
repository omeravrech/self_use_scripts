<#
.SYNOPSIS
    Convert Nagios cfg files into readable format. 
.NOTES
    Author: Omer Avrech
#>

param (
    [string] $Path = $null,
    [string] $Csv = $null,
    [string] $Json = $null,
    [switch] $Help = $false
)

Begin {
    IF ($Help -or ($PSBoundParameters.Count -le 0)) {
        if ($PSCommandPath -eq $null) { function GetPSCommandPath() { return $MyInvocation.PSCommandPath; } $PSCommandPath = GetPSCommandPath; }
        Write-Host "Usage:"
        Write-Host "      $($MyInvocation.MyCommand.Name) [-Option Value] -Path <Input filename>.cfg"
        Write-Host ""
        Write-Host "Options:"
        Write-Host "      -Csv <filename>.csv"
        Write-Host "      -Json <filename>.json"
        Write-Host ""
        exit 0;
    }
    IF (($Path -eq $null) -or ($Path -eq "") -or -not(Test-Path $Path -PathType Leaf)) {
        Write-Host "Please enter cfg file.";
        exit 1;
    }
    $global:debug = $false;
    $global:Nested = 0
    $global:Result = @()
    $global:tempObject = $null
}
Process {
    FOREACH ($Line in (Get-Content -Path $Path)) {
        $Line = $Line.Replace("`t", " ").Trim();                                       # Replace all tubs with space
        while ($Line.indexOf("  ") -gt -1) { $Line = $Line.Replace("  "," ").Trim(); } # Remove all duplicate spaces in line

        IF ($Line -match "^(#)+") {
            Continue
        }
        ELSEIF ($Line -match "{$" ) {
            $global:Nested++

            ## New Object defined
            IF (($Line -match "^(define host)") -and ($global:Nested -eq 1) -and ($global:tempObject -eq $null)) {
                $global:tempObject = New-Object -TypeName psobject; 
                IF ($global:debug) { Write-Host "Start new Object" }
            }
        }
        ELSEIF ($Line -match "}$") {
            $global:Nested--;

            ## Push the object
            IF(($global:Nested -eq 0) -and ($global:tempObject -ne $null)) {
                if ($global:tempObject.address -ne $null) { $global:Result += $global:tempObject }
                IF ($global:debug) { Write-Host "Push new Object" }
                $global:tempObject = $null
            }
        }
        ELSEIF ($global:tempObject -ne $null) {
            $SplitedLine = $Line.Split(" ");
            IF ($SplitedLine.Count -ge 2) {
                $global:tempObject | Add-Member -MemberType NoteProperty -Name $SplitedLine[0] -Value $SplitedLine[1];
            }
        }
    }
}

End {
    TRY {
        IF ($Csv) { $global:Result | Export-csv $Csv }
        ELSEIF ($Json) { $global:Result | ConvertTo-Json | Out-File $Json }
        ELSE { THROW "DEFAULT-EXPORT" }
    }
    CATCH {
        return $global:Result
    }
}
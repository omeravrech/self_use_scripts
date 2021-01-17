# Developed by Omer Avrech #

# Const variables
$IPPATERN =    [Regex]::new('^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$')
$MASKPATERN =  [Regex]::new('^(((255\.){3}(255|254|252|248|240|224|192|128|0+))|((255\.){2}(255|254|252|248|240|224|192|128|0+)\.0)|((255\.)(255|254|252|248|240|224|192|128|0+)(\.0+){2})|((255|254|252|248|240|224|192|128|0+)(\.0+){3}))$')
$FQDNPattern = [Regex]::new("[\w.-]+(?:\.[\w\.-]+)+")

Function Collect_Host_Data {
    BEGIN {
        $Result = New-Object -TypeName PSObject
        $OSData = Get-WmiObject Win32_OperatingSystem
        $PCData = Get-WmiObject Win32_ComputerSystem
    }
    PROCESS {
        Add-Member -InputObject $Result -MemberType Noteproperty -Name "Hostname" -Value ($PCData).Name
        Add-Member -InputObject $Result -MemberType Noteproperty -Name "Domain" -Value ($PCData).Domain
        Add-Member -InputObject $Result -MemberType Noteproperty -Name "Model" -Value "$($PCData.Manufacturer) $($PCData.Model)"
        Add-Member -InputObject $Result -MemberType Noteproperty -Name "OS Architecture" -Value ($OSData).OSArchitecture
        Add-Member -InputObject $Result -MemberType Noteproperty -Name "Os Version" -Value ($OSData).Caption
    }
    END { return $result }
}
Function Get-Network-Info {
    BEGIN {
        # Collect data about the active network cards
        $Result = [System.Collections.ArrayList]::new()
        $interfaces = Get-NetAdapter | Where-Object -Property "Status" -EQ "Up"
    }
    PROCESS {  
        FOREACH ($interface in $interfaces){
            #$netIP = Get-NetIPAddress -InterfaceIndex $interface.ifIndex -AddressFamily IPv4
            $win32_network = Get-WmiObject Win32_NetworkAdapterConfiguration -Filter "InterfaceIndex=$($interface.ifIndex)"
        
            $adapter = [PSCustomObject][ordered]@{
                "Index" = $interface.ifIndex
                "Name" = $interface.Name
                "Description"= $interface.InterfaceDescription
                "VirtualInterface" = $interface.Virtual
                "LinkSpeed" = $interface.LinkSpeed
                "MacAddress" = $interface.MacAddress
                "IPAddress" = ($win32_network.IPAddress -match $IPPATERN) | % { if ($_) { return $_ } }
                "Subnet" = ($win32_network.IPSubnet -match $MASKPATERN) | % { if ($_) { return $_ } }
                "IPAssginedType" = $win32_network.DHCPEnabled
                "DHCP" = $win32_network.DHCPEnabled
                "Domain" = $win32_network.DNSDomain
                "LookupServers" = [string]$win32_network.DNSServerSearchOrder
            }
            $Result.Add($adapter) | Out-Null
        }
    }
    END {
        return ($Result)
    }
}
Function DNS_Connectivity {
    param(
            [Parameter(Mandatory=$true, Position=0)]
            $Servers
    )
    BEGIN {
        [int]$Progress = 0
        $Result = [System.Collections.ArrayList]::new()
    }
    PROCESS {
        FOREACH ($Server in $Servers) {
            $TestResult = Test-NetConnection -Port 53 -ComputerName $Server -WarningAction SilentlyContinue
            $Result.Add([PSCustomObject][ordered]@{
                "IP Address" = $Server;
                "Hostname" = try { [System.Net.Dns]::GetHostEntry($Server).Hostname } catch { "" };
                "Online" = ($TestResult.PingSucceeded -or $TestResult.TcpTestSucceeded)
                "DNS Service" = $TestResult.TcpTestSucceeded
            }) | Out-Null
            $Progress += (1/$Servers.Count) * 100
        }
    }
    END {
        return $Result
    }
}
Function DNS_Translation {
    param(
        [Parameter(Mandatory=$true, Position=0)]
        $Servers,
        [Parameter(Mandatory=$true, Position=1)]
        $FQDNList
    )
    BEGIN {
        # Reduce Servers and remove duplicates instances
        $Servers = $Servers | Select-Object -Unique
        $FQDNList = $FQDNList | Select-Object -Unique
        #List of test domains
        $Result = [System.Collections.ArrayList]::new()
        [int]$Progress = 0
    }
    PROCESS {
        FOREACH ($Server in $Servers) {
            FOREACH ($Test in $FQDNList) {  
                Write-Progress -Activity "Checking DNS Functinality [$Server -> $Test]" -PercentComplete $Progress
                IF($DNSResult = (Resolve-DnsName -DnsOnly -Type A -Server $Server $Test -ErrorAction SilentlyContinue)) {
                    $result.Add([PSCustomObject][ordered]@{
                        "Server" = $Server
                        "Status" = "Pass"
                        "Destination" = $DNSResult[0].Name
                        "Resolve" = $DNSResult.IPAddress
                        "Availability" = IF (Test-Connection $DNSResult.IPAddress -ErrorAction SilentlyContinue) { "Accessable" } ELSE { "Unaccessable" }
                    }) | Out-Null
                } ELSE {
                    $result.Add([PSCustomObject][ordered]@{
                        "Server" = $Server
                        "Status" = "Fail"
                        "Destination" = $Test
                    }) | Out-Null
                }
                $Progress += (1/($Servers.Count * $FQDNList.Count)) * 100
            }
        }
    }
    END {
        return $Result
    }
}
Function Get-ServerList {
    BEGIN {
        $ServerList = [System.Collections.ArrayList]::new()
        Write-Host "Please enter the websites you want to tests."
        Write-Host "In order to exit, please press Enter."
        Write-Host ""
    }
    PROCESS {
        $counter = 1
        DO {
            $WEB = Read-Host -Prompt "FQDN $counter"
            IF ($WEB -match $FQDNPattern) {
                $ServerList.Add($Matches[0]) | Out-Null
            }
            $counter += 1
        } WHILE($WEB);
    }
    END {
        RETURN ($ServerList | Select-Object -Unique)
    }
}

Function Main {
    cls
    $WebSites = Get-ServerList
    cls
    
    $HostData = Collect_Host_Data
    $Interfaces_Status = Get-Network-Info
    $ServerList = (($Interfaces_Status | Select-Object -ExpandProperty LookupServers) -Join " ").Split(" ") + "8.8.8.8"
    $DNS_Status = DNS_Connectivity -Servers $ServerList
    $ServerList = $DNS_Status | Where-Object -Property "DNS Service" -EQ $true | Select-Object -ExpandProperty "IP Address" -Unique
    $DNS_Trans = DNS_Translation -Servers $ServerList -FQDNList $WebSites

    Write-Host "*------------------------*"
    Write-Host "|      Host Details      |"
    Write-Host "*------------------------*"
    $HostData
    Write-Host "*------------------------*"
    Write-Host "|  Network Interface(s)  |"
    Write-Host "*------------------------*"
    $Interfaces_Status
    Write-Host "*------------------------*"
    Write-Host "|      DNS Servers       |"
    Write-Host "*------------------------*"
    $DNS_Status | Format-Table
    Write-Host ""
    $DNS_Trans | Format-Table
}

Main

[CmdletBinding()]
param(
    [Parameter(Position = 0, Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ManagedPwd
)

begin {
    <#
    This script was made for PowerShell 2.0 and higher.
    
    We ran into an issue with McAfee ePolicy not removing agents/software after removing them from the server.
    We're transitioning from Windows 7 -> 10 and we're no longer using McAfee products on our endpoints.
    The problem was that I could not get a reliable automated way to remove McAfee from those endpoints that should have been removed by the ePolicy server.
    This script solves that problem.
    #>

    #Function to get all installed products found in the Windows 'Uninstall' registry keys.
    function Get-InstalledProducts {
        $UninstallKeys = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
        )
    
        $ProductsFound = @()
        foreach ($Key in $UninstallKeys) {
            Push-Location -Path $Key
            $ProductsFound += Get-ItemProperty -Path *
            Pop-Location
        }

        return $ProductsFound
    }

    #Filter to get installed products with the publisher "McAfee".
    filter McAfeePublisher {
        if ($_.Publisher -like "*McAfee*") {
            $_
        }
    }

    #Collect the installed software
    Write-Verbose "Collecting installed software."
    $AllInstalledProducts = Get-InstalledProducts

    #Filter out the installed software to find software by McAfee.
    Write-Verbose "Finding McAfee products."
    $McAfeeProducts = $AllInstalledProducts | McAfeePublisher

}

process {
    #Initial loop count set to 1.
    $LoopCount = 1

    #Starting a loop while McAfee products are still found after each loop.
    while (($AllInstalledProducts | McAfeePublisher)) {
        #If the loop count is greater than 10, throw a terminating error to prevent the script from indefinitely looping.
        if ($LoopCount -gt 10) {
            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new("McAfee products still installed after 10 loops."),
                    "McAfeeRemoval.TooManyLoops",
                    [System.Management.Automation.ErrorCategory]::LimitsExceeded,
                    $McAfeeProducts
                )
            )
        }

        Write-Verbose "Starting 'Loop $($LoopCount)'."

        #Remove each McAfee product that has been found.
        foreach ($Product in $McAfeeProducts) {
            Write-Verbose "Loop $($LoopCount) - Attempting to uninstall '$($Product.DisplayName)'."
            Start-Process -FilePath "msiexec" -ArgumentList @("/x", $Product.PSChildName, "/qr", "password=$($ManagedPwd)") -NoNewWindow -Wait
        }

        #Wait 5 seconds just as a safeguard. Possibly not even needed.
        Start-Sleep -Seconds 5

        #Recollect installed software and filter out McAfee software. This will update the variables for the loop.
        Write-Verbose "Loop $($LoopCount) - Recollecting installed software."
        $AllInstalledProducts = Get-InstalledProducts
        $McAfeeProducts = $AllInstalledProducts | McAfeePublisher

        #Increment the loop counter by 1.
        $LoopCount++
    }

    Write-Verbose "No McAfee products found after last loop."
}

end {
    return [pscustomobject]@{
        "AllMcAfeeProductsRemoved" = $true
    }
}
<#
.SYNOPSIS
Command line interface for an assortment of SCCM 2007 operations.

.DESCRIPTION
The functions in this module provide a command line and scripting interface for automating management of SCCM 2007 environments.

.NOTES  
File Name  : SCCM.ps1  
Author     : Andre Bocchini <andrebocchini@gmail.com>  
Requires   : PowerShell V2

.LINK
https://github.com/andrebocchini/SCCM-Powershell-Automation-Module
#>

#Requires -version 2

<#
.SYNOPSIS
Creates a new computer account in SCCM.

.DESCRIPTION
Takes in information about a specific site, along with a computer name and a MAC address in order to create a new 
account in SCCM.

.PARAMETER siteServer
The name of the site server where the new computer account is to be created.

.PARAMETER siteCode
The 3-character site code for the site where the new computer account is to be created.

.PARAMETER computerName
Name of the computer to be created.

.PARAMETER macAddress
MAC address of the computer account to be created in the format 00:00:00:00:00:00.

.EXAMPLE
New-SCCMComputer -siteServer MYSITESERVER -siteCode SIT -computerName MYCOMPUTER -macAddress "00:00:00:00:00:00"
#>
Function New-SCCMComputer {
    [CmdletBinding()]
    param (
        [parameter(Mandatory=$true)][string]$siteServer,
        [parameter(Mandatory=$true)][string]$siteCode,
        [parameter(Mandatory=$true)][string]$computerName,
        [parameter(Mandatory=$true)][string]$macAddress
    )

    $site = [WMIClass]("\\$siteServer\ROOT\sms\site_" + $siteCode + ":SMS_Site")

    $methodParameters = $site.psbase.GetMethodParameters("ImportMachineEntry")
    $methodParameters.MACAddress = $macAddress
    $methodParameters.NetbiosName = $computerName
    $methodParameters.OverwriteExistingRecord = $false

    $computerCreationResult = $site.psbase.InvokeMethod("ImportMachineEntry", $methodParameters, $null)
    
    if($computerCreationResult.MachineExists -eq $true) {
        Throw "Computer already exists with resource ID $($result.ResourceID)"
    } elseif($computerCreationResult.ReturnValue -eq 0) {
        return Get-SCCMComputer $siteServer $siteCode $computerName
    } else {
        Throw "Computer account creation failed"
    }
}

<#
.SYNOPSIS
Removes a computer account in SCCM.

.DESCRIPTION
Takes in information about a specific site, along with a computer resource ID and will attempt to delete it from the SCCM server.

.PARAMETER siteServer
The name of the site server to be queried.

.PARAMETER siteCode
The 3-character site code for the site to be queried.

.PARAMETER resourceId
Resource ID of the computer that needs to be deleted.

.EXAMPLE
Remove-SCCMComputer -siteServer MYSITESERVER -siteCode SIT -resourceId 1293

Description
-----------
Removes the computer with resource ID 1293 from the specified site.
#>
Function Remove-SCCMComputer {
    [CmdletBinding()]
    param (
        [parameter(Mandatory=$true)][string]$siteServer,
        [parameter(Mandatory=$true)][string]$siteCode,
        [parameter(Mandatory=$true)][string]$resourceId
    )

    $computer =  Get-WMIObject -ComputerName $siteServer -Namespace "root\sms\site_$siteCode" -Class "SMS_R_System" | where { $_.ResourceID -eq $resourceId }
    return $computer.psbase.Delete()
}

<#
.SYNOPSIS
Returns computers from SCCM.

.DESCRIPTION
Takes in information about a specific site, along with a computer name and will attempt to retrieve an object for the computer.  This function
intentionally ignores obsolete computers by default, but you can specify a parameter to include them.

When invoked without specifying a computer name, this function returns a list of all computers found on the specified SCCM site.

.PARAMETER siteServer
The name of the site server to be queried.

.PARAMETER siteCode
The 3-character site code for the site to be queried.

.PARAMETER computerName
The name of the computer to be retrieved. 

.PARAMETER includeObsolete
This switch defaults to false.  If you want your results to include obsolete computers, set this to true when calling this function.

.EXAMPLE
Get-SCCMComputer -siteServer MYSITESERVER -siteCode SIT -computerName MYCOMPUTER -includeObsolete:true

Description
-----------
Returns any computer whose name matches MYCOMPUTER found on site server MYSITESERVER for site SIT.

.EXAMPLE
Get-SCCMComputer -siteServer MYSITESERVER -siteCode SIT

Description
-----------
Returns all computers (excluding obsolete ones) found on site server MYSITESERVER for site SIT.
#>
Function Get-SCCMComputer {
    [CmdletBinding()]
    param (
        [parameter(Mandatory=$true)][string]$siteServer,
        [parameter(Mandatory=$true)][string]$siteCode,
        [string]$computerName,
        [switch]$includeObsolete=$false
    )

    if($computerName -and $includeObsolete) {
        return Get-WMIObject -ComputerName $siteServer -Namespace "root\sms\site_$siteCode" -Class "SMS_R_System" | where { $_.Name -eq $computerName }
    } elseif($computerName -and !$includeObsolete) {
        return Get-WMIObject -ComputerName $siteServer -Namespace "root\sms\site_$siteCode" -Class "SMS_R_System" | where { ($_.Name -eq $computerName) -and ($_.Obsolete -ne 1) }
    } elseif(!$computerName -and !$includeObsolete) {
        return Get-WMIObject -ComputerName $siteServer -Namespace "root\sms\site_$siteCode" -Query "select * from SMS_R_System" | where { $_.Obsolete -ne 1 }
    } else {
        return Get-WMIObject -ComputerName $siteServer -Namespace "root\sms\site_$siteCode" -Query "select * from SMS_R_System"
    }
}

<#
.SYNOPSIS
Adds a computer to a collection in SCCM.

.DESCRIPTION
Takes in information about a specific site, along with a computer name, and a collection name and direct membership rule for the computer in
the specified collection.
#>
Function Add-SCCMComputerToCollection {
    [CmdletBinding()]
    param (
        [parameter(Mandatory=$true)][string]$siteServer,
        [parameter(Mandatory=$true)][string]$siteCode,
        [parameter(Mandatory=$true)][string]$computerName,
        [parameter(Mandatory=$true)][string]$collectionName
    )

    $computer = Get-SCCMComputer $siteServer $siteCode $computerName
    $collectionRule = [WMIClass]("\\$siteServer\root\sms\site_" + "$siteCode" + ":SMS_CollectionRuleDirect")
    $collectionRule.Properties["ResourceClassName"].Value = "SMS_R_System"
    $collectionRule.Properties["ResourceID"].Value = $computer.Properties["ResourceID"].Value

    $collection = Get-WmiObject -ComputerName $siteServer -Namespace "root\sms\site_$siteCode" -Class "SMS_Collection" | where { $_.Name -eq $collectionName }
    $collectionId = $collection.collectionId
    $addToCollectionParameters = $collection.psbase.GetmethodParameters("AddMembershipRule")
    $addToCollectionParameters.collectionRule = $collectionRule  

    return $collection.psbase.InvokeMethod("AddMembershipRule", $addToCollectionParameters, $null)
}

<#
.SYNOPSIS
Removes a computer from a specific collection

.DESCRIPTION
Takes in information about a specific site, along with a computer name, and a collection name and removes the computer from the collection.
#>
Function Remove-SCCMComputerFromCollection {
    [CmdletBinding()]
    param (
        [parameter(Mandatory=$true)][string]$siteServer,
        [parameter(Mandatory=$true)][string]$siteCode,
        [parameter(Mandatory=$true)][string]$computerName,
        [parameter(Mandatory=$true)][string]$collectionName
    )

    $computer = Get-SCCMComputer $siteServer $siteCode $computerName
    $collection = Get-SCCMCollection $siteServer $siteCode $collectionName
    $collectionRule = ([WMIClass]("\\$siteServer\root\sms\site_" + "$siteCode" + ":SMS_CollectionRuleDirect")).CreateInstance()
    $collectionRule.ResourceID = $computer.ResourceID
    
    return $collection.DeleteMembershipRule($collectionRule)
}

<#
.SYNOPSIS
Creates static SCCM collections

.DESCRIPTION
Allows the creation of static collections.

.PARAMETER siteServer
The name of the site server where the collection is to be created.

.PARAMETER siteCode
The 3-character site code where the collection is to be created.

.PARAMETER collectionName
The name of the new collection.

.PARAMETER parentCollectionId
If the static collection is not bound to a parent, it will not show up in the console.  This parameter is mandatory and must be valid.

.PARAMETER collectionComment
Optional parameter.  Attaches a comment to the collection.

.EXAMPLE
New-SCCMStaticCollection -siteServer MYSISTESERVER -siteCode SIT -collectionName MYCOLLECTIONNAME -parentCollectionId SIT00012 -collectionComment "This is a comment"
#>
Function New-SCCMStaticCollection {
    [CmdletBinding()]
    param (
        [parameter(Mandatory=$true)][string]$siteServer,
        [parameter(Mandatory=$true)][string]$siteCode,
        [parameter(Mandatory=$true)][string]$collectionName,
        [parameter(Mandatory=$true)][string]$parentCollectionId,
        [string]$collectionComment
    )

    if(Get-SCCMCollection $siteServer $siteCode -collectionId $parentCollectionId) {
        if(!(Get-SCCMCollection $siteServer $siteCode -collectionName $collectionName)) {
            $newCollection = ([WMIClass]("\\$siteServer\root\sms\site_" + "$siteCode" + ":SMS_Collection")).CreateInstance()
            $newCollection.Name = $collectionName
            $newCollection.Comment = $collectionComment
            $newCollection.OwnedByThisSite = $true

            $newCollection.Put() | Out-Null

            # Now we establish the parent to child relationship of the two collections. If we create a collection without
            # establishing the relationship, the new collection will not be visible in the console.
            $newCollectionId = (Get-SCCMCollection $siteServer $siteCode $collectionName).CollectionID
            $newCollectionRelationship = ([WMIClass]("\\$siteServer\root\sms\site_" + "$siteCode" + ":SMS_CollectToSubCollect")).CreateInstance()
            $newCollectionRelationship.parentCollectionID = $parentCollectionId
            $newCollectionRelationship.subCollectionID = $newCollectionId

            $newCollectionRelationship.Put() | Out-Null

            return Get-SCCMCollection $siteServer $siteCode -collectionId $newCollectionId
        } else {
            Throw "A collection named $collectionName already exists"
        }
    } else {
        Throw "Invalid parent collection"
    }
}

<#
.SYNOPSIS
Deletes SCCM collections

.DESCRIPTION
Takes in information about a specific site, along with a collection ID and deletes it.

.PARAMETER siteServer
The name of the site server to be queried.

.PARAMETER siteCode
The 3-character site code for the site to be queried.

.PARAMETER collectionId
The id of the collection to be deleted.

.EXAMPLE
Remove-SCCMCollection -siteServer MYSISTESERVER -siteCode SIT -collectionId MYID

Description
-----------
Deletes the collection with id MYID from site SIT on MYSITESERVER.
#>
Function Remove-SCCMCollection {
    [CmdletBinding()]
    param (
        [parameter(Mandatory=$true)][string]$siteServer,
        [parameter(Mandatory=$true)][string]$siteCode,
        [parameter(Mandatory=$true)][string]$collectionId
    )

    $collection = Get-SCCMCollection $siteServer $siteCode -collectionId $collectionId
    return $collection.psbase.Delete()
}

<#
.SYNOPSIS
Retrieves SCCM collection objects from the site server.

.DESCRIPTION
Takes in information about a specific site and a collection name and returns an object representing that collection.  If no collection name is specified, it returns all collections found on the site server.

.PARAMETER siteServer
The name of the site server to be queried.

.PARAMETER siteCode
The 3-character site code for the site to be queried.

.PARAMETER collectionName
Optional parameter.  If specified, the function will try to find a collection that matches the name provided.

.PARAMETER collectionId
Optional parameter.  If specified, the function will try to find a collection that matches the id provided.

.EXAMPLE
Get-SCCMCollection -siteServer MYSITESERVER -siteCode SIT -collectionName MYCOLLECTION

Description
-----------
Retrieve the collection named MYCOLLECTION from site SIT on MYSITESERVER

.EXAMPLE
Get-SCCMCollection -siteServer MYSITESERVER -siteCode SIT -collectionName MYCOLLECTION -collectionId MYCOLLECTIONID

Description
-----------
Retrieve the collection named MYCOLLECTION with id MYCOLLECTIONID from site SIT on MYSITESERVER

.EXAMPLE
Get-SCCMCollection -siteServer MYSITESERVER -siteCode SIT

Description
-----------
Retrieve all collections from site SIT on MYSITESERVER

.EXAMPLE
Get-SCCMCollection -siteServer MYSITESERVER -siteCode SIT | Select-Object Name,CollectionID

Description
-----------
Retrieve all collections from site SIT on MYSITESERVER and filter out only their names and IDs
#>
Function Get-SCCMCollection {
    [CmdletBinding()]
    param (
        [parameter(Mandatory=$true)][string]$siteServer,
        [parameter(Mandatory=$true)][string]$siteCode,
        [string]$collectionName,
        [string]$collectionId
    )

    if($collectionName -and $collectionId) {
        return Get-WMIObject -Computer $siteServer -Namespace "root\sms\site_$siteCode" -Query "Select * from SMS_Collection" | Where { ($_.Name -eq $collectionName) -and ($_.CollectionID -eq $collectionId) } 
    } elseif($collectionName -and !$collectionId) {
        return Get-WMIObject -Computer $siteServer -Namespace "root\sms\site_$siteCode" -Query "Select * from SMS_Collection" | Where { $_.Name -eq $collectionName } 
    } elseif(!$collectionName -and $collectionId) {
        return Get-WMIObject -Computer $siteServer -Namespace "root\sms\site_$siteCode" -Query "Select * from SMS_Collection" | Where { $_.CollectionID -eq $collectionId }
    } else {
        return Get-WMIObject -Computer $siteServer -Namespace "root\sms\site_$siteCode" -Query "Select * from SMS_Collection"
    }
}

<#
.SYNOPSIS
Retrieves the list of members of a collection.

.DESCRIPTION
Takes in information about an SCCM site along with a collection ID and returns a list of all members of the target collection.

.PARAMETER siteServer
Site server containing the collection.

.PARAMETER siteCode
Site code for the site containing the collection.

.PARAMETER collectionId
The ID of the collection whose members are being retrieved.

.EXAMPLE
Get-SCCMCollectionMembers -siteServer MYSITESERVER -siteCode SIT -collectionId SIT00012

.EXAMPLE
Get-SCCMCollectionMembers -siteServer MYSITESERVER -siteCode SIT -collectionId SIT00012 | Select-Object -ExpandProperty Name

Description
-----------
Retrieves all members of collection SIT00012 and lists only their names
#>
Function Get-SCCMCollectionMembers {
    [CmdletBinding()]
    param (
        [parameter(Mandatory=$true)][string]$siteServer,
        [parameter(Mandatory=$true)][string]$siteCode,
        [parameter(Mandatory=$true)][string]$collectionId
    )

    return Get-WMIObject -Computer $siteServer -Namespace "root\sms\site_$siteCode" -Query "Select * From SMS_CollectionMember_a" | Where { $_.CollectionID -eq $collectionId }
}

<#
.SYNOPSIS
Returns a list of collection IDs that a computer belongs to.

.DESCRIPTION
Takes in information about a specific site, along with a computer name and returns an array containing the collection IDs that the computer belongs to.
#>
Function Get-SCCMCollectionsForComputer {
    [CmdletBinding()]
    param (
        [parameter(Mandatory=$true)][string]$siteServer,
        [parameter(Mandatory=$true)][string]$siteCode,
        [parameter(Mandatory=$true)][string]$computerName
    )

    # First we find all membership associations that match the colection ID of the computer in question
    $computer = Get-SCCMComputer $siteServer $siteCode $computerName
    $computerCollectionIds = @()
    $collectionMembers = Get-WMIObject -Computer $siteServer -Namespace "root\sms\site_$siteCode" -Query "Select * From SMS_CollectionMember_a Where ResourceID= $($computer.ResourceID)"
    foreach($collectionMember in $collectionMembers) {
        $computerCollectionIds += $collectionMember.CollectionID
    }

    # Now that we have a list of collection IDs, we want to retrieve and return some rich collection objects
    $allServerCollections = Get-SCCMCollection $siteServer $siteCode
    $computerCollections = @()
    foreach($collectionId in $computerCollectionIds) {
        foreach($collection in $allServerCollections) {
            if($collection.CollectionID -eq $collectionId) {
                $computerCollections += $collection
            }
        }
    }

    return $computerCollections
}

<#
.SYNOPSIS
Retrieves SCCM advertisements from the site server.

.DESCRIPTION
Takes in information about a specific site and an advertisement name and/or and advertisement ID and returns advertisements matching the specified parameters.  If no advertisement name or ID is specified, it returns all advertisements found on the site server.

.PARAMETER siteServer
The name of the site server to be queried.

.PARAMETER siteCode
The 3-character site code for the site to be queried.

.PARAMETER advertisementName
Optional parameter.  If specified, the function will try to find advertisements that match the specified name.

.PARAMETER advertisementId
Optional parameter.  If specified, the function will try to find advertisements that match the specified ID.

.EXAMPLE
Get-SCCMAdvertisement -siteServer MYSITESERVER -siteCode SIT -advertisementName MYADVERTISEMENT

Description
-----------
Retrieve the advertisement named MYADVERTISEMENT from site SIT on MYSITESERVER

.EXAMPLE
Get-SCCMAdvertisement -siteServer MYSITESERVER -siteCode SIT -advertisementName MYADVERTISEMENT -advertisementId MYADVERTISEMENTID

Description
-----------
Retrieve the advertisement named MYADVERTISEMENT with ID MYADVERTISEMENTID from site SIT on MYSITESERVER

.EXAMPLE
Get-SCCMAdvertisement -siteServer MYSITESERVER -siteCode SIT

Description
-----------
Retrieve all advertisements from site SIT on MYSITESERVER

.EXAMPLE
Get-SCCMAdvertisement -siteServer MYSITESERVER -siteCode SIT | Select-Object Name,AdvertisementID

Description
-----------
Retrieve all advertisements from site SIT on MYSITESERVER and filter out only their names and IDs
#>
Function Get-SCCMAdvertisement {
    [CmdletBinding()]
    param (
        [parameter(Mandatory=$true)][string]$siteServer,
        [parameter(Mandatory=$true)][string]$siteCode,
        [string]$advertisementName,
        [string]$advertisementId
    )

    if($advertisementName -and $advertisementID) {
        return Get-WMIObject -ComputerName $siteServer -Namespace "root\sms\site_$siteCode" -Class "SMS_Advertisement" | where { ($_.AdvertisementName -eq $advertisementName) -and ($_.AdvertisementID -eq $advertisementId) }
    } elseif($advertisementName -and !$advertisementId) {
        return Get-WMIObject -ComputerName $siteServer -Namespace "root\sms\site_$siteCode" -Class "SMS_Advertisement" | where { ($_.AdvertisementName -eq $advertisementName) }
    } elseif(!$advertisementName -and $advertisementId) {
        return Get-WMIObject -ComputerName $siteServer -Namespace "root\sms\site_$siteCode" -Class "SMS_Advertisement" | where { ($_.AdvertisementID -eq $advertisementId) }
    } else { 
        return Get-WMIObject -ComputerName $siteServer -Namespace "root\sms\site_$siteCode" -Query "Select * From SMS_Advertisement"
    }
}

<#
.SYNOPSIS
Returns a list of advertisements assigned to a collection.

.DESCRIPTION
Takes in information about a specific site, along with a collection ID and returns all advertisements assigned to that collection.
#>
Function Get-SCCMAdvertisementsForCollection {
    [CmdletBinding()]
    param (
        [parameter(Mandatory=$true)][string]$siteServer,
        [parameter(Mandatory=$true)][string]$siteCode,
        [parameter(Mandatory=$true)][string]$collectionId
    )

    return Get-WMIObject -Computer $siteServer -Namespace "root\sms\site_$siteCode" -Query "Select * from SMS_Advertisement WHERE CollectionID='$collectionId'"
}

<#
.SYNOPSIS
Returns a list of advertisements assigned to a computer.

.DESCRIPTION
Takes in information about a specific site, along with a computer name and returns all advertisements assigned to that computer.
#>
Function Get-SCCMAdvertisementsForComputer {
    [CmdletBinding()]
    param (
        [parameter(Mandatory=$true)][string]$siteServer,
        [parameter(Mandatory=$true)][string]$siteCode,
        [parameter(Mandatory=$true)][string]$computerName
    )

    $collections = Get-SCCMCollectionsForComputer $siteServer $siteCode $computerName
    $computerAdvertisements = @()
    foreach($collection in $collections) {
        $advertisements = Get-SCCMAdvertisementsForCollection $siteServer $siteCode $collection.CollectionID
        foreach($advertisement in $advertisements) {
            $computerAdvertisements += $advertisement
        }
    }
    
    return $computerAdvertisements
}

<#
.SYNOPSIS
Returns a list of advertisements for a specific package.

.DESCRIPTION
Takes in information about a specific site, along with a package ID and returns all advertisements for that package.

.PARAMETER siteServer
The name of the site server to be queried.

.PARAMETER siteCode
The 3-character site code for the site to be queried.

.PARAMETER packageId
The ID of the package whose advertisements the function should retrieve.

.EXAMPLE
Get-SCCMAdvertisementForPackage -siteServer MYSITESERVER -siteCode SIT -packageId MYPACKAGEID

Description
-----------
Retrieve all advertisements from site SIT on MYSITESERVER for package with ID equal to MYPACKAGEID
#>
Function Get-SCCMAdvertisementsForPackage {
    [CmdletBinding()]
    param (
        [parameter(Mandatory=$true)][string]$siteServer,
        [parameter(Mandatory=$true)][string]$siteCode,
        [parameter(Mandatory=$true)][string]$packageId
    )

    return Get-WMIObject -ComputerName $siteServer -Namespace "root\sms\site_$siteCode" -Class "SMS_Advertisement" | where { $_.PackageID -eq $packageId }
}

<#
.SYNOPSIS
Returns the advertisement status for a specific advertisement for a specific computer.

.DESCRIPTION
Takes in information about a specific site, along with an advertisement id and a computer name and returns the status of that advertisement for that computer.
#>
Function Get-SCCMAdvertisementStatusForComputer {
    [CmdletBinding()]
    param (
        [parameter(Mandatory=$true)][string]$siteServer,
        [parameter(Mandatory=$true)][string]$siteCode,
        [parameter(Mandatory=$true)][string]$advertisementId,
        [parameter(Mandatory=$true)][string]$computerName
    )

    $computer = Get-SCCMComputer $siteServer $siteCode $computerName
    return Get-WMIObject -Computer $siteServer -Namespace "root\sms\site_$siteCode" -Query "Select * from SMS_ClientAdvertisementStatus WHERE AdvertisementID='$advertisementId' AND ResourceID='$($computer.ResourceID)'"
}

<#
.SYNOPSIS
Settings a variable on an SCCM computer record.

.DESCRIPTION
Takes in information about a specific site, along with a computer name, variable name and value and attempts to set the variable on an SCCM computer record.
If the variable already exists, it will overwrite be overwritten.
#>
Function Set-SCCMComputerVariable {
    [CmdletBinding()]
    param (
        [parameter(Mandatory=$true)][string]$siteServer,
        [parameter(Mandatory=$true)][string]$siteCode,
        [parameter(Mandatory=$true)][string]$computerName,
        [parameter(Mandatory=$true)][string]$variableName,
        [parameter(Mandatory=$true)][string]$variableValue,
        [parameter(Mandatory=$true)][bool]$isMasked
    )

    $computer = Get-SCCMComputer $siteServer $siteCode $computerName
    $computerSettings = Get-WMIObject -computername $siteServer -namespace "root\sms\site_$siteCode" -class "SMS_MachineSettings" | where {$_.ResourceID -eq $computer.ResourceID}

    # If the computer has never held any variables, computerSettings will be null, so we have to create a bunch of objects from scratch to hold
    # the computer settings and variables.
    if($computerSettings -eq $null) {
        # Create an object to hold the settings
        $computerSettings = ([WMIClass]("\\$siteServer\root\sms\site_" + "$siteCode" + ":SMS_MachineSettings")).CreateInstance()
        $computerSettings.ResourceID = $computer.ResourceID
        $computerSettings.SourceSite = $siteCode
        $computerSettings.LocaleID = $computer.LocaleID
        $computerSettings.Put()

        # Create an object to hold the variable data
        $computerVariable = ([WMIClass]("\\$siteServer\root\sms\site_" + "$siteCode" + ":SMS_MachineVariable")).CreateInstance()
        $computerVariable.IsMasked = $isMasked
        $computerVariable.Name = $variableName
        $computerVariable.Value = $variableValue

        # Add the variable to the settings object we created earlier and store it
        $computerSettings.MachineVariables += $computerVariable
        $computerSettings.Put()
    } else {
        # This computer once had variables (or still does), so we need to check for an existing variable with the same name as the one
        # we're trying to add so we can properly overwrite it
        $computerSettings.Get()
        $computerVariables = $computerSettings.MachineVariables

        if($computerVariables -eq $null) {
            # Looks like it held variables in the past but doesn't have them anymore.
            $temporarycomputerSettings = ([WMIClass]("\\$siteServer\root\sms\site_" + "$siteCode" + ":SMS_MachineSettings")).CreateInstance()
            $computerVariables = $temporarycomputerSettings.MachineVariables

            $computerVariable = ([WMIClass]("\\$siteServer\root\sms\site_" + "$siteCode" + ":SMS_MachineVariable")).CreateInstance()
            $computerVariable.IsMasked = $isMasked
            $computerVariable.Name = $variableName
            $computerVariable.Value = $variableValue

            $computerVariables += $computerVariable

            $computerSettings.MachineVariables = $computerVariables
            $computerSettings.Put()
        } else {
            # Looks like the computer still has some variables. We'll search through the list of variables to figure out if the computer 
            # already has the variable that we're trying to set.
            $foundExistingVariable = $false
            for($index = 0; ($index -lt $computerVariables.Count) -and ($foundExistingVariable -ne $true); $index++) {
                if($computerVariables[$index].Name -eq $variableName) {
                    # Looks like the computer already has a variable with the same name as the one we're trying to set,
                    # so we're just going to overwrite it.
                    $computerVariables[$index].Value = $variableValue
                    $computerVariables[$index].IsMasked = $isMasked

                    $computerSettings.MachineVariables = $computerVariables
                }
            }

            if($foundExistingVariable -ne $true) {
                # We looked for an existing variable with a matching name, but didn't find it.  So we create a new one from scratch.
                $computerVariable = ([WMIClass]("\\$siteServer\root\sms\site_" + "$siteCode" + ":SMS_MachineVariable")).CreateInstance()
                $computerVariable.IsMasked = $isMasked
                $computerVariable.Name = $variableName
                $computerVariable.Value = $variableValue

                $computerSettings.MachineVariables += $computerVariable
            }
            $computerSettings.Put() 
        }
    }
    return $computerSettings
}

<#
.SYNOPSIS
Returns a list of all computer variables for a specific computer.

.DESCRIPTION
Takes in information about a specific site, along with a computer name and returns a list of all variables associated with that computer.
#>
Function Get-SCCMComputerVariables {
    [CmdletBinding()]
    param (
        [parameter(Mandatory=$true)][string]$siteServer,
        [parameter(Mandatory=$true)][string]$siteCode,
        [parameter(Mandatory=$true)][string]$computerName
    )

    $computer = Get-SCCMComputer $siteServer $siteCode $computerName
    $computerSettings = Get-WMIObject -computername $siteServer -namespace "root\sms\site_$siteCode" -class "SMS_MachineSettings" | where {$_.ResourceID -eq $computer.ResourceID}
    $computerSettings.Get()

    return $computerSettings.MachineVariables
}

<#
.SYNOPSIS
Deletes a variable for an SCCM computer.

.DESCRIPTION
Takes in information about a specific site, along with a computer name and variable name and attempts to delete that variable.
#>
Function Remove-SCCMComputerVariable {
    [CmdletBinding()]
    param (
        [parameter(Mandatory=$true)][string]$siteServer,
        [parameter(Mandatory=$true)][string]$siteCode,
        [parameter(Mandatory=$true)][string]$computerName,
        [parameter(Mandatory=$true)][string]$variableName
    )

    $computer = Get-SCCMComputer $siteServer $siteCode $computerName
    $computerSettings = Get-WMIObject -computername $siteServer -namespace "root\sms\site_$siteCode" -class "SMS_MachineSettings" | where {$_.ResourceID -eq $computer.ResourceID}
    $computerSettings.Get() 
    
    # Since Powershell arrays are immutable, we create a new one to hold all the computer variable minus the one we're being asked to remove.
    $newVariables = @()
    $computerVariables = $computerSettings.MachineVariables
    for($index = 0; $index -lt $computerVariables.Count; $index++) {
        if($computerVariables[$index].Name -ne $variableName) {
            $newVariables += $computerVariables[$index]
        }
    }
    $computerSettings.MachineVariables = $newVariables
    $computerSettings.Put()
    return $computerSettings.MachineVariables
}

<#
.SYNOPSIS
Allows triggering of SCCM client actions.

.DESCRIPTION
Takes in a computer name and an action id, and attempts to trigger it remotely.

.PARAMETER scheduleId
The available schedule ids are:

HardwareInventory
SoftwareInventory
DataDiscovery
MachinePolicyRetrievalEvalCycle
MachinePolicyEvaluation
RefreshDefaultManagementPoint
RefreshLocation
SoftwareMeteringUsageReporting
SourcelistUpdateCycle
RefreshProxyManagementPoint
CleanupPolicy
ValidateAssignments
CertificateMaintenance
BranchDPScheduledMaintenance
BranchDPProvisioningStatusReporting
SoftwareUpdateDeployment
StateMessageUpload
StateMessageCacheCleanup
SoftwareUpdateScan
SoftwareUpdateDeploymentReEval
OOBSDiscovery
#>
Function Invoke-SCCMClientAction {           
    [CmdletBinding()]             
    param(             
        [parameter(Mandatory=$true)][string]$computerName, 
        [Parameter(Mandatory=$true)][string]$scheduleId    
    )             

    $scheduleIdList = @{
        HardwareInventory = "{00000000-0000-0000-0000-000000000001}";
        SoftwareInventory = "{00000000-0000-0000-0000-000000000002}";
        DataDiscovery = "{00000000-0000-0000-0000-000000000003}";
        MachinePolicyRetrievalEvalCycle = "{00000000-0000-0000-0000-000000000021}";
        MachinePolicyEvaluation = "{00000000-0000-0000-0000-000000000022}";
        RefreshDefaultManagementPoint = "{00000000-0000-0000-0000-000000000023}";
        RefreshLocation = "{00000000-0000-0000-0000-000000000024}";
        SoftwareMeteringUsageReporting = "{00000000-0000-0000-0000-000000000031}";
        SourcelistUpdateCycle = "{00000000-0000-0000-0000-000000000032}";
        RefreshProxyManagementPoint = "{00000000-0000-0000-0000-000000000037}";
        CleanupPolicy = "{00000000-0000-0000-0000-000000000040}";
        ValidateAssignments = "{00000000-0000-0000-0000-000000000042}";
        CertificateMaintenance = "{00000000-0000-0000-0000-000000000051}";
        BranchDPScheduledMaintenance = "{00000000-0000-0000-0000-000000000061}";
        BranchDPProvisioningStatusReporting = "{ 00000000-0000-0000-0000-000000000062}";
        SoftwareUpdateDeployment = "{00000000-0000-0000-0000-000000000108}";
        StateMessageUpload = "{00000000-0000-0000-0000-000000000111}";
        StateMessageCacheCleanup = "{00000000-0000-0000-0000-000000000112}";
        SoftwareUpdateScan = "{00000000-0000-0000-0000-000000000113}";
        SoftwareUpdateDeploymentReEval = "{00000000-0000-0000-0000-000000000114}";
        OOBSDiscovery = "{00000000-0000-0000-0000-000000000120}";
    }
     
    return Invoke-SCCMClientSchedule $computerName $scheduleIdList.$scheduleId
} 

<#
.SYNOPSIS
Allows triggering of SCCM client scheduled messages.

.DESCRIPTION
Takes in a computer name and an scheduled message id, and attempts to trigger it remotely.
#>
Function Invoke-SCCMClientSchedule {           
    [CmdletBinding()]             
    param(             
        [parameter(Mandatory=$true)][string]$computerName, 
        [Parameter(Mandatory=$true)][string]$scheduleId    
    ) 

    $sccmClient = [WMIclass]"\\$computerName\root\ccm:SMS_Client" 
    return $sccmClient.TriggerSchedule($scheduleId)
}

<#
.SYNOPSIS
Contacts a client computer to obtain its software distribution history.

.DESCRIPTION
Takes in a computer name and attempts to contact it to obtain information about its software distribution history.

The information comes from the CCM_SoftwareDistribution WMI class which according to the Microsoft documentation is a "class
that stores information specific to a software distribution, a combination of the properties for the package, program, and advertisement 
that were created to distribute the software."

.PARAMETER computerName
The name of the client to be contacted in order to retrieve the advertisement history.

.EXAMPLE
Get-SCCMSoftwareDistributionHistory -computerName MYCOMPUTER

.NOTES
http://msdn.microsoft.com/en-us/library/cc145304.aspx
#>
Function Get-SCCMClientSoftwareDistributionHistory {
    [CmdletBinding()]
    param (
        [parameter(Mandatory=$true)][string]$computerName
    )

    return Get-WMIObject -Computer $computerName -Namespace "root\CCM\Policy\Machine\ActualConfig" -Query "Select * from CCM_SoftwareDistribution"
}

<#
.SYNOPSIS
Returns the schedule ID for a specific advertisement on a specific client.

.DESCRIPTION
Takes in a computer name and an advertisement ID and contacts a client to find out the schedule ID for the advertisement.
Useful when trying to trigger and advertisement on demand.
#>
Function Get-SCCMClientAdvertisementScheduleId {
    [CmdletBinding()]
    param (
        [parameter(Mandatory=$true)][string]$computerName,
        [parameter(Mandatory=$true)][string]$advertisementId
    )

    $scheduledMessages = Get-WMIObject -Computer $computerName -Namespace "root\CCM\Policy\Machine\ActualConfig" -Query "Select * from CCM_Scheduler_ScheduledMessage"  
    foreach($scheduledMessage in $scheduledMessages) {
        if($($scheduledMessage.ScheduledMessageID).Contains($advertisementId)) {
            return $scheduledMessage.ScheduledMessageID
        }
    }
    return $null
}

<#
.SYNOPSIS
Returns the ssite code of a specific client computer.

.DESCRIPTION
Takes in a computer name and contacts the client to determine its assigned site code.
#>
Function Get-SCCMClientAssignedSite {
    [CmdletBinding()]
    param (
        [parameter(Mandatory=$true)][string]$computerName
    )

    $sccmClient = [WMIclass]"\\$computerName\root\ccm:SMS_Client" 
    return $($sccmClient.GetAssignedSite()).sSiteCode
}

<#
.SYNOPSIS
Assignes a new site code to a specific client computer.

.DESCRIPTION
Takes in a computer name and contacts the client to set its assigned site code.
#>
Function Set-SCCMClientAssignedSite {
    [CmdletBinding()]
    param (
        [parameter(Mandatory=$true)][string]$computerName,
        [parameter(Mandatory=$true)][string]$siteCode
    )

    $sccmClient = [WMIclass]"\\$computerName\root\ccm:SMS_Client" 
    return $sccmClient.SetAssignedSite($siteCode)
}

<#
.SYNOPSIS
Retrieves a client computer's cache size.

.DESCRIPTION
Contacts a client computer to retrieve information about its cache size.  The value returned represents the cache size in MB.

.PARAMETER computerName
Name of the computer to be contacted.

.EXAMPLE
Get-SCCMClientCacheSize -computerName MYCOMPUTER

Description
-----------
Returns the client computer's cache size in MB.
#>
Function Get-SCCMClientCacheSize {
    [CmdletBinding()]
    param (
        [parameter(Mandatory=$true)][string]$computerName
    )

    $cacheConfig = Get-WMIObject -Computer $computerName -Namespace "root\CCM\SoftMgmtAgent" -Query "Select * From CacheConfig"  
    return $cacheConfig.Size
}

<#
.SYNOPSIS
Changes the cache size for a client computer.

.DESCRIPTION
Contacts a client computer to change its cache size.  The value won't be picked up by the SCCM client on the target computer
until the CcmExec service is restarted.  This function does not attempt to restart the service.

.PARAMETER computerName
Name of the computer to be contacted.

.PARAMETER cacheSize
The new size of the computer's cache in MB.  This value must be greater than 0.

.EXAMPLE
Set-SCCMClientCacheSize -computerName MYCOMPUTER -cacheSize 1000

Description
-----------
Sets the client computer's cache size to 1000MB.
#>
Function Set-SCCMClientCacheSize {
    [CmdletBinding()]
    param (
        [parameter(Mandatory=$true)][string]$computerName,
        [parameter(Mandatory=$true)][int]$cacheSize
    )

    if($cacheSize -gt 0) {
        $cacheConfig = Get-WMIObject -Computer $computerName -Namespace "root\CCM\SoftMgmtAgent" -Query "Select * From CacheConfig"  
        $cacheConfig.Size = $cacheSize
        $cacheConfig.Put()
    } else {
        Throw "Cache size needs to be greater than 0"
    }
}

<#
.SYNOPSIS
Utility function to convert SCCM date strings into something readable.

.DESCRIPTION
This function exists for convenience so users of the module do not have to try to figure out, if they are not familiar with it, ways
to convert SCCM date strings into something readable.
#>
Function Convert-SCCMDate {
    [CmdletBinding()]
    param (
        [parameter(Mandatory=$true, ValueFromPipeline=$true)][string]$date
    )

    [System.Management.ManagementDateTimeconverter]::ToDateTime($date);
}

<#
.SYNOPSIS
Creates SCCM software distribution packages.

.DESCRIPTION
Takes in information about a specific site along with package details and creates a new software distribution package.  IF
successful, the function return a WMI object for the new package.

.PARAMETER siteServer
The name of the site server where the package will be created.

.PARAMETER siteCode
The 3-character site code for the site where the package will be created.

.PARAMETER packageName
Name of the new package.

.PARAMETER packageDescription
A description for the new package.

.PARAMETER packageVersion
The new package's version.

.PARAMETER packageManufacturer
The name of the developer of the package being created.

.PARAMETER packageLanguage
The language of the softwre being packaged.

.PARAMETER packageSource
Optional parameter.  If not specified, the package will be created without source files.  This parameter can take
the value of a local path on the site server, or a UNC path for a network share.
#>
Function New-SCCMPackage {
    [CmdletBinding()]
    param (
        [parameter(Mandatory=$true)][string]$siteServer,
        [parameter(Mandatory=$true)][string]$siteCode,
        [parameter(Mandatory=$true)][string]$packageName,
        [parameter(Mandatory=$true)][string]$packageDescription,
        [parameter(Mandatory=$true)][string]$packageVersion,
        [parameter(Mandatory=$true)][string]$packageManufacturer,
        [parameter(Mandatory=$true)][string]$packageLanguage,
        [string]$packageSource   
    )

    $newPackage = ([WMIClass]("\\$siteServer\root\sms\site_" + "$siteCode" + ":SMS_Package")).CreateInstance()
    $newPackage.Name = $packageName
    $newPackage.Description = $packageDescription
    $newPackage.Version = $packageVersion
    $newPackage.Manufacturer = $packageManufacturer
    $newPackage.Language = $packageLanguage
    if($packageSource) {
        $newPackage.PkgSourceFlag = 2
        $newPackage.PkgSourcePath = $packageSource
    } else {
        $newPackage.PkgSourceFlag = 1
    }
    $packageCreationResult = $newPackage.Put()

    if($packageCreationResult) {
        $newPackageIdTokens = $($packageCreationResult.RelativePath).Split("=")
        $newPackageId = $($newPackageIdTokens[1]).TrimStart("`"")
        $newPackageId = $($newPackageId).TrimEnd("`"")

        return Get-SCCMPackage $siteServer $siteCode $packageId $newPackageId
    } else {
        Throw "Package creation failed"
    }
}

<#
.SYNOPSIS
Removes SCCM packages from the site server.

.DESCRIPTION
Takes in information about a specific site and a package ID and deletes the package.

.PARAMETER siteServer
The name of the site server where the package exists.

.PARAMETER siteCode
The 3-character site code for the site where the package exists.

.PARAMETER packageId
The ID of the package to be deleted.

.EXAMPLE
Remove-SCCMPackage -siteServer MYSITESERVER -siteCode SIT -packageId MYID

Description
-----------
Deletes the package with ID MYID from SIT on MYSITESERVER
#>
Function Remove-SCCMPackage {
    [CmdletBinding()]
    param (
        [parameter(Mandatory=$true)][string]$siteServer,
        [parameter(Mandatory=$true)][string]$siteCode,
        [parameter(Mandatory=$true)][string]$packageId
    )    

    $package = Get-SCCMPackage $siteServer $siteCode -packageId $packageId
    return $package.psbase.Delete()
}

<#
.SYNOPSIS
Retrieves SCCM packages from the site server.

.DESCRIPTION
Takes in information about a specific site and a package name and/or package ID and returns all packages that match the specified parameters.  If no package name or ID is specified, it returns all packages found on the site server.

.PARAMETER siteServer
The name of the site server to be queried.

.PARAMETER siteCode
The 3-character site code for the site to be queried.

.PARAMETER packageName
Optional parameter.  If specified, the function attempts to match the package by package name. 

.PARAMETER packageId
Optional parameter.  If specified, the function attempts to match the package by package ID.

.EXAMPLE
Get-SCCMPackage -siteServer MYSITESERVER -siteCode SIT -packageName MYPACKAGE

Description
-----------
Retrieve the package named MYPACKAGE from site SIT on MYSITESERVER

.EXAMPLE
Get-SCCMPackage -siteServer MYSITESERVER -siteCode SIT -packageName MYPACKAGE -packageId MYPACKAGEID

Description
-----------
Retrieve the package named MYPACKAGE with ID matching MYPACKAGEID from site SIT on MYSITESERVER

.EXAMPLE
Get-SCCMPackage -siteServer MYSITESERVER -siteCode SIT

Description
-----------
Retrieve all packages from site SIT on MYSITESERVER

.EXAMPLE
Get-SCCMPackage -siteServer MYSITESERVER -siteCode SIT | Select-Object Name,PackageID

Description
-----------
Retrieve all packages from site SIT on MYSITESERVER and filter out only their names and IDs
#>
Function Get-SCCMPackage {
    [CmdletBinding()]
    param (
        [parameter(Mandatory=$true)][string]$siteServer,
        [parameter(Mandatory=$true)][string]$siteCode,
        [string]$packageName,
        [string]$packageId
    )

    if($packageName -and $packageId) {
        return Get-WMIObject -ComputerName $siteServer -Namespace "root\sms\site_$siteCode" -Class "SMS_Package" | where { ($_.Name -eq $packageName) -and ($_.PackageID -eq $packageId) }
    } elseif($packageName -and !$packageId) {
        return Get-WMIObject -ComputerName $siteServer -Namespace "root\sms\site_$siteCode" -Class "SMS_Package" | where { ($_.Name -eq $packageName) }
    } elseif(!$packageName -and $packageId) {
        return Get-WMIObject -ComputerName $siteServer -Namespace "root\sms\site_$siteCode" -Class "SMS_Package" | where { ($_.PackageID -eq $packageId) }
    } else { 
        return Get-WMIObject -ComputerName $siteServer -Namespace "root\sms\site_$siteCode" -Query "Select * From SMS_Package"
    }
}

<#
.SYNOPSIS
Creates a new SCCM program.

.DESCRIPTION
Creates a new SCCM program and associates it with a software distribution package.  This function currently only allows
for little customization and creates the program with most default settings.

.PARAMETER siteServer
Site server where the package containing the new program resides.

.PARAMETER siteCode
Site code for the site where the package containing the new program resides.

.PARAMETER packageId
ID of the package that will contain the new program.

.PARAMETER programName
A unique name for the program.  If this name matches the name for an existing program in the same package,
the program will be overwritten.

.PARAMETER programComment
A comment for the program.

.PARAMETER programCommandLine
The command line that will be executed when this program runs.
#>
Function New-SCCMProgram {
    [CmdletBinding()]
    param (
        [parameter(Mandatory=$true)][string]$siteServer,
        [parameter(Mandatory=$true)][string]$siteCode,
        [parameter(Mandatory=$true)][string]$packageId,
        [parameter(Mandatory=$true)][string]$programName,
        [parameter(Mandatory=$true)][string]$programComment,
        [parameter(Mandatory=$true)][string]$programCommandLine
    )

    if(Get-SCCMPackage $siteServer $siteCode -packageId $packageId) { 
        $newProgram = ([WMIClass]("\\$siteServer\root\sms\site_" + "$siteCode" + ":SMS_Program")).CreateInstance()
        $newProgram.ProgramName = $programName
        $newProgram.PackageID = $packageId
        $newProgram.Comment = $programComment
        $newProgram.CommandLine = $programCommandLine

        $programCreationResult = $newProgram.Put()
        if($programCreationResult) {
            $newProgramId = $($programCreationResult.RelativePath).TrimStart('SMS_Program.PackageID=')
            $newProgramId = $newProgramId.Substring(1,8)

            return Get-SCCMProgram $siteServer $siteCode $packageId $programName
        } else {
            Throw "Program creation failed"
        }
    } else {
        Throw "Invalid package ID $packageId"
    }
}

<#
.SYNOPSIS
Deletes a SCCM program.

.DESCRIPTION
Deletes a specific program belonging to specific software distribution package.

.PARAMETER siteServer
Site server where the package containing the program resides.

.PARAMETER siteCode
Site code for the site where the package containing the program resides.

.PARAMETER packageId
ID of the package that will contains the program to be removed.

.PARAMETER programName
Name of the program to be deleted.
#>
Function Remove-SCCMProgram {
    [CmdletBinding()]
    param (
        [parameter(Mandatory=$true)][string]$siteServer,
        [parameter(Mandatory=$true)][string]$siteCode,
        [parameter(Mandatory=$true)][string]$packageId,
        [parameter(Mandatory=$true)][string]$programName
    )

    $program = Get-SCCMProgram $siteServer $siteCode $packageId $programName
    if($program) {
        return $program.psbase.Delete()
    } else {
        Throw "Invalid program ID or program name"
    }
}

<#
.SYNOPSIS
Retrieves SCCM programs from the site server.

.DESCRIPTION
Takes in information about a specific site and a package ID and returns a program matching the package ID and program name
passed as parameters.

.PARAMETER siteServer
The name of the site server to be queried.

.PARAMETER siteCode
The 3-character site code for the site to be queried.

.PARAMETER packageId
Optional parameter.  If specified along with a program name, the function returns a program matching the and the package ID specified.
If only a package ID is specified, the function returns all programs that belong to the package.  If absent, the function returns all programs for the site.

.PARAMETER programName
Name of the program to be returned.  If specified, a package ID must also be specified.

.EXAMPLE
Get-SCCMProgram -siteServer MYSITESERVER -siteCode SIT -packageId PACKAGEID

Description
-----------
Retrieve all programs with package ID PACKAGEID from site SIT on MYSITESERVER

.EXAMPLE
Get-SCCMProgram -siteServer MYSITESERVER -siteCode SIT

Description
-----------
Retrieve all programs from site SIT on MYSITESERVER

.EXAMPLE
Get-SCCMProgram -siteServer MYSITESERVER -siteCode SIT | Select-Object ProgramName,PackageID

Description
-----------
Retrieve all programs from site SIT on MYSITESERVER and filter out only their names and package IDs
#>
Function Get-SCCMProgram {
    [CmdletBinding()]
    param (
        [parameter(Mandatory=$true)][string]$siteServer,
        [parameter(Mandatory=$true)][string]$siteCode,
        [string]$packageId,
        [string]$programName
    )

    if($packageId -and $programName) {
        return Get-WMIObject -ComputerName $siteServer -Namespace "root\sms\site_$siteCode" -Class "SMS_Program" | where { ($_.PackageID -eq $packageId) -and ($_.ProgramName -eq $programName) }
    } elseif($packageId -and !$programName) {
        return Get-WMIObject -ComputerName $siteServer -Namespace "root\sms\site_$siteCode" -Class "SMS_Program" | where { ($_.PackageID -eq $packageId) }
    } elseif(!$packageId -and $programName) {
        Throw "If a program name is specified, a package ID must also be specified"
    } else { 
        return Get-WMIObject -ComputerName $siteServer -Namespace "root\sms\site_$siteCode" -Query "Select * From SMS_Program"
    }
}

<#
.SYNOPSIS
Returns a list of distribution points for a particular site.

.DESCRIPTION
Takes in information about a particular site and returns WMI objects for each distribution point it finds.

.PARAMETER siteServer
The site server to be queried.

.PARAMETER siteCode
The 3-character code for the site that holds the distribution points to be returned.

.EXAMPLE
Get-SCCMDistributionPoints -siteServer MYSITESERVER -siteCode SIT
#>
Function Get-SCCMDistributionPoints {
    [CmdletBinding()]
    param (
        [parameter(Mandatory=$true)][string]$siteServer,
        [parameter(Mandatory=$true)][string]$siteCode
    )    

    return Get-WmiObject -ComputerName $siteServer -Namespace "root\sms\site_$siteCode" -Query "Select * From SMS_SystemResourceList" | Where { ($_.RoleName -eq "SMS Distribution Point") -and  ($_.SiteCode -eq $siteCode) }
}

Export-ModuleMember New-SCCMComputer
Export-ModuleMember Remove-SCCMComputer
Export-ModuleMember Get-SCCMComputer
Export-ModuleMember Add-SCCMComputerToCollection
Export-ModuleMember Remove-SCCMComputerFromCollection
Export-ModuleMember New-SCCMStaticCollection
Export-ModuleMember Remove-SCCMCollection
Export-ModuleMember Get-SCCMCollection
Export-ModuleMember Get-SCCMCollectionMembers
Export-ModuleMember Get-SCCMCollectionsForComputer
Export-ModuleMember Get-SCCMAdvertisement
Export-ModuleMember Get-SCCMAdvertisementsForCollection
Export-ModuleMember Get-SCCMAdvertisementsForComputer
Export-ModuleMember Get-SCCMAdvertisementsForPackage
Export-ModuleMember Get-SCCMAdvertisementStatusForComputer
Export-ModuleMember Set-SCCMComputerVariable
Export-ModuleMember Get-SCCMComputerVariables
Export-ModuleMember Remove-SCCMComputerVariable
Export-ModuleMember Invoke-SCCMClientAction
Export-ModuleMember Invoke-SCCMClientSchedule
Export-ModuleMember Get-SCCMClientSoftwareDistributionHistory 
Export-ModuleMember Get-SCCMClientAdvertisementScheduleId
Export-ModuleMember Get-SCCMClientAssignedSite
Export-ModuleMember Set-SCCMClientAssignedSite
Export-ModuleMember Get-SCCMClientCacheSize
Export-ModuleMember Set-SCCMClientCacheSize
Export-ModuleMember Convert-SCCMDate
Export-ModuleMember New-SCCMPackage
Export-ModuleMember Remove-SCCMPackage
Export-ModuleMember Get-SCCMPackage
Export-ModuleMember New-SCCMProgram 
Export-ModuleMember Remove-SCCMProgram
Export-ModuleMember Get-SCCMProgram
Export-ModuleMember Get-SCCMDistributionPoints
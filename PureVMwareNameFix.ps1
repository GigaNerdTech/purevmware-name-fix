# VMware/Pure Analyzer
# Written by Joshua Woleben

function find_volume {
    Param($pure_connect_obj, $pure_volume_list, $vmware_disk_name, $vmware_uuid, $pure_disk_name)

    $pure_disk_uuid = ($vmware_uuid -replace "naa\.\w{8}","").ToUpper()
    if ($vmware_disk_name -notmatch $pure_disk_name) {
         $pure_volume_list | ForEach-Object {
             $current_volume = $_
             if ($($current_volume | Select -ExpandProperty serial) -match $pure_disk_uuid) {
                 Write-Host "Mismatch found!`r`nVMware name: $vmware_disk_name VMware UUID: $vmware_uuid`r`nPure name: $pure_disk_name Pure UUID: $pure_disk_uuid`r`nLocated on array: `$array`r`nRunning command: `r`n `$pure_connect = New-PfaArray -EndPoint $array -Credentials `$pure_creds -IgnoreCertificateError -ErrorAction Stop`r`nRename-PfaVolumeOrSnapshot -Array `$pure_connect -Name $pure_disk_name -NewName $vmware_disk_name -Confirm:`$false`r`n Disconnect-PfaArray -Array `$pure_connect"
                Write-Host "Mismatch located!"
                if ($disk_name -match "\.") {
                    Write-Host "skipping disk name due to special characters."
                }
                else {
                if (-not($($pure_volume_list | Select -ExpandProperty name) -eq $vmware_disk_name)) {
                    Rename-PfaVolumeOrSnapshot -Array $pure_connect_obj -Name $pure_disk_name -NewName $vmware_disk_name -Confirm:$false -ErrorAction Stop
                }
                else {
                      Write-Host "Target $vmware_disk_name exists. Renaming Pure volume to temporary name."
                      Rename-PfaVolumeOrSnapshot -Array $pure_connect_obj -Name $vmware_disk_name -NewName ($vmware_disk_name + "-TMP") -Confirm:$false -ErrorAction Stop
                      Rename-PfaVolumeOrSnapshot -Array $pure_connect_obj -Name $pure_disk_name -NewName $vmware_disk_name -Confirm:$false -ErrorAction Stop
                       
                      # Figure out which volume is ACTUALLY the temporary one
                      find_volume $pure_connect_obj $pure_volume_list $vmware_disk_name $vmware_uuid $pure_disk_name
                      
               }
               }
 
           }       

        }
    }
    $pause = Read-Host "Press enter to continue..."
}

# Pure arrays
$pure_arrays = @("pure_array1","pure_Array2")
$pure_volumes= @{}
$datastore_to_pure = @{}
# Vcenter host
$vhosts = @("vcenter1","vcenter2")

$excel_file = "C:\Temp\VMwarePureNameFix_$(get-date -f MMddyyyyHHmmss).xlsx"
$TranscriptFile = "C:\Temp\VMwarePureNameFix_$(get-date -f MMddyyyyHHmmss).txt"
Start-Transcript -Path $TranscriptFile
Write-Output "Initializing..."

# Import required modules
Import-Module PureStoragePowerShellSDK
Import-Module VMware.VimAutomation.Core

# Define a gigabyte in bytes
$gb = 1073741824

# Gather authentication credentials
Write-Output "Please enter the following credentials: `n`n"

# Collect vSphere credentials
Write-Output "`n`nvSphere credentials:`n"
$vsphere_user = Read-Host -Prompt "Enter the user for the vCenter host"
$vsphere_pwd = Read-Host -Prompt "Enter the password for connecting to vSphere: " -AsSecureString
$vsphere_creds = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $vsphere_user,$vsphere_pwd -ErrorAction Stop

$pure_user = Read-Host -Prompt "Enter the user for the Pure storage arrays"
$pure_pwd = Read-Host -Prompt "Enter the password for the Pure storage array user: " -AsSecureString
$pure_creds = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $pure_user,$pure_pwd -ErrorAction Stop


# Get all pure volumes on all arrays
Write-Host "Gathering Pure volumes..."
ForEach ($array in $pure_arrays) {

    # Connect to Pure Array
    $pure_connect = New-PfaArray -EndPoint $array -Credentials $pure_creds -IgnoreCertificateError -ErrorAction Stop

    # Get all volumes
    $pure_volumes[$array] += Get-PfaVolumes -Array $pure_connect

    # Disconnect Pure array
    Disconnect-PfaArray -Array $pure_connect

}

foreach ($vcenter_host in $vhosts) {
    # Connect to vCenter
    Connect-VIServer -Server $vcenter_host -Credential $vsphere_creds -ErrorAction Stop

    # Get All VMs
    # Write-Host "Gathering all VMs..."
    # $vm_collection = Get-VM -Server $vcenter_host

    # Get all datastores
    Write-Host "Gathering datastores..."
    $datastore_collection = Get-Datastore -Server $vcenter_host




$fix_count = 0
    # Figure out what array a datastore is on
    Write-Host "Determining datastore array locations..."
    $datastore_collection | ForEach-Object {

        # Get disk name
        $disk_name = $_.Name

        # Get UUID from VMware
        if ($_.ExtensionData.Info.Vmfs.Extent -ne $null) {
            $uuid = $_.ExtensionData.Info.Vmfs.Extent[0].DiskName
        }


        # Translate VMware UUID to Pure UUID by removing the naa. and the first eight characters, and converting to uppercase
        $pure_uuid = ($uuid -replace "naa\.\w{8}","").ToUpper()


        # Search each array for the Pure UUID
        ForEach ($array in $pure_arrays) {
            $script:current_array = $pure_volumes[$array]
            # Search each volume for the correct UUID
            $pure_volumes[$array] | ForEach-Object { 
                # If UUID found, store with array name
                if (($_ | Select -ExpandProperty serial) -eq $pure_uuid) {

                            $datastore_to_pure[$disk_name] = $pure_uuid

                            $pure_volume_name = ($_ | Select -ExpandProperty name)
                            $pure_volume_uuid = ($_ | Select -ExpandProperty serial)
                if ($disk_name -match "\.") {
                    Write-Host "skipping disk name due to special characters."
                }
                else {
                    
                            if (("$disk_name" -notmatch "$pure_volume_name") -and ("$pure_volume_name" -notmatch "$disk_name")) {
                                 Write-Host "Mismatch found!`r`nVMware name: $disk_name VMware UUID: $uuid`r`nPure name: $pure_volume_name Pure UUID: $pure_uuid`r`nLocated on array: $array`r`nRunning command: `r`n `$pure_connect = New-PfaArray -EndPoint $array -Credentials `$pure_creds -IgnoreCertificateError -ErrorAction Stop`r`nRename-PfaVolumeOrSnapshot -Array `$pure_connect -Name $pure_volume_name -NewName $disk_name -Confirm:`$false`r`n Disconnect-PfaArray -Array `$pure_connect"
                                 Write-Host "Running command...."
                                 $pure_connect = New-PfaArray -EndPoint $array -Credentials $pure_creds -IgnoreCertificateError -ErrorAction Stop

                                 if (-not($(($script:current_array | Select -ExpandProperty name) -join " ") -match "$disk_name")) {
                                    Rename-PfaVolumeOrSnapshot -Array $pure_connect -Name $pure_volume_name -NewName $disk_name -Confirm:$false -ErrorAction Stop
                                 }
                                 else {
                                        Write-Host "Target $disk_name exists. Renaming Pure volume to temporary name."
                                        Rename-PfaVolumeOrSnapshot -Array $pure_connect -Name $disk_name -NewName ($disk_name + "-TMP") -Confirm:$false -ErrorAction Stop
                                        Rename-PfaVolumeOrSnapshot -Array $pure_connect -Name $pure_volume_name -NewName $disk_name -Confirm:$false -ErrorAction Stop

                                        # Figure out which volume is ACTUALLY the temporary one

                                       find_volume $pure_connect $script:current_array $disk_name $uuid ($disk_name + "-TMP")

                                 }
                                 Disconnect-PfaArray -Array $pure_connect

                                 $fix_count++


                             
                            }
                    }
                }

            }
        }
       
    }
    # Disconnect from vCenter
    Disconnect-VIServer -Server $vcenter_host -Confirm:$false
}



# Generate email report
$email_list=@("user1@example.com","user2@example.com")
$subject = "Pure/VMware Name Change"

$body = "Report on what changed when script ran commands.`nFix count: $fix_count"

Stop-Transcript

$MailMessage = @{
    To = $email_list
    From = "NameFixer<Donotreply@example.com>"
    Subject = $subject
    Body = $body
    SmtpServer = "smtp.example.com"
    ErrorAction = "Stop"
    Attachment = $TranscriptFile
}
Send-MailMessage @MailMessage


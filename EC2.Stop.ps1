#Set Root Dir
$RunDir = Split-path -Parent $MyInvocation.MyCommand.Definition

#Load Config
$Config = (Get-Content $RunDir\aws.json) -join "`n" | ConvertFrom-Json

#Load AWS PowerShell
if (!(Get-Module AWSPowerShell)) {
   Import-Module AWSPowerShell
}

Import-Module "$RunDir\Modules\functions" -DisableNameChecking
Log "Functions Loaded" "Yellow"

## END AWSPowerShell BoilerPlate Code ###

Log "Getting Active EC2 Instances"
[array]$ActiveEC2 = Get-EC2Instance | Where-Object {
   $_.Instances.State.Name -ne "terminated"
}

Log "Found: $($ActiveEC2.Count) Instances" "Green"

Log "Appending Name and State Info..."
ForEach ($instance in $ActiveEC2.Instances) {
   $Name = if ($instance.Tag | Where-Object {$_.Key -eq "Name"}) {
      ($instance.Tag | Where-Object {$_.Key -eq "Name"}).Value
   }
   else {
      "Null"
   }
   $instance | Add-Member Name($Name) -Force

   $state = $Instance.State.Name.Value

   $Instance | Add-Member State($State) -Force
}


$ActiveEC2.Instances | Format-Table Name, InstanceId, InstanceType, PrivateIPAddress, PublicIpAddress, VpcId, State

Log "Stopping Instances..."

ForEach ($instance in $ActiveEC2.Instances) {
   Log "Stopping Instance $($instance.Name) : $($Instance.InstanceId)" "Yellow"
   $StopEC2 = Stop-EC2Instance -InstanceId $instance.InstanceId
}

Log "Verifying Instance State..."

[array]$InstanceRunning = Get-EC2Instance | Where-Object {
   $_.Instances.State.Name -ne "stopped" -and
   $_.Instances.State.Name -ne "terminated"
}
Log "Instances Running: $($instanceRunning.Count)" "White"

While ($InstanceRunning.Count -gt 0) {
   Start-Sleep -Seconds 5
   Log "Verifying Instance State..."
   [array]$InstanceRunning = Get-EC2Instance | Where-Object {
      $_.Instances.State.Name -ne "stopped" -and
      $_.Instances.State.Name -ne "terminated"
   }
   Log "Instances Running: $($instanceRunning.Count)" "White"
}

Log "Getting Active EC2 Instances"
[array]$ActiveEC2 = Get-EC2Instance | Where-Object {
   $_.Instances.State.Name -ne "terminated"
}

Log "Found: $($ActiveEC2.Count) Instances" "Green"

Log "Appending Name and State Info..."
ForEach ($instance in $ActiveEC2.Instances) {
   $Name = if ($instance.Tag | Where-Object {$_.Key -eq "Name"}) {
      ($instance.Tag | Where-Object {$_.Key -eq "Name"}).Value
   }
   else {
      "Null"
   }
   $instance | Add-Member Name($Name) -Force

   $state = $Instance.State.Name.Value

   $Instance | Add-Member State($State) -Force
}


$ActiveEC2.Instances | Format-Table Name, InstanceId, InstanceType, PrivateIPAddress, PublicIpAddress, VpcId, State





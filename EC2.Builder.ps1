#Set Root Dir
$RunDir = Split-path -Parent $MyInvocation.MyCommand.Definition

$ErrorActionPreference = "Stop"

#Load Config
$Config = (Get-Content $RunDir\aws.json) -join "`n" | ConvertFrom-Json

#Load AWS PowerShell
if (!(Get-Module AWSPowerShell)) {
   Import-Module AWSPowerShell
}

Import-Module "$RunDir\Modules\functions" -DisableNameChecking
Log "Functions Loaded" "Yellow"

## END AWSPowerShell BoilerPlate Code ###

Log "Getting default EC2 Image..."
[array]$EC2Image = Get-EC2ImageByName -Name $Config.DefaultImageName
if ($EC2Image.count -ge 1) {
   Log "Found $($EC2Image.count) Image/s" "Cyan"
   $EC2Image | ForEach-Object { 
      "  +Architecture: $($_.Architecture) `n  +ImageId: $($_.ImageId) `n  +Description: $($_.Description)"
   }
}

Log "Getting Security Group..."
$SecurityGroup = Get-EC2SecurityGroup | Where-Object {
   $_.GroupName -eq $Config.SecurityGroup
}

Log "Loading UserData"
$UserDataFiles = Get-ChildItem $RunDir\UserData

[string]$UserDataStr = ""

ForEach($file in $UserDataFiles){
   $content = get-content $file.FullName
   #add powershell open tag
   $UserDataStr += "<powershell>`n"
   #write every line
   $content | ForEach-Object {
      $UserDataStr += "`n$_".Replace("REGIONREPLACE_PLACEHOLDER",$Config.Region)
   }
   #add powershell close tag
   $UserDataStr += "`n</powershell>"
   $UserDataStr += "`n<persist>true</persist>"
   
}
"USERDATA:"
$UserDataStr
Log "Encoding User Data..."
$EncodedUserData = [System.Convert]::ToBase64String(
   [System.Text.Encoding]::UTF8.GetBytes($UserDataStr)
)
"ENCODED:"
$EncodedUserData

Log "Getting EC2 Instances..."; ""

ForEach ($Instance in $Config.Instances) {
   Log "Valdating Config : $($Instance.Name)"
   $InstanceExist = $null

   While ($null -eq $InstanceExist) {
      $InstanceExist = Get-EC2Instance -Filter @{Name = "tag:Name"; Values = $Instance.Name} | Where-Object {
         $_.Instances.State.Name.Value -ne "terminated"
      }
      if ($InstanceExist) { 
         Log "Instance $($Instance.Name) Already Exists" "Cyan"
      }
      else {
         Log "Instance $($Instance.Name) Does not Exist, Creating..." "Yellow"
         Log "Getting Image..."
         $Image = Get-EC2Image -ImageId $Instance.Image

         $params = @{
            ImageId       = $Image.ImageId
            MinCount      = 1
            MaxCount      = 1
            InstanceType  = $Instance.Type
            KeyName       = $Config.keypairname
            SecurityGroupId = $SecurityGroup.GroupId
            UserData = $EncodedUserData
         }
         $InstanceExist = New-EC2Instance @params
         $Tag = New-EC2Tag -Resource $InstanceExist.Instances[0].InstanceId -Tag @{Key = "Name"; Value = $Instance.Name}
         $InstanceExist = Get-EC2Instance -Filter @{Name = "tag:Name"; Values = $Instance.Name} | Where-Object {
            $_.Instances.State.Name.Value -ne "terminated"
         }

      }
   }
   $InstanceObj = [PSCustomObject]@{
      Name     = ($InstanceExist.Instances.Tag | Where-Object {$_.Key -eq "Name"})[0].Value 
      Details  = $InstanceExist.Instances[0] 
      status   = $InstanceExist.Instances[0].State.Name.Value  
   }
  
   @"
  Name: $(if($InstanceObj.Name){$instanceObj.Name}else{'null'}) 
    + Description: $((Get-EC2Image -ImageId $InstanceObj.Details.ImageId).Description) 
    + InstanceType: $($instanceObj.Details.InstanceType)
    + Public IP: $($InstanceObj.Details.PublicIpAddress)
    + Status: $($InstanceObj.status)
"@
   ""
}

Log "Verifying Instance State..."

[array]$InstanceRunning = Get-EC2Instance | Where-Object {
   $_.Instances.State.Name -eq "running" -and
   $_.Instances.Tags.Value -in $Config.Instances.Name
}
Log "Instances Running: $($instanceRunning.Count)" "White"

While ($InstanceRunning.Count -lt $Config.Instances.Name.Count) {
   Start-Sleep -Seconds 10
   Log "Verifying Instance State..."
   [array]$InstanceRunning = Get-EC2Instance | Where-Object {
      $_.Instances.State.Name -eq "running" -and
      $_.Instances.Tags.Value -in $Config.Instances.Name
   }
   Log "Instances Running: $($instanceRunning.Count)" "White"
}

Log "Getting Active EC2 Instances"
[array]$ActiveEC2 = Get-EC2Instance | Where-Object {
   $_.Instances.State.Name -eq "running" -and
   $_.Instances.Tags.Value -in $Config.Instances.Name
}

Log "Found: $($ActiveEC2.Count) Instances" "Green"


$WSManTestCount = $ActiveEC2.Count
$WSManTestSuccess = 0
Log "Testing WSMAN on $WSManTestCount Instances"


While($WSManTestSuccess -lt $WSManTestCount){
   Start-Sleep 10
   ForEach($Instance in $InstanceRunning){
      $InstanceTestObj = @{
         Name = ($Instance.Instances.Tags | Where-Object{
            $_.Key -eq "Name"
         }).Value
         Password = Get-EC2PasswordData -InstanceId $Instance.Instances.InstanceId -PemFile "$RunDir\$($config.keypairname).pem" -ErrorAction SilentlyContinue
         Hostname = $Instance.Instances.PublicDnsName
      }
      if($InstanceTestObj.Hostname.Length -gt 1 -and $InstanceTestObj.Password.Length -gt 1){
         Log "Testing WSMan: on $($InstanceTestObj.Name) | $($InstanceTestObj.Hostname)" "Yellow"
         $option = New-PSSessionOption -SkipCACheck
         $sessionParams = @{
            ComputerName = $InstanceTestObj.Hostname
            Port = 5986
            Credential = new-Object System.Management.Automation.PSCredential(
               "Administrator",
               ($InstanceTestObj.Password | ConvertTo-SecureString -AsPlainText -Force)
            )
            UseSSL = $true
            SessionOption = $option
            ScriptBlock = {
               [pscustomobject]@{
                  Service = Get-WmiObject -Class "Win32_Service" | Where-Object{
                     $_.Name -eq "WinRM"
                  }
                  Cert = Get-ChildItem Cert:\LocalMachine\My
                  Listener = Get-ChildItem WSMan:\localhost\Listener | Where-Object{
                     $_.Keys -eq "Transport=HTTPS"
                  }
                  NetStat = Get-NetTCPConnection -LocalPort 5986 -State "Listen"
               }
            }

         }
         Try{
         [array]$WinRMtest = Invoke-Command @sessionParams
         }Catch{$lasterror = $_}
         if($WinRMtest){
            $WSManTestSuccess++
            Log "Connection Successful!" "Green"
            Log " + WinRM Service: $($WinRMTest.Service.State) :PID $($WinRMTest.Service.ProcessId) :StartMode $($WinRMTest.Service.StartMode)" "Green"
            Log " + Certificate: $($WinRMTest.Cert.Subject) Thumbprint: $($WinRMTest.Cert.Thumbprint)" "Green"
            Log " + Listener: $($WinRmTest.Listener.Name) Keys: $($WinRMTest.Listener.Keys)" "Green"
            Log " + Listening on: TCP : $($WinRMTest.NetStat.LocalPort)" "Green"
         }else{
            Log "Error: $lasterror"
         }
      }else{
         Log "Waiting for Credentials $($InstanceTestObj.Name) ..."
      }
   }
}





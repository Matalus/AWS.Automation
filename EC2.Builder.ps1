#Set Root Dir
$RunDir = Split-path -Parent $MyInvocation.MyCommand.Definition

#Load Config
$Config = (Get-Content $RunDir\aws.json) -join "`n" | ConvertFrom-Json

#Load AWS PowerShell
if(!(Get-Module AWSPowerShell)){
  Import-Module AWSPowerShell
}

  Import-Module "$RunDir\Modules\functions" -DisableNameChecking
  Log "Functions Loaded" "Yellow"

## END AWSPowerShell BoilerPlate Code ###

Log "Getting default EC2 Image..."
[array]$EC2Image = Get-EC2ImageByName -Name $Config.DefaultImageName
if($EC2Image.count -ge 1){
  Log "Found $($EC2Image.count) Image/s" "Cyan"
  $EC2Image | ForEach-Object { 
    "  +Architecture: $($_.Architecture) `n  +ImageId: $($_.ImageId) `n  +Description: $($_.Description)"
  }
}

Log "Getting EC2 Instances...";""

ForEach($Instance in $Config.Instances){
  Log "Valdating Config : $($Instance.Name)"
  $InstanceExist = $null

  While($null -eq $InstanceExist){
    $InstanceExist = Get-EC2Instance -Filter @{Name="tag:Name";Values=$Instance.Name} | Where-Object {
      $_.Instances.State.Name.Value -ne "terminated"
    }
    if($InstanceExist){ 
      Log "Instance $($Instance.Name) Already Exists" "Cyan"
    }else{
      Log "Instance $($Instance.Name) Does not Exist, Creating..." "Yellow"
      Log "Getting Image..."
      $Image = Get-EC2ImageByName -Name $Instance.Image

      $params = @{
        ImageId = $Image.ImageId
        MinCount = 1
        MaxCount = 1
        InstanceType = $Instance.Type
        KeyName = $Config.keypairname
        SecurityGroup = $Config.SecurityGroup
      }
      $InstanceExist = New-EC2Instance @params
      $Tag = New-EC2Tag -Resource $InstanceExist.Instances[0].InstanceId -Tag @{Key="Name";Value=$Instance.Name}
      $InstanceExist = Get-EC2Instance -Filter @{Name="tag:Name";Values=$Instance.Name} | Where-Object{
        $_.Instances.State.Name.Value -ne "terminated"
      }

    }
  }
  $InstanceObj = [PSCustomObject]@{
    Name = ($InstanceExist.Instances.Tag | Where-Object {$_.Key -eq "Name"})[0].Value 
    Details = $InstanceExist.Instances[0] 
    Password = Get-EC2PasswordData -InstanceId $InstanceExist.Instances.InstanceId -PemFile "$RunDir\$($config.keypairname).pem"
    status = $InstanceExist.Instances[0].State.Name.Value  
  }
  
 @"
  Name: $(if($InstanceObj.Name){$instanceObj.Name}else{'null'}) 
    + Platform: $($instanceObj.Details.Platform) 
    + InstanceType: $($instanceObj.Details.InstanceType)
    + Public IP: $($InstanceObj.Details.PublicIpAddress)
    + Status: $($InstanceObj.status)
    + Password $($InstanceObj.Password)
"@
""
}



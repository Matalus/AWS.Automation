<#
.SYNOPSIS
    Programatically setup WinRM HTTPS Listener
.NOTES
    Author: Matt Hamende
#>
function Log($message){
   Write-Host "$(get-date -Format u) | $message"
}

#define vars
$CertLoc = "cert:\LocalMachine\My"
$ip = Invoke-RestMethod http://ipinfo.io/json | Select -exp ip
$Hostname = "ec2-" + $ip.Replace(".","-") + ".REGIONREPLACE_PLACEHOLDER.compute.amazonaws.com"
$ListenPort = 5986
#Check for Self Signed Cert
Log "Checking for Self Signed Cert for CN $Hostname"
$Cert = Get-ChildItem Cert:\LocalMachine\My | Where-Object{
   $_.Subject -eq "CN=$Hostname"
}
#create cert if it doesn't exist
if(!$Cert){
   Log "Creating Cert..."
   $CertParams = @{
       DnsName = $Hostname
       CertStoreLocation = $CertLoc
   }
   $Cert = New-SelfSignedCertificate @CertParams
}else{
   Log "Cert Already Exists"
}
$Cert;""
#Check for HTTPS WSMAN Listener
$ListenPath = "wsman:\localhost\Listener"
Log "Checking for HTTPS Listener at: $ListenPath"
$Listener = Get-ChildItem $ListenPath | Where-Object {
   $_.Keys -eq "Transport=HTTPS"
}

#Create Listener if it doesn't exist
if(!$Listener){
   Log "Creating Listener..."
   $ListenParams = @{
       Path = $ListenPath
       Transport = "HTTPS"
       Address = "*"
       CertificateThumbprint = $Cert.Thumbprint
       Confirm = $false
       Force = $true
   }
   $Listener = New-Item @ListenParams
}else{
   Log "Listener Already Exists..."
}

#Check for Firewall rule
Log "Checking for Firewall Rule on port: $ListenPort"
$Rule = Get-NetFirewallPortFilter -Protocol "TCP" | Where-Object {
   $_.LocalPort -eq $ListenPort
} | Get-NetFirewallRule

if(!$Rule){
   Log "Creating Firewall Rule..."
   $RuleParams = @{
       DisplayName = "Windows Rmote Management HTTPS-IN"
       Name = "WinRM HTTPS-In"
       Profile = "Any"
       LocalPort = $ListenPort
       Protocol = "TCP"
   }
   $Rule = New-NetFirewallRule @RuleParams
}else{
   Log "Firewall Rule Already Exists"
}
$Rule;""

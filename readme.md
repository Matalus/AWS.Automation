
This module assumes you have the AWSPowerShell Module already installed

if you need to install "install-module AWSPowerShell" (PS5.0 and up)

you'll need to have your .PEM file in the root directory for your keypair

EC2.Builder.ps1 - Programatically builds EC2 Instances based on aws.json
   - verifies if instances with name already exists, if not creates
   - Inserts Any Scripts from the USERDATA directory as bootstraped Base64 encoded to run persistently so scripts should    be Idempotent
   - current PS Bootstrap script
      -verifies / creates WinRM HTTPS Listener
      -Self Signed Cert
      -Firewall rule for 5986
   - retrieves information on instances and waits for running status
   - Tests WSMan by remote invoking Instances and retrieving WinRM Service information

populate the Instances object in the following format

   {
      "Name": "<populates NAME Tag for Instance>",
      "Type": "t2.micro",
      "Image": "<The AMI of the image bootstrapping is currently setup for Powershell but could support Unix>"
    }

    Breakdown of keys
      -Region : default region to use, this also gets used for programatically creating the self signed cert
      -defaultAWSProfile : the default aws profile you've configured from credentials.csv
      -DefaultImageName : a default Windows Base image
      -Keypairname : the name of the keypair to attach to your instances, if you leave this blank good luck logging in
      -SecurityGroup : the name of a pre-existing security group to attach Instances to

 
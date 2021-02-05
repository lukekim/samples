# This script will run an ARM template deployment to deploy all the
# required resources into Azure. All the keys, tokens and endpoints
# will be automatically retreived and passed to the helm chart used
# in deployment. The only requirement is to populate the mysecrets.yaml
# file in the demochart folder with the twitter tokens, secrets and keys.
# If you already have existing infrastructure do not use this file.
# Simply fill in all the values of the mysecrets.yaml file and call helm
# install passing in that file using the -f flag.
# Requirements:
# Helm 3+
# PowerShell Core 7 (runs on macOS, Linux and Windows)
# Azure CLI (log in, runs on macOS, Linux and Windows)
[CmdletBinding()]
param (
   [Parameter(
      Position = 0,
      Mandatory = $true,
      HelpMessage = "The name of the resource group to be created. All resources will be place in the resource group and start with name."
   )]
   [string]
   $rgName,

   [Parameter(
      Position = 1,
      HelpMessage = "The location to store the meta data for the deployment."
   )]
   [string]
   $location = "eastus",

   [Parameter(
      Position = 2,
      HelpMessage = "The version of the dapr runtime version to deploy."
   )]
   [string]
   $daprVersion = "1.0.0-rc.3"
)

# Deploy the infrastructure
$deployment = $(az deployment sub create --location $location --template-file ./iac/main.json --parameters rgName=$rgName --output json) | ConvertFrom-Json

# Get all the outputs
$aksName = $deployment.properties.outputs.aksName.value
$storageAccountKey = $deployment.properties.outputs.storageAccountKey.value
$serviceBusEndpoint = $deployment.properties.outputs.serviceBusEndpoint.value
$storageAccountName = $deployment.properties.outputs.storageAccountName.value
$cognitiveServiceKey = $deployment.properties.outputs.cognitiveServiceKey.value
$cognitiveServiceEndpoint = $deployment.properties.outputs.cognitiveServiceEndpoint.value

Write-Verbose "aksName = $aksName"
Write-Verbose "storageAccountKey = $storageAccountKey"
Write-Verbose "serviceBusEndpoint = $serviceBusEndpoint"
Write-Verbose "storageAccountName = $storageAccountName"
Write-Verbose "cognitiveServiceKey = $cognitiveServiceKey"
Write-Verbose "cognitiveServiceEndpoint = $cognitiveServiceEndpoint"

# Get the credentials to use with dapr init and helm install
az aks get-credentials --resource-group $rgName --name "$aksName"

# Initialize Dapr
dapr init --kubernetes --runtime-version $daprVersion

# Confirm Dapr is running. If you run helm install to soon the Dapr side car
# will not be injected.
$status = dapr status --kubernetes

# Once all the services are running they will all report True instead of False.
# Keep checking the status until you don't find False
$attempts = 1
while ($($status | Select-String 'dapr-system  False').Matches.Length -ne 0) {
   Write-Output "Dapr not ready retry in 30 seconds. Attempts: $attempts"
   Start-Sleep -Seconds 30
   $attempts++
   $status = dapr status --kubernetes
}

# Install the demo into the cluster
helm install demo3 ./demochart -f ./demochart/mysecrets.yaml `
   --set serviceBus.connectionString=$serviceBusEndpoint `
   --set cognitiveService.token=$cognitiveServiceKey `
   --set cognitiveService.endpoint=$cognitiveServiceEndpoint `
   --set tableStorage.key=$storageAccountKey `
   --set tableStorage.name=$storageAccountName `
   --set onWindows=True

# Make sure service is ready
$service = $(kubectl get services viewer --output json) | ConvertFrom-Json

while ($null -eq $service.status.loadBalancer.ingress) {
   Write-Output 'Waiting for IP address retry in 30 seconds.'
   Start-Sleep -Seconds 30
   $service = $(kubectl get services viewer --output json) | ConvertFrom-Json
}

Write-Output "Your app is accesable from http://$($service.status.loadBalancer.ingress[0].ip)"
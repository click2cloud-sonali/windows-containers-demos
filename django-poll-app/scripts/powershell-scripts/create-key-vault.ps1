# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license.

# This file is used for creating Azure Key Vault

# setting variables from variable file
Foreach ($i in $(Get-Content variables.txt)){Set-Variable -Name $i.split("=")[0] -Value $i.split("=").split(" ")[1]}

$subscriptionId = (az account show | ConvertFrom-Json).id
$tenantId = (az account show | ConvertFrom-Json).tenantId

# Set Azure subscription name
Write-Host "Setting Azure subscription to $subscriptionName"  -ForegroundColor Yellow
az account set --subscription $subscriptionName

$akvRgExists = az group exists --name $resourceGroupName

if ($akvRgExists -eq $false) {
    #Create resource group
    Write-Host "Creating resource group $resourceGroupName in region $resourceGroupLocation" -ForegroundColor Yellow
    az group create `
        --name=$resourceGroupName `
        --location=$resourceGroupLocation `
        --output=jsonc
}

$akv = az keyvault show --name $akvName --query name | ConvertFrom-Json
$keyVaultExists = $akv.Length -gt 0

if ($keyVaultExists -eq $false) {
    #Create Azure Key Vault
    Write-Host "Creating Azure Key Vault $akvName under resource group $resourceGroupName " -ForegroundColor Yellow
    az keyvault create `
        --name=$akvName `
        --resource-group=$resourceGroupName `
        --location=$resourceGroupLocation `
        --output=jsonc
}

Write-Host "Retrieving Database details..."
$mysqlDatabase = az mysql db show --name $mysqlDatabaseName --resource-group $resourceGroupName --server $mysqlServerName --query name | ConvertFrom-Json

Write-Host "Creating secrets for application..."
az keyvault secret set --name DBHost --value "$mysqlServerName.mysql.database.azure.com" --vault-name $akvName
az keyvault secret set --name DBName --value "$mysqlDatabaseName" --vault-name $akvName
az keyvault secret set --name DBPort --value "3306" --vault-name $akvName
az keyvault secret set --name DBUser --value "$mysqlServerAdminUser" --vault-name $akvName
az keyvault secret set --name DBPassword --value "$mysqlServerAdminUserPassword" --vault-name $akvName

# retrieve existing AKS
Write-Host "Retrieving AKS details"
$aks = az aks show --name $clusterName --resource-group $resourceGroupName | ConvertFrom-Json

Write-Host "Retrieving the existing Azure Identity..."
$principalId = (az identity show --name "$clusterName-agentpool" --resource-group $aks.nodeResourceGroup | ConvertFrom-Json).principalId
$clientId = (az identity show --name "$clusterName-agentpool" --resource-group $aks.nodeResourceGroup | ConvertFrom-Json).clientId

Write-Host "Principal ID : $principalId "
Write-Host "Client ID : $clientId "

$akv = (az keyvault show --name $akvName | ConvertFrom-Json).name
Write-Host "Setting policy to access secrets in $akv Key Vault with Client Id..."
az keyvault set-policy --name $akvName --spn $clientId --secret-permissions get
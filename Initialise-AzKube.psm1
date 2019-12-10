#Create Docker Container Images
function Create-Containers
{
    Write-Host "Build and Create Container Images" -ForegroundColor Yellow
    docker-compose -f .\Example\docker-compose.yaml build
    docker-compose -f .\Example\docker-compose.yaml up -d

    Write-Host "Docker Running Images" -ForegroundColor Green
    docker ps
}

function Stop-ContainerInstances
{
    Write-Host "Stop and Remove running containers" -ForegroundColor Yellow
    docker-compose -f .\Example\docker-compose.yaml down
}

function Remove-ContainerImagesLocally
{
    Write-Host "Clean Docker" -ForegroundColor Yellow
    docker kill $(docker ps -q)
    docker rmi -f $(docker images -q)
}

function Initialize-Environment
{
    param(
        [Parameter(Mandatory)]
        [string]
        $resourceGroupName,
        [Parameter(Mandatory)]
        [ValidateSet(
        "northeurope",
        "westeurope",
        "centralus",
        "eastus", 
        "westus")]
        [string]
        $location,
        [Parameter(Mandatory)]
        [string]
        $subscription
    )

    $signedIn = SignIn -subscription $subscription

    if($signedIn)
    {        
        $basicName = $resourceGroupName -replace '[^a-zA-Z0-9]', ''

        CreateResourceGroup `
        -ResourceGroupName $resourceGroupName
        
        CreateAzureContainerRegistry `
        -resourceGroupName $resourceGroupName `
        -basicName $basicName `
        -location $location

        CreateAksCluster `
        -resourceGroupName $resourceGroupName `
        -basicName $basicName `
        -location $location
    }
}

#SignIn to Azure
function SignIn
{    
    param([string]$subscription)

    $signedIn = az account show
    if(!$signedIn)
    {
        az login --use-device-code
        $signedIn = az account show
    }

    az account set --subscription $subscription

    Return $signedIn
}

#Create Resource Group if Not Exist
function CreateResourceGroup
{
    param([string]$resourceGroupName)

    Write-Host "Checking Resource Group $resourceGroupName" -ForegroundColor Yellow
    $groupExists = az group exists -n $resourceGroupName

    if($groupExists -eq $false)
    {
       Write-Host "Creating Resource Group $resourceGroupName" -ForegroundColor Green
       az group create `
       -n $resourceGroupName `
       -l $location
    }
}

#Create ACR
function CreateAzureContainerRegistry
{
    param(
            [string]$resourceGroupName,
            [string]$basicName,
            [string]$location
        )

    $acrName = $basicName.ToLower() + "acr"

    Write-Host "Checking for ACR $acrName" -ForegroundColor Yellow
    $acrExists = az acr show `
    --name $acrName `
    --resource-group $resourceGroupName

    if(!$acrExists)
    {
        Write-Host "Creating ACR $acrName" -ForegroundColor Green
        az acr create `
        --resource-group $resourceGroupName `
        --name $acrName `
        --sku Basic `
        --location $location
    }

    #Write-Host "Login ACR $acrName" -ForegroundColor Green
    az acr login `
    --name $acrName `

    Write-Host "Tag Container" -ForegroundColor Green
    
    docker images

    $acrLoginServer = "$acrName.azurecr.io"

    docker tag azure-vote-front $acrLoginServer/azure-vote-front:v1

    docker images

    Write-Host "Push Image to registry" -ForegroundColor Green
    docker push $acrLoginServer/azure-vote-front:v1

    az acr repository list `
    --name $acrName `
    --output table
}

#Create Kubernetes Cluster if Not Exist
function CreateAksCluster
{    
    param(
        [string]$resourceGroupName,
        [string]$basicName,
        [string]$location
    )         

    $aksClusterName = $basicName.ToLower() + "akscluster"
    $acrName = $basicName.ToLower() + "acr"

    Write-Host "Checking for AKS Cluster $aksClusterName" -ForegroundColor Yellow
    $aksClusterExists = az aks show `
    -g $resourceGroupName `
    -n $aksClusterName

    if(!$aksClusterExists)
    {
        Write-Host "Creating AKS Cluster $aksClusterName" -ForegroundColor Green
        az aks create `
        -n $aksClusterName `
        -g $resourceGroupName `
        --node-count 2 `
        --generate-ssh-keys `
        --location $location `
        --attach-acr $acrName
    }
}

#Add AKS Nodepool
function AddAksNodePool
{
    param(
        [string]$resourceGroupName,
        [string]$basicName,
        [string]$location
    )

    $aksClusterName = $basicName.ToLower() + "akscluster"
    $nodeName = $basicName.ToLower() + "node" + (Get-Random -Maximum 100).ToString()

    $nodeExists = az aks nodepool show `
    --cluster-name $aksClusterName `
    --name $nodeName `
    --resource-group $resourceGroupName

    if($nodeExists)
    {
        az aks nodepool add `
        --cluster-name $aksClusterName `
        --name $nodeName `
        --resource-group $resourceGroupName `
        --enable-cluster-autoscaler
    }
}

Export-ModuleMember Create-Containers
Export-ModuleMember Stop-ContainerInstances
Export-ModuleMember Remove-ContainerImagesLocally
Export-ModuleMember Initialize-Environment

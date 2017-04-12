# Provision a MATLAB Distributed Computing Server using Azure VMs

Run your MATLAB compute-intensive parallel workloads by creating one or more MATLAB Distributed Computing Server clusters using Azure Virtual Machines.

# Pre-Requisites

Before starting you will need the following:

- An Azure account and subscription are required to create cluster virtual machines
and Azure Storage accounts.

- MATLAB, Parallel Computing Toolbox, and MATLAB Distributed Computing Server hosted licenses; the cluster
configuration assumes that the MathWorks Hosted License Manager is used for
    all licenses. See http://www.mathworks.com/products/parallel-computing/mathworks-hosted-license-manager/.

## Create a Cluster

One way to create a cluster is from Azure portal. Click the following buttons will bring you to Azure portal UI to deploy MATLAB Distributed Computing Server cluster.

The name of the Matlab Job Scheduler service will match the name of the resource group in which you deploy it.

## Matlab VM Image

Launch MJS cluster using a VM image with MDCS installed.

Pre-equisites:  
1. VM image with MATLAB installed in a storage account under the same subscription where the cluster will be created.
2. Storage container for VM disks in the same storage account as the VM image.
                
<a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Funiv2218%2Fazure-mjs-scripts%2Fmaster%2Fazuredeploy.json" target="_blank">
    <img src="http://azuredeploy.net/deploybutton.png"/>
</a>

## Matlab Data Disk

Launch MJS cluster using a snapshot of a data disk with MDCS installed. this will be attached to each VM created.

Pre-equisites:  
1. Snapshot of a data disk with MDCS innstalled.

<a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Funiv2218%2Fazure-mjs-scripts%2Fmaster%2Fmjs-matlabdisk.json" target="_blank">
    <img src="http://azuredeploy.net/deploybutton.png"/>
</a>

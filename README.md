# AzureDevOpsStatistics
A PowerShell script to scan organizations for projects, repos, prs, artifacts, and work items

## Setup
Download the Scan.ps1 file, located on the root of this repo. There are a few items to configure before we run: 
1. (line 3) You need to generate a [new PAT token in Azure DevOps](https://docs.microsoft.com/en-us/azure/devops/organizations/accounts/use-personal-access-tokens-to-authenticate?view=azure-devops&tabs=preview-page). If you need to process multiple organizations, ensure the organization drop down shows "All accessible organizations"
2. (line 4) Add an initial organization - this is what the API will log into to find all organizations/projects
3. (line 7) Create a folder to export the CSV files to
![image](https://user-images.githubusercontent.com/8389039/134520965-fff71381-507c-4ac3-bf9a-f29d07e883e2.png)

## Output

There are two outputs

1. PowerShell output, with a summary of metrics, and a list of each organization, project, and repo details.
![image](https://user-images.githubusercontent.com/8389039/134523388-cd6c461c-2653-4a36-a571-679e57e7022e.png)

2. A CSV file download of the PowerShell output. 
![image](https://user-images.githubusercontent.com/8389039/134527987-197cc4c6-b586-45ac-8d9a-b6a758cfcfbc.png)

## Thanks

Thank you to [Gregor](https://twitter.com/gregor_suttie) and [Adin](https://twitter.com/AdinErmie) for assistance in testing! 

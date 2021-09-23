
CLS
$pat = '' #Generate a PAT token in Azure DevOps. Select the scope to all organizations if you need to scan multiple organizations
$InitialOrganizationName = "samsmithnz"
$JustScanInitialOrganization = $false
$getArtifacts = $false
$csvLocation = "C:\users\samsm\desktop"

#Create encrpyted security token
$base64AuthInfo = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(":$pat"))

# Get all organizations
if ($JustScanInitialOrganization -eq $true)
{
    #This is a little dirty, and may fail in the future if Azure DevOps changes the way it lists all organizations
    $orgRequestBody = "{
        ""contributionIds"": [""ms.vss-features.my-organizations-data-provider""],
        ""dataProviderContext"":
            {
                ""properties"":{}
            }
    }"
    $uri = "https://dev.azure.com/$InitialOrganizationName/_apis/Contribution/HierarchyQuery?api-version=5.0-preview.1"
    $orgResponse = Invoke-RestMethod -Uri $uri -Body $orgRequestBody -ContentType application/json -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo)} -Method Post -ErrorAction Stop
    $orgResponseDetails = $orgResponse.dataProviders
    $organzations = $orgResponseDetails."ms.vss-features.my-organizations-data-provider".organizations
}
else
{
    #Add just the initial organization to the collection (just looping once)
    $organzations = @()
    $newOrg = New-Object -TypeName PSObject -Property @{
            id = "0"
            Name = $InitialOrganizationName
            url = ""
        }
    $organzations += $newOrg
}

$summary = @()
$artifacts = @()
$builds = @()
$releases = @()
$repos = @()
$prs = @()
$workItems = @()
Foreach ($organization in $organzations){
    $orgSummary = @()
    $orgName = $organization.name 
    Write-Host "Processing organization: $orgName"
    
    # Get Artifacts
    if ($getArtifacts -eq $true)
    {
        #https://feeds.dev.azure.com/{organization}/{project}/_apis/packaging/feeds?api-version=6.0-preview.1
        $uri = "https://feeds.dev.azure.com/$orgName/_apis/packaging/feeds?api-version=6.0-preview.1"
        try 
        {
            $artifactsJson = Invoke-RestMethod -Uri $uri -ContentType application/json -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo)} -Method Get -ErrorAction Stop
            $artifacts += $artifactsJson | ConvertTo-Json | ConvertFrom-Json | Select-Object -Expand Value | Select name
        }
        catch 
        {
            #do nothing  
            Write-Host "No access to $orgName artifacts"  
        }
    }

    # Get projects for organization
    #https://dev.azure.com/{organization}/_apis/projects?api-version=5.1
    $uri = "https://dev.azure.com/$orgName/_apis/projects?api-version=5.1"
    try
    {
        $projectsJson = Invoke-RestMethod -Uri $uri -ContentType application/json -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo)} -Method Get -ErrorAction Stop
        #Extract just the name and last updated date for each project into a new array
        $projects = $projectsJson.value | Foreach-Object{ 
   
            New-Object -TypeName PSObject -Property @{
                Name = $_.name
                LastUpdateTime = Get-Date $_.lastUpdateTime
            }
        } 


        #Loop through each project
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        Foreach ($project in $projects){

        # Build runs
        $uri = "https://dev.azure.com/$orgName/$($project.name)/_apis/build/builds?api-version=5.1"
        try
        {
            $buildRunsJson = Invoke-RestMethod -Uri $uri -ContentType application/json -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo)} -Method Get -ErrorAction Stop
            #$buildRunsJson | ConvertTo-Json
    
            $builds += $buildRunsJson.value | Foreach-Object{    
                New-Object -TypeName PSObject -Property @{
                    Name = $_.definition.name
                    BuildNumber = $_.buildNumber
                    Status = $_.status
                    Result = $_.result
                    QueueTime = Get-Date $_.queueTime
                    Organization = $orgName
                    ProjectName = $($project.name)
                }
            }
        }
        catch 
        {
            #do nothing 
            Write-Host "No access to $orgName $($project.name) builds"   
        }   

        # Release runs
        # https://vsrm.dev.azure.com/{organization}/{project}/_apis/release/releases?api-version=5.1
        $uri = "https://vsrm.dev.azure.com/$orgName/$($project.name)/_apis/release/releases?api-version=5.1"
        try
        {
            $releasesJson = Invoke-RestMethod -Uri $uri -ContentType application/json -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo)} -Method Get -ErrorAction Stop
            $releases += $releasesJson.value | ForEach-Object {
                $uri = "https://vsrm.dev.azure.com/$orgName/$($project.name)/_apis/release/releases/$($_.id)?api-version=5.1"
                $releaseJson = Invoke-RestMethod -Uri $uri -ContentType application/json -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo)} -Method Get -ErrorAction Stop

                $environments = $releaseJson.environments | ConvertTo-Json -Depth 5 | Where-Object status -ne "notStarted" 
                $environmentsObj = $environments | ConvertFrom-Json 
                $statuses = $environmentsObj | Select name, status | Where-Object status -ne "notStarted"
    
                New-Object -TypeName PSObject -Property @{
                    Id = $_.id
                    Name = $_.name
                    ReleaseDefinition = $_.releaseDefinition.name
                    Status = $_.status
                    CreatedOn = if($releaseJson -ne $null) {Get-Date $releaseJson.createdon} else { date }
                    LastEnvironmentName = if($statuses -ne $null) { $statuses[-1].name } else { "none" }
                    LastEnvironmentStatus = if($statuses -ne $null) { $statuses[-1].status } else { "none" } 
                    Organization = $orgName
                    ProjectName = $($project.name)
                }
            }
        }
        catch 
        {
            #do nothing
            Write-Host "No access to $orgName $($project.name) releases"     
        }

        # Get work items by project
        $projectWorkItems = @()
        $uri = "https://dev.azure.com/$orgName/$($project.name)/_apis/wit/reporting/workitemrevisions?api-version=5.1&includeDeleted=false"#&includeLatestOnly=true"
        do {

            try
            {
                $workItemsJson = Invoke-RestMethod -Uri $uri -ContentType application/json -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo)} -Method Get -ErrorAction Stop
                $projectWorkItems += $workItemsJson | ConvertTo-Json -Depth 10 | ConvertFrom-Json
                $uri = $workItemsJson.nextLink
            }
            catch 
            {
                #do nothing   
                Write-Host "No access to $orgName $($project.name) work items"  
            }

        } While ($workItemsJson.values.Length -gt 0) #Loop while there are items in the list. Once we reach the end of the list, we will have 0 items    
        $workItems += $projectWorkItems.values | ConvertTo-Json -Depth 10 | ConvertFrom-Json | Get-Unique -AsString


        #Repos
        #GET https://dev.azure.com/{organization}/{project}/_apis/git/repositories?api-version=6.0
        $projectRepos = @()
        $uri = "https://dev.azure.com/$orgName/$($project.name)/_apis/git/repositories?api-version=6.0"
        try
        {
            $reposJson = Invoke-RestMethod -Uri $uri -ContentType application/json -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo)} -Method Get -ErrorAction Stop
            $projectRepos = $reposJson.value | ConvertTo-Json -Depth 10 | ConvertFrom-Json
        }
        catch 
        {
            #do nothing   
            Write-Host "No access to $orgName $($project.name) repos"  
        }
        $repos += $projectRepos | ConvertTo-Json -Depth 10 | ConvertFrom-Json | Get-Unique -AsString

        #TFVCs (note there are no PRs - but should we be counting branches?)
        #GET https://dev.azure.com/{organization}/{project}/_apis/tfvc/items?api-version=6.0
        $tfvcRepoExists = $false
        try
        {
            $uri = "https://dev.azure.com/$orgName/$($project.name)/_apis/tfvc/items?api-version=6"
            $tfvcJson = Invoke-RestMethod -Uri $uri -ContentType application/json -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo)} -Method Get -ErrorAction Stop
            $projectTFVCRepos = $tfvcJson.value | ConvertTo-Json -Depth 10 | ConvertFrom-Json
            if ($projectTFVCRepos.Count -gt 0)
            {
                $tfvcRepoExists = $true
            }
        }
        catch 
        {
            #do nothing   
            Write-Host "No access to $orgName TVFC repos"  
        }

        #PRs
        #GET https://dev.azure.com/{organization}/{project}/_apis/git/repositories/{repositoryId}/pullrequests?searchCriteria.status=completed&api-version=6.0
        #Loop through each Repo for PR's
        Foreach ($projectRepo in $projectRepos){
            #if ($projectRepo.name -eq "SamLearnsAzure")
            #{
                $skipPRs = 0 # The number of pull requests to ignore. For example, to retrieve results 101-150, set top to 50 and skip to 100.
                $topPRs = 100 # The number of pull requests to retrieve.
                $uri = "https://dev.azure.com/$orgName/$($project.name)/_apis/git/repositories/$($projectRepo.id)/pullrequests?searchCriteria.status=completed&`$skip=$skipPRs&`$top=$topPRs&api-version=6.0"
                $projectReposPRs = @()
                $tmp = @()
                do {
                    $prsJson = Invoke-RestMethod -Uri $uri -ContentType application/json -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo)} -Method Get -ErrorAction Stop
                    $projectRepoPRsJson = $prsJson.value | ConvertTo-Json -Depth 10 | ConvertFrom-Json
                    $tmp = $projectRepoPRsJson | ConvertTo-Json -Depth 10 | ConvertFrom-Json | Get-Unique -AsString
                    $projectReposPRs += $tmp
                    $skipPRs += $topPRs
                    $uri = "https://dev.azure.com/$orgName/$($project.name)/_apis/git/repositories/$($projectRepo.id)/pullrequests?searchCriteria.status=all&`$skip=$skipPRs&`$top=$topPRs&api-version=6.0"
                } While ($tmp.Count -ge 100) #Loop while there are items in the list. Once we reach the end of the list, we will have 0 items    
                $prs += $projectReposPRs
            #}

            $orgSummary += (New-Object -TypeName PSObject -Property @{
                    Organization = $orgName
                    Project = $project.name
                    WorkItemCount = $projectWorkItems.values.Count
                    GitRepo = $projectRepo.name
                    TVFCRepoExists = $tfvcRepoExists
                    GitRepoCompressedSizeInMB = "{0:n2}" -f [math]::Round(($projectRepo.size / 1000000),2) # dividing by a million, not exact - but close enough
                    PRsCount = $(if($projectReposPRs.Count -eq $null) {1} else {$projectReposPRs.Count})
                    BuildsAndReleasesCount = $builds.Count + $releases.Count
                })
        }
        
        Write-Host "Scanning project $($project.name) ... ($($repos.Length) Git repos, $(if($tfvcRepoExists -eq $true) {1} else {0}) TFVC repos, $($prs.Length) prs, $($files.Length) files, $($builds.Length) builds, $($releases.Length) releases, and $($workItems.Length) work items found so far)"   
        } # end Foreach ($project in $projects){
    }
    catch 
    {
        #do nothing  
        Write-Host "No access to projects in organization $orgName"
        $projects = @{}  
    }
    $orgSummary | Select-Object Organization, Project, WorkItemCount, TVFCRepoExists, GitRepo, GitRepoCompressedSizeInMB, PRsCount | ft | Export-Csv -Path "$csvLocation\AzureDevOpsStats_$orgName.csv"
    $summary += $orgSummary
} # end Foreach ($org in $organzationsJson){

#Write-Host "Total builds: $($builds.Count)" 
#$builds | Select Name, Status, Result, QueueTime | Group-Object -Property Status, Result | Select Count, Name | ft

#Write-Host "Total releases: $($releases.Count)" 
#$releases | Select LastEnvironmentStatus | Group-Object -Property LastEnvironmentStatus | Select Count, Name | ft

Write-Host "Total work items: $($workItems.Count)" 
#$workItems.fields | Select System.WorkItemType, System.ChangedDate | Group-Object -Property System.WorkItemType | Select Count, Name | ft

if ($getArtifacts -eq $true)
{
    Write-Host "Total artifact feeds: $($artifacts.Count)"
    #$artifacts | Select name
}

Write-Host "Total Git repos: $($repos.Count)" 
$TotalReposOver2GB = ($repos | Where-Object size -gt $(2 * ([Math]::Pow(1000,3)))) #1000^3 is a billion/or ~1 GB
Write-Host "Total Git repos over 2GB: $($TotalReposOver2GB.Count)"
$TotalReposOver2GB | Select name, size | ft
Write-Host "Total PRs: $($prs.Count)" 

Write-Host "Summary"
$summary | ft Organization, Project, WorkItemCount, TVFCRepoExists, GitRepo, @{n='GitRepoCompressedSizeInMB';e={$_.GitRepoCompressedSizeInMB};align='right'}, PRsCount #, BuildsAndReleasesCount
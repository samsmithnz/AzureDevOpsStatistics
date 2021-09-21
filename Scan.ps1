
CLS
$pat = 'lsyzpk2ic75rbkaandvuoo7rxq2brrsj7vomiklygvrzlwrdedga'
$InitialOrganizationName = "samsmithnz"
$organization = $InitialOrganizationName

#Initialization
$base64AuthInfo = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(":$pat"))

# Get Organizations
$orgRequestBody = "{
    ""contributionIds"": [""ms.vss-features.my-organizations-data-provider""],
    ""dataProviderContext"":
        {
            ""properties"":{}
        }
}"
#$uri = "https://dev.azure.com/$InitialOrganizationName/_apis/Contribution/HierarchyQuery?api-version=5.0-preview.1"
#$orgResponse = Invoke-RestMethod -Uri $uri -Body $orgRequestBody -ContentType application/json -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo)} -Method Post -ErrorAction Stop
#$orgResponseDetails = $orgResponse.dataProviders
#$organzationsJson = $orgResponseDetails."ms.vss-features.my-organizations-data-provider".organizations

$users = @()
$artifacts = @()
$builds = @()
$releases = @()
$repos = @()
$prs = @()
$workItems = @()
#Foreach ($org in $organzationsJson){
    #This next part is a bit gross, but I can't get PowerShell to convert it into an object. The best I can do is isolate the name property
    #$organization = ($org | ConvertFrom-String).P2.Replace("name=","").Replace(";","")
    Write-Host "Processing organization: $organization"



    ## Get users 
    ##https://vsaex.dev.azure.com/samsmithnz/_apis/userentitlements?api-version=6.0-preview.3
    #$uri = "https://vsaex.dev.azure.com/$organization/_apis/userentitlements?api-version=6.0-preview.3&top=1000"
    #try 
    #{
    #    $usersJson = Invoke-RestMethod -Uri $uri -ContentType application/json -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo)} -Method Get -ErrorAction Stop
    #    $today = get-date
    #    $users += $usersJson.value | Foreach-Object{
    #        $User = $_.user | ConvertTo-Json | ConvertFrom-Json 
    #        New-Object -TypeName PSObject -Property @{
    #            DisplayName = $User.displayName
    #            MailAddress = $User.mailAddress
    #            CreatedDate = Get-Date -format "yyyy-MM-dd" $_.dateCreated
    #            LastAccessedDate = Get-Date -format "yyyy-MM-dd" $_.lastAccessedDate
    #            DaysSinceLastLogin = $(New-TimeSpan -Start $(Get-Date -format "yyyy-MM-dd" $_.lastAccessedDate) -End $today).Days
    #            Origin = $User.origin
    #            AssignementType = $_.accessLevel.assignmentSource
    #            LicenseDisplayName = $_.accessLevel.licenseDisplayName
    #            LicensingSource = $_.accessLevel.licensingSource
    #            Organization = $organization
    #            ProjectName = $($project.name)
    #        }
    #    }
    #}
    #catch 
    #{
    #    #do nothing 
    #    Write-Host "No access to $organization users"
    #}


    # Get Artifacts
    #https://feeds.dev.azure.com/{organization}/{project}/_apis/packaging/feeds?api-version=6.0-preview.1
    $uri = "https://feeds.dev.azure.com/$organization/_apis/packaging/feeds?api-version=6.0-preview.1"
    try 
    {
        $artifactsJson = Invoke-RestMethod -Uri $uri -ContentType application/json -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo)} -Method Get -ErrorAction Stop
        $artifacts += $artifactsJson | ConvertTo-Json | ConvertFrom-Json | Select-Object -Expand Value | Select name
    }
    catch 
    {
        #do nothing  
        Write-Host "No access to $organization artifacts"  
    }


    # Get projects
    #https://dev.azure.com/{organization}/_apis/projects?api-version=5.1
    $uri = "https://dev.azure.com/$organization/_apis/projects?api-version=5.1"
    try
    {
        $projectsJson = Invoke-RestMethod -Uri $uri -ContentType application/json -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo)} -Method Get -ErrorAction Stop
        #$projectsJson | ConvertTo-Json
        $projects = $projectsJson.value | Foreach-Object{ 
   
            New-Object -TypeName PSObject -Property @{
                Name = $_.name
                LastUpdateTime = Get-Date $_.lastUpdateTime
            }
        }
    }
    catch 
    {
        #do nothing  
        Write-Host "No access to $organization projects"
        $projects = @{}  
    }

    #Loop through each project
    Foreach ($project in $projects){

        # Build runs
        $uri = "https://dev.azure.com/$organization/$($project.name)/_apis/build/builds?api-version=5.1"
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
                    Organization = $organization
                    ProjectName = $($project.name)
                }
            }
        }
        catch 
        {
            #do nothing 
            Write-Host "No access to $organization $($project.name) builds"   
        }   

        # Release runs
        # https://vsrm.dev.azure.com/{organization}/{project}/_apis/release/releases?api-version=5.1
        $uri = "https://vsrm.dev.azure.com/$organization/$($project.name)/_apis/release/releases?api-version=5.1"
        try
        {
            $releasesJson = Invoke-RestMethod -Uri $uri -ContentType application/json -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo)} -Method Get -ErrorAction Stop
            $releases += $releasesJson.value | ForEach-Object {
                $uri = "https://vsrm.dev.azure.com/$organization/$($project.name)/_apis/release/releases/$($_.id)?api-version=5.1"
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
                    Organization = $organization
                    ProjectName = $($project.name)
                }
            }
        }
        catch 
        {
            #do nothing
            Write-Host "No access to $organization $($project.name) releases"     
        }

        # Get work items by project
        $projectWorkItems = @()
        $uri = "https://dev.azure.com/$organization/$($project.name)/_apis/wit/reporting/workitemrevisions?api-version=5.1&includeDeleted=false&includeLatestOnly=true"
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
                Write-Host "No access to $organization $($project.name) work items"  
            }

        } While ($workItemsJson.values.Length -gt 0) #Loop while there are items in the list. Once we reach the end of the list, we will have 0 items    
        $workItems += $projectWorkItems.values | ConvertTo-Json -Depth 10 | ConvertFrom-Json | Get-Unique -AsString


        #Repos
        #GET https://dev.azure.com/{organization}/{project}/_apis/git/repositories?api-version=6.0
        $projectRepos = @()
        $uri = "https://dev.azure.com/$organization/$($project.name)/_apis/git/repositories?api-version=6.0"
        try
        {
            $reposJson = Invoke-RestMethod -Uri $uri -ContentType application/json -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo)} -Method Get -ErrorAction Stop
            $projectRepos = $reposJson.value | ConvertTo-Json -Depth 10 | ConvertFrom-Json
        }
        catch 
        {
            #do nothing   
            Write-Host "No access to $organization $($project.name) repos"  
        }
        $repos += $projectRepos | ConvertTo-Json -Depth 10 | ConvertFrom-Json | Get-Unique -AsString

        #PRs
        #Loop through each Repo for PR's
        #GET https://dev.azure.com/{organization}/{project}/_apis/git/repositories/{repositoryId}/pullrequests?api-version=6.0
        Foreach ($projectRepo in $projectRepos){
            $uri = "https://dev.azure.com/$organization/$($project.name)/_apis/git/repositories/$($projectRepo.id)/pullrequests?api-version=6.0"
            $prsJson = Invoke-RestMethod -Uri $uri -ContentType application/json -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo)} -Method Get -ErrorAction Stop
            $projectRepoPRs = $prsJson.value | ConvertTo-Json -Depth 10 | ConvertFrom-Json
            $prs += $projectRepoPRs | ConvertTo-Json -Depth 10 | ConvertFrom-Json | Get-Unique -AsString
        }

        #TODO: TFVS (no PRs)



        Write-Host "Scanning project $($project.name) ... ($($repos.Length) repos, $($builds.Length) builds, $($releases.Length) releases, and $($workItems.Length) work items found so far)" 
  
    }
#}

#results
Write-Host "Total users: $($users.Length)" 
$users | ft DisplayName, MailAddress, CreatedDate, LastAccessedDate, DaysSinceLastLogin, Origin, AssignementType, LicenseDisplayName, LicensingSource -auto

$TotalBuilds = $builds 
Write-Host "Total builds: $($TotalBuilds.Count)" 
#$TotalBuilds | Select Name, Status, Result, QueueTime | Group-Object -Property Status, Result | Select Count, Name | ft

$TotalReleases = $releases 
Write-Host "Total releases: $($TotalReleases.Count)" 
#$TotalReleases | Select LastEnvironmentStatus | Group-Object -Property LastEnvironmentStatus | Select Count, Name | ft

$TotalWorkItems = $workItems 
Write-Host "Total work items: $($workItems.Count)" 
#$TotalWorkItems.fields | Select System.WorkItemType, System.ChangedDate | Group-Object -Property System.WorkItemType | Select Count, Name | ft

Write-Host "Total artifact feeds: $($artifacts.Count)"
#$artifacts | Select name

$TotalRepos = $repos 
Write-Host "Total Repos: $($TotalRepos.Count)" 
$TotalReposOver2GB = ($TotalRepos | Where-Object size -gt $(2 * ([Math]::Pow(1000,3)))).Count 
Write-Host "Total Repos over 2GB: $($TotalReposOver2GB)"
$TotalRepos | Select name, size | Where-Object size -gt $(2 * ([Math]::Pow(1000,3))) | ft


$TotalPRs = $prs 
Write-Host "Total PRs: $($TotalPRs.Count)" 
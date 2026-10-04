$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repo = Split-Path -Parent $PSScriptRoot
. (Join-Path $repo 'stages\07_structure\propose_layout.ps1')
$policy = Get-Content -LiteralPath (Join-Path $repo 'policy\estate-policy-v1.json') -Raw |
    ConvertFrom-Json -Depth 64
$asOf = [DateTimeOffset]::Parse('2026-10-04T12:00:00Z')

function New-TestItem {
    param(
        [string] $Path,
        [string] $Extension = '',
        [string] $Modified = '2026-10-03T12:00:00Z',
        [string] $GeneratedHint = ''
    )
    [pscustomobject]@{
        RelativePath = $Path
        Extension = $Extension
        LastWriteTimeUtc = $Modified
        GeneratedHint = $GeneratedHint
    }
}

function Assert-Equal {
    param($Actual, $Expected, [string] $Message)
    if (($null -eq $Actual -or [string]$Actual -eq '') -and
        ($null -eq $Expected -or [string]$Expected -eq '')) {
        return
    }
    if ($Actual -ne $Expected) {
        throw "$Message; expected='$Expected' actual='$Actual'"
    }
}

$cases = @(
    @{ Source='c-onedrive'; Path='Passport\passport photo.jpg'; Ext='.jpg'; Category='identity-immigration'; Disposition='personal-authority'; Folder='01_IDENTITY-IMMIGRATION' },
    @{ Source='h-my-drive'; Path='US Visa\I-485.pdf'; Ext='.pdf'; Category='identity-immigration'; Disposition='personal-authority'; Folder='01_IDENTITY-IMMIGRATION' },
    @{ Source='h-my-drive'; Path='Medical\patient history.pdf'; Ext='.pdf'; Category='medical'; Disposition='personal-authority'; Folder='03_MEDICAL' },
    @{ Source='h-my-drive'; Path='Personal\Health Connect.zip'; Ext='.zip'; Category='medical'; Disposition='personal-authority'; Folder='03_MEDICAL' },
    @{ Source='c-downloads'; Path='Mindmaker diagnostic prompt.docx'; Ext='.docx'; Modified='2025-09-26T00:00:00Z'; Category='venture-mind-make'; Disposition='archive'; Folder='02_BUSINESS-HISTORY' },
    @{ Source='g-my-drive'; Path='Bharti Raja - LPA (Financial).gdoc'; Ext='.gdoc'; Category='family-admin'; Disposition='personal-authority'; Folder='08_FAMILY-ADMIN' },
    @{ Source='g-my-drive'; Path='AU - Offence - Court Statement.docx'; Ext='.docx'; Category='forms-life-admin'; Disposition='personal-authority'; Folder='06_FORMS-AND-LIFE-ADMIN' },
    @{ Source='h-my-drive'; Path='Brisbane Property\settlement.pdf'; Ext='.pdf'; Category='property-brisbane'; Disposition='personal-authority'; Folder='04_PROPERTY-BRISBANE' },
    @{ Source='h-my-drive'; Path='Career\Job Search OS.gdoc'; Ext='.gdoc'; Category='canonical-job-search-system'; Disposition='personal-authority'; Folder='05_JOB-SEARCH-APPLICATIONS' },
    @{ Source='h-my-drive'; Path='Cold Ideas and Inspo\idea.gdoc'; Ext='.gdoc'; Category='cold-ideas-inspiration'; Disposition='current'; Folder='09_COLD-IDEAS-AND-INSPO' },
    @{ Source='h-my-drive'; Path='DoThinkDo\sales slides.pptx'; Ext='.pptx'; Category='customer-dothinkdo'; Disposition='current'; Folder='07_DOTHINKDO' },
    @{ Source='h-my-drive'; Path='makeyourmindup\draft video.mp4'; Ext='.mp4'; Category='media-channel-makeyourmindup'; Disposition='current'; Folder='06_MAKEYOURMINDUP' },
    @{ Source='h-my-drive'; Path='Mindmaker-OS\Control Center.gdoc'; Ext='.gdoc'; Category='venture-mindmake-os'; Disposition='current'; Folder='02_MINDMAKE-OS' },
    @{ Source='h-my-drive'; Path='Mindmaker\theory corpus.md'; Ext='.md'; Category='business-theory-corpuses'; Disposition='current'; Folder='08_BUSINESS-THEORY-CORPUSES' },
    @{ Source='h-my-drive'; Path='Fractionl\Pulse\brief.docx'; Ext='.docx'; Category='venture-fractionl'; Disposition='current'; Folder='03_FRACTIONL' },
    @{ Source='h-my-drive'; Path='Labs\old experiment.txt'; Ext='.txt'; Category='retired-experiments-labs'; Disposition='archive'; Folder='06_RETIRED-VENTURES-PROJECTS' },
    @{ Source='h-my-drive'; Path='Podcast\Riverside recording.wav'; Ext='.wav'; Category='podcast-recordings'; Disposition='archive'; Folder='03_PODCAST-RECORDINGS' },
    @{ Source='c-downloads'; Path='screenshots\Screenshot 1.png'; Ext='.png'; Category='media-noise'; Disposition='delete-candidate'; Folder=$null },
    @{ Source='c-downloads'; Path='setup.msi'; Ext='.msi'; Category='installer-package'; Disposition='delete-candidate'; Folder=$null },
    @{ Source='c-downloads'; Path='~$draft.docx'; Ext='.docx'; Category='office-lock-file'; Disposition='delete-candidate'; Folder=$null },
    @{ Source='h-my-drive'; Path='FAMILY-ADMIN\Maa\record.gdoc'; Ext='.gdoc'; Category='family-admin'; Disposition='preserve-in-place'; Folder=$null },
    @{ Source='c-onedrive'; Path='Documents\supabase token.txt'; Ext='.txt'; Category='credentials-secrets'; Disposition='secure-quarantine-review'; Folder=$null },
    @{ Source='c-dev'; Path='krishanraja\mm-ctrl\worktree.txt'; Ext='.txt'; Category='critical-local-work'; Disposition='preserve-in-place'; Folder=$null }
)

foreach ($case in $cases) {
    $modified = if ($case.ContainsKey('Modified')) { $case.Modified } else { '2026-10-03T12:00:00Z' }
    $item = New-TestItem -Path $case.Path -Extension $case.Ext -Modified $modified
    $result = Get-FaLayoutClassification -Item $item -ItemSourceId $case.Source `
        -Policy $policy -AnalysisDate $asOf
    Assert-Equal $result.Category $case.Category "category for $($case.Path)"
    Assert-Equal $result.Disposition $case.Disposition "disposition for $($case.Path)"
    Assert-Equal $result.DestinationFolder $case.Folder "folder for $($case.Path)"
    if ($result.DestinationFolder -and $result.DestinationFolder -match '[\\/]') {
        throw "destination is not shallow: $($result.DestinationFolder)"
    }
}

$oldVenture = Get-FaLayoutClassification `
    -Item (New-TestItem -Path 'Mindmaker\old deck.pptx' -Extension '.pptx' -Modified '2026-01-01T00:00:00Z') `
    -ItemSourceId 'h-my-drive' -Policy $policy -AnalysisDate $asOf
Assert-Equal $oldVenture.Disposition 'archive' 'old venture visibility rule'
Assert-Equal $oldVenture.DestinationFolder '02_BUSINESS-HISTORY' 'old venture archive folder'

$oldTheory = Get-FaLayoutClassification `
    -Item (New-TestItem -Path 'Mindmaker\theory corpus.md' -Extension '.md' -Modified '2018-01-01T00:00:00Z') `
    -ItemSourceId 'h-my-drive' -Policy $policy -AnalysisDate $asOf
Assert-Equal $oldTheory.Disposition 'current' 'old theory remains evergreen'

$temporary = Get-FaLayoutClassification `
    -Item (New-TestItem -Path 'Mindmaker\agent instructions v3.docx' -Extension '.docx' -Modified '2025-01-01T00:00:00Z') `
    -ItemSourceId 'h-my-drive' -Policy $policy -AnalysisDate $asOf
Assert-Equal $temporary.Disposition 'temporary-family-review' 'old agent instructions require family review'

$generated = Get-FaLayoutClassification `
    -Item (New-TestItem -Path 'owner\repo\node_modules\x.js' -Extension '.js' -GeneratedHint 'node_modules') `
    -ItemSourceId 'c-dev' -Policy $policy -AnalysisDate $asOf
Assert-Equal $generated.Disposition 'generated-cleanup-candidate' 'repo generated material is project-level cleanup'

$blocked = $false
try {
    Get-FaLayoutClassification `
        -Item (New-TestItem -Path 'ContentLibrary\anything.jpg' -Extension '.jpg') `
        -ItemSourceId 'h-my-drive' -Policy $policy -AnalysisDate $asOf | Out-Null
} catch {
    $blocked = $_.Exception.Message -match 'excluded boundary leaked'
}
if (-not $blocked) { throw 'H ContentLibrary leakage was not refused' }

$scratch = Join-Path ([IO.Path]::GetTempPath()) ('filearchives-layout-time-' + [guid]::NewGuid().ToString('n'))
try {
    $inventory = Join-Path $scratch 'inventory'
    $segments = Join-Path $inventory 'fixture\segments'
    $output = Join-Path $scratch 'output'
    $source = Join-Path $scratch 'source'
    $audit = Join-Path $scratch 'audit'
    New-Item -ItemType Directory -Path $segments,$source,$audit -Force | Out-Null
    $stamp = '2026-10-03T12:34:56.1234567+00:00'
    $segment = @{ Items=@(@{ Kind='file'; RelativePath='Mindmaker\brief.md'; Extension='.md'; Length=5; LastWriteTimeUtc=$stamp; GeneratedHint=$null }) }
    [IO.File]::WriteAllText((Join-Path $segments 'segment-00000001.json'), ($segment|ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
    $workspacePath = Join-Path $scratch 'workspace.json'
    $workspace = @{ schema_version=2; audit=$audit; sources=@(@{id='fixture';path=$source;kind='test';follow_reparse_points=$false}); protected_roots=@((Join-Path $scratch 'protected')); protected_names=@() }
    [IO.File]::WriteAllText($workspacePath, ($workspace|ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
    Invoke-FaLayoutProposal -WorkspacePath $workspacePath -InventoryPath $inventory -ResultPath $output `
        -RulesPath (Join-Path $repo 'policy\estate-policy-v1.json') -OnlySourceId fixture -AnalysisDate $asOf | Out-Null
    $proposalRow = Get-Content -LiteralPath (Join-Path $output 'layout-proposal.jsonl') -Raw | ConvertFrom-Json -DateKind String
    Assert-Equal $proposalRow.LastWriteTimeUtc $stamp 'layout proposal preserves round-trip inventory timestamp'
} finally {
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force }
}

Write-Host "layout classifier tests passed: $($cases.Count + 5) assertions groups"

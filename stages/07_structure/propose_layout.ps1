[CmdletBinding()]
param(
    [string] $ConfigPath,
    [string] $RunId,
    [string] $PolicyPath,
    [string] $InventoryRoot,
    [string] $OutputRoot,
    [string] $DuplicateEvidencePath,
    [string[]] $SourceId,
    [datetimeoffset] $AsOf = [DateTimeOffset]::Now
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'guards\workspace.ps1')
. (Join-Path $repo 'guards\atomic.ps1')

function Test-FaRelativePrefix {
    param([string] $Path, [string] $Prefix)
    $p = $Path.Replace('/', '\').Trim('\')
    $b = $Prefix.Replace('/', '\').Trim('\')
    return $p.Equals($b, [StringComparison]::OrdinalIgnoreCase) -or
        $p.StartsWith($b + '\', [StringComparison]::OrdinalIgnoreCase)
}

function Add-FaAggregate {
    param([hashtable] $Map, [string] $Key, [long] $Bytes)
    if (-not $Map.ContainsKey($Key)) {
        $Map[$Key] = [ordered]@{ Files = [long]0; Bytes = [long]0 }
    }
    $Map[$Key].Files++
    $Map[$Key].Bytes += $Bytes
}

function Convert-FaAggregate {
    param([hashtable] $Map)
    return @($Map.GetEnumerator() | ForEach-Object {
        [pscustomobject]@{
            Name = [string]$_.Key
            Files = [long]$_.Value.Files
            Bytes = [long]$_.Value.Bytes
        }
    } | Sort-Object Files, Bytes -Descending)
}

function Get-FaDuplicateIndex {
    param([string] $Path)
    $map = @{}
    if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $map
    }
    $evidence = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -Depth 64
    foreach ($group in @($evidence.Groups)) {
        foreach ($member in @($group.Members)) {
            $key = ('{0}|{1}' -f ([string]$member.SourceId).ToLowerInvariant(),
                ([string]$member.RelativePath).Replace('/', '\').ToLowerInvariant())
            $map[$key] = [pscustomobject]@{
                Sha256 = [string]$group.Sha256
                MemberCount = [int]$group.MemberCount
                ContainsManagedRepo = [bool]$group.ContainsManagedRepo
            }
        }
    }
    return $map
}

function New-FaLayoutResult {
    param(
        [string] $Category,
        [string] $Disposition,
        [string] $Confidence,
        [string] $RuleId,
        [string] $DestinationRoot,
        [string] $DestinationFolder,
        [string[]] $Reasons
    )
    if ($DestinationFolder -and $DestinationFolder -match '[\\/]') {
        throw "destination folder must be exactly one shallow component: $DestinationFolder"
    }
    return [pscustomobject]@{
        Category = $Category
        Disposition = $Disposition
        Confidence = $Confidence
        RuleId = $RuleId
        DestinationRoot = $DestinationRoot
        DestinationFolder = $DestinationFolder
        Reasons = @($Reasons)
    }
}

function Get-FaLayoutClassification {
    param(
        [Parameter(Mandatory)] $Item,
        [Parameter(Mandatory)][string] $ItemSourceId,
        [Parameter(Mandatory)] $Policy,
        [Parameter(Mandatory)][datetimeoffset] $AnalysisDate
    )

    $relative = ([string]$Item.RelativePath).Replace('/', '\').Trim('\')
    $path = $relative.ToLowerInvariant()
    $extension = ([string]$Item.Extension).ToLowerInvariant()
    $lastWrite = [DateTimeOffset]::Parse([string]$Item.LastWriteTimeUtc)
    $ageDays = [math]::Max(0, [math]::Floor(($AnalysisDate - $lastWrite).TotalDays))
    $recent = $ageDays -le [int]$Policy.visibility_days

    foreach ($boundary in @($Policy.excluded_boundaries)) {
        if ($ItemSourceId -eq [string]$boundary.source_id -and
            (Test-FaRelativePrefix -Path $relative -Prefix ([string]$boundary.relative_prefix))) {
            throw "excluded boundary leaked into structure input: $ItemSourceId/$relative"
        }
    }
    foreach ($critical in @($Policy.critical_paths)) {
        if ($ItemSourceId -eq [string]$critical.source_id -and
            (Test-FaRelativePrefix -Path $relative -Prefix ([string]$critical.relative_prefix))) {
            return New-FaLayoutResult -Category 'critical-local-work' `
                -Disposition 'preserve-in-place' -Confidence 'high' `
                -RuleId ([string]$critical.rule_id) -DestinationRoot $null `
                -DestinationFolder $null -Reasons @([string]$critical.reason)
        }
    }
    foreach ($family in @($Policy.preserve_families)) {
        if ($ItemSourceId -eq [string]$family.source_id -and
            (Test-FaRelativePrefix -Path $relative -Prefix ([string]$family.relative_prefix))) {
            return New-FaLayoutResult -Category 'family-admin' `
                -Disposition 'preserve-in-place' -Confidence 'high' `
                -RuleId ([string]$family.rule_id) `
                -DestinationRoot 'H:\My Drive\FAMILY-ADMIN' `
                -DestinationFolder $null `
                -Reasons @('Google-native family records remain with their owning account; canonical G pointers are separate.')
        }
    }
    if ($relative -match [string]$Policy.credential_name_regex) {
        return New-FaLayoutResult -Category 'credentials-secrets' `
            -Disposition 'secure-quarantine-review' -Confidence 'medium' `
            -RuleId 'credential-name-hint' -DestinationRoot $null `
            -DestinationFolder $null `
            -Reasons @('Credential-like name; content must not be logged or copied to a normal archive.')
    }
    if ([IO.Path]::GetFileName($relative) -like '~$*') {
        return New-FaLayoutResult -Category 'office-lock-file' `
            -Disposition 'delete-candidate' -Confidence 'high' `
            -RuleId 'office-lock-prefix' -DestinationRoot $null `
            -DestinationFolder $null `
            -Reasons @('Microsoft Office lock/owner file; never a canonical document.')
    }

    $generated = -not [string]::IsNullOrWhiteSpace([string]$Item.GeneratedHint)
    if ($generated) {
        $reason = "generated-hint=$($Item.GeneratedHint)"
        if ($ItemSourceId -eq 'c-dev' -or $ItemSourceId -eq 'l-dev') {
            return New-FaLayoutResult -Category 'generated-repository-material' `
                -Disposition 'generated-cleanup-candidate' -Confidence 'high' `
                -RuleId 'generated-inside-repository' -DestinationRoot $null `
                -DestinationFolder $null `
                -Reasons @($reason, 'Project-level rebuild proof required; never delete individual repo duplicates.')
        }
        return New-FaLayoutResult -Category 'generated-or-cache-material' `
            -Disposition 'delete-candidate' -Confidence 'high' `
            -RuleId 'generated-outside-repository' -DestinationRoot $null `
            -DestinationFolder $null -Reasons @($reason, 'Deletion is quarantined until backup and rebuild proof.')
    }

    $isTemporaryDocument = $relative -match [string]$Policy.temporary_document_regex
    $isEvergreenKnowledge = $relative -match [string]$Policy.evergreen_knowledge_regex
    if ($isTemporaryDocument -and -not $isEvergreenKnowledge) {
        $disposition = if ($recent) { 'current-review' } else { 'temporary-family-review' }
        $destinationKey = if ($recent) { 'business_current' } else { 'business_archive' }
        $folder = if ($recent) { '00_INBOX' } else { '05_CANONICAL-OLD-VERSIONS' }
        return New-FaLayoutResult -Category 'temporary-ai-or-planning-document' `
            -Disposition $disposition -Confidence 'medium' `
            -RuleId 'temporary-document-family' `
            -DestinationRoot ([string]$Policy.destinations.$destinationKey) `
            -DestinationFolder $folder `
            -Reasons @('Latest useful family representative is archived; older repeats require semantic family proof before deletion.', "age-days=$ageDays")
    }

    foreach ($rule in @($Policy.rules)) {
        if ($relative -notmatch [string]$rule.path_regex) { continue }
        if ([string]$rule.id -eq 'personal-history-context' -and
            ((@($Policy.image_extensions) -contains $extension) -or
             (@($Policy.video_extensions) -contains $extension) -or
             (@($Policy.audio_extensions) -contains $extension))) {
            continue
        }
        $destinationKey = [string]$rule.destination_key
        $folder = [string]$rule.destination_folder
        $disposition = if ($destinationKey -eq 'personal') { 'personal-authority' } `
            elseif ($destinationKey -eq 'business_archive') { 'archive' } else { 'current' }
        if ([string]$rule.age_policy -eq 'recent' -and -not $recent) {
            $destinationKey = 'business_archive'
            $folder = [string]$rule.archive_folder
            $disposition = 'archive'
        }
        return New-FaLayoutResult -Category ([string]$rule.category) `
            -Disposition $disposition -Confidence 'high' `
            -RuleId ([string]$rule.id) `
            -DestinationRoot ([string]$Policy.destinations.$destinationKey) `
            -DestinationFolder $folder `
            -Reasons @("matched=$($rule.id)", "age-days=$ageDays", "age-policy=$($rule.age_policy)")
    }

    if ($relative -match [string]$Policy.media_noise_regex) {
        return New-FaLayoutResult -Category 'media-noise' -Disposition 'delete-candidate' `
            -Confidence 'medium' -RuleId 'media-noise-name' -DestinationRoot $null `
            -DestinationFolder $null -Reasons @('Screenshot, meme, thumbnail or cache name signal; visual confirmation required.')
    }
    if ($relative -match [string]$Policy.temporary_junk_regex) {
        return New-FaLayoutResult -Category 'temporary-or-failed-output' `
            -Disposition 'delete-candidate' -Confidence 'medium' `
            -RuleId 'temporary-junk-name' -DestinationRoot $null `
            -DestinationFolder $null -Reasons @('Temporary, preview, partial or failed-output name signal; replacement proof required.')
    }
    if (@($Policy.installer_extensions) -contains $extension) {
        return New-FaLayoutResult -Category 'installer-package' -Disposition 'delete-candidate' `
            -Confidence 'medium' -RuleId 'installer-extension' -DestinationRoot $null `
            -DestinationFolder $null -Reasons @("extension=$extension", 'Preserve only unavailable software or sole recoverable packages.')
    }
    if (@($Policy.image_extensions) -contains $extension) {
        return New-FaLayoutResult -Category 'useful-photo-candidate' `
            -Disposition 'content-extra' -Confidence 'medium' -RuleId 'generic-image' `
            -DestinationRoot ([string]$Policy.destinations.content_extra) `
            -DestinationFolder 'PHOTOS' -Reasons @('Visual review must exclude screenshots, memes and caches before movement.')
    }
    if (@($Policy.video_extensions) -contains $extension) {
        return New-FaLayoutResult -Category 'useful-video-candidate' `
            -Disposition 'content-extra' -Confidence 'medium' -RuleId 'generic-video' `
            -DestinationRoot ([string]$Policy.destinations.content_extra) `
            -DestinationFolder 'VIDEO' -Reasons @('Project and channel routing rules take precedence over generic media routing.')
    }
    if (@($Policy.audio_extensions) -contains $extension) {
        if ($ItemSourceId -in @('c-music', 'l-music') -or
            $relative -match '(?i)(^Personal[\\/]|(^|[\\/])(music|1 home & personal[\\/]media)([\\/]|$))') {
            return New-FaLayoutResult -Category 'personal-music-audio' `
                -Disposition 'personal-authority' -Confidence 'high' -RuleId 'personal-music-context' `
                -DestinationRoot ([string]$Policy.destinations.personal) `
                -DestinationFolder '10_PERSONAL-MEDIA' `
                -Reasons @('Personal music routes to G; application caches are caught before this rule.')
        }
        return New-FaLayoutResult -Category 'audio-needs-context' `
            -Disposition 'manual-review' -Confidence 'low' -RuleId 'generic-audio' `
            -DestinationRoot $null -DestinationFolder $null `
            -Reasons @('Audio must split between podcast archive, personal music, business recordings and cache.')
    }
    if ($ItemSourceId -eq 'c-dev' -or $ItemSourceId -eq 'l-dev') {
        return New-FaLayoutResult -Category 'local-source-work' `
            -Disposition 'preserve-in-place' -Confidence 'high' -RuleId 'local-dev-source' `
            -DestinationRoot $null -DestinationFolder $null `
            -Reasons @('Git or source-work disposition is repository-level, never individual-file cleanup.')
    }
    if ($recent) {
        return New-FaLayoutResult -Category 'unclassified-recent' -Disposition 'manual-review' `
            -Confidence 'low' -RuleId 'fallback-recent' `
            -DestinationRoot ([string]$Policy.destinations.business_current) `
            -DestinationFolder '00_INBOX' -Reasons @("age-days=$ageDays", 'Needs content classification before filing.')
    }
    return New-FaLayoutResult -Category 'unclassified-unique-or-unproven' `
        -Disposition 'archive' -Confidence 'low' -RuleId 'fallback-old' `
        -DestinationRoot ([string]$Policy.destinations.business_archive) `
        -DestinationFolder '90_UNCLASSIFIED-UNIQUE' `
        -Reasons @("age-days=$ageDays", 'Old does not mean deletable; preserve until content classification resolves it.')
}

function Invoke-FaLayoutProposal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $WorkspacePath,
        [Parameter(Mandatory)][string] $InventoryPath,
        [Parameter(Mandatory)][string] $ResultPath,
        [Parameter(Mandatory)][string] $RulesPath,
        [string] $DedupePath,
        [string[]] $OnlySourceId,
        [datetimeoffset] $AnalysisDate
    )

    $workspace = Import-FaWorkspace -ConfigPath $WorkspacePath
    $policy = Get-Content -LiteralPath $RulesPath -Raw | ConvertFrom-Json -Depth 64
    if ($policy.schema_version -ne 1) { throw 'estate policy schema_version must be 1' }
    $dupes = Get-FaDuplicateIndex -Path $DedupePath
    $selected = @($workspace.Sources | Where-Object {
        -not $OnlySourceId -or $OnlySourceId.Count -eq 0 -or $OnlySourceId -contains $_.Id
    })
    if ($selected.Count -eq 0) { throw 'no configured sources matched -SourceId' }

    New-Item -ItemType Directory -Path $ResultPath -Force | Out-Null
    $proposalPath = Join-Path $ResultPath 'layout-proposal.jsonl'
    $tempPath = $proposalPath + '.writing'
    $encoding = [Text.UTF8Encoding]::new($false)
    $stream = [IO.FileStream]::new($tempPath, [IO.FileMode]::Create,
        [IO.FileAccess]::Write, [IO.FileShare]::None)
    $writer = [IO.StreamWriter]::new($stream, $encoding)
    $byDisposition = @{}
    $byCategory = @{}
    $byDestination = @{}
    $bySource = @{}
    $manualExamples = [Collections.Generic.List[object]]::new()
    [long]$totalFiles = 0
    [long]$totalBytes = 0
    [long]$exactDuplicateFiles = 0
    try {
        foreach ($source in $selected) {
            $sourceRun = Join-Path $InventoryPath $source.Id
            $segmentsPath = Join-Path $sourceRun 'segments'
            if (-not (Test-Path -LiteralPath $segmentsPath -PathType Container)) { continue }
            foreach ($segmentFile in @(Get-ChildItem -LiteralPath $segmentsPath -Filter 'segment-*.json' -File | Sort-Object Name)) {
                $segment = Get-Content -LiteralPath $segmentFile.FullName -Raw | ConvertFrom-Json -Depth 32
                foreach ($item in @($segment.Items)) {
                    if ($item.Kind -ne 'file') { continue }
                    $classification = Get-FaLayoutClassification -Item $item `
                        -ItemSourceId $source.Id -Policy $policy -AnalysisDate $AnalysisDate
                    $length = [long]$item.Length
                    $key = ('{0}|{1}' -f $source.Id.ToLowerInvariant(),
                        ([string]$item.RelativePath).Replace('/', '\').ToLowerInvariant())
                    $duplicate = if ($dupes.ContainsKey($key)) { $dupes[$key] } else { $null }
                    if ($duplicate) { $exactDuplicateFiles++ }
                    $row = [ordered]@{
                        SchemaVersion = 1
                        SourceId = $source.Id
                        RelativePath = [string]$item.RelativePath
                        Length = $length
                        LastWriteTimeUtc = [string]$item.LastWriteTimeUtc
                        Category = $classification.Category
                        Disposition = $classification.Disposition
                        Confidence = $classification.Confidence
                        RuleId = $classification.RuleId
                        DestinationRoot = $classification.DestinationRoot
                        DestinationFolder = $classification.DestinationFolder
                        ExactDuplicate = [bool]($null -ne $duplicate)
                        DuplicateSha256 = if ($duplicate) { $duplicate.Sha256 } else { $null }
                        DuplicateMemberCount = if ($duplicate) { $duplicate.MemberCount } else { $null }
                        ActionAuthorized = $false
                        BlockedAction = 'Proposal only. Any move or deletion requires a separate frozen manifest and action-time revalidation.'
                        Reasons = @($classification.Reasons)
                    }
                    $writer.WriteLine(($row | ConvertTo-Json -Depth 12 -Compress))
                    $totalFiles++
                    $totalBytes += $length
                    Add-FaAggregate -Map $byDisposition -Key $classification.Disposition -Bytes $length
                    Add-FaAggregate -Map $byCategory -Key $classification.Category -Bytes $length
                    Add-FaAggregate -Map $bySource -Key $source.Id -Bytes $length
                    $destinationName = if ($classification.DestinationRoot) {
                        if ($classification.DestinationFolder) {
                            "$($classification.DestinationRoot)\$($classification.DestinationFolder)"
                        } else { [string]$classification.DestinationRoot }
                    } else { '[none]' }
                    Add-FaAggregate -Map $byDestination -Key $destinationName -Bytes $length
                    if ($manualExamples.Count -lt 100 -and
                        $classification.Disposition -in @('manual-review', 'temporary-family-review', 'secure-quarantine-review')) {
                        $manualExamples.Add([pscustomobject]@{
                            SourceId = $source.Id
                            RelativePath = [string]$item.RelativePath
                            RuleId = $classification.RuleId
                        })
                    }
                }
            }
        }
        $writer.Flush()
        $stream.Flush($true)
    } finally {
        $writer.Dispose()
        $stream.Dispose()
    }
    [IO.File]::Move($tempPath, $proposalPath, $true)
    $summary = [ordered]@{
        SchemaVersion = 1
        PolicyId = [string]$policy.policy_id
        AsOf = $AnalysisDate.ToString('o')
        ProposalPath = $proposalPath
        PolicySha256 = Get-FaSha256 -Path $RulesPath
        DuplicateEvidenceSha256 = if ($DedupePath -and (Test-Path -LiteralPath $DedupePath)) {
            Get-FaSha256 -Path $DedupePath
        } else { $null }
        Sources = @($selected.Id)
        Files = $totalFiles
        Bytes = $totalBytes
        ExactDuplicateFiles = $exactDuplicateFiles
        ByDisposition = Convert-FaAggregate $byDisposition
        ByCategory = Convert-FaAggregate $byCategory
        ByDestination = Convert-FaAggregate $byDestination
        BySource = Convert-FaAggregate $bySource
        ManualReviewExamples = @($manualExamples)
        MutationPerformed = $false
        CreatedAt = [DateTimeOffset]::Now.ToString('o')
    }
    $summaryPath = Join-Path $ResultPath 'layout-summary.json'
    Write-FaAtomicJson -Path $summaryPath -Value $summary -Depth 16
    Write-Host "layout proposal: $proposalPath"
    Write-Host "layout summary: $summaryPath"
    Write-Host ("files={0} bytes={1} exact-duplicate-members={2}" -f
        $totalFiles, $totalBytes, $exactDuplicateFiles)
    return $summary
}

if ($MyInvocation.InvocationName -ne '.') {
    if (-not $ConfigPath) { $ConfigPath = Get-FaDefaultWorkspacePath }
    if (-not $PolicyPath) { $PolicyPath = Join-Path $repo 'policy\estate-policy-v1.json' }
    if (-not $InventoryRoot) {
        if (-not $RunId) { throw '-RunId is required when -InventoryRoot is omitted' }
        $workspaceForDefaults = Import-FaWorkspace -ConfigPath $ConfigPath
        $InventoryRoot = Join-Path $workspaceForDefaults.Audit ("runs\{0}\inventory" -f $RunId)
    }
    if (-not $OutputRoot) {
        if (-not $RunId) { throw '-RunId is required when -OutputRoot is omitted' }
        $workspaceForDefaults = Import-FaWorkspace -ConfigPath $ConfigPath
        $OutputRoot = Join-Path $workspaceForDefaults.Audit ("runs\{0}\structure" -f $RunId)
    }
    if (-not $DuplicateEvidencePath -and $RunId) {
        $workspaceForDefaults = Import-FaWorkspace -ConfigPath $ConfigPath
        $candidate = Join-Path $workspaceForDefaults.Audit ("runs\{0}\dedupe\duplicate-evidence.json" -f $RunId)
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { $DuplicateEvidencePath = $candidate }
    }
    Invoke-FaLayoutProposal -WorkspacePath $ConfigPath -InventoryPath $InventoryRoot `
        -ResultPath $OutputRoot -RulesPath $PolicyPath `
        -DedupePath $DuplicateEvidencePath -OnlySourceId $SourceId -AnalysisDate $AsOf | Out-Null
}

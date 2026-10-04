$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo = Split-Path -Parent $PSScriptRoot
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('filearchives-regex-test-' + [guid]::NewGuid().ToString('n'))
$scope = Join-Path $scratch 'scope'
$photos = Join-Path $scope 'PHOTOS'
$archive = Join-Path $scope 'ARCHIVE'
$quarantine = Join-Path $archive '99_DELETE-QUARANTINE\Media-Noise'
$audit = Join-Path $scratch 'audit'
$config = Join-Path $scratch 'workspace.json'
try {
    New-Item -ItemType Directory -Path $photos,$archive,$audit -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $photos 'Screenshot 1.png'),'noise')
    [IO.File]::WriteAllText((Join-Path $photos 'family.jpg'),'keep')
    $workspace=@{schema_version=2;audit=$audit;sources=@(@{id='fixture';path=$scope;kind='test';follow_reparse_points=$false});protected_roots=@((Join-Path $scratch 'protected'));protected_names=@()}
    [IO.File]::WriteAllText($config,($workspace|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
    $manifest=Join-Path $audit 'manifest.json';$receipt=Join-Path $audit 'receipt.json'
    & (Join-Path $repo 'stages\07_structure\new_path_regex_quarantine_manifest.ps1') -SearchRoot $photos `
        -QuarantineRoot $quarantine -IncludePathRegex '(?i)screenshot' -IncludeExtension @('.png','.jpg') `
        -ManifestPath $manifest -ApprovalReason 'test fixture' -ConfigPath $config
    $frozen=Get-Content $manifest -Raw|ConvertFrom-Json
    if($frozen.MoveCount -ne 1){throw 'expected exactly one regex quarantine move'}
    & (Join-Path $repo 'stages\07_structure\invoke_live_file_move_manifest.ps1') -ManifestPath $manifest -ReceiptPath $receipt -Execute -ConfigPath $config
    if(-not(Test-Path (Join-Path $photos 'family.jpg')) -or (Test-Path (Join-Path $photos 'Screenshot 1.png'))){throw 'regex quarantine moved wrong files'}
    Write-Host 'PASS: path-regex quarantine is scoped and provenance-preserving'
} finally {if(Test-Path $scratch){Remove-Item $scratch -Recurse -Force}}

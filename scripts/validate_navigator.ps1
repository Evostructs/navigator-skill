param(
    [string]$SkillPath = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$failures = [System.Collections.Generic.List[string]]::new()

function Add-Failure([string]$Message) {
    $script:failures.Add($Message)
}

$requiredFiles = @(
    'SKILL.md',
    'agents\openai.yaml',
    'references\evidence-model.md',
    'references\interaction-playbook.md',
    'references\relationship-intent-and-pace.md',
    'references\risk-cost-integrity.md',
    'references\calibration-growth.md',
    'references\inner-navigation.md',
    'evals\cases.jsonl',
    'evals\rubric.md'
)

foreach ($relative in $requiredFiles) {
    $path = Join-Path $SkillPath $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Add-Failure "Missing file: $relative"
    }
}

$skillFile = Join-Path $SkillPath 'SKILL.md'
if (Test-Path -LiteralPath $skillFile) {
    $skillText = Get-Content -LiteralPath $skillFile -Raw -Encoding UTF8
    if ($skillText -notmatch '(?s)^---\s*\r?\n.*?\r?\n---') {
        Add-Failure 'SKILL.md frontmatter is missing or malformed'
    }
    if ($skillText -notmatch '(?m)^name:\s*navigator\s*$') {
        Add-Failure 'SKILL.md name must be navigator'
    }
    if ($skillText -notmatch '(?m)^description:\s*\S+') {
        Add-Failure 'SKILL.md description is missing'
    }

    $linkMatches = [regex]::Matches($skillText, 'references/[A-Za-z0-9._-]+\.md')
    foreach ($match in $linkMatches) {
        $target = Join-Path $SkillPath ($match.Value -replace '/', '\')
        if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
            Add-Failure "Broken reference: $($match.Value)"
        }
    }
}

$yamlFile = Join-Path $SkillPath 'agents\openai.yaml'
if (Test-Path -LiteralPath $yamlFile) {
    $yamlText = Get-Content -LiteralPath $yamlFile -Raw -Encoding UTF8
    if ($yamlText -notmatch [regex]::Escape('$navigator')) {
        Add-Failure 'agents/openai.yaml default prompt must mention $navigator'
    }
}

$casesFile = Join-Path $SkillPath 'evals\cases.jsonl'
$caseCount = 0
$hardGateCount = 0
$ids = [System.Collections.Generic.HashSet[string]]::new()
if (Test-Path -LiteralPath $casesFile) {
    $lineNumber = 0
    foreach ($line in Get-Content -LiteralPath $casesFile -Encoding UTF8) {
        $lineNumber++
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try {
            $case = $line | ConvertFrom-Json
        }
        catch {
            Add-Failure "Invalid JSON at cases.jsonl line $lineNumber"
            continue
        }

        $caseCount++
        foreach ($field in @('id','prompt','required','forbidden','hard_gate','tags')) {
            if ($null -eq $case.$field) {
                Add-Failure "Case line $lineNumber missing field: $field"
            }
        }
        if (-not $ids.Add([string]$case.id)) {
            Add-Failure "Duplicate case id: $($case.id)"
        }
        if (@($case.required).Count -eq 0) {
            Add-Failure "Case $($case.id) has no required invariants"
        }
        if ([bool]$case.hard_gate) { $hardGateCount++ }
    }
}

if ($caseCount -lt 15) {
    Add-Failure "Expected at least 15 eval cases, found $caseCount"
}
if ($hardGateCount -lt 5) {
    Add-Failure "Expected at least 5 hard-gate cases, found $hardGateCount"
}

if ($failures.Count -gt 0) {
    Write-Output 'NAVIGATOR_VALIDATION=FAIL'
    $failures | ForEach-Object { Write-Output "ERROR=$_" }
    exit 1
}

Write-Output 'NAVIGATOR_VALIDATION=PASS'
Write-Output "SkillPath=$SkillPath"
Write-Output "EvalCases=$caseCount"
Write-Output "HardGateCases=$hardGateCount"
Write-Output "RequiredFiles=$($requiredFiles.Count)"

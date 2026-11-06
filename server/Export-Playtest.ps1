param(
    [string]$Event = ""
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$EventsDir = Join-Path $RepoRoot "events"

if ([string]::IsNullOrWhiteSpace($Event)) {
    $latestEvent = Get-ChildItem -Path $EventsDir -Directory | Sort-Object Name -Descending | Select-Object -First 1
    if (-not $latestEvent) {
        Write-Error "No event folders found in $EventsDir"
        exit 1
    }
    $Event = $latestEvent.Name
}

$EventPath = Join-Path $EventsDir $Event
$QuestionsFile = Join-Path $EventPath "questions.json"
$OutCleanFile = Join-Path $EventPath "playtest_questions_only.txt"
$OutKeyFile = Join-Path $EventPath "playtest_with_answers.txt"

if (-not (Test-Path $QuestionsFile)) {
    Write-Error "Could not find questions.json at $QuestionsFile"
    exit 1
}

$data = [System.IO.File]::ReadAllText($QuestionsFile, [System.Text.Encoding]::UTF8) | ConvertFrom-Json

function Format-PlaytestText([bool]$includeAnswers) {
    $sb = New-Object System.Text.StringBuilder
    $null = $sb.AppendLine("============================================================")
    $null = $sb.AppendLine("$($data.title.ToUpper()) - PLAYTEST SHEET" + $(if ($includeAnswers) { " (WITH ANSWERS)" } else { " (QUESTIONS ONLY)" }))
    $null = $sb.AppendLine("============================================================")
    if ($includeAnswers -and $data.formalTheme) {
        $null = $sb.AppendLine("Theme: $($data.formalTheme)")
        $null = $sb.AppendLine("------------------------------------------------------------")
    }
    $null = $sb.AppendLine("")

    foreach ($round in $data.rounds) {
        $null = $sb.AppendLine("############################################################")
        $null = $sb.AppendLine("  $($round.title.ToUpper())")
        if ($round.subtitle) {
            $null = $sb.AppendLine("  $($round.subtitle)")
        }
        $null = $sb.AppendLine("############################################################")
        $null = $sb.AppendLine("")

        foreach ($q in $round.questions) {
            if ($q.sectionIntroTitle) {
                $null = $sb.AppendLine("--- [ $($q.sectionIntroTitle.ToUpper()) ] ---")
                if ($q.sectionIntroDesc) {
                    $null = $sb.AppendLine($q.sectionIntroDesc)
                }
                $null = $sb.AppendLine("")
            }

            $headerParts = @("Q$($q.number)")
            if ($q.category) { $headerParts += $q.category }
            if ($q.answerType) { $headerParts += "Target: $($q.answerType)" }
            $null = $sb.AppendLine(($headerParts -join " | "))

            if ($q.text) {
                $null = $sb.AppendLine($q.text)
            } elseif ($q.clue1 -or $q.clue2) {
                $c = @()
                if ($q.clue1) { $c += $q.clue1 }
                if ($q.clue2) { $c += $q.clue2 }
                $null = $sb.AppendLine(($c -join " "))
            }

            if ($q.steps) {
                $stepNum = 1
                foreach ($s in @($q.steps)) {
                    $null = $sb.AppendLine("  ($stepNum) $s")
                    $stepNum++
                }
            }

            if ($q.releaseYear -or $q.cast) {
                $castStr = (@($q.cast) -join ", ")
                $null = $sb.AppendLine("  Cast: $castStr ($($q.releaseYear))")
            }

            if ($q.tracks) {
                $tracksStr = (@($q.tracks) | ForEach-Object { "`"$_`"" }) -join " / "
                $null = $sb.AppendLine("  Songs: $tracksStr")
            }

            if ($q.puzzleBoard) {
                $null = $sb.AppendLine("  Board: $($q.puzzleBoard)")
            }

            if ($q.questionPrompt) {
                $null = $sb.AppendLine("  Ask: $($q.questionPrompt)")
            }

            if ($includeAnswers) {
                $null = $sb.AppendLine("  --> ANSWER: $($q.answer)")
            } else {
                $null = $sb.AppendLine("  Your Guess: ________________________")
            }

            $null = $sb.AppendLine("")
        }
    }

    return $sb.ToString()
}

$cleanTxt = Format-PlaytestText $false
$keyTxt = Format-PlaytestText $true

[System.IO.File]::WriteAllText($OutCleanFile, $cleanTxt, [System.Text.Encoding]::UTF8)
[System.IO.File]::WriteAllText($OutKeyFile, $keyTxt, [System.Text.Encoding]::UTF8)

Write-Host "Exported playtest files for '$Event':" -ForegroundColor Green
Write-Host "  1. Questions Only : $OutCleanFile" -ForegroundColor Cyan
Write-Host "  2. With Answers   : $OutKeyFile" -ForegroundColor Yellow

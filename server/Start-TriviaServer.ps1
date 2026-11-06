param(
    [string]$Event = "",
    [int]$Port = 8080
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$EventsDir = Join-Path $RepoRoot "events"
$WebDir = Join-Path $RepoRoot "web"

if ([string]::IsNullOrWhiteSpace($Event)) {
    $allEvents = @(Get-ChildItem -Path $EventsDir -Directory | Sort-Object Name -Descending)
    if ($allEvents.Count -eq 0) {
        Write-Error "No event folders found in $EventsDir"
        exit 1
    } elseif ($allEvents.Count -eq 1) {
        $Event = $allEvents[0].Name
    } else {
        Write-Host ""
        Write-Host "Select a Trivia Event to load:" -ForegroundColor Cyan
        for ($i = 0; $i -lt $allEvents.Count; $i++) {
            Write-Host "  [$($i + 1)] $($allEvents[$i].Name)" -ForegroundColor Yellow
        }
        $choice = Read-Host "Enter number (default 1)"
        $idx = 0
        if ($choice -match "^\d+$" -and [int]$choice -ge 1 -and [int]$choice -le $allEvents.Count) {
            $idx = [int]$choice - 1
        }
        $Event = $allEvents[$idx].Name
    }
}

$EventPath = Join-Path $EventsDir $Event
$QuestionsFile = Join-Path $EventPath "questions.json"
$StateFile = Join-Path $EventPath "state.json"
$AssetsDir = Join-Path $EventPath "assets"

if (-not (Test-Path $QuestionsFile)) {
    Write-Error "Could not find questions.json at $QuestionsFile"
    exit 1
}

$LanIp = "localhost"
try {
    $ipObj = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.InterfaceAlias -notmatch "Loopback|vEthernet|WSL" -and $_.IPAddress -notmatch "^169\.254" -and $_.IPAddress -ne "127.0.0.1" } |
        Select-Object -First 1
    if ($ipObj) { $LanIp = $ipObj.IPAddress }
} catch {}

$fwRuleName = "Antigravity Trivia Server (TCP $Port)"
$existingFw = Get-NetFirewallRule -DisplayName $fwRuleName -ErrorAction SilentlyContinue
if (-not $existingFw) {
    $psFw = Get-NetFirewallRule -DisplayName "Windows PowerShell" -ErrorAction SilentlyContinue |
        Where-Object { $_.Enabled -eq "True" -and $_.Direction -eq "Inbound" -and $_.Action -eq "Allow" }
    if (-not $psFw) {
        try {
            $fwCmd = "netsh advfirewall firewall add rule name=`"$fwRuleName`" dir=in action=allow protocol=TCP localport=$Port profile=any"
            Start-Process cmd.exe -ArgumentList "/c $fwCmd" -Verb RunAs -WindowStyle Hidden -Wait
        } catch {}
    }
}

function Get-QuestionsData {
    $raw = [System.IO.File]::ReadAllText($QuestionsFile, [System.Text.Encoding]::UTF8)
    return ($raw | ConvertFrom-Json)
}

function Save-GameState($stateObj) {
    $stateObj.updatedAt = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $json = $stateObj | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($StateFile, $json, [System.Text.Encoding]::UTF8)
}

function New-DefaultGameState {
    return [ordered]@{
        eventId        = $Event
        phase          = "LOBBY"          # LOBBY | ROUND_INTRO | QUESTION_OPEN | SUBMISSIONS_LOCKED | ANSWER_REVEALED | LEADERBOARD
        roundIndex     = 0
        questionIndex  = 0
        clueStep       = 2
        timerEndUtcMs  = 0
        themeRevealed  = $false
        updatedAt      = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        teams          = @()              # @{ id, name, pin, bonusPoints }
        submissions    = @()              # @{ questionId, teamId, answer, wager, poolId, grade, autoMatched, submittedAt }
        themeGuesses   = @()              # @{ id, teamId, teamName, guess, status, bonusPoints, questionNumber, submittedAt }
    }
}

function Clean-LoadedArray($items, [string]$requiredKey) {
    $out = @()
    if ($null -eq $items) { return $out }
    foreach ($it in @($items)) {
        if ($null -ne $it -and $null -ne $it.$requiredKey -and [string]$it.$requiredKey -ne "") {
            $out += $it
        }
    }
    return $out
}

if (Test-Path $StateFile) {
    Write-Host ""
    Write-Host "Found saved game state for '$Event'." -ForegroundColor Yellow
    Write-Host "  [C] Continue saved game"
    Write-Host "  [R] Reset scores/submissions (Keep connected teams)"
    Write-Host "  [N] New clean game (Wipe everything including teams)"
    $mode = Read-Host "Choose [C / R / N] (default C)"
    if ($mode -match "^[Nn]$") {
        $GameState = New-DefaultGameState
        Save-GameState $GameState
    } else {
        try {
            $rawState = [System.IO.File]::ReadAllText($StateFile, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
            $loadedTeams = Clean-LoadedArray $rawState.teams "id"
            if ($mode -match "^[Rr]$") {
                $GameState = New-DefaultGameState
                $GameState.teams = $loadedTeams
                Save-GameState $GameState
            } else {
                $GameState = [ordered]@{
                    eventId       = [string]$rawState.eventId
                    phase         = [string]$rawState.phase
                    roundIndex    = [int]$rawState.roundIndex
                    questionIndex = [int]$rawState.questionIndex
                    clueStep      = if ($null -ne $rawState.clueStep) { [int]$rawState.clueStep } else { 2 }
                    timerEndUtcMs = if ($null -ne $rawState.timerEndUtcMs) { [long]$rawState.timerEndUtcMs } else { 0 }
                    themeRevealed = if ($null -ne $rawState.themeRevealed) { [bool]$rawState.themeRevealed } else { $false }
                    updatedAt     = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
                    teams         = $loadedTeams
                    submissions   = Clean-LoadedArray $rawState.submissions "teamId"
                    themeGuesses  = Clean-LoadedArray $rawState.themeGuesses "id"
                }
            }
        } catch {
            $GameState = New-DefaultGameState
            Save-GameState $GameState
        }
    }
} else {
    $GameState = New-DefaultGameState
    Save-GameState $GameState
}

function Normalize-Answer([string]$str) {
    if ([string]::IsNullOrWhiteSpace($str)) { return "" }
    $clean = $str.ToLowerInvariant().Trim()
    $clean = $clean -replace "^(the|a|an)\s+", ""
    $clean = $clean -replace "[^a-z0-9\s]", ""
    $clean = $clean -replace "\s+", " "
    return $clean.Trim()
}

function Test-AutoGrade($question, [string]$submittedAnswer) {
    $normSub = Normalize-Answer $submittedAnswer
    if ([string]::IsNullOrWhiteSpace($normSub)) { return $false }
    $normPrimary = Normalize-Answer $question.answer
    if ($normSub -eq $normPrimary) { return $true }
    if ($question.acceptedAnswers) {
        foreach ($alt in $question.acceptedAnswers) {
            if ($normSub -eq (Normalize-Answer $alt)) { return $true }
        }
    }
    return $false
}

function Get-TeamRawScore($team, $questionsMap) {
    $score = [int]($team.bonusPoints)
    $correctCount = 0

    foreach ($tg in $GameState.themeGuesses) {
        if ($tg.teamId -eq $team.id -and $tg.status -eq "approved") {
            $score += [int]($tg.bonusPoints)
        }
    }

    foreach ($sub in $GameState.submissions) {
        if ($sub.teamId -eq $team.id) {
            $qObj = $questionsMap[$sub.questionId]
            $qType = if ($qObj -and $qObj.mechanic) { [string]$qObj.mechanic } else { "standard" }
            $basePts = if ($qObj -and $qObj.points) { [int]$qObj.points } else { 4 }
            $wagerVal = if ($null -ne $sub.wager -and [int]$sub.wager -gt 0) { [int]$sub.wager } else { 0 }

            if ($qType -eq "confidence") {
                $pts = if ($wagerVal -gt 0) { $wagerVal } else { $basePts }
                if ($sub.grade -eq "correct") {
                    $score += $pts
                    $correctCount++
                } elseif ($sub.grade -eq "half") {
                    $score += [int][Math]::Round($pts / 2.0)
                }
            } elseif ($qType -eq "jeopardy") {
                if ($sub.grade -eq "correct") {
                    $score += $wagerVal
                    $correctCount++
                } elseif ($sub.grade -eq "wrong" -and -not [string]::IsNullOrWhiteSpace($sub.answer)) {
                    $score -= $wagerVal
                }
            } else {
                if ($sub.grade -eq "correct") {
                    $score += $basePts
                    $correctCount++
                } elseif ($sub.grade -eq "half") {
                    $score += [int][Math]::Round($basePts / 2.0)
                }
            }
        }
    }

    return @{ score = $score; correctCount = $correctCount }
}

function Build-ClientPayload($questionsData, [bool]$isHost) {
    $rounds = @($questionsData.rounds)
    $rIdx = [Math]::Max(0, [Math]::Min($GameState.roundIndex, $rounds.Count - 1))
    $currentRound = if ($rounds.Count -gt 0) { $rounds[$rIdx] } else { $null }
    $questions = if ($currentRound) { @($currentRound.questions) } else { @() }
    $qIdx = [Math]::Max(0, [Math]::Min($GameState.questionIndex, $questions.Count - 1))
    $currentQ = if ($questions.Count -gt 0) { $questions[$qIdx] } else { $null }

    $questionsMap = @{}
    foreach ($r in $rounds) {
        foreach ($q in $r.questions) {
            $questionsMap[$q.id] = $q
        }
    }

    $isPublicTheme = ($GameState.themeRevealed -or $rIdx -ge 1)
    $formalTheme = if ($questionsData.formalTheme) { $questionsData.formalTheme } else { $questionsData.theme }

    $teamRows = @()
    foreach ($t in $GameState.teams) {
        $calc = Get-TeamRawScore $t $questionsMap
        $submittedCurrent = $false
        $currentSubObj = $null

        if ($currentQ) {
            foreach ($sub in $GameState.submissions) {
                if ($sub.teamId -eq $t.id -and $sub.questionId -eq $currentQ.id) {
                    if ($currentQ.mechanic -eq "jeopardy") {
                        # In Jeopardy, check if wager is locked or answer is locked
                        $submittedCurrent = $true
                    } else {
                        $submittedCurrent = $true
                    }
                    $currentSubObj = $sub
                    break
                }
            }
        }

        # Check team's theme status
        $teamApprovedTheme = $GameState.themeGuesses | Where-Object { $_.teamId -eq $t.id -and $_.status -eq "approved" } | Select-Object -First 1

        $row = [ordered]@{
            id               = $t.id
            name             = $t.name
            score            = $calc.score
            bonusPoints      = [int]$t.bonusPoints
            correctCount     = $calc.correctCount
            submittedCurrent = $submittedCurrent
            themeSolved      = ($null -ne $teamApprovedTheme)
        }

        if ($isHost -or $GameState.phase -eq "ANSWER_REVEALED") {
            $row.currentAnswer = if ($currentSubObj) { $currentSubObj.answer } else { "" }
            $row.currentWager  = if ($currentSubObj -and $null -ne $currentSubObj.wager) { $currentSubObj.wager } else { $null }
            $row.currentGrade  = if ($currentSubObj) { $currentSubObj.grade } else { "ungraded" }
        }
        $teamRows += $row
    }

    $leaderboard = @($teamRows | Sort-Object -Property @{Expression="score";Descending=$true}, @{Expression="name";Descending=$false})

    $qView = $null
    if ($currentQ) {
        $showAnswer = ($isHost -or $GameState.phase -eq "ANSWER_REVEALED")
        $qMechanic = if ($currentQ.mechanic) { [string]$currentQ.mechanic } else { "standard" }
        # For Jeopardy, if phase is QUESTION_OPEN and clueStep == 1, only show category & answerType so teams lock in wagers first!
        $hideJeopardyClue = ($qMechanic -eq "jeopardy" -and $GameState.phase -eq "QUESTION_OPEN" -and $GameState.clueStep -lt 2 -and -not $isHost)

        $qView = [ordered]@{
            id                = $currentQ.id
            number            = $currentQ.number
            totalInRound      = $questions.Count
            points            = if ($currentQ.points) { $currentQ.points } else { 4 }
            mechanic          = $qMechanic
            sectionTitle      = $currentQ.sectionTitle
            sectionIntroTitle = $currentQ.sectionIntroTitle
            sectionIntroDesc  = $currentQ.sectionIntroDesc
            poolId            = $currentQ.poolId
            poolCategories    = $currentQ.poolCategories
            poolValues        = $currentQ.poolValues
            category          = $currentQ.category
            answerType        = $currentQ.answerType
            text              = if ($hideJeopardyClue) { $null } else { $currentQ.text }
            puzzleBoard       = if ($hideJeopardyClue) { $null } else { $currentQ.puzzleBoard }
            steps             = if ($hideJeopardyClue) { $null } else { $currentQ.steps }
            cast              = if ($hideJeopardyClue) { $null } else { $currentQ.cast }
            tracks            = if ($hideJeopardyClue) { $null } else { $currentQ.tracks }
            releaseYear       = if ($hideJeopardyClue) { $null } else { $currentQ.releaseYear }
            clue1             = if ($hideJeopardyClue) { $null } else { $currentQ.clue1 }
            clue2             = if ($hideJeopardyClue) { $null } else { $currentQ.clue2 }
            questionPrompt    = if ($hideJeopardyClue) { "Lock in your point wager based on the category above before the question is revealed!" } else { $currentQ.questionPrompt }
            jeopardyWagerPhase = ($qMechanic -eq "jeopardy" -and $GameState.clueStep -lt 2)
            media             = $currentQ.media
            answer            = if ($showAnswer) { $currentQ.answer } else { $null }
            acceptedAnswers   = if ($isHost) { $currentQ.acceptedAnswers } else { $null }
            funFact           = if ($showAnswer) { $currentQ.funFact } else { $null }
        }
    }

    $outline = @()
    if ($isHost) {
        for ($ri = 0; $ri -lt $rounds.Count; $ri++) {
            $r = $rounds[$ri]
            $qList = @()
            for ($qi = 0; $qi -lt $r.questions.Count; $qi++) {
                $qItem = $r.questions[$qi]
                $qList += [ordered]@{
                    index        = $qi
                    id           = $qItem.id
                    number       = $qItem.number
                    mechanic     = if ($qItem.mechanic) { $qItem.mechanic } else { "standard" }
                    sectionTitle = $qItem.sectionTitle
                    category     = $qItem.category
                    answer       = $qItem.answer
                }
            }
            $outline += [ordered]@{
                roundIndex  = $ri
                roundNumber = $r.roundNumber
                title       = $r.title
                questions   = $qList
            }
        }
    }

    return [ordered]@{
        serverTimeUtcMs = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        joinUrl         = "http://$($LanIp):$($Port)"
        event           = [ordered]@{
            eventId       = $questionsData.eventId
            title         = $questionsData.title
            subtitle      = $questionsData.subtitle
            date          = $questionsData.date
            themeRevealed = $isPublicTheme
            formalTheme   = if ($isPublicTheme -or $isHost) { $formalTheme } else { $null }
            themeHint     = $questionsData.themeHint
            rules         = $questionsData.rules
        }
        state           = [ordered]@{
            phase         = $GameState.phase
            roundIndex    = $rIdx
            questionIndex = $qIdx
            clueStep      = $GameState.clueStep
            timerEndUtcMs = $GameState.timerEndUtcMs
            themeRevealed = $isPublicTheme
            updatedAt     = $GameState.updatedAt
        }
        round           = if ($currentRound) {
            [ordered]@{
                roundNumber   = $currentRound.roundNumber
                totalRounds   = $rounds.Count
                title         = $currentRound.title
                subtitle      = $currentRound.subtitle
                questionCount = $questions.Count
            }
        } else { $null }
        question        = $qView
        leaderboard     = $leaderboard
        themeGuesses    = if ($isHost) { @($GameState.themeGuesses) } else { $null }
        outline         = if ($isHost) { $outline } else { $null }
    }
}

$MimeTypes = @{
    ".html" = "text/html; charset=utf-8"
    ".css"  = "text/css; charset=utf-8"
    ".js"   = "application/javascript; charset=utf-8"
    ".json" = "application/json; charset=utf-8"
    ".png"  = "image/png"
    ".jpg"  = "image/jpeg"
    ".jpeg" = "image/jpeg"
    ".gif"  = "image/gif"
    ".svg"  = "image/svg+xml"
}

function Send-TcpResponse($stream, [int]$statusCode, [string]$statusText, [string]$contentType, [byte[]]$bodyBytes) {
    $header = "HTTP/1.1 $statusCode $statusText`r`n" +
              "Content-Type: $contentType`r`n" +
              "Content-Length: $($bodyBytes.Length)`r`n" +
              "Cache-Control: no-store, no-cache`r`n" +
              "Access-Control-Allow-Origin: *`r`n" +
              "Connection: close`r`n`r`n"
    $headerBytes = [System.Text.Encoding]::ASCII.GetBytes($header)
    $stream.Write($headerBytes, 0, $headerBytes.Length)
    if ($bodyBytes.Length -gt 0) {
        $stream.Write($bodyBytes, 0, $bodyBytes.Length)
    }
    $stream.Flush()
}

function Send-TcpJson($stream, $obj, [int]$statusCode = 200) {
    $statusText = if ($statusCode -eq 200) { "OK" } elseif ($statusCode -eq 400) { "Bad Request" } elseif ($statusCode -eq 403) { "Forbidden" } else { "Error" }
    $json = $obj | ConvertTo-Json -Depth 10 -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    Send-TcpResponse $stream $statusCode $statusText "application/json; charset=utf-8" $bytes
}

function Parse-QueryString([string]$query) {
    $result = @{}
    if ([string]::IsNullOrWhiteSpace($query)) { return $result }
    $q = $query.TrimStart('?')
    foreach ($pair in ($q -split '&')) {
        if ([string]::IsNullOrWhiteSpace($pair)) { continue }
        $kv = $pair -split '=', 2
        $k = [System.Uri]::UnescapeDataString($kv[0])
        $v = if ($kv.Length -gt 1) { [System.Uri]::UnescapeDataString($kv[1]) } else { "" }
        $result[$k] = $v
    }
    return $result
}

$TcpListener = [System.Net.Sockets.TcpListener]::Create($Port)
$TcpListener.Start()

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  ANTIGRAVITY LIVE TRIVIA SERVER RUNNING (Wi-Fi Ready!)" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  Active Event  : $Event" -ForegroundColor Yellow
Write-Host "  Projector Deck: http://localhost:$Port/deck.html" -ForegroundColor White
Write-Host "  Host Console  : http://localhost:$Port/host.html" -ForegroundColor White
Write-Host "  Player Phones : http://$($LanIp):$Port/" -ForegroundColor Magenta
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

try {
    Start-Process "http://localhost:$Port/deck.html"
    Start-Sleep -Milliseconds 250
    Start-Process "http://localhost:$Port/host.html"
} catch {}

try {
    while ($true) {
        $client = $TcpListener.AcceptTcpClient()
        try {
            $client.ReceiveTimeout = 1000
            $client.SendTimeout = 2000
            $stream = $client.GetStream()

            $waitCycles = 0
            while (-not $stream.DataAvailable -and $waitCycles -lt 30) {
                Start-Sleep -Milliseconds 5
                $waitCycles++
            }
            if (-not $stream.DataAvailable) {
                $client.Close()
                continue
            }

            $buffer = New-Object byte[] 65536
            $ms = New-Object System.IO.MemoryStream
            $totalRead = 0

            while ($true) {
                $read = $stream.Read($buffer, 0, $buffer.Length)
                if ($read -le 0) { break }
                $ms.Write($buffer, 0, $read)
                $totalRead += $read

                $currentBytes = $ms.ToArray()
                $asciiSoFar = [System.Text.Encoding]::ASCII.GetString($currentBytes)
                $headerEndIndex = $asciiSoFar.IndexOf("`r`n`r`n")
                if ($headerEndIndex -ge 0) {
                    $headerPart = $asciiSoFar.Substring(0, $headerEndIndex)
                    $contentLength = 0
                    if ($headerPart -match "(?im)^Content-Length:\s*(\d+)") {
                        $contentLength = [int]$Matches[1]
                    }
                    $headerByteCount = [System.Text.Encoding]::ASCII.GetByteCount($headerPart) + 4
                    while (($ms.Length - $headerByteCount) -lt $contentLength) {
                        $more = $stream.Read($buffer, 0, $buffer.Length)
                        if ($more -le 0) { break }
                        $ms.Write($buffer, 0, $more)
                    }
                    break
                }
                if ($totalRead -ge 65536) { break }
            }

            $allBytes = $ms.ToArray()
            if ($allBytes.Length -eq 0) {
                $client.Close()
                continue
            }

            $rawReq = [System.Text.Encoding]::UTF8.GetString($allBytes)
            $splitIdx = $rawReq.IndexOf("`r`n`r`n")
            $headerBlock = if ($splitIdx -ge 0) { $rawReq.Substring(0, $splitIdx) } else { $rawReq }
            $bodyText = if ($splitIdx -ge 0) { $rawReq.Substring($splitIdx + 4) } else { "" }

            $lines = $headerBlock -split "`r`n"
            $reqLine = $lines[0] -split " "
            if ($reqLine.Length -lt 2) {
                $client.Close()
                continue
            }

            $method = $reqLine[0].ToUpperInvariant()
            $rawUrl = $reqLine[1]
            $urlParts = $rawUrl -split '\?', 2
            $path = $urlParts[0]
            $queryParams = if ($urlParts.Length -gt 1) { Parse-QueryString $urlParts[1] } else { @{} }

            if ($path -eq "/api/state" -and $method -eq "GET") {
                $isHost = ($queryParams["role"] -eq "host")
                $qData = Get-QuestionsData
                $payload = Build-ClientPayload $qData $isHost

                $teamId = $queryParams["teamId"]
                if (-not [string]::IsNullOrWhiteSpace($teamId)) {
                    if ($payload.question) {
                        $qId = $payload.question.id
                        $mySub = $GameState.submissions | Where-Object { $_.teamId -eq $teamId -and $_.questionId -eq $qId } | Select-Object -First 1
                        $payload["mySubmission"] = if ($mySub) {
                            [ordered]@{
                                answer = $mySub.answer
                                wager  = $mySub.wager
                                grade  = if ($GameState.phase -eq "ANSWER_REVEALED") { $mySub.grade } else { "pending" }
                            }
                        } else { $null }

                        # If Confidence question, return which wagers this team has already used in this poolId
                        if ($payload.question.mechanic -eq "confidence" -and $payload.question.poolId) {
                            $targetPool = $payload.question.poolId
                            $usedWagers = @()
                            foreach ($s in $GameState.submissions) {
                                if ($s.teamId -eq $teamId -and $s.poolId -eq $targetPool -and $s.questionId -ne $qId -and $null -ne $s.wager) {
                                    $usedWagers += [int]$s.wager
                                }
                            }
                            $payload["usedPoolWagers"] = $usedWagers
                        }
                    }

                    # Return this team's theme guesses
                    $myThemeGuesses = @($GameState.themeGuesses | Where-Object { $_.teamId -eq $teamId })
                    $approvedGuess = $myThemeGuesses | Where-Object { $_.status -eq "approved" } | Select-Object -First 1
                    $formalTheme = if ($qData.formalTheme) { $qData.formalTheme } else { $qData.theme }
                    $payload["myThemeStatus"] = [ordered]@{
                        guesses     = $myThemeGuesses
                        approved    = ($null -ne $approvedGuess)
                        formalTheme = if ($null -ne $approvedGuess -or $payload.event.themeRevealed) { $formalTheme } else { $null }
                    }
                }

                Send-TcpJson $stream $payload 200
                $client.Close()
                continue
            }

            if ($path -eq "/api/join" -and $method -eq "POST") {
                $body = $bodyText | ConvertFrom-Json
                $teamName = ([string]$body.teamName).Trim()
                $pin = ([string]$body.pin).Trim()
                if ([string]::IsNullOrWhiteSpace($teamName)) {
                    Send-TcpJson $stream @{ error = "Team name is required." } 400
                    $client.Close()
                    continue
                }
                if ([string]::IsNullOrWhiteSpace($pin)) { $pin = "0000" }

                $teamId = ($teamName.ToLowerInvariant() -replace "[^a-z0-9]", "-")
                if ([string]::IsNullOrWhiteSpace($teamId)) { $teamId = "team-" + [Guid]::NewGuid().ToString().Substring(0,6) }

                $existing = $GameState.teams | Where-Object { $_.id -eq $teamId } | Select-Object -First 1
                if ($existing) {
                    if ($existing.pin -ne $pin) {
                        Send-TcpJson $stream @{ error = "That team name is locked with a different PIN. Enter the same PIN to reconnect." } 403
                        $client.Close()
                        continue
                    }
                    Send-TcpJson $stream @{ ok = $true; team = $existing; reconnected = $true } 200
                    $client.Close()
                    continue
                }

                $newTeam = [ordered]@{
                    id          = $teamId
                    name        = $teamName
                    pin         = $pin
                    bonusPoints = 0
                }
                $GameState.teams += $newTeam
                Save-GameState $GameState
                Send-TcpJson $stream @{ ok = $true; team = $newTeam; reconnected = $false } 200
                $client.Close()
                continue
            }

            if ($path -eq "/api/submit" -and $method -eq "POST") {
                $body = $bodyText | ConvertFrom-Json
                $teamId = [string]$body.teamId
                $answer = if ($null -ne $body.answer) { ([string]$body.answer).Trim() } else { "" }
                $hasWager = ($null -ne $body.wager -and [string]$body.wager -ne "")
                $wager = if ($hasWager) { [int]$body.wager } else { $null }

                if ($GameState.phase -ne "QUESTION_OPEN") {
                    Send-TcpJson $stream @{ error = "Submissions are closed for this question." } 400
                    $client.Close()
                    continue
                }

                $qData = Get-QuestionsData
                $curRound = $qData.rounds[$GameState.roundIndex]
                $curQ = $curRound.questions[$GameState.questionIndex]
                $qMechanic = if ($curQ.mechanic) { [string]$curQ.mechanic } else { "standard" }

                # Validate Confidence pool wagers
                if ($qMechanic -eq "confidence" -and $curQ.poolId) {
                    if ($null -eq $wager) {
                        Send-TcpJson $stream @{ error = "Please select a confidence point value (8, 6, 4, or 2)." } 400
                        $client.Close()
                        continue
                    }
                    foreach ($s in $GameState.submissions) {
                        if ($s.teamId -eq $teamId -and $s.poolId -eq $curQ.poolId -and $s.questionId -ne $curQ.id -and [int]$s.wager -eq $wager) {
                            Send-TcpJson $stream @{ error = "You already used the $wager-point value in this Confidence set! Pick an available value." } 400
                            $client.Close()
                            continue
                        }
                    }
                }

                $autoMatch = Test-AutoGrade $curQ $answer
                $defaultGrade = if ($autoMatch) { "correct" } else { "wrong" }

                $updated = $false
                for ($i = 0; $i -lt $GameState.submissions.Count; $i++) {
                    if ($GameState.submissions[$i].teamId -eq $teamId -and $GameState.submissions[$i].questionId -eq $curQ.id) {
                        if (-not [string]::IsNullOrWhiteSpace($answer) -or $qMechanic -ne "jeopardy" -or $GameState.clueStep -ge 2) {
                            $GameState.submissions[$i].answer = $answer
                            $GameState.submissions[$i].grade = $defaultGrade
                            $GameState.submissions[$i].autoMatched = $autoMatch
                        }
                        if ($null -ne $wager) {
                            $GameState.submissions[$i].wager = $wager
                        }
                        $GameState.submissions[$i].submittedAt = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
                        $updated = $true
                        break
                    }
                }

                if (-not $updated) {
                    $GameState.submissions += [ordered]@{
                        questionId  = $curQ.id
                        poolId      = $curQ.poolId
                        teamId      = $teamId
                        answer      = $answer
                        wager       = $wager
                        grade       = $defaultGrade
                        autoMatched = $autoMatch
                        submittedAt = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
                    }
                }

                Save-GameState $GameState
                Send-TcpJson $stream @{ ok = $true; answer = $answer; wager = $wager } 200
                $client.Close()
                continue
            }

            if ($path -eq "/api/theme-guess" -and $method -eq "POST") {
                $body = $bodyText | ConvertFrom-Json
                $teamId = [string]$body.teamId
                $guessText = ([string]$body.guess).Trim()

                if ([string]::IsNullOrWhiteSpace($guessText)) {
                    Send-TcpJson $stream @{ error = "Enter a theme guess first." } 400
                    $client.Close()
                    continue
                }

                $teamObj = $GameState.teams | Where-Object { $_.id -eq $teamId } | Select-Object -First 1
                $teamName = if ($teamObj) { $teamObj.name } else { $teamId }

                $qData = Get-QuestionsData
                $curRound = $qData.rounds[$GameState.roundIndex]
                $curQ = if ($curRound -and $curRound.questions.Count -gt $GameState.questionIndex) { $curRound.questions[$GameState.questionIndex] } else { $null }
                $qNum = if ($curQ) { $curQ.number } else { 1 }

                $newGuess = [ordered]@{
                    id             = "tg-" + [Guid]::NewGuid().ToString().Substring(0, 8)
                    teamId         = $teamId
                    teamName       = $teamName
                    guess          = $guessText
                    status         = "pending" # pending | approved | rejected
                    bonusPoints    = 0
                    questionNumber = $qNum
                    submittedAt    = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
                }
                $GameState.themeGuesses += $newGuess
                Save-GameState $GameState
                Send-TcpJson $stream @{ ok = $true; guess = $newGuess } 200
                $client.Close()
                continue
            }

            if ($path -eq "/api/host/action" -and $method -eq "POST") {
                $body = $bodyText | ConvertFrom-Json
                $action = [string]$body.action
                $qData = Get-QuestionsData
                $rounds = @($qData.rounds)

                switch ($action) {
                    "set_phase" {
                        $GameState.phase = [string]$body.phase
                        if ($GameState.phase -ne "QUESTION_OPEN") {
                            $GameState.timerEndUtcMs = 0
                        }
                    }
                    "set_clue_step" {
                        $GameState.clueStep = [int]$body.clueStep
                    }
                    "reveal_theme" {
                        $GameState.themeRevealed = [bool]$body.revealed
                    }
                    "review_theme_guess" {
                        $guessId = [string]$body.guessId
                        $status = [string]$body.status # approved | rejected
                        $bonus = if ($null -ne $body.bonusPoints) { [int]$body.bonusPoints } else { 5 }
                        for ($i = 0; $i -lt $GameState.themeGuesses.Count; $i++) {
                            if ($GameState.themeGuesses[$i].id -eq $guessId) {
                                $GameState.themeGuesses[$i].status = $status
                                $GameState.themeGuesses[$i].bonusPoints = if ($status -eq "approved") { $bonus } else { 0 }
                                break
                            }
                        }
                    }
                    "start_timer" {
                        $seconds = if ($body.seconds) { [int]$body.seconds } else { 45 }
                        $GameState.timerEndUtcMs = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() + ($seconds * 1000)
                    }
                    "stop_timer" {
                        $GameState.timerEndUtcMs = 0
                    }
                    "jump" {
                        $rIdx = [int]$body.roundIndex
                        $qIdx = [int]$body.questionIndex
                        $GameState.roundIndex = $rIdx
                        $GameState.questionIndex = $qIdx
                        $targetQ = $rounds[$rIdx].questions[$qIdx]
                        $isJeopardy = ($targetQ.mechanic -eq "jeopardy")
                        $defaultPhase = if ($targetQ.sectionIntroTitle) { "SECTION_INTRO" } else { "QUESTION_OPEN" }
                        $GameState.phase = if ($body.phase) { [string]$body.phase } else { $defaultPhase }
                        $GameState.clueStep = if ($body.clueStep) { [int]$body.clueStep } elseif ($isJeopardy) { 1 } else { 2 }
                        $GameState.timerEndUtcMs = 0
                    }
                    "next_step" {
                        $curRound = $rounds[$GameState.roundIndex]
                        $qCount = $curRound.questions.Count
                        $curQ = $curRound.questions[$GameState.questionIndex]

                        if ($GameState.phase -eq "LOBBY") {
                            $GameState.phase = "ROUND_INTRO"
                        } elseif ($GameState.phase -eq "ROUND_INTRO") {
                            $GameState.questionIndex = 0
                            $firstQ = $curRound.questions[0]
                            $GameState.clueStep = if ($firstQ.mechanic -eq "jeopardy") { 1 } else { 2 }
                            $GameState.phase = if ($firstQ.sectionIntroTitle) { "SECTION_INTRO" } else { "QUESTION_OPEN" }
                        } elseif ($GameState.phase -eq "SECTION_INTRO") {
                            $GameState.clueStep = if ($curQ.mechanic -eq "jeopardy") { 1 } else { 2 }
                            $GameState.phase = "QUESTION_OPEN"
                        } elseif ($GameState.phase -eq "QUESTION_OPEN") {
                            if ($GameState.clueStep -lt 2) {
                                $GameState.clueStep = 2
                            } else {
                                $GameState.phase = "SUBMISSIONS_LOCKED"
                                $GameState.timerEndUtcMs = 0
                            }
                        } elseif ($GameState.phase -eq "SUBMISSIONS_LOCKED") {
                            $GameState.phase = "ANSWER_REVEALED"
                            $GameState.timerEndUtcMs = 0
                        } elseif ($GameState.phase -eq "ANSWER_REVEALED") {
                            if ($GameState.questionIndex + 1 -lt $qCount) {
                                $GameState.questionIndex++
                                $nextQ = $curRound.questions[$GameState.questionIndex]
                                $GameState.clueStep = if ($nextQ.mechanic -eq "jeopardy") { 1 } else { 2 }
                                $GameState.phase = if ($nextQ.sectionIntroTitle) { "SECTION_INTRO" } else { "QUESTION_OPEN" }
                            } else {
                                if ($GameState.roundIndex -eq 0) {
                                    $GameState.themeRevealed = $true
                                }
                                $GameState.phase = "LEADERBOARD"
                            }
                        } elseif ($GameState.phase -eq "LEADERBOARD") {
                            if ($GameState.roundIndex + 1 -lt $rounds.Count) {
                                $GameState.roundIndex++
                                $GameState.questionIndex = 0
                                $GameState.themeRevealed = $true
                                $GameState.phase = "ROUND_INTRO"
                            }
                        }
                    }
                    "prev_step" {
                        $curRound = $rounds[$GameState.roundIndex]
                        $curQ = $curRound.questions[$GameState.questionIndex]

                        if ($GameState.phase -eq "ANSWER_REVEALED") {
                            $GameState.phase = "SUBMISSIONS_LOCKED"
                        } elseif ($GameState.phase -eq "SUBMISSIONS_LOCKED") {
                            $GameState.phase = "QUESTION_OPEN"
                        } elseif ($GameState.phase -eq "QUESTION_OPEN") {
                            if ($curQ -and $curQ.sectionIntroTitle) {
                                $GameState.phase = "SECTION_INTRO"
                            } elseif ($GameState.questionIndex -gt 0) {
                                $GameState.questionIndex--
                                $GameState.phase = "ANSWER_REVEALED"
                            } else {
                                $GameState.phase = "ROUND_INTRO"
                            }
                        } elseif ($GameState.phase -eq "SECTION_INTRO") {
                            if ($GameState.questionIndex -gt 0) {
                                $GameState.questionIndex--
                                $GameState.phase = "ANSWER_REVEALED"
                            } else {
                                $GameState.phase = "ROUND_INTRO"
                            }
                        } elseif ($GameState.phase -eq "ROUND_INTRO") {
                            if ($GameState.roundIndex -gt 0) {
                                $GameState.roundIndex--
                                $GameState.phase = "LEADERBOARD"
                            } else {
                                $GameState.phase = "LOBBY"
                            }
                        } elseif ($GameState.phase -eq "LEADERBOARD") {
                            $GameState.questionIndex = $curRound.questions.Count - 1
                            $GameState.phase = "ANSWER_REVEALED"
                        }
                    }
                    "grade" {
                        $qId = [string]$body.questionId
                        $tId = [string]$body.teamId
                        $grade = [string]$body.grade
                        $found = $false
                        for ($i = 0; $i -lt $GameState.submissions.Count; $i++) {
                            if ($GameState.submissions[$i].questionId -eq $qId -and $GameState.submissions[$i].teamId -eq $tId) {
                                $GameState.submissions[$i].grade = $grade
                                $found = $true
                                break
                            }
                        }
                        if (-not $found) {
                            $GameState.submissions += [ordered]@{
                                questionId  = $qId
                                teamId      = $tId
                                answer      = "(Host Override)"
                                wager       = $null
                                grade       = $grade
                                autoMatched = $false
                                submittedAt = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
                            }
                        }
                    }
                    "adjust_bonus" {
                        $tId = [string]$body.teamId
                        $delta = [int]$body.delta
                        for ($i = 0; $i -lt $GameState.teams.Count; $i++) {
                            if ($GameState.teams[$i].id -eq $tId) {
                                $GameState.teams[$i].bonusPoints = [int]$GameState.teams[$i].bonusPoints + $delta
                                break
                            }
                        }
                    }
                    "reset_game" {
                        $keepTeams = [bool]$body.keepTeams
                        $existingTeams = if ($keepTeams) { $GameState.teams } else { @() }
                        $GameState = New-DefaultGameState
                        $GameState.teams = $existingTeams
                    }
                }

                Save-GameState $GameState
                $payload = Build-ClientPayload $qData $true
                Send-TcpJson $stream $payload 200
                $client.Close()
                continue
            }

            $relPath = if ($path -eq "/") { "/play.html" } else { $path }
            $targetFile = $null

            if ($relPath.StartsWith("/assets/")) {
                $assetName = [System.Uri]::UnescapeDataString($relPath.Substring(8))
                $candidate = Join-Path $AssetsDir $assetName
                if (Test-Path $candidate -PathType Leaf) { $targetFile = $candidate }
            } else {
                $cleanRel = [System.Uri]::UnescapeDataString($relPath.TrimStart("/")).Replace("/", "\")
                $candidate = Join-Path $WebDir $cleanRel
                if (Test-Path $candidate -PathType Leaf) { $targetFile = $candidate }
            }

            if ($targetFile) {
                $ext = [System.IO.Path]::GetExtension($targetFile).ToLowerInvariant()
                $mime = if ($MimeTypes.ContainsKey($ext)) { $MimeTypes[$ext] } else { "application/octet-stream" }
                $bytes = [System.IO.File]::ReadAllBytes($targetFile)
                Send-TcpResponse $stream 200 "OK" $mime $bytes
            } else {
                $notFoundBytes = [System.Text.Encoding]::UTF8.GetBytes("404 Not Found")
                Send-TcpResponse $stream 404 "Not Found" "text/plain; charset=utf-8" $notFoundBytes
            }
            $client.Close()
        } catch {
            try { $client.Close() } catch {}
        }
    }
} finally {
    $TcpListener.Stop()
}

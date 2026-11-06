# Monthly Trivia Workflow & Host Guide

This repository contains a reusable **Live Trivia Engine & Slide Deck System** plus individual folders for each monthly trivia event.

---

## Folder Structure

```text
Trivia/
├── Start-Trivia.bat                  # Double-click to launch the live server & slides
├── docs/
│   ├── TRIVIA_GUIDELINES.md          # Question design heuristics & 2-5-2-1 calibration rules
│   ├── MONTHLY_WORKFLOW.md           # This guide: how to create & host a new monthly trivia
│   └── THEME_BANK.md                 # Backlog of theme ideas, mechanics, and spare questions
├── server/
│   └── Start-TriviaServer.ps1        # Zero-dependency local HTTP + API server for phones & projector
├── web/
│   ├── deck.html                     # Projector Slide Deck (Keyboard controlled + live status)
│   ├── host.html                     # Host Controller & Instant Grading Console
│   ├── play.html                     # Mobile Player App (Team session lock-in + answer submission)
│   ├── styles.css                    # Shared styling for projector and mobile interfaces
│   └── app.js                        # Shared client helpers
├── templates/
│   └── event-template/               # Copy this folder when starting a new month
│       ├── questions.json            # Structured questions, clues, answers, and calibration metadata
│       ├── worksheet.md              # Drafting & playtesting scratchpad with 2-5-2-1 checklists
│       └── assets/                   # Images or audio for visual rounds
└── events/
    └── 2026-10-13_tuesday-trivia/    # This Tuesday's active trivia event!
        ├── questions.json
        ├── worksheet.md
        ├── state.json                # Auto-generated live scores & team sessions (crash-safe)
        └── assets/
```

---

## How to Create a New Monthly Trivia

1. **Duplicate the Template:**
   Copy `templates/event-template` into `events/YYYY-MM-DD_theme-name/`.
2. **Draft & Calibrate in `worksheet.md`:**
   Ask Antigravity to brainstorm rounds and questions using `docs/TRIVIA_GUIDELINES.md`.
   Verify that every 10-question round follows the **2–5–2–1 curve** (2 Layups, 5 Sweet Spot, 2 Stretches, 1 Separator) and rotates sub-genres.
3. **Compile to `questions.json`:**
   Have Antigravity populate `events/YYYY-MM-DD_theme-name/questions.json`. The slide deck and phone app read directly from this file—no manual slide building required!
4. **Launch & Host:**
   Run `Start-Trivia.bat` (or run `.\server\Start-TriviaServer.ps1 -Event "YYYY-MM-DD_theme-name"`).

---

## Hosting Game Flow (Immediate Reveal Mode)

1. **Lobby Phase:**
   * Open the **Projector View** (`http://localhost:8080/deck.html`) on the TV/projector. It displays the Wi-Fi join URL and QR code.
   * Players open `http://<YOUR-LAN-IP>:8080` on their phones and enter their **Team Name** (plus a 4-digit team PIN/session token so if their phone locks or disconnects, they reconnect right back into their team).
2. **Question Phase (`QUESTION_OPEN`):**
   * Advance to a question using the **Host View** (`http://localhost:8080/host.html`) or keyboard arrows on the deck.
   * The projector shows the Question, Category, Tier badge, and Answer Type pin (e.g., *"Name the Country"*).
   * Players' phones automatically unlock an input box for that question. As teams submit, the projector shows a live badge of which teams are locked in (without showing their answers!).
3. **Lock & Grade Phase (`SUBMISSIONS_LOCKED`):**
   * Once all teams are in (or the timer hits 0), lock submissions.
   * On your **Host View** (on your laptop or phone), you see every team's submitted answer side-by-side with the correct answer. Auto-matching highlights exact/close matches in green, and you can tap to toggle ✅ Correct, ½ Partial, or ❌ Incorrect in 2 seconds.
4. **Immediate Answer Reveal (`ANSWER_REVEALED`):**
   * Press **Space** or **Reveal Answer**.
   * The projector flips to the Answer Card, shows the "Why / Fun Fact" deduction breakdown, and displays which teams got it right (+ points)!
5. **Round Leaderboard (`LEADERBOARD`):**
   * At the end of each round, switch to the Leaderboard slide to celebrate standings before starting the next round.

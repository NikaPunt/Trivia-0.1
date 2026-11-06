# Trivia Design Guidelines & Rules (`antigravity`)

Target audience: **Informed casuals** (sharper than the average person, not dedicated trivia sharks).
Game Flow: **Immediate Reveal via Live Phone Submission** (Teams lock in answers on their phones per question; host reveals the answer immediately after submissions close).

---

## 1. Question Construction Rules

* **Famous Answer, Lateral Clue:** Aim for answers that ~80% of players recognize once revealed, paired with a clue that requires connecting two concepts. Never pair an obscure clue with an obscure answer.
* **Deduction Over Recall:** Avoid binary "know it or don't" trivia. Give players puzzle pieces (etymology, physical mechanisms, historical context) so they can talk it through and deduce the answer.
* **The Pinning Rule (2 Clues per Prompt):** Open with a harder, clever clue for the enthusiasts, and close with a broader context clue so casual players still have an angle to guess.
* **No Raw Dates or Numbers:** Only ask for numbers if they can be logically estimated or triangulated via adjacent events.

---

## 2. Round Calibration (55%–65% Target Solve Rate)

Structure a standard 10-question round using the **2–5–2–1 curve**:

| Tier | Count | Target Solve Rate | Formula |
| :--- | :---: | :---: | :--- |
| **Layups** | 2 | 85%+ | Famous answer + direct 1-hop clue. Keeps every team off zero. |
| **Sweet Spot** | 5 | 50%–70% | Famous answer + 2-hop deduction, or niche answer + generous context. |
| **Stretches** | 2 | 30%–45% | Rewards domain fans of the specific theme. |
| **Separator** | 1 | 15%–25% | Prevents ties. Use multi-part answers or "closest without going over." |

**Playtest Litmus Test:** When a tester misses a question and hears the answer, you want *"Oh, I should have gotten that"* (keep), never *"Never heard of it"* (cut or invert the prompt/answer).

---

## 3. Pacing & Player Engagement (Adapted for Immediate Reveal)

* **Eliminate Dead Air:** Every question needs a "chewable" constraint that shrinks the search space (e.g., *"One of the four landlocked states starting with M..."*) to spark table debate while the timer runs.
* **Hidden Connection Rounds (Immediate-Reveal Adaptation):**
  * Link answers 1–4 around a secret theme. Since answers are revealed right after each question, **do not announce that it is a Hidden Connection round up front**, OR reveal Question 5 (*"What connects the first four answers?"*) as a speed/bonus synthesis question right after Q4's answer is revealed!
  * *Alternative Progressive Mode:* Teams submit a guess for the "Hidden Connection" alongside Q1–Q4 for diminishing bonus points (4 pts after Q1, 3 pts after Q2, 2 pts after Q3, 1 pt after Q4).
* **Format Variety:** Break up standard Q&A by round 3 with *Before & After* wordplay, visual media on the slide/phone, or chronological ordering puzzles.
* **Hard Cap:** 40–50 questions total (4–5 rounds), 60–90 minutes max. Show the full leaderboard slide after every round.

---

## 4. Quality Control Checklist

Before finalizing any event's `questions.json` deck, verify every question against this checklist:

- [ ] **Pin the Answer Type:** Explicitly state whether you want a city, state, country, person, or year (`answerType` badge on slide & phone) to avoid grading disputes.
- [ ] **2-Clue Structure:** Does the prompt have both an enthusiast angle (Clue 1) and an accessible foothold (Clue 2)?
- [ ] **Audit for Cross-Spoilers:** Read the full game top-to-bottom to ensure Question 4's setup doesn't accidentally name the answer to Question 19.
- [ ] **Rotate Sub-Genres:** Within any single theme, force variety across history, science, geography, food/drink, and pop culture (`category` tag).
- [ ] **Write for the Ear:** Read every prompt aloud. Strip out nested clauses, avoid homophones, and place the core question word (*"Which country..."*, *"What film..."*) at the very start or very end.
- [ ] **Accepted Aliases:** List common acceptable spelling variations or last-name-only answers in `acceptedAnswers` so the host grading view can auto-suggest grades accurately.

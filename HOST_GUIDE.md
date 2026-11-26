# Host guide: running the Bob Quiz Challenge (UKI QUALICON-26)

Everything the host and co-host need, in the order you will need it. No secrets are stored in this repo.
The host code and the Supabase keys are shared privately and never written here.

## 1. Links

| Who | Link |
|---|---|
| Participants | https://uki-qualicon-26.github.io/quiz/ |
| Big screen (projector) | https://uki-qualicon-26.github.io/quiz/presenter.html |
| Host test mode (hosts only) | https://uki-qualicon-26.github.io/quiz/?host=1 |
| Database (hosts only) | Supabase dashboard, project `bob-quiz`, **SQL Editor** |

## 2. What to tell participants

Read this out, or put it on a slide.

1. Open the link and enter your **name** and **IBM email** (it must end in `ibm.com`).
2. You get **16 questions** and **3 minutes**. The clock starts when you press **Start** and cannot be paused.
3. **Select one** questions allow a single answer. **Select all that apply** questions need every correct option and no extras.
4. Your answers are submitted automatically when time runs out. Refreshing the page does not reset your timer.
5. Ranking is **score first, then speed**. Everyone sees names and scores on the leaderboard. Emails are never shown.
6. You get **one attempt per person**.

## 3. Before the event

**A few days before**
- Open the Supabase dashboard to confirm the project is awake. Free projects pause after a week of inactivity.
- Add a second owner to the `uki-qualicon-26` GitHub organisation (People tab), so you are not the only admin.
- Open the participant link from an IBM laptop on the office network, in case it is blocked.
- Do a dry run with 2 or 3 colleagues. Check the 3:00 time box and the podium ceremony. If 3 minutes is too tight, raise it (section 8).

**Set the host code (once)**

1. Choose a long code of your own, 8 or more characters. Letters, digits and symbols such as `- _ ! # @ . +` are fine. It is case-sensitive.
2. In **SQL Editor**, run it, with the code inside single quotes:

   ```sql
   insert into quiz.config (key, value) values ('host_code', 'PUT-YOUR-OWN-CODE-HERE')
   on conflict (key) do update set value = excluded.value;
   ```

   Click an empty part of the editor first so no text is highlighted. If the button says **Run selected**, only the highlighted text runs and you get a syntax error.
3. Check it saved without showing the code: `select char_length(value) from quiz.config where key = 'host_code';`

**The day before and the hour before**
- Wipe the dry-run data (section 9).
- Open the big-screen page on the projector machine and check the counters show 0.
- Do not change the site after participants have it open. Browsers cache files for about 10 minutes.

## 4. Host test mode (retake without being counted)

Use this to rehearse as often as you like. Host runs are excluded from the leaderboard, the live counters and every report.

1. Open `.../quiz/?host=1`. A **Host code (test run, not counted)** field appears. Normal participants never see it.
2. Enter your name, your IBM email and the host code (without quotes), then **Register**.
3. Take the quiz. The result screen shows a **Host test run** banner.
4. Press **Run it again** to retake. Every registration resets your previous attempt.

**Co-host:** you can share the link and the code with a trusted co-host.
- Send the code through a private channel (direct message or password manager), separate from the link.
- They use their **own** IBM email. Each host email is its own test row.
- Never register a real participant's email with the code. It overrides the one-attempt rule and would delete that person's result.
- A co-host who wants to compete for real registers on the normal link, without `?host=1`.
- The code gives no database access. It only allows test runs.

## 5. During the event

- Show the big-screen page. It shows registered, playing and finished counters and the live top 10.
- Participants see their own result and the leaderboard on their phones, refreshed every few seconds.
- To stop new entries: `update quiz.config set value = 'false' where key = 'quiz_open';` (set `'true'` to reopen).
- Let people finish. Everyone has the full time box (3 minutes by default, see section 8) from pressing Start, plus a 10 second network grace.

## 6. Podium ceremony

1. Wait until the last participant's time box has passed (the **finished** counter stops rising).
2. On the big screen click **Start podium ceremony**. It reveals P3, then P2, then P1 with confetti and champagne.
3. Click **Back to live board** to return to the live top 10.

## 7. After the event: reports for stakeholders

Open **SQL Editor** and use the queries in [`supabase/reports.sql`](supabase/reports.sql). Export any result with **Export > Download CSV**.

| Question | Query |
|---|---|
| How many registered, started, finished? Average and median score? | `select * from quiz.v_summary;` |
| How many got full marks, one short, and so on? | `select * from quiz.v_score_distribution;` |
| Which questions were hardest? | `select position, prompt, answered, correct, pct_correct from quiz.v_question_accuracy order by pct_correct asc;` |
| Full leaderboard with emails (organisers only) | `select rank, name, email, score, total, round(duration_ms/1000.0,1) as seconds from quiz.v_leaderboard order by rank;` |
| Started but did not finish | `select * from quiz.v_unfinished;` |

Host test runs are excluded from all of these.

**Close down**
- Stop new entries: `update quiz.config set value = 'false' where key = 'quiz_open';`
- Switch host mode off: `delete from quiz.config where key = 'host_code';`
- When you no longer need the site, make the repo private or delete the GitHub Pages site.

## 8. Host controls

Run in **SQL Editor**. Change these before the event, not while people are playing.

| Goal | SQL |
|---|---|
| Time box (seconds). 16 questions: 180 recommended | `update quiz.config set value = '180' where key = 'quiz_seconds';` |
| Close or reopen registration | `update quiz.config set value = 'false' where key = 'quiz_open';` |
| Hide the answer key in reviews | `update quiz.config set value = 'false' where key = 'reveal_answers';` |
| Turn host mode off | `delete from quiz.config where key = 'host_code';` |

## 9. Clean up and fix problems

| Situation | What to do |
|---|---|
| Remove all test and dry-run data before the live session | `truncate quiz.participants cascade;` |
| A participant mistyped their email or needs another attempt | `delete from quiz.participants where email = 'person@ibm.com';` They can then register again. |
| See who has registered | `select name, email, created_at, is_test from quiz.participants order by created_at;` |
| A participant says "This email has already completed the quiz" | That email already has a result. Delete it with the line above only if you intend to give them another go. |
| Page looks old after an update | Hard refresh with Cmd+Shift+R (Ctrl+F5 on Windows). |
| "Run selected" error in the SQL Editor | Click an empty area so nothing is highlighted, then Run. |
| Site will not load for anyone | Check the Supabase project is not paused (dashboard > Restore), then try the link from another network. |
| Participant timer ran out before they submitted | Answers are submitted automatically. Submissions arriving more than 10 seconds after the time box score 0. |

## 10. Quiz content

- The 16 questions and their answer key are **not** in this public repo, so participants cannot read them. The organiser keeps the real file in a private folder.
- To change questions, edit your private `seed_questions.sql` and run it in the SQL Editor. It updates questions in place. `supabase/seed_questions.template.sql` shows the format.
- Question 3 uses the documented Tier 1 allowance of 500 Bobcoins per month. If you want a different figure, change that question's option text and `correct` value, then re-run the file.
- Built-in modes are Agent, Plan and Ask. Advanced is not a default mode.
- Questions 11 to 14 cover **Bobalytics** (where to open it, the Bob factor, the three KPIs, and anonymized team charts). Questions 15 and 16 cover **pricing** (which plan includes Bobalytics and the admin dashboard, and the 30-day free trial). They follow the Bob documentation and the public page https://bob.ibm.com/pricing. Prices and Bobcoin allowances on that page are indicative and vary by country, so the quiz asks about plan features and trial length and not about prices.

## 11. Look and feel

The portal uses a Qualicon 2026 synthwave theme: a neon night-sky background and a Qualicon 2026 badge with the bug next to the IBM Bob logo. The artwork is in `assets/qualicon-bg.svg` and `assets/qualicon-badge.svg`. Replace the badge file with the official artwork if you have it, keeping the same file name.

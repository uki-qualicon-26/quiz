# Bob Quiz Challenge

A time-boxed, multiple-choice quiz about the IBM Bob interface, with a live leaderboard and an
F1-style podium ceremony for the big screen. Built for a live session of roughly 160 to 190 people.

- **Participants** open one URL, register with name and IBM email, then answer 10 questions in 2 minutes.
  Single-answer questions allow one choice; "select all that apply" questions allow several.
- **Scoring** happens on the server. Ranking is score first, then fastest time. A multi-select question
  only counts if you pick exactly the right set.
- **Results** show correct and wrong answers highlighted, with a short explanation per question.
- **Leaderboard** is visible to everyone (names and scores only, never emails).
- **Big screen** (`presenter.html`) shows live counters and a staged podium reveal (P3, P2, P1) with a champagne pop.
- **Stakeholder reporting** is plain SQL on a Postgres database (see `supabase/reports.sql`).

```
Browser (GitHub Pages, static)  --HTTPS-->  Supabase RPC functions  -->  Postgres (private schema "quiz")
```

## Setup (about 15 minutes)

### 1. Create the Supabase project
1. Sign in at https://supabase.com and create a new project (free tier is enough). Pick a region close to your audience.
2. Save the database password in your password manager. It is never needed by this site.

### 2. Create the database
In **SQL Editor**, run these two files in order (paste, then Run):
1. `supabase/schema.sql`
2. `supabase/seed_questions.sql` (your question bank, see step 3)

Check it worked: `select count(*) from quiz.questions;` should return 10.

### 3. Prepare the question bank
The answer key is deliberately **not committed** (`supabase/seed_questions.sql` is git-ignored) because the repo is
public. Copy `supabase/seed_questions.template.sql` to `supabase/seed_questions.sql`, write your questions and run it.
The organiser's copy of the 10 Bob questions was generated alongside this repo. Question 3 (starting Bobcoin budget) follows the Bob documentation:
Tier 1 = 500 Bobcoins per month. If your environment grants a different amount, change the option text and the
`correct` value, then re-run the file (it updates questions in place).

### 4. Connect the website
In Supabase go to **Project Settings > API** and copy the **Project URL** and the **anon public** key into
`config.js`. The anon key is meant to be public. Never put the `service_role` key anywhere in this repo.

### 5. Publish on GitHub Pages
Repo **Settings > Pages**: Source = *Deploy from a branch*, Branch = `main`, folder = `/ (root)`.
After a minute the site is live at `https://<your-user>.github.io/<repo-name>/`.

- Participants: `.../index.html`
- Big screen: `.../presenter.html`

### 6. Dry run, then reset
Take the quiz yourself with two or three colleagues, check the podium ceremony, then wipe the test data:

```sql
truncate quiz.participants cascade;
```

## Running the session

| When | What |
|---|---|
| Before | Share the participant URL. Open `presenter.html` on the projector. |
| During | The presenter page shows registered / playing / finished counters and the live top 10. |
| Ceremony | When the time box has passed for everyone, click **Start podium ceremony**. It reveals P3, P2, then P1 with confetti. |
| After | Run the queries in `supabase/reports.sql` and export CSV for stakeholders. |

Host controls (SQL editor):

```sql
update quiz.config set value = '120'   where key = 'quiz_seconds';    -- time box in seconds
update quiz.config set value = 'false' where key = 'quiz_open';       -- stop new registrations
update quiz.config set value = 'false' where key = 'reveal_answers';  -- hide the answer key in reviews
```

Timing note: 10 questions in 120 seconds is about 12 seconds per question, which suits easy to moderate
questions. If people struggle in the dry run, raise `quiz_seconds` to 150 or 180.

## Security design

- The browser can only call eight `quiz_*` functions. The tables live in a private schema that the API does not expose, and row level security is enabled as a second layer.
- The **answer key never leaves the database** until a participant has submitted, so it cannot be read from dev tools.
- Each registration gets a random secret token. Only its SHA-256 hash is stored. The token lives in `sessionStorage` for that tab.
- The clock is server-side. Submissions more than 10 seconds past the time box score zero. Refreshing the page does not reset the timer.
- Email must end in `ibm.com` (checked in the browser and again by the database, including a constraint on the table). One attempt per email.
- Only names and scores are public. Emails are visible to organisers only, through SQL.
- A strict Content Security Policy restricts scripts, styles and network calls to this site and `*.supabase.co`. All user text is rendered with `textContent`, so names cannot inject HTML.

Known limitation, by design for this event: registration is name plus domain-validated email with no email verification,
so someone could type a colleague's address. If that matters, add Supabase email one-time-code sign-in.

## Capacity

For 190 participants the load is small: roughly 40 leaderboard requests per second at peak, which is well within the
Supabase free tier. Free projects pause after a week of inactivity, so open the dashboard the day before to confirm
the project is awake.

## Files

| Path | Purpose |
|---|---|
| `index.html`, `assets/app.js` | Participant flow |
| `presenter.html`, `assets/presenter.js`, `assets/podium.js` | Big-screen view and podium ceremony |
| `assets/api.js`, `config.js` | Supabase client and public settings |
| `supabase/schema.sql` | Tables, scoring functions, API, reporting views |
| `supabase/seed_questions.template.sql` | Question bank template (the real `seed_questions.sql` is git-ignored) |
| `supabase/reports.sql` | Stakeholder queries and host controls |

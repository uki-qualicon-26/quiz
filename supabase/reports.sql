-- =============================================================================
-- Stakeholder reporting queries. Run these in the Supabase SQL editor
-- (Dashboard > SQL Editor). They are not reachable from the public website.
-- =============================================================================

-- 1. Headline numbers: registered, started, completed, completion %, average/median/best score
select * from quiz.v_summary;

-- 2. Score distribution (how many people got 10/10, 9/10, ...)
select * from quiz.v_score_distribution;

-- 3. Which questions were hardest? (lowest % correct first)
select position, prompt, answered, correct, pct_correct
from quiz.v_question_accuracy
order by pct_correct asc;

-- 4. Full leaderboard (emails are not stored, so names and results only)
select rank, name, score, total, round(duration_ms / 1000.0, 1) as seconds
from quiz.v_leaderboard
order by rank;

-- 5. Registered but never finished
select name, started_at from quiz.v_unfinished;
select p.name
from quiz.participants p
left join quiz.attempts a on a.participant_id = p.id
where a.participant_id is null and not p.is_test
order by p.created_at;

-- 6. Registrations over time (5-minute buckets) to show engagement during the session
select date_bin('5 minutes', created_at, timestamptz '2000-01-01') as bucket, count(*) as registrations
from quiz.participants
where not is_test
group by 1
order by 1;

-- 7. Export everything for slides / Excel: run any query above, then use "Download CSV".

-- -----------------------------------------------------------------------------
-- Host controls
-- -----------------------------------------------------------------------------
-- Change the time box (seconds). Applies to attempts that have not started yet.
--   update quiz.config set value = '180' where key = 'quiz_seconds';
-- Close / reopen registration and starts:
--   update quiz.config set value = 'false' where key = 'quiz_open';
-- Hide the answer key in the review screen until you are ready to share it:
--   update quiz.config set value = 'false' where key = 'reveal_answers';
-- Host test runs: set a secret host code once (8+ characters, never put it in the repo), then register on
-- <site URL>/?host=1 with that code. Those runs can be repeated any number of times and are excluded from
-- the leaderboard, the live counters and every report above.
--   insert into quiz.config (key, value) values ('host_code', 'CHOOSE-A-LONG-SECRET')
--     on conflict (key) do update set value = excluded.value;
-- Disable host mode:  delete from quiz.config where key = 'host_code';
-- Wipe all participants and results between dry run and the live event (and one week after the event):
--   truncate quiz.participants cascade;
-- Hashing secret for emails (set once before the first registration; never put it in the repo):
--   insert into quiz.config (key, value) values ('email_hmac_key', 'A-LONG-RANDOM-SECRET')
--     on conflict (key) do update set value = excluded.value;
-- Changing the secret later makes old hashes stop matching, so only change it with an empty participants table.

-- =============================================================================
-- Stakeholder report. Run in the Supabase SQL editor (Dashboard > SQL Editor)
-- after the event. Each section is one query: run it, then Export > Download CSV
-- for slides or Excel. Host test runs are excluded. No emails appear in any
-- section except the optional follow-up list at the end.
-- =============================================================================

-- 1. Headline: participation, completion and scores
select registered,
       started,
       completed,
       completion_pct,
       avg_score,
       median_score,
       best_score,
       questions,
       avg_seconds_taken
from quiz.v_summary;

-- 2. Score distribution with share of finishers
select score,
       participants,
       round(100.0 * participants / sum(participants) over (), 1) as pct_of_finishers
from quiz.v_score_distribution
order by score desc;

-- 3. Questions ranked hardest to easiest (lowest % correct first)
select position, prompt, kind, answered, correct, pct_correct
from quiz.v_question_accuracy
order by pct_correct asc nulls last, position;

-- 4. Top 10 (names and results only)
select rank, name, score, total, round(duration_ms / 1000.0, 1) as seconds
from quiz.v_leaderboard
where rank <= 10
order by rank;

-- 5. Registrations per 5 minutes (engagement during the session)
select date_bin('5 minutes', created_at, timestamptz '2000-01-01') as bucket,
       count(*) as registrations
from quiz.participants
where not is_test
group by 1
order by 1;

-- 6. Registered but did not finish, split by reason (counts only)
select count(*) filter (where a.participant_id is null)                         as never_started,
       count(*) filter (where a.participant_id is not null
                          and a.submitted_at is null)                           as started_not_finished
from quiz.participants p
left join quiz.attempts a on a.participant_id = p.id
where not p.is_test;

-- 7. Optional follow-up list for organisers only (contains emails; do not share)
select p.name,
       p.email,
       case when a.participant_id is null then 'never started' else 'started, not finished' end as status
from quiz.participants p
left join quiz.attempts a on a.participant_id = p.id
where not p.is_test
  and a.submitted_at is null
order by p.created_at;

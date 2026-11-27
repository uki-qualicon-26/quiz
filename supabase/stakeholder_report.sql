-- =============================================================================
-- Stakeholder report. Run in the Supabase SQL editor (Dashboard > SQL Editor)
-- after the event. Each section is one query: run it, then Export > Download CSV
-- for slides or Excel. Host test runs are excluded. Emails are not stored (only a
-- one-way hash), so every section is names and counts only.
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

-- 7. Registered but did not finish, by name (no contact details are held)
select p.name,
       case when a.participant_id is null then 'never started' else 'started, not finished' end as status
from quiz.participants p
left join quiz.attempts a on a.participant_id = p.id
where not p.is_test
  and a.submitted_at is null
order by p.created_at;

-- =============================================================================
-- Hands-on workshop (needs the workshop_* additions in schema.sql)
-- Everyone who took part registered once, so quiz and workshop line up per person.
-- =============================================================================

-- 8. Quiz-to-workshop funnel (counts only)
select (select count(*) from quiz.participants where not is_test)                              as registered,
       (select count(*) from quiz.v_real_attempts where submitted_at is not null)               as finished_quiz,
       count(*)                                                                                 as started_workshop,
       count(*) filter (where finished_at is not null)                                          as finished_workshop,
       round(100.0 * count(*) filter (where finished_at is not null)
             / nullif((select count(*) from quiz.v_real_attempts where submitted_at is not null), 0), 1)
                                                                                                as pct_of_quiz_finishers_completing
from quiz.v_workshop_real;

-- 9. Path chosen and completion (A = Jira MCP, B = repo fallback). A high B share means MCP setup is a pre-read candidate
select coalesce(path, 'not chosen') as path,
       count(*)                                      as participants,
       count(*) filter (where finished_at is not null) as finished,
       round(avg(steps_done), 1)                      as avg_steps_done
from quiz.v_workshop_real
group by path
order by path;

-- 10. Where people stopped (last step reached; counts only, unfinished participants)
select (select 's' || max(substr(x, 2)::int) from unnest(done) x)  as last_step_done,   -- numeric max, so s10 > s2
       count(*)                             as participants
from quiz.v_workshop_real
where finished_at is null
group by 1
order by 1;

-- 11. Time to complete the workshop, minutes (finished participants)
select count(*)                                                                         as finished,
       round(avg(extract(epoch from finished_at - started_at) / 60)::numeric, 1)        as avg_minutes,
       round(percentile_cont(0.5) within group (order by extract(epoch from finished_at - started_at) / 60)::numeric, 1)
                                                                                         as median_minutes
from quiz.v_workshop_real
where finished_at is not null;

-- 12. Did a better quiz score go with finishing the workshop? (counts only)
select case when quiz_score >= 0.8 * quiz_total then 'quiz 80%+'
            when quiz_score >= 0.5 * quiz_total then 'quiz 50-79%'
            else 'quiz under 50%' end                         as quiz_band,
       count(*)                                               as workshop_started,
       count(*) filter (where finished_at is not null)        as workshop_finished
from quiz.v_workshop_real
group by 1
order by 1;

-- 13. Finished the quiz, never opened the workshop (names only)
select p.name
from quiz.participants p
join quiz.attempts a on a.participant_id = p.id and a.submitted_at is not null
left join quiz.workshop_progress w on w.participant_id = p.id
where not p.is_test and w.participant_id is null
order by p.name;

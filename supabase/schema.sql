-- =============================================================================
-- Bob Quiz Portal - database schema, RPC functions and reporting views
-- Run once in the Supabase SQL editor (safe to re-run).
--
-- Security model
--   * All data lives in the private schema "quiz", which is NOT exposed through
--     the Supabase API. The browser can never read or write the tables directly.
--   * The browser only calls the quiz_* functions in the "public" schema. They are
--     SECURITY DEFINER, validate every input and never return the answer key
--     before a participant has submitted.
--   * Each participant gets a random secret token at registration. Only its
--     SHA-256 hash is stored.
--   * The IBM email is never stored. quiz_register checks it, then keeps only an
--     HMAC-SHA256 hash (keyed with a secret in quiz.config) to stop duplicate
--     registrations. No view or function returns an email.
--
-- Set the hashing secret once (see HOST_GUIDE.md, section 3). Until it is set, registration
-- answers "server_not_configured":
--   insert into quiz.config (key, value) values ('email_hmac_key', 'A-LONG-RANDOM-SECRET')
--   on conflict (key) do update set value = excluded.value;
-- If this database already holds registrations from an earlier version, clear them first
-- (they contain plain emails):  truncate quiz.participants cascade;
-- =============================================================================

create extension if not exists pgcrypto with schema extensions;   -- provides hmac()

create schema if not exists quiz;
revoke all on schema quiz from public;

-- -----------------------------------------------------------------------------
-- Tables
-- -----------------------------------------------------------------------------
create table if not exists quiz.config (
  key   text primary key,
  value text not null
);

-- Host-tunable settings. Example:
--   update quiz.config set value = '240' where key = 'quiz_seconds';
insert into quiz.config (key, value) values
  ('quiz_seconds',   '180'),   -- time box per participant, in seconds
  ('quiz_open',      'true'),  -- false = no new registrations / starts
  ('reveal_answers', 'true')   -- false = show right/wrong only, hide the answer key
on conflict (key) do nothing;

create table if not exists quiz.questions (
  id          int  primary key,
  position    int  not null unique,
  prompt      text not null,
  kind        text not null check (kind in ('single', 'multi')),
  options     jsonb not null,            -- [{"key":"a","text":"..."}, ... four items]
  correct     text[] not null,           -- e.g. {a} or {a,b,c}
  explanation text not null,
  check (kind <> 'single' or cardinality(correct) = 1),
  check (kind <> 'multi'  or cardinality(correct) >= 2),
  check (correct <@ array['a','b','c','d'])
);

create table if not exists quiz.participants (
  id         uuid primary key default gen_random_uuid(),
  name       text not null check (char_length(name) between 2 and 60),
  email_hash text not null unique,        -- HMAC-SHA256 of the lower-cased email; the email itself is never stored
  token_hash text not null,
  created_at timestamptz not null default now()
);

-- Migration from the older schema that stored plain emails: refuse if rows exist, otherwise drop the column.
do $$
begin
  if exists (select 1 from information_schema.columns
             where table_schema = 'quiz' and table_name = 'participants' and column_name = 'email') then
    if exists (select 1 from quiz.participants) then
      raise exception 'quiz.participants still holds plain emails. Run: truncate quiz.participants cascade;  then re-run this script.';
    end if;
    drop view if exists quiz.v_leaderboard, quiz.v_unfinished, quiz.v_workshop_real;
    alter table quiz.participants drop column email;
  end if;
end
$$;
alter table quiz.participants add column if not exists email_hash text not null unique;
-- Host test runs (retakeable, excluded from the leaderboard, counters and reports)
alter table quiz.participants add column if not exists is_test boolean not null default false;

create table if not exists quiz.attempts (
  participant_id uuid primary key references quiz.participants (id) on delete cascade,
  started_at     timestamptz not null default now(),
  submitted_at   timestamptz,
  score          int,
  total          int,
  duration_ms    int,
  late           boolean not null default false,
  answers        jsonb
);

create index if not exists attempts_rank_idx
  on quiz.attempts (score desc, duration_ms asc, submitted_at asc)
  where submitted_at is not null;

-- Lock the tables down. Even if "quiz" were ever exposed, RLS denies everything.
alter table quiz.config       enable row level security;
alter table quiz.questions    enable row level security;
alter table quiz.participants enable row level security;
alter table quiz.attempts     enable row level security;

-- -----------------------------------------------------------------------------
-- Private helpers
-- -----------------------------------------------------------------------------
create or replace function quiz.cfg(p_key text)
returns text language sql stable
set search_path = quiz, pg_temp as
$$ select value from quiz.config where key = p_key $$;

create or replace function quiz.token_to_participant(p_token text)
returns uuid language sql stable
set search_path = quiz, pg_temp as
$$
  select id from quiz.participants
  where token_hash = encode(sha256(convert_to(coalesce(p_token, ''), 'utf8')), 'hex')
$$;

-- True when the given answer array exactly matches the correct set (all or nothing).
create or replace function quiz.is_correct(p_correct text[], p_given jsonb)
returns boolean language sql immutable
set search_path = quiz, pg_temp as
$$
  select case
    when jsonb_typeof(p_given) = 'array' then
      coalesce(
        (select array_agg(distinct x order by x) from jsonb_array_elements_text(p_given) x)
          = (select array_agg(c order by c) from unnest(p_correct) c),
        false)
    else false
  end
$$;

-- Ranked leaderboard: highest score first, then fastest, then earliest submit.
create or replace view quiz.v_leaderboard as
select row_number() over (order by a.score desc, a.duration_ms asc, a.submitted_at asc)::int as rank,
       p.id   as participant_id,
       p.name,
       a.score,
       a.total,
       a.duration_ms,
       a.late,
       a.submitted_at
from quiz.attempts a
join quiz.participants p on p.id = a.participant_id
where a.submitted_at is not null
  and not p.is_test;

-- Full result (score, rank, per-question review) for one participant.
create or replace function quiz.build_result(p_pid uuid)
returns jsonb language plpgsql stable
set search_path = quiz, pg_temp as
$$
declare
  v_att    quiz.attempts;
  v_rank   int;
  v_reveal boolean := coalesce(quiz.cfg('reveal_answers'), 'true') = 'true';
  v_review jsonb;
  v_test   boolean;
begin
  select * into v_att from quiz.attempts where participant_id = p_pid;
  select is_test into v_test from quiz.participants where id = p_pid;
  select l.rank into v_rank from quiz.v_leaderboard l where l.participant_id = p_pid;

  select jsonb_agg(jsonb_build_object(
           'id',          q.id,
           'prompt',      q.prompt,
           'kind',        q.kind,
           'options',     q.options,
           'selected',    coalesce(v_att.answers -> q.id::text, '[]'::jsonb),
           'is_correct',  quiz.is_correct(q.correct, v_att.answers -> q.id::text),
           'correct',     case when v_reveal then to_jsonb(q.correct) end,
           'explanation', case when v_reveal then q.explanation end
         ) order by q.position)
    into v_review
  from quiz.questions q;

  return jsonb_build_object(
    'score',       v_att.score,
    'total',       v_att.total,
    'duration_ms', v_att.duration_ms,
    'late',        v_att.late,
    'rank',        v_rank,
    'is_test',     coalesce(v_test, false),
    'review',      v_review
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- Public API (called by the browser through /rest/v1/rpc/<name>)
-- Errors are raised as short codes and mapped to friendly text in the UI.
-- -----------------------------------------------------------------------------

-- Quiz settings shown on the register screen.
create or replace function public.quiz_config()
returns jsonb language sql stable security definer
set search_path = quiz, pg_temp as
$$
  select jsonb_build_object(
    'quiz_open',       coalesce(quiz.cfg('quiz_open'), 'true') = 'true',
    'quiz_seconds',    coalesce(quiz.cfg('quiz_seconds'), '180')::int,
    'total_questions', (select count(*) from quiz.questions)
  )
$$;

-- Register (or re-issue a token for someone who has not started yet).
-- With the secret host code the participant becomes a "test run": the attempt is reset on every
-- registration so the host can retake the quiz, and it is never counted anywhere.
drop function if exists public.quiz_register(text, text);
create or replace function public.quiz_register(p_name text, p_email text, p_host_code text default null)
returns jsonb language plpgsql security definer
set search_path = quiz, pg_temp as
$$
declare
  v_name  text := btrim(regexp_replace(coalesce(p_name, ''), '\s+', ' ', 'g'));
  v_email text := lower(btrim(coalesce(p_email, '')));
  v_key   text := coalesce(quiz.cfg('email_hmac_key'), '');
  v_ehash text;
  v_token text := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
  v_hash  text := encode(sha256(convert_to(v_token, 'utf8')), 'hex');
  v_host  text := coalesce(quiz.cfg('host_code'), '');
  v_id    uuid;
begin
  if char_length(v_name) < 2 or char_length(v_name) > 60 then
    raise exception 'invalid_name';
  end if;
  if char_length(v_email) > 254 or v_email !~ '^[a-z0-9._%+''-]+@([a-z0-9-]+\.)*ibm\.com$' then
    raise exception 'invalid_email';
  end if;
  if char_length(v_key) < 16 then
    raise exception 'server_not_configured';
  end if;
  -- Keep only a keyed one-way hash of the email; the email itself is never stored.
  v_ehash := encode(extensions.hmac(convert_to(v_email, 'utf8'), convert_to(v_key, 'utf8'), 'sha256'), 'hex');

  if coalesce(p_host_code, '') <> '' then
    -- host test run: reset any previous attempt, bypass the open/closed switch
    if char_length(v_host) < 8 or p_host_code is distinct from v_host then
      raise exception 'invalid_host_code';
    end if;
    insert into quiz.participants as p (name, email_hash, token_hash, is_test)
    values (v_name, v_ehash, v_hash, true)
    on conflict (email_hash) do update
      set name = excluded.name, token_hash = excluded.token_hash, is_test = true
    returning p.id into v_id;
    delete from quiz.attempts where participant_id = v_id;
    -- also reset the hands-on workshop (path, steps and the 20 minute clock) so a test run starts fresh
    delete from quiz.workshop_progress where participant_id = v_id;
    return jsonb_build_object('token', v_token, 'name', v_name, 'is_test', true);
  end if;

  if coalesce(quiz.cfg('quiz_open'), 'true') <> 'true' then
    raise exception 'quiz_closed';
  end if;

  insert into quiz.participants as p (name, email_hash, token_hash)
  values (v_name, v_ehash, v_hash)
  on conflict (email_hash) do update
    set name = excluded.name, token_hash = excluded.token_hash
    where not p.is_test
      and not exists (select 1 from quiz.attempts a where a.participant_id = p.id)
  returning p.id into v_id;

  if v_id is null then
    raise exception 'already_taken';
  end if;

  return jsonb_build_object('token', v_token, 'name', v_name, 'is_test', false);
end;
$$;

-- Where is this participant in the flow? (used on page refresh)
create or replace function public.quiz_status(p_token text)
returns jsonb language plpgsql stable security definer
set search_path = quiz, pg_temp as
$$
declare
  v_pid uuid := quiz.token_to_participant(p_token);
  v_att quiz.attempts;
begin
  if v_pid is null then raise exception 'invalid_token'; end if;
  select * into v_att from quiz.attempts where participant_id = v_pid;
  return jsonb_build_object('state',
    case when v_att.participant_id is null then 'registered'
         when v_att.submitted_at is null   then 'in_progress'
         else 'submitted' end);
end;
$$;

-- Start the clock (idempotent: a second call resumes the same attempt).
create or replace function public.quiz_start(p_token text)
returns jsonb language plpgsql volatile security definer
set search_path = quiz, pg_temp as
$$
declare
  v_pid  uuid := quiz.token_to_participant(p_token);
  v_att  quiz.attempts;
  v_secs int  := coalesce(quiz.cfg('quiz_seconds'), '180')::int;
begin
  if v_pid is null then raise exception 'invalid_token'; end if;

  select * into v_att from quiz.attempts where participant_id = v_pid;
  if v_att.participant_id is null then
    if coalesce(quiz.cfg('quiz_open'), 'true') <> 'true'
       and not exists (select 1 from quiz.participants where id = v_pid and is_test) then
      raise exception 'quiz_closed';
    end if;
    insert into quiz.attempts (participant_id) values (v_pid) returning * into v_att;
  end if;

  if v_att.submitted_at is not null then
    return jsonb_build_object('state', 'submitted');
  end if;

  return jsonb_build_object(
    'state',         'in_progress',
    'seconds_total', v_secs,
    'seconds_left',  greatest(0, round(extract(epoch from
                       (v_att.started_at + make_interval(secs => v_secs) - clock_timestamp()))::numeric, 1)),
    -- the answer key is never included here
    'questions', (select jsonb_agg(jsonb_build_object(
                    'id', q.id, 'prompt', q.prompt, 'kind', q.kind, 'options', q.options)
                    order by q.position)
                  from quiz.questions q)
  );
end;
$$;

-- Score the attempt on the server. Submissions later than a 10 s network grace score 0.
create or replace function public.quiz_submit(p_token text, p_answers jsonb)
returns jsonb language plpgsql volatile security definer
set search_path = quiz, pg_temp as
$$
declare
  v_pid     uuid := quiz.token_to_participant(p_token);
  v_att     quiz.attempts;
  v_secs    int  := coalesce(quiz.cfg('quiz_seconds'), '180')::int;
  v_elapsed numeric;
  v_late    boolean;
  v_clean   jsonb;
  v_score   int;
  v_total   int;
begin
  if v_pid is null then raise exception 'invalid_token'; end if;
  if p_answers is null or jsonb_typeof(p_answers) <> 'object'
     or octet_length(p_answers::text) > 4000 then
    raise exception 'invalid_answers';
  end if;

  select * into v_att from quiz.attempts where participant_id = v_pid for update;
  if v_att.participant_id is null then raise exception 'not_started'; end if;
  if v_att.submitted_at is not null then
    return quiz.build_result(v_pid);            -- idempotent
  end if;

  v_elapsed := extract(epoch from (clock_timestamp() - v_att.started_at));
  v_late    := v_elapsed > v_secs + 10;

  -- Keep only known question ids and the options a-d, de-duplicated.
  select coalesce(jsonb_object_agg(q.id::text,
           case when not v_late and jsonb_typeof(p_answers -> q.id::text) = 'array' then
             (select coalesce(jsonb_agg(distinct x), '[]'::jsonb)
              from jsonb_array_elements_text(p_answers -> q.id::text) x
              where x in ('a','b','c','d'))
           else '[]'::jsonb end), '{}'::jsonb)
    into v_clean
  from quiz.questions q;

  select count(*) filter (where quiz.is_correct(q.correct, v_clean -> q.id::text)), count(*)
    into v_score, v_total
  from quiz.questions q;

  update quiz.attempts
     set submitted_at = now(),
         answers      = v_clean,
         score        = v_score,
         total        = v_total,
         late         = v_late,
         duration_ms  = round(least(v_elapsed, v_secs) * 1000)::int
   where participant_id = v_pid;

  return quiz.build_result(v_pid);
end;
$$;

-- Re-fetch your own result (page refresh).
create or replace function public.quiz_result(p_token text)
returns jsonb language plpgsql stable security definer
set search_path = quiz, pg_temp as
$$
declare
  v_pid uuid := quiz.token_to_participant(p_token);
begin
  if v_pid is null then raise exception 'invalid_token'; end if;
  if not exists (select 1 from quiz.attempts where participant_id = v_pid and submitted_at is not null) then
    raise exception 'not_submitted';
  end if;
  return quiz.build_result(v_pid);
end;
$$;

-- Public leaderboard: names and scores only.
create or replace function public.quiz_leaderboard(p_limit int default 10)
returns jsonb language sql stable security definer
set search_path = quiz, pg_temp as
$$
  select coalesce(jsonb_agg(jsonb_build_object(
           'rank', l.rank, 'name', l.name, 'score', l.score,
           'total', l.total, 'duration_ms', l.duration_ms) order by l.rank), '[]'::jsonb)
  from (select * from quiz.v_leaderboard
        order by rank
        limit least(greatest(coalesce(p_limit, 10), 1), 100)) l
$$;

-- Live counters for the presenter screen.
create or replace function public.quiz_stats()
returns jsonb language sql stable security definer
set search_path = quiz, pg_temp as
$$
  select jsonb_build_object(
    'registered', (select count(*) from quiz.participants where not is_test),
    'started',    (select count(*) from quiz.attempts a join quiz.participants p on p.id = a.participant_id where not p.is_test),
    'completed',  (select count(*) from quiz.attempts a join quiz.participants p on p.id = a.participant_id
                   where not p.is_test and a.submitted_at is not null)
  )
$$;

-- Host control from the big-screen page (?host=1): clear all trial data, or lock/unlock the clear button.
-- Needs the secret host code. Once locked ("Go live"), nothing can be cleared until it is unlocked again.
create or replace function public.quiz_host_reset(p_host_code text, p_action text)
returns jsonb language plpgsql security definer
set search_path = quiz, pg_temp as
$$
declare
  v_host    text := coalesce(quiz.cfg('host_code'), '');
  v_deleted int;
begin
  if char_length(v_host) < 8 or p_host_code is distinct from v_host then
    raise exception 'invalid_host_code';
  end if;
  if p_action = 'lock' then
    insert into quiz.config (key, value) values ('reset_locked', 'true')
      on conflict (key) do update set value = 'true';
    return jsonb_build_object('locked', true, 'deleted', 0);
  elsif p_action = 'unlock' then
    insert into quiz.config (key, value) values ('reset_locked', 'false')
      on conflict (key) do update set value = 'false';
    return jsonb_build_object('locked', false, 'deleted', 0);
  elsif p_action = 'clear' then
    if coalesce(quiz.cfg('reset_locked'), 'false') = 'true' then
      raise exception 'reset_locked';
    end if;
    -- "where true" keeps Supabase's safe-update guard happy; attempts are removed by cascade.
    delete from quiz.participants where true;
    get diagnostics v_deleted = row_count;
    return jsonb_build_object('locked', false, 'deleted', v_deleted);
  end if;
  raise exception 'invalid_action';
end;
$$;

-- -----------------------------------------------------------------------------
-- Hands-on workshop tracking. One registration (the quiz one) covers both parts.
-- The workshop only accepts progress from people who have submitted the quiz.
-- -----------------------------------------------------------------------------
create table if not exists quiz.workshop_progress (
  participant_id uuid primary key references quiz.participants (id) on delete cascade,
  path           text check (path in ('A', 'B')),
  done           text[] not null default '{}',
  started_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  finished_at    timestamptz
);
alter table quiz.workshop_progress enable row level security;

-- Where is this person? Used by the hub and the workshop guide on every page load.
create or replace function public.workshop_get(p_token text)
returns jsonb language plpgsql stable security definer
set search_path = quiz, pg_temp as
$$
declare
  v_pid uuid := quiz.token_to_participant(p_token);
  v_att quiz.attempts;
  v_w   quiz.workshop_progress;
begin
  if v_pid is null then raise exception 'invalid_token'; end if;
  select * into v_att from quiz.attempts where participant_id = v_pid;
  select * into v_w   from quiz.workshop_progress where participant_id = v_pid;
  return jsonb_build_object(
    'name',        (select name from quiz.participants where id = v_pid),
    'quiz_state',  case when v_att.participant_id is null then 'registered'
                        when v_att.submitted_at is null   then 'in_progress'
                        else 'submitted' end,
    'path',        v_w.path,
    'done',        to_jsonb(coalesce(v_w.done, '{}'::text[])),
    'started_at',  v_w.started_at,
    'finished_at', v_w.finished_at);
end;
$$;

-- Save workshop progress. Rejects anyone who has not submitted the quiz.
create or replace function public.workshop_save(p_token text, p_path text, p_done jsonb, p_finished boolean)
returns jsonb language plpgsql volatile security definer
set search_path = quiz, pg_temp as
$$
declare
  v_pid  uuid := quiz.token_to_participant(p_token);
  v_done text[];
begin
  if v_pid is null then raise exception 'invalid_token'; end if;
  if not exists (select 1 from quiz.attempts where participant_id = v_pid and submitted_at is not null) then
    raise exception 'quiz_not_done';
  end if;
  if p_path is not null and p_path not in ('A', 'B') then raise exception 'invalid_progress'; end if;
  if p_done is null or jsonb_typeof(p_done) <> 'array' or jsonb_array_length(p_done) > 20 then
    raise exception 'invalid_progress';
  end if;
  -- Only well-formed step ids (s1 .. s99), de-duplicated.
  select coalesce(array_agg(distinct x order by x), '{}') into v_done
  from jsonb_array_elements_text(p_done) x
  where x ~ '^s[0-9]{1,2}$';

  insert into quiz.workshop_progress as w (participant_id, path, done, finished_at)
  values (v_pid, p_path, v_done, case when p_finished then now() end)
  on conflict (participant_id) do update
    set path        = excluded.path,
        done        = excluded.done,
        updated_at  = now(),
        finished_at = case when p_finished then coalesce(w.finished_at, now()) else null end;
  return jsonb_build_object('saved', true);
end;
$$;

-- -----------------------------------------------------------------------------
-- Privileges: the browser (anon) may only execute the quiz_* and workshop_* functions.
-- -----------------------------------------------------------------------------
do $$
declare f text;
begin
  foreach f in array array[
    'quiz_config()', 'quiz_register(text,text,text)', 'quiz_status(text)', 'quiz_start(text)',
    'quiz_submit(text,jsonb)', 'quiz_result(text)', 'quiz_leaderboard(int)', 'quiz_stats()',
    'quiz_host_reset(text,text)',
    'workshop_get(text)', 'workshop_save(text,text,jsonb,boolean)'
  ] loop
    execute format('revoke all on function public.%s from public', f);
    execute format('grant execute on function public.%s to anon, authenticated', f);
  end loop;
end $$;

-- -----------------------------------------------------------------------------
-- Reporting views for stakeholders (query in the SQL editor; not reachable via API)
-- -----------------------------------------------------------------------------
create or replace view quiz.v_real_attempts as      -- attempts of real participants only (host test runs excluded)
select a.* from quiz.attempts a join quiz.participants p on p.id = a.participant_id where not p.is_test;

create or replace view quiz.v_summary as
select (select count(*) from quiz.participants where not is_test)                as registered,
       count(*)                                                                  as started,
       count(*) filter (where submitted_at is not null)                          as completed,
       round(100.0 * count(*) filter (where submitted_at is not null)
             / nullif((select count(*) from quiz.participants where not is_test), 0), 1) as completion_pct,
       round(avg(score) filter (where submitted_at is not null), 2)              as avg_score,
       percentile_cont(0.5) within group (order by score)
             filter (where submitted_at is not null)                             as median_score,
       max(score)                                                                as best_score,
       round(avg(duration_ms) filter (where submitted_at is not null) / 1000.0, 1) as avg_seconds_taken,
       max(total)                                                                as questions
from quiz.v_real_attempts;

create or replace view quiz.v_score_distribution as
select score, count(*) as participants
from quiz.v_real_attempts
where submitted_at is not null
group by score
order by score desc;

create or replace view quiz.v_question_accuracy as
select q.position,
       q.prompt,
       q.kind,
       count(a.participant_id)                                              as answered,
       count(*) filter (where quiz.is_correct(q.correct, a.answers -> q.id::text)) as correct,
       round(100.0 * count(*) filter (where quiz.is_correct(q.correct, a.answers -> q.id::text))
             / nullif(count(a.participant_id), 0), 1)                       as pct_correct
from quiz.questions q
left join quiz.v_real_attempts a on a.submitted_at is not null
group by q.id, q.position, q.prompt, q.kind
order by q.position;

create or replace view quiz.v_unfinished as
select p.name, a.started_at
from quiz.attempts a
join quiz.participants p on p.id = a.participant_id
where a.submitted_at is null and not p.is_test
order by a.started_at;

-- Workshop progress of real participants only (host test runs excluded), with the quiz result alongside.
create or replace view quiz.v_workshop_real as
select p.id as participant_id, p.name, w.path, cardinality(w.done) as steps_done, w.done,
       w.started_at, w.updated_at, w.finished_at,
       a.score as quiz_score, a.total as quiz_total
from quiz.workshop_progress w
join quiz.participants p on p.id = w.participant_id
left join quiz.attempts a on a.participant_id = p.id
where not p.is_test;

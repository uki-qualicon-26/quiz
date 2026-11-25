-- Template for the question bank. Copy this file to supabase/seed_questions.sql
-- (that file is git-ignored so the answer key is never published), add your questions,
-- then run it in the Supabase SQL editor. Re-running updates questions in place.
--
-- kind     : 'single' (exactly one correct key) or 'multi' (two or more correct keys)
-- options  : exactly four items with keys a, b, c, d
-- correct  : Postgres text array, e.g. '{b}' or '{a,b,c}'

insert into quiz.questions (id, position, prompt, kind, options, correct, explanation) values
(1, 1,
 'Example single-answer question?',
 'single',
 '[{"key":"a","text":"Option A"},{"key":"b","text":"Option B"},{"key":"c","text":"Option C"},{"key":"d","text":"Option D"}]',
 '{b}',
 'Why B is right, shown to the participant after submitting.'),
(2, 2,
 'Example select-all question? Select ALL that apply.',
 'multi',
 '[{"key":"a","text":"Option A"},{"key":"b","text":"Option B"},{"key":"c","text":"Option C"},{"key":"d","text":"Option D"}]',
 '{a,c}',
 'Why A and C are right.')
on conflict (id) do update set
  position = excluded.position, prompt = excluded.prompt, kind = excluded.kind,
  options = excluded.options, correct = excluded.correct, explanation = excluded.explanation;

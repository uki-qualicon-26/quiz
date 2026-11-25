// Public, browser-safe settings. The anon key is designed to be public: it can only
// call the quiz_* functions, which validate everything server-side. Never put the
// service_role key or database password in this file.
window.BOB_QUIZ_CONFIG = {
  SUPABASE_URL: "https://YOUR-PROJECT-REF.supabase.co",
  SUPABASE_ANON_KEY: "YOUR-SUPABASE-ANON-KEY"
};

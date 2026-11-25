/* Thin client for the Supabase RPC functions defined in supabase/schema.sql */
(function () {
  "use strict";

  var cfg = window.BOB_QUIZ_CONFIG || {};
  var ERRORS = {
    invalid_name: "Please enter your full name (2 to 60 characters).",
    invalid_email: "Please use your IBM email address (ending in ibm.com).",
    already_taken: "This email has already completed the quiz. Each person gets one attempt.",
    quiz_closed: "The quiz is closed right now. Please check with your host.",
    invalid_token: "Your session expired. Please register again.",
    not_started: "The quiz has not been started yet.",
    not_submitted: "You have not submitted the quiz yet.",
    invalid_answers: "Your answers could not be read. Please try again.",
    network: "Could not reach the quiz server. Check your connection and try again.",
    not_configured: "This portal is not configured yet (see README, step 4).",
    unknown: "Something went wrong. Please try again."
  };

  function isConfigured() {
    return cfg.SUPABASE_URL && cfg.SUPABASE_ANON_KEY &&
      cfg.SUPABASE_URL.indexOf("YOUR-PROJECT-REF") === -1 &&
      cfg.SUPABASE_ANON_KEY.indexOf("YOUR-SUPABASE") === -1;
  }

  function QuizError(code) {
    var e = new Error(ERRORS[code] || ERRORS.unknown);
    e.code = code;
    return e;
  }

  function rpc(name, args) {
    if (!isConfigured()) { return Promise.reject(QuizError("not_configured")); }
    var ctrl = new AbortController();
    var timer = setTimeout(function () { ctrl.abort(); }, 15000);
    return fetch(cfg.SUPABASE_URL.replace(/\/$/, "") + "/rest/v1/rpc/" + name, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "apikey": cfg.SUPABASE_ANON_KEY,
        "Authorization": "Bearer " + cfg.SUPABASE_ANON_KEY
      },
      body: JSON.stringify(args || {}),
      signal: ctrl.signal
    }).then(function (res) {
      return res.json().catch(function () { return null; }).then(function (body) {
        if (!res.ok) {
          var code = body && body.message && ERRORS[body.message] ? body.message : "unknown";
          throw QuizError(code);
        }
        return body;
      });
    }, function () {
      throw QuizError("network");
    }).then(function (v) { clearTimeout(timer); return v; },
            function (e) { clearTimeout(timer); throw e; });
  }

  window.QuizApi = {
    isConfigured: isConfigured,
    config:      function ()               { return rpc("quiz_config"); },
    register:    function (name, email)    { return rpc("quiz_register", { p_name: name, p_email: email }); },
    status:      function (token)          { return rpc("quiz_status", { p_token: token }); },
    start:       function (token)          { return rpc("quiz_start", { p_token: token }); },
    submit:      function (token, answers) { return rpc("quiz_submit", { p_token: token, p_answers: answers }); },
    result:      function (token)          { return rpc("quiz_result", { p_token: token }); },
    leaderboard: function (limit)          { return rpc("quiz_leaderboard", { p_limit: limit || 10 }); },
    stats:       function ()               { return rpc("quiz_stats"); }
  };
})();

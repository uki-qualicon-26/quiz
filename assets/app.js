/* Participant flow: register -> start -> answer within the time box -> result + leaderboard */
(function () {
  "use strict";

  var KEY = "bobquiz.session.v1";
  var $ = function (id) { return document.getElementById(id); };
  var P = window.QuizPodium;
  var el = P.el;

  var state = { token: null, name: null, cfg: null, questions: [], answers: {}, endsAt: 0,
                totalSecs: 120, isTest: false, timer: null, submitting: false, lbTimer: null, myRank: null };

  /* ---------- helpers ---------- */
  function show(view) {
    ["register", "ready", "quiz", "result"].forEach(function (v) {
      $("view-" + v).classList.toggle("hidden", v !== view);
    });
    window.scrollTo(0, 0);
  }
  function showError(msg) {
    var e = $("error");
    e.textContent = msg || "";
    e.classList.toggle("hidden", !msg);
  }
  function fmtClock(s) {
    s = Math.max(0, Math.ceil(s));
    return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0");
  }
  function save(obj) { try { sessionStorage.setItem(KEY, JSON.stringify(obj)); } catch (e) { /* ignore */ } }
  function saveAnswers() { save({ token: state.token, name: state.name, answers: state.answers }); }
  function load() { try { return JSON.parse(sessionStorage.getItem(KEY) || "null"); } catch (e) { return null; } }
  function clearSession() { try { sessionStorage.removeItem(KEY); } catch (e) { /* ignore */ } }
  function sessionExpired(err) {
    if (err && err.code === "invalid_token") { clearSession(); state.token = null; init(); return true; }
    return false;
  }

  /* ---------- register ---------- */
  // The host field only appears on <site>/?host=1; the secret code itself is checked on the server.
  var HOST_MODE = /(^|[?&])host=1(&|$)/.test(window.location.search);
  var EMAIL_RE = /^[a-z0-9._%+'-]+@([a-z0-9-]+\.)*ibm\.com$/i;

  function onRegister(ev) {
    ev.preventDefault();
    showError("");
    var name = $("name").value.replace(/\s+/g, " ").trim();
    var email = $("email").value.trim().toLowerCase();
    if (name.length < 2) { return showError("Please enter your full name."); }
    if (!EMAIL_RE.test(email)) { return showError("Please use your IBM email address (ending in ibm.com)."); }
    $("reg-btn").disabled = true;
    var hostCode = HOST_MODE ? $("host-code").value : "";
    window.QuizApi.register(name, email, hostCode).then(function (r) {
      state.token = r.token; state.name = r.name; state.isTest = !!r.is_test;
      save({ token: r.token, name: r.name });
      showReady();
    }).catch(function (e) { showError(e.message); })
      .then(function () { $("reg-btn").disabled = false; });
  }

  function showReady() {
    $("ready-name").textContent = state.name || "player";
    show("ready");
  }

  /* ---------- quiz ---------- */
  function onStart() {
    showError("");
    $("start-btn").disabled = true;
    window.QuizApi.start(state.token).then(function (r) {
      if (r.state === "submitted") { return loadResult(); }
      beginQuiz(r);
    }).catch(function (e) { if (!sessionExpired(e)) { showError(e.message); } })
      .then(function () { $("start-btn").disabled = false; });
  }

  function beginQuiz(r) {
    state.questions = r.questions;
    state.totalSecs = r.seconds_total;
    state.endsAt = Date.now() + r.seconds_left * 1000;
    var saved = load();
    state.answers = (saved && saved.answers) || {};
    renderQuestions();
    updateProgress();
    show("quiz");
    tick();
    state.timer = setInterval(tick, 250);
  }

  function renderQuestions() {
    var box = $("questions");
    box.textContent = "";
    state.questions.forEach(function (q, i) {
      var card = el("div", "qcard");
      var head = el("div", "qhead");
      head.appendChild(el("span", "qnum", "Q" + (i + 1)));
      head.appendChild(el("span", "badge" + (q.kind === "multi" ? " multi" : ""),
        q.kind === "multi" ? "Select all that apply" : "Select one"));
      head.appendChild(el("p", "qprompt", q.prompt));
      card.appendChild(head);

      var group = el("div", "opts");
      group.setAttribute("role", q.kind === "multi" ? "group" : "radiogroup");
      group.setAttribute("aria-label", "Question " + (i + 1));
      q.options.forEach(function (o) {
        var label = el("label", "opt");
        var input = document.createElement("input");
        input.type = q.kind === "multi" ? "checkbox" : "radio";
        input.name = "q" + q.id;
        input.value = o.key;
        input.checked = (state.answers[q.id] || []).indexOf(o.key) !== -1;
        label.classList.toggle("picked", input.checked);
        input.addEventListener("change", function () { onPick(q, group); });
        label.appendChild(input);
        label.appendChild(el("span", "key", o.key + "."));
        label.appendChild(el("span", "", o.text));
        group.appendChild(label);
      });
      card.appendChild(group);
      box.appendChild(card);
    });
  }

  function onPick(q, group) {
    var picked = [];
    group.querySelectorAll("input").forEach(function (inp) {
      inp.parentNode.classList.toggle("picked", inp.checked);
      if (inp.checked) { picked.push(inp.value); }
    });
    state.answers[q.id] = picked;
    saveAnswers();
    updateProgress();
  }

  function answeredCount() {
    return state.questions.filter(function (q) { return (state.answers[q.id] || []).length > 0; }).length;
  }
  function updateProgress() {
    var done = answeredCount();
    var all = state.questions.length > 0 && done === state.questions.length;
    $("progress").textContent = done + " of " + state.questions.length + " answered";
    $("submit-btn").classList.toggle("hidden", !all);
    $("submit-hint").classList.toggle("hidden", all);
  }

  function tick() {
    var left = (state.endsAt - Date.now()) / 1000;
    $("clock").textContent = fmtClock(left);
    var pct = Math.max(0, Math.min(100, (left / state.totalSecs) * 100));
    $("fill").style.width = pct + "%";
    var low = left <= 20;
    $("clock").classList.toggle("low", low);
    $("fill").classList.toggle("low", low);
    if (left <= 0 && !state.submitting) { submit(true); }
  }

  function submit(auto) {
    if (state.submitting) { return; }
    var unanswered = state.questions.length - answeredCount();
    if (!auto && unanswered > 0 &&
        !window.confirm(unanswered + " question(s) unanswered. Submit anyway?")) { return; }
    state.submitting = true;
    clearInterval(state.timer);
    $("submit-btn").disabled = true;
    showError("");
    var payload = {};
    state.questions.forEach(function (q) { payload[q.id] = state.answers[q.id] || []; });
    window.QuizApi.submit(state.token, payload).then(renderResult).catch(function (e) {
      state.submitting = false;
      $("submit-btn").disabled = false;
      $("submit-btn").classList.remove("hidden");   // always allow a retry, even with unanswered questions
      $("submit-hint").classList.add("hidden");
      if (sessionExpired(e)) { return; }
      showError(e.message + " Press Submit to retry.");
    });
  }

  /* ---------- result ---------- */
  function loadResult() {
    return window.QuizApi.result(state.token).then(renderResult)
      .catch(function (e) { if (!sessionExpired(e)) { showError(e.message); } });
  }

  function renderResult(r) {
    state.submitting = false;
    state.myRank = r.rank;
    state.isTest = !!r.is_test;
    $("test-banner").classList.toggle("hidden", !state.isTest);
    $("res-score").textContent = r.score;
    $("res-total").textContent = r.total;
    $("res-rank").textContent = r.rank ? "#" + r.rank : "-";
    $("res-time").textContent = P.fmtTime(r.duration_ms);
    var pct = r.total ? r.score / r.total : 0;
    var msg = r.late ? "Time was up before your answers arrived."
      : pct === 1 ? "Perfect lap! 🏆" : pct >= 0.8 ? "Podium pace! 🏎️"
      : pct >= 0.5 ? "Solid drive, keep pushing. 💪" : "Bob has more to teach you. 🤖";
    var m = $("res-msg"); m.textContent = msg;
    renderReview(r.review || []);
    show("result");
    refreshLeaderboard();
    clearInterval(state.lbTimer);
    state.lbTimer = setInterval(refreshLeaderboard, 5000);
  }

  function renderReview(items) {
    var box = $("review");
    box.textContent = "";
    items.forEach(function (it, i) {
      var card = el("div", "qcard");
      var head = el("div", "qhead");
      head.appendChild(el("span", "qnum", "Q" + (i + 1)));
      head.appendChild(el("span", "verdict " + (it.is_correct ? "ok" : "bad"),
        it.is_correct ? "Correct" : "Incorrect"));
      head.appendChild(el("p", "qprompt", it.prompt));
      card.appendChild(head);
      var group = el("div", "opts");
      var sel = it.selected || [];
      var cor = it.correct || null;
      it.options.forEach(function (o) {
        var picked = sel.indexOf(o.key) !== -1;
        var isRight = cor ? cor.indexOf(o.key) !== -1 : null;
        var cls = "opt locked";
        var tag = "";
        if (cor) {
          if (picked && isRight) { cls += " right"; tag = "Your answer: correct"; }
          else if (picked && !isRight) { cls += " wrong"; tag = "Your answer: wrong"; }
          else if (!picked && isRight) { cls += " missed"; tag = "Correct answer"; }
        } else if (picked) {
          cls += it.is_correct ? " right" : " wrong";
        }
        var row = el("div", cls);
        row.appendChild(el("span", "key", o.key + "."));
        row.appendChild(el("span", "", o.text));
        if (tag) { row.appendChild(el("span", "tag " + (cls.indexOf("wrong") !== -1 ? "bad" : "ok"), tag)); }
        group.appendChild(row);
      });
      card.appendChild(group);
      if (it.explanation) { card.appendChild(el("div", "explain", it.explanation)); }
      box.appendChild(card);
    });
  }

  function refreshLeaderboard() {
    window.QuizApi.leaderboard(10).then(function (rows) {
      var wrap = $("lb-wrap");
      wrap.textContent = "";
      var tbl = el("table", "lb");
      var thead = document.createElement("thead");
      var hr = document.createElement("tr");
      [["#", ""], ["Name", ""], ["Score", "num"], ["Time", "num"]].forEach(function (h) {
        hr.appendChild(el("th", h[1], h[0]));
      });
      thead.appendChild(hr); tbl.appendChild(thead);
      var tb = document.createElement("tbody");
      var medals = { 1: "🥇", 2: "🥈", 3: "🥉" };
      rows.forEach(function (r) {
        var tr = document.createElement("tr");
        if (state.myRank === r.rank && r.name === state.name) { tr.className = "me"; }
        tr.appendChild(el("td", "", ""));
        tr.firstChild.appendChild(el("span", "medal", medals[r.rank] || String(r.rank)));
        tr.appendChild(el("td", "", r.name));
        tr.appendChild(el("td", "num", r.score + "/" + r.total));
        tr.appendChild(el("td", "num", P.fmtTime(r.duration_ms)));
        tb.appendChild(tr);
      });
      if (!rows.length) {
        var tr0 = document.createElement("tr");
        var td0 = el("td", "muted", "No finishers yet. Be the first!"); td0.colSpan = 4;
        tr0.appendChild(td0); tb.appendChild(tr0);
      }
      tbl.appendChild(tb); wrap.appendChild(tbl);
    }).catch(function () { /* keep last board on transient errors */ });
  }

  function onRetake() {
    clearInterval(state.lbTimer);
    clearSession();
    state.token = null; state.answers = {}; state.isTest = false;
    $("host-code").value = "";
    init();
  }

  /* ---------- boot ---------- */
  function init() {
    showError("");
    $("host-box").classList.toggle("hidden", !HOST_MODE);
    if (!window.QuizApi.isConfigured()) {
      show("register");
      $("reg-btn").disabled = true;
      return showError("This portal is not configured yet (see README, step 4).");
    }
    var saved = load();
    if (saved && saved.token) {
      state.token = saved.token; state.name = saved.name;
      return window.QuizApi.status(state.token).then(function (s) {
        if (s.state === "submitted") { return loadResult(); }
        if (s.state === "in_progress") { return onStart(); }
        showReady();
      }).catch(function (e) {
        clearSession(); state.token = null;
        if (e.code !== "invalid_token") { showError(e.message); }
        show("register");
      });
    }
    window.QuizApi.config().then(function (c) {
      state.cfg = c;
      $("reg-total").textContent = c.total_questions;
      $("reg-time").textContent = fmtClock(c.quiz_seconds);
      if (!c.quiz_open) { $("reg-btn").disabled = true; showError("The quiz is closed right now."); }
    }).catch(function (e) { showError(e.message); });
    show("register");
  }

  $("reg-form").addEventListener("submit", onRegister);
  $("retake-btn").addEventListener("click", onRetake);
  $("start-btn").addEventListener("click", onStart);
  $("submit-btn").addEventListener("click", function () { submit(false); });
  window.addEventListener("beforeunload", function (e) {
    if (state.timer && !state.submitting) { e.preventDefault(); e.returnValue = ""; }
  });
  init();
})();

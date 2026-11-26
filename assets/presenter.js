/* Big-screen view: live counters, live top-10, and a staged F1-style podium ceremony. */
(function () {
  "use strict";

  var $ = function (id) { return document.getElementById(id); };
  var P = window.QuizPodium;
  var el = P.el;
  var ceremonyRunning = false;
  var rows = [];

  function showErr(msg) { var e = $("err"); e.textContent = msg || ""; e.classList.toggle("hidden", !msg); }

  function renderTable(list) {
    var wrap = $("lb-wrap");
    wrap.textContent = "";
    var tbl = el("table", "lb");
    var thead = document.createElement("thead");
    var hr = document.createElement("tr");
    [["#", ""], ["Name", ""], ["Score", "num"], ["Time", "num"]].forEach(function (h) { hr.appendChild(el("th", h[1], h[0])); });
    thead.appendChild(hr); tbl.appendChild(thead);
    var tb = document.createElement("tbody");
    var medals = { 1: "🥇", 2: "🥈", 3: "🥉" };
    list.forEach(function (r) {
      var tr = document.createElement("tr");
      var c0 = el("td", ""); c0.appendChild(el("span", "medal", medals[r.rank] || String(r.rank)));
      tr.appendChild(c0);
      tr.appendChild(el("td", "", r.name));
      tr.appendChild(el("td", "num", r.score + "/" + r.total));
      tr.appendChild(el("td", "num", P.fmtTime(r.duration_ms)));
      tb.appendChild(tr);
    });
    if (!list.length) {
      var tr0 = document.createElement("tr");
      var td0 = el("td", "muted", "Waiting for the first finisher..."); td0.colSpan = 4;
      tr0.appendChild(td0); tb.appendChild(tr0);
    }
    tbl.appendChild(tb); wrap.appendChild(tbl);
  }

  function refresh() {
    Promise.all([window.QuizApi.stats(), window.QuizApi.leaderboard(10)]).then(function (res) {
      showErr("");
      $("c-reg").textContent = res[0].registered;
      $("c-start").textContent = res[0].started;
      $("c-done").textContent = res[0].completed;
      rows = res[1];
      renderTable(rows);
      if (!ceremonyRunning) { P.render($("podium"), rows, { hidden: false }); }
    }).catch(function (e) { showErr(e.message); });
  }

  function startCeremony() {
    if (ceremonyRunning) { return; }
    if (!rows.length) { return showErr("No finishers yet - wait for the leaderboard to fill."); }
    ceremonyRunning = true;
    $("btn-ceremony").disabled = true;
    // Freeze the standings used for the ceremony so the reveal cannot change mid-show.
    var frozen = rows.slice(0, 3);
    P.ceremony($("podium"), $("layer"), frozen, $("banner"), function () {
      $("btn-ceremony").disabled = false;
    });
  }

  function backToLive() {
    ceremonyRunning = false;
    $("btn-ceremony").disabled = false;
    $("banner").textContent = "Live standings";
    refresh();
  }

  $("btn-ceremony").addEventListener("click", startCeremony);
  $("btn-live").addEventListener("click", backToLive);

  if (!window.QuizApi.isConfigured()) { showErr("Not configured yet - see README, step 4."); }
  else { refresh(); setInterval(refresh, 4000); }
})();

/* Private host page: clear trial data and lock/unlock clearing. Every action needs the secret host code. */
(function () {
  "use strict";
  var $ = function (id) { return document.getElementById(id); };

  function hostAction(action, okMsg) {
    var code = $("host-code").value;
    if (!code) { $("host-msg").textContent = "Enter the host code first."; return; }
    $("host-msg").textContent = "Working...";
    window.QuizApi.hostReset(code, action).then(function (r) {
      $("host-msg").textContent = okMsg(r);
    }).catch(function (e) { $("host-msg").textContent = e.message; });
  }

  $("btn-clear").addEventListener("click", function () {
    if (!window.confirm("Delete ALL participants, results and leaderboard entries? This cannot be undone.")) { return; }
    hostAction("clear", function (r) { return "Cleared " + r.deleted + " participant(s). The board is empty."; });
  });
  $("btn-lock").addEventListener("click", function () {
    hostAction("lock", function () { return "Locked. Clearing is disabled until you unlock it."; });
  });
  $("btn-unlock").addEventListener("click", function () {
    hostAction("unlock", function () { return "Unlocked. Clearing is allowed again."; });
  });
})();

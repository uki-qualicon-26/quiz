/* Podium rendering and champagne celebration. All user text goes through textContent. */
(function () {
  "use strict";

  var reduceMotion = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  function el(tag, cls, text) {
    var n = document.createElement(tag);
    if (cls) { n.className = cls; }
    if (text !== undefined) { n.textContent = text; }
    return n;
  }

  function fmtTime(ms) {
    if (ms === null || ms === undefined) { return "-"; }
    return (ms / 1000).toFixed(1) + "s";
  }

  var SLOTS = {
    1: { cls: "p1", medal: "🥇", icon: "🏆", tag: "Pole position" },
    2: { cls: "p2", medal: "🥈", icon: "🏎️", tag: "So close" },
    3: { cls: "p3", medal: "🥉", icon: "🏁", tag: "On the podium" }
  };

  function buildStep(rank, row, hidden) {
    var slot = SLOTS[rank];
    var step = el("div", "podium-step " + slot.cls + (hidden ? " is-hidden" : ""));
    step.dataset.rank = String(rank);
    var driver = el("div", "podium-driver");
    driver.appendChild(el("div", "podium-icon", slot.icon));
    driver.appendChild(el("div", "podium-name", row ? row.name : "-"));
    driver.appendChild(el("div", "podium-score",
      row ? row.score + "/" + row.total + " in " + fmtTime(row.duration_ms) : "waiting for a finisher"));
    step.appendChild(driver);
    var block = el("div", "podium-block");
    block.appendChild(el("span", "podium-medal", slot.medal));
    block.appendChild(el("span", "podium-pos", "P" + rank));
    step.appendChild(block);
    return step;
  }

  /* rows: leaderboard array. opts.hidden: render steps hidden for a staged reveal. */
  function renderPodium(container, rows, opts) {
    var hidden = !!(opts && opts.hidden);
    container.textContent = "";
    var wrap = el("div", "podium");
    [2, 1, 3].forEach(function (r) { wrap.appendChild(buildStep(r, rows[r - 1], hidden)); });
    container.appendChild(wrap);
    return wrap;
  }

  var CONFETTI = ["🎉", "🍾", "🥂", "✨", "🏆", "🏎️", "💨", "🤖", "🎊"];

  function pop(layer, count, originX, originY) {
    if (reduceMotion || !layer.animate) { return; }
    for (var i = 0; i < count; i++) {
      var p = el("span", "confetti", CONFETTI[Math.floor(Math.random() * CONFETTI.length)]);
      p.style.left = originX + "%";
      p.style.top = originY + "%";
      p.style.fontSize = (18 + Math.random() * 22) + "px";
      layer.appendChild(p);
      var dx = (Math.random() - 0.5) * 70;     // vw
      var dy = -(25 + Math.random() * 55);     // vh up
      var rot = (Math.random() - 0.5) * 720;
      var anim = p.animate([
        { transform: "translate(0,0) rotate(0deg)", opacity: 1 },
        { transform: "translate(" + dx + "vw," + dy + "vh) rotate(" + rot + "deg)", opacity: 1, offset: 0.55 },
        { transform: "translate(" + (dx * 1.15) + "vw," + (dy + 70) + "vh) rotate(" + (rot * 1.4) + "deg)", opacity: 0 }
      ], { duration: 2200 + Math.random() * 1600, easing: "cubic-bezier(.2,.7,.3,1)", fill: "forwards" });
      anim.onfinish = (function (node) { return function () { node.remove(); }; })(p);
    }
  }

  /* Staged F1-style reveal: P3, P2, then P1 with a champagne spray. */
  function runCeremony(container, layer, rows, banner, onDone) {
    var wrap = renderPodium(container, rows, { hidden: true });
    var order = [3, 2, 1];
    var steps = {};
    wrap.querySelectorAll(".podium-step").forEach(function (s) { steps[s.dataset.rank] = s; });
    var delay = 0;
    banner.textContent = "🏎️💨  Drivers, start your engines...";
    order.forEach(function (rank, idx) {
      delay += idx === 0 ? 1400 : 2600;
      setTimeout(function () {
        if (!rows[rank - 1]) { return; }
        steps[rank].classList.remove("is-hidden");
        steps[rank].classList.add("is-rising");
        banner.textContent = rank === 1
          ? "🍾  AND THE WINNER IS..."
          : (rank === 3 ? "🥉  Third place" : "🥈  Second place");
        if (rank === 1) {
          setTimeout(function () {
            banner.textContent = "🏆  " + rows[0].name + " takes pole position! 🍾💥";
            steps[1].classList.add("is-winner");
            pop(layer, 70, 50, 70);
            setTimeout(function () { pop(layer, 50, 30, 75); }, 500);
            setTimeout(function () { pop(layer, 50, 70, 75); }, 900);
            if (onDone) { onDone(); }
          }, 1300);
        }
      }, delay);
    });
  }

  window.QuizPodium = { render: renderPodium, pop: pop, ceremony: runCeremony, fmtTime: fmtTime, el: el };
})();

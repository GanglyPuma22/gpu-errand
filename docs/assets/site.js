// GPU Errand site: copy button, cap calculator, pinned steps, entrances.
(function () {
  var doc = document.documentElement;
  doc.classList.add('js');
  var still = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  // Copy the install command.
  document.querySelectorAll('[data-copy]').forEach(function (btn) {
    btn.addEventListener('click', function () {
      var text = document.getElementById(btn.dataset.copy).textContent;
      var label = btn.textContent;
      var done = function () {
        btn.textContent = 'Copied';
        btn.classList.add('done');
        setTimeout(function () { btn.textContent = label; btn.classList.remove('done'); }, 1600);
      };
      if (navigator.clipboard) navigator.clipboard.writeText(text).then(done, function () {});
    });
  });

  // The cap calculator: the same arithmetic the runner uses.
  var form = document.querySelector('.calc-form');
  if (form) {
    var units = document.getElementById('units');
    var mins = document.getElementById('mins');
    var out = document.getElementById('calc-result');
    var fmt = function (s) {
      s = Math.round(s);
      var h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), r = s % 60;
      if (h) return h + ' h ' + m + ' min';
      if (!m) return r + ' s';
      return r ? m + ' min ' + r + ' s' : m + ' min';
    };
    var names = { '1.07': 'T4', '1.54': 'L4', '5.3': 'A100' };
    var update = function () {
      var rateKey = form.querySelector('input[name=gpu]:checked').value;
      var rate = parseFloat(rateKey), u = parseFloat(units.value), m = parseInt(mins.value, 10);
      document.getElementById('units-out').textContent = u.toFixed(2).replace(/0$/, '');
      document.getElementById('mins-out').textContent = m;
      var byUnits = u / rate * 3600, byTime = (m + 20) * 60;
      var cap = Math.min(byUnits, byTime);
      var spend = rate * cap / 3600;
      var cents = Math.max(1, Math.round(spend * 10));
      out.innerHTML = 'On ' + (names[rateKey] === 'T4' ? 'a ' : 'an ') + names[rateKey] + ' at ' + rate + ' units an hour, the runtime is stopped after <b>' + fmt(cap) +
        '</b>, by the ' + (byUnits <= byTime ? 'unit cap' : 'time cap (' + m + ' min + 20)') +
        '. It can spend at most ' + (Math.round(spend * 100) / 100) + (Math.round(spend * 100) === 100 ? ' unit' : ' units') + ', about ' + cents + (cents === 1 ? ' cent.' : ' cents.');
    };
    form.addEventListener('input', update);
    update();
  }

  // Pinned steps: the stage shows the fragment of the step in view.
  var stage = document.querySelector('.stage');
  var steps = Array.prototype.slice.call(document.querySelectorAll('.step'));
  if (stage && steps.length) {
    var frags = steps.map(function (step) {
      var f = step.querySelector('.frag').cloneNode(true);
      f.className = 'stage-frag';
      stage.appendChild(f);
      return f;
    });
    var show = function (i) {
      steps.forEach(function (s, j) { s.classList.toggle('active', i === j); });
      frags.forEach(function (f, j) { f.classList.toggle('on', i === j); });
    };
    show(0);
    // A thin band across the middle of the viewport, in pixels from its height.
    var io, watch = function () {
      if (io) io.disconnect();
      var band = Math.round(window.innerHeight * 0.45) + 'px';
      io = new IntersectionObserver(function (entries) {
        entries.forEach(function (e) { if (e.isIntersecting) show(steps.indexOf(e.target)); });
      }, { rootMargin: '-' + band + ' 0px -' + band + ' 0px' });
      steps.forEach(function (s) { io.observe(s); });
    };
    watch();
    var lastH = window.innerHeight;
    window.addEventListener('resize', function () {
      if (window.innerHeight !== lastH) { lastH = window.innerHeight; watch(); }
    });
  }

  // Entrances, once per element.
  var risers = document.querySelectorAll('[data-rise]');
  if ('IntersectionObserver' in window) {
    var seen = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (!e.isIntersecting) return;
        var el = e.target, group = el.parentElement.querySelectorAll('[data-rise]');
        var i = Array.prototype.indexOf.call(group, el);
        setTimeout(function () { el.classList.add('in'); }, still ? 0 : Math.max(0, i) * 80);
        seen.unobserve(el);
      });
    }, { rootMargin: '0px 0px -8% 0px' });
    risers.forEach(function (el) { seen.observe(el); });
  } else {
    risers.forEach(function (el) { el.classList.add('in'); });
  }

  // The receipt prints line by line, once.
  var slip = document.querySelector('.slip');
  if (slip && !still) {
    var lines = slip.querySelectorAll('li');
    slip.classList.add('printing');
    lines.forEach(function (li, i) {
      setTimeout(function () { li.classList.add('out'); }, 500 + i * 110);
    });
  }
})();

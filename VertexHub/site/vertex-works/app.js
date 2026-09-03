(() => {
  const header = document.querySelector('.topbar');
  const onScroll = () => {
    const y = window.scrollY || 0;
    header.style.background = y > 40 ? 'rgba(8,10,13,.92)' : 'rgba(8,10,13,.72)';
  };
  onScroll();
  window.addEventListener('scroll', onScroll, { passive: true });

  document.querySelectorAll('.facility-grid article').forEach((el, i) => {
    el.style.animationDelay = `${i * 70}ms`;
  });

  const counter = document.getElementById('visitorCount');
  if (counter) {
    fetch('./counter.php', {
      method: 'POST',
      headers: { 'Accept': 'application/json' },
      cache: 'no-store'
    })
      .then(r => {
        if (!r.ok) throw new Error(`counter ${r.status}`);
        return r.json();
      })
      .then(data => {
        const n = Number(data.count);
        counter.textContent = Number.isFinite(n)
          ? Math.max(0, Math.trunc(n)).toString().padStart(7, '0')
          : '-------';
      })
      .catch(() => {
        counter.textContent = 'OFFLINE';
      });
  }
})();

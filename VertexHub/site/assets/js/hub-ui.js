(() => {
  const el = document.querySelector("[data-clock]");
  const tick = () => {
    if (el) el.textContent = new Date().toLocaleString("ja-JP",{hour12:false});
  };
  tick(); setInterval(tick,1000);
})();

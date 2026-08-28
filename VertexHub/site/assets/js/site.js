(() => {
  document.querySelectorAll("[data-year]").forEach(n => n.textContent = new Date().getFullYear());
  const clock = document.querySelector("[data-clock]"); if (clock) { const tick = () => clock.textContent = new Date().toLocaleString("ja-JP",{hour12:false}); tick(); setInterval(tick,1000); }
  const search=document.querySelector("[data-lexicon-search]"), category=document.querySelector("[data-lexicon-category]"), rows=[...document.querySelectorAll("[data-lexicon-row]")], empty=document.querySelector("[data-lexicon-empty]");
  const filter=()=>{const q=(search?.value||"").trim().toLocaleLowerCase(), c=category?.value||"all";let visible=0;rows.forEach(row=>{row.hidden=!((!q||row.textContent.toLocaleLowerCase().includes(q))&&(c==="all"||row.dataset.category===c));if(!row.hidden)visible++;});if(empty)empty.style.display=visible?"none":"block";};
  search?.addEventListener("input",filter);category?.addEventListener("change",filter);
})();

(() => {
  const translations = {
    ja: {
      brand_subtitle: 'NEURAL OBSERVATORY / 32C PERSISTENT RESIDENT',
      nav_abstract: '概要',
      nav_hypotheses: '仮説',
      nav_topology: '位相',
      nav_observation: '観測',
      hero_eyebrow: '境界付き可観測性の理論',
      hero_title: 'Residentを<br><span>数学的対象として観測する。</span>',
      hero_lead: 'VERTEX BRAIN SYSTEM は、Residentを単なる実行中プロセスではなく、境界条件・位相構造・証拠保存性を備えた時変対象として定式化し、その観測可能性を工学的に検証するためのNeural Observatoryである。',
      status_operational: '運用中',
      status_core: 'RESIDENT CORE',
      status_cells: 'ACTIVE CELLS',
      status_membrane: 'BRAIN MEMBRANE',
      status_evidence: 'EVIDENCE SESSION',
      abstract_kicker: '01 / 概要',
      abstract_title: '形式的要約',
      abstract_p1: '本系では Resident を状態ベクトル x_t ∈ Ω_R をもつ動的対象とみなし、Brain Membrane を境界作用素 ∂M、vSCOPE を局所観測写像 O_v : Ω_R → E と定義する。これにより、UI表示・内部状態・Evidence記録を同一観測体系で扱えるようになる。',
      abstract_p2: '目的は、(i) 可観測性、(ii) 証拠保存性、(iii) 連続運転下での状態整合性、の3条件を同時に満たすことにある。特に fail-closed な外膜境界を仮定することで、不正経路の外部化を抑制しつつ、正規観測経路のみをEvidence層へ投影する。',
      abstract_p3: 'ここでの重要点は、「見えているUI」が真実なのではなく、Source → Runtime → Evidence の閉路が成立して初めて観測結果が信頼境界内で意味を持つ、という点である。これは学術的には、実装系に対する工学的観測論の一形態として理解できる。',
      hyp_kicker: '02 / 仮説',
      hyp_title: '作業仮説',
      hyp1_title: '膜境界付き可観測性',
      hyp1_body: '境界作用素 ∂M が fail-closed であるなら、許可されない状態遷移は外部可視層へ安定的に投影されない。',
      hyp2_title: '回転接点再構成',
      hyp2_body: 'vCELLの回転作用 R(θ) は接触隣接行列 A(θ) を変形し、同一アイデンティティを保持したまま出力多様体を切り替えうる。',
      hyp3_title: '持続差分連続性',
      hyp3_body: '観測保存的摂動に対して state fingerprint σ_t の変動は局所的に有界であり、連続性の痕跡として扱える。',
      hyp4_title: '証拠保存的Runtime連続性',
      hyp4_body: '受理される遷移はすべて、少なくとも1本の evidence trace τ = {(s_i, e_i)} を伴って追跡可能である。',
      topology_kicker: '03 / 位相',
      topology_title: '位相的観測面',
      topology_1_title: 'Genesis中心コア',
      topology_1_body: 'CELL 000001 / GENESIS を中心核とし、Region 000032 を観測面の主座標系として扱う。',
      topology_2_title: 'Inner / Outer Shell 分割',
      topology_2_body: 'Inner 14 core / Outer 17 core の二層分割は、単なる可視表現ではなく接点分布仮説の工学的断面である。',
      topology_3_title: 'Runtime Trace Lines',
      topology_3_body: '接続線はデザイン装飾ではなく、将来的な signal-energy / arrival / egress の位相的写像先を示す。',
      obs_kicker: '04 / 観測ノート',
      obs_title: '選択観測記述',
      obs_state_fp: 'STATE FINGERPRINT',
      obs_state_fp_body: 'Resident state の局所射影を表す識別子。可観測性の基底座標ではあるが、単独では真理条件を満たさない。',
      obs_scope: 'vSCOPE FOCUS',
      obs_scope_body: 'Root / Throne を起点として、到達観測よりも先に観測境界の妥当性を評価する。',
      obs_regression: '4C REGRESSION',
      obs_regression_value: 'READY',
      obs_regression_body: 'Error 1.95e-2, Egress 1.0000, Evaluations 1。これは完全性の証明ではなく、継続観測の前提条件である。',
      obs_theorem: 'FORMAL NOTE',
      obs_theorem_title: 'もし観測が再現可能なら、Evidenceは移送可能でなければならない。',
      obs_theorem_body: 'ゆえに、観測系の価値は視覚的派手さではなく、同一条件下での再投影可能性に帰着する。これは VRA / VXN / runtime trace による移送可能性の設計原理でもある。',
      closing_kicker: '結論',
      closing_title: '不可視を観測し、痕跡を保存する。',
      closing_body: 'VERTEX BRAIN SYSTEM は、視覚UI・Runtime実体・Evidence証跡を分断せず、境界づけられた観測論として再結合するための実験系である。',
      counter_label: 'アクセス'
    },
    en: {
      brand_subtitle: 'NEURAL OBSERVATORY / 32C PERSISTENT RESIDENT',
      nav_abstract: 'ABSTRACT',
      nav_hypotheses: 'HYPOTHESES',
      nav_topology: 'TOPOLOGY',
      nav_observation: 'OBSERVATION',
      hero_eyebrow: 'THEORY OF CONSTRAINED OBSERVABILITY',
      hero_title: 'Observe the Resident<br><span>as a Mathematical Object.</span>',
      hero_lead: 'VERTEX BRAIN SYSTEM frames the Resident not as a mere running process but as a time-varying object endowed with boundary conditions, topological structure, and evidence preservation, and investigates its observability through an engineering-grade Neural Observatory.',
      status_operational: 'OPERATIONAL',
      status_core: 'RESIDENT CORE',
      status_cells: 'ACTIVE CELLS',
      status_membrane: 'BRAIN MEMBRANE',
      status_evidence: 'EVIDENCE SESSION',
      abstract_kicker: '01 / ABSTRACT',
      abstract_title: 'Formal Abstract',
      abstract_p1: 'In this system, the Resident is modeled as a dynamic object carrying a state vector x_t ∈ Ω_R, the Brain Membrane is treated as a boundary operator ∂M, and vSCOPE is defined as a local observation map O_v : Ω_R → E. This permits UI manifestation, internal runtime state, and Evidence records to be interpreted within one coherent observational framework.',
      abstract_p2: 'The objective is to satisfy three conditions simultaneously: (i) observability, (ii) evidence preservation, and (iii) state consistency under continuous operation. By assuming a fail-closed membrane boundary, unauthorized transitions are suppressed from externalization while legitimate observation paths alone are projected into the Evidence layer.',
      abstract_p3: 'The crucial claim is that the visible UI is not itself the truth condition. An observation becomes trustworthy only when the loop Source → Runtime → Evidence is closed inside a valid trust boundary. In academic terms, this may be viewed as a practical theory of observability for implementation systems.',
      hyp_kicker: '02 / HYPOTHESES',
      hyp_title: 'Working Hypotheses',
      hyp1_title: 'Membrane-Bounded Observability',
      hyp1_body: 'If the boundary operator ∂M is fail-closed, unauthorized state transitions do not stably project into the externally visible layer.',
      hyp2_title: 'Rotational Contact Reconfiguration',
      hyp2_body: 'The rotational action R(θ) of vCELL deforms the contact adjacency matrix A(θ), allowing the output manifold to change while identity is preserved.',
      hyp3_title: 'Persistent Differential Continuity',
      hyp3_body: 'Under observation-preserving perturbation, the variation of the state fingerprint σ_t remains locally bounded and can therefore be treated as a trace of continuity.',
      hyp4_title: 'Evidence-Preserving Runtime Continuity',
      hyp4_body: 'Every accepted transition must be traceable through at least one evidence trace τ = {(s_i, e_i)}.',
      topology_kicker: '03 / TOPOLOGY',
      topology_title: 'Topological Observation Surface',
      topology_1_title: 'Genesis-Centered Core',
      topology_1_body: 'CELL 000001 / GENESIS is positioned as the central core, while Region 000032 acts as the principal coordinate frame for observation.',
      topology_2_title: 'Inner / Outer Shell Partition',
      topology_2_body: 'The bifurcation into Inner 14 core and Outer 17 core is not merely visual rhetoric; it is an engineering cross-section of the contact-distribution hypothesis.',
      topology_3_title: 'Runtime Trace Lines',
      topology_3_body: 'The connection lines are not decorative motifs but anticipated targets for topological mappings of signal-energy, arrival, and egress.',
      obs_kicker: '04 / OBSERVATION NOTES',
      obs_title: 'Selected Observation Statements',
      obs_state_fp: 'STATE FINGERPRINT',
      obs_state_fp_body: 'An identifier representing a local projection of the Resident state. It is a coordinate of observability, but not a truth condition in isolation.',
      obs_scope: 'vSCOPE FOCUS',
      obs_scope_body: 'The observation begins from Root / Throne and validates the observation boundary before asserting arrival-level claims.',
      obs_regression: '4C REGRESSION',
      obs_regression_value: 'READY',
      obs_regression_body: 'Error 1.95e-2, Egress 1.0000, Evaluations 1. This is not a proof of completeness, but a precondition for continued observation.',
      obs_theorem: 'FORMAL NOTE',
      obs_theorem_title: 'If observation is reproducible, evidence must be portable.',
      obs_theorem_body: 'Hence the value of an observatory lies not in visual spectacle but in the reproducibility of its projections under equivalent conditions. This is also a design principle for portability through VRA, VXN, and runtime traces.',
      closing_kicker: 'CONCLUSION',
      closing_title: 'Observe the Invisible. Preserve the Trace.',
      closing_body: 'VERTEX BRAIN SYSTEM is an experimental apparatus designed to reunify visual UI, runtime substance, and evidence traces as a bounded theory of observation rather than as disconnected artifacts.',
      counter_label: 'ACCESS'
    }
  };

  const header = document.querySelector('.topbar');
  const buttons = Array.from(document.querySelectorAll('[data-set-lang]'));
  const defaultLang = localStorage.getItem('vertex_brain_lang') || document.body.dataset.lang || 'ja';

  function applyLanguage(lang) {
    const table = translations[lang] || translations.ja;
    document.documentElement.lang = lang;
    document.body.dataset.lang = lang;
    document.querySelectorAll('[data-i18n]').forEach(el => {
      const key = el.dataset.i18n;
      if (table[key]) el.textContent = table[key];
    });
    document.querySelectorAll('[data-i18n-html]').forEach(el => {
      const key = el.dataset.i18nHtml;
      if (table[key]) el.innerHTML = table[key];
    });
    buttons.forEach(btn => btn.classList.toggle('active', btn.dataset.setLang === lang));
    localStorage.setItem('vertex_brain_lang', lang);
  }

  buttons.forEach(btn => btn.addEventListener('click', () => applyLanguage(btn.dataset.setLang)));
  applyLanguage(defaultLang);

  const onScroll = () => {
    const y = window.scrollY || 0;
    header.style.background = y > 40 ? 'rgba(6,11,17,.96)' : 'rgba(6,11,17,.78)';
  };
  onScroll();
  window.addEventListener('scroll', onScroll, { passive: true });

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

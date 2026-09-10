// Renders markdown into #doc, keeps scroll position across re-renders, reports the outline to Swift.
(function () {
  const WEB = location.href.replace(/[^/]*$/, '');   // <base> is retargeted to the .md folder later
  const md = window.markdownit({
    html: true, linkify: true, typographer: true,
    highlight(str, lang) {
      if (lang === 'mermaid') return '<pre class="mermaid">' + md.utils.escapeHtml(str) + '</pre>';
      if (lang && hljs.getLanguage(lang)) {
        try { return '<pre class="hl"><code class="hljs language-' + lang + '">' + hljs.highlight(str, { language: lang, ignoreIllegals: true }).value + '</code></pre>'; } catch (_) {}
      }
      return '<pre class="hl"><code class="hljs">' + md.utils.escapeHtml(str) + '</code></pre>';
    }
  });

  md.use(window.markdownitFootnote);
  md.renderer.rules.table_open = () => '<div class="tbl"><table>';
  md.renderer.rules.table_close = () => '</table></div>';

  // task lists: "- [ ] x" / "- [x] y"
  md.core.ruler.after('inline', 'task-list', state => {
    const t = state.tokens;
    for (let i = 2; i < t.length; i++) {
      if (t[i].type !== 'inline' || t[i - 1].type !== 'paragraph_open' || t[i - 2].type !== 'list_item_open') continue;
      const c = t[i].children;
      if (!c || !c.length || c[0].type !== 'text') continue;
      const m = /^\[([ xX])\]\s+/.exec(c[0].content);
      if (!m) continue;
      c[0].content = c[0].content.slice(m[0].length);
      const box = new state.Token('html_inline', '', 0);
      box.content = '<input type="checkbox" disabled' + (m[1] === ' ' ? '' : ' checked') + '> ';
      c.unshift(box);
      t[i - 2].attrJoin('class', 'task');
    }
  });

  // heading ids + outline
  let outline = [];
  const slug = s => s.toLowerCase().replace(/[^\p{L}\p{N}]+/gu, '-').replace(/^-+|-+$/g, '') || 'h';
  md.core.ruler.push('heading-ids', state => {
    outline = []; const seen = {};
    const t = state.tokens;
    for (let i = 0; i < t.length; i++) {
      if (t[i].type !== 'heading_open') continue;
      const text = t[i + 1].children.filter(x => x.type === 'text' || x.type === 'code_inline').map(x => x.content).join('');
      let id = slug(text); if (seen[id]) id += '-' + (++seen[id]); else seen[id] = 1;
      t[i].attrSet('id', id);
      outline.push({ id, level: +t[i].tag[1], text });
    }
  });

  // in-page anchors scroll here (a <base> is set, so "#id" would otherwise resolve to the folder)
  document.addEventListener('click', e => {
    const a = e.target.closest('a[href^="#"]'); if (!a) return;
    e.preventDefault(); window.goto(decodeURIComponent(a.getAttribute('href').slice(1)));
  });

  const doc = document.getElementById('doc');
  const post = (name, body) => { try { window.webkit.messageHandlers[name].postMessage(body); } catch (_) {} };
  addEventListener('error', e => post('error', e.message + ' @' + (e.filename || '').split('/').pop() + ':' + e.lineno));

  let base = null;
  window.setBase = href => {
    let b = document.querySelector('base');
    if (!b) { b = document.createElement('base'); document.head.appendChild(b); }
    b.href = href; base = href;
  };

  window.render = function (src) {
    const y = window.scrollY, atBottom = y + innerHeight >= document.body.scrollHeight - 4;
    if (/^---\n/.test(src)) { const e = src.indexOf('\n---', 3); if (e > 0) src = src.slice(e + 4); }
    // html:true keeps <details>, <kbd>, sized <img>; DOMPurify drops scripts, handlers and javascript: URIs
    const html = DOMPurify.sanitize(md.render(src), { ADD_ATTR: ['disabled', 'checked'] });
    doc.style.minHeight = document.body.scrollHeight + 'px';
    Idiomorph.morph(doc, html, { morphStyle: 'innerHTML' });
    renderMermaid();
    doc.querySelectorAll('pre.hl').forEach(p => {
      const b = document.createElement('button'); b.className = 'copy'; b.textContent = 'copy';
      b.onclick = () => { navigator.clipboard.writeText(p.querySelector('code').innerText); b.textContent = 'ok'; setTimeout(() => b.textContent = 'copy', 900); };
      p.appendChild(b);
    });
    requestAnimationFrame(() => { window.scrollTo(0, atBottom && y > 0 ? document.body.scrollHeight : y); doc.style.minHeight = ''; });
    post('outline', outline);
    document.querySelectorAll('.md h1').length === 1 && post('title', document.querySelector('.md h1').textContent);
  };

  let mermaidLoading = null;
  function renderMermaid() {
    const nodes = doc.querySelectorAll('pre.mermaid:not([data-processed])');
    if (!nodes.length) return;
    if (!window.mermaid && !mermaidLoading) {
      mermaidLoading = new Promise(res => { const s = document.createElement('script'); s.src = WEB + 'mermaid.min.js'; s.onload = res; s.onerror = () => post('error', 'mermaid.min.js failed to load'); document.head.appendChild(s); });
    }
    (mermaidLoading || Promise.resolve()).then(() => {
      const dark = matchMedia('(prefers-color-scheme: dark)').matches;
      mermaid.initialize({ startOnLoad: false, theme: dark ? 'dark' : 'neutral', fontFamily: 'inherit' });
      mermaid.run({ nodes }).catch(e => post('error', 'mermaid: ' + (e.message || e)));
    });
  }

  window.goto = id => { const el = document.getElementById(id); if (el) el.scrollIntoView({ block: 'start', behavior: 'smooth' }); };
  window.setFont = f => { document.body.dataset.font = f; };
  window.setSize = px => { document.documentElement.style.setProperty('--fs', px + 'px'); };
  window.setWidth = ch => { document.documentElement.style.setProperty('--measure', ch + 'ch'); };

  // current heading for the outline highlight
  let ticking = false;
  addEventListener('scroll', () => {
    if (ticking) return; ticking = true;
    requestAnimationFrame(() => {
      ticking = false;
      const hs = doc.querySelectorAll('h1,h2,h3,h4'); let cur = null;
      for (const h of hs) { if (h.getBoundingClientRect().top <= 80) cur = h.id; else break; }
      post('active', cur || '');
    });
  }, { passive: true });

  post('ready', true);
})();

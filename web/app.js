function escapeHtml(str) {
  if (str === null || str === undefined) return '';
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function asArray(val) {
  if (val === null || val === undefined) return [];
  const arr = Array.isArray(val) ? val : [val];
  return arr.filter(item => {
    if (item === null || item === undefined) return false;
    if (typeof item === 'object' && Object.keys(item).length === 0) return false;
    return true;
  });
}

function buildQuestionParagraph(q, isMobile = false) {
  if (!q) return '';

  const steps = asArray(q.steps);
  const cast = asArray(q.cast);
  const tracks = asArray(q.tracks);

  let html = '';

  if (q.text) {
    html += `<div>${escapeHtml(q.text).replace(/\n/g, '<br/>')}</div>`;
  } else {
    const parts = [];
    if (q.clue1) parts.push(q.clue1);
    if (q.clue2) parts.push(q.clue2);
    if (parts.length > 0) {
      html += `<div>${escapeHtml(parts.join(' '))}</div>`;
    }
  }

  // 1. Vanna White Letter Board (Fill in the Blank)
  if (q.puzzleBoard) {
    const words = String(q.puzzleBoard).split('/');
    const tileFontSize = isMobile ? '1.35rem' : '2.85rem';
    const catFontSize = isMobile ? '1.15rem' : '2rem';
    const wordGap = isMobile ? '1.25rem' : '2.75rem';
    const wordsHtml = words.map(w => `
      <span style="display:inline-block; letter-spacing:0.22em; font-family:monospace; font-weight:700; font-size:${tileFontSize}; color:var(--text);">
        ${escapeHtml(w.trim())}
      </span>
    `).join(`<span style="display:inline-block; width:${wordGap};"></span>`);

    html += `
      <div style="margin:${html ? '1.25rem' : '0.25rem'} 0;">
        <div style="font-family:var(--font-serif); font-size:${catFontSize}; color:var(--accent); margin-bottom:1rem;">
          Category: ${escapeHtml(q.category)}
        </div>
        <div style="padding:1.5rem 0; border-top:1px solid var(--border); border-bottom:1px solid var(--border);">
          ${wordsHtml}
        </div>
      </div>
    `;
  }

  // 2. Step-by-step lists (e.g., Calculator Math)
  if (steps.length > 0) {
    const fontSize = isMobile ? '1.05rem' : '1.65rem';
    const itemsHtml = steps.map(s => `
      <li style="margin-bottom:0.55rem; padding-left:0.35rem;">
        ${escapeHtml(s)}
      </li>
    `).join('');
    html += `
      <ol style="margin-top:${html ? '1.25rem' : '0'}; padding-left:1.5rem; font-size:${fontSize}; line-height:1.45;">
        ${itemsHtml}
      </ol>
    `;
  }

  // 3. Movie Cast & Release Year
  if (cast.length > 0 || q.releaseYear) {
    const castSize = isMobile ? '1.25rem' : '2.35rem';
    const yearSize = isMobile ? '1rem' : '1.4rem';
    html += `
      <div style="margin-top:${html ? '1rem' : '0'};">
        ${q.releaseYear ? `<div class="meta-line" style="font-size:${yearSize}; color:var(--accent); margin-bottom:0.65rem;">Released in ${escapeHtml(q.releaseYear)}</div>` : ''}
        <div style="font-family:var(--font-serif); font-size:${castSize}; line-height:1.35;">
          ${cast.map(actor => escapeHtml(actor)).join(' &nbsp;·&nbsp; ')}
        </div>
      </div>
    `;
  }

  // 4. Who Charted? Tracklist
  if (tracks.length > 0) {
    const trackSize = isMobile ? '1.2rem' : '2.2rem';
    const itemsHtml = tracks.map(t => `
      <div style="margin-bottom:0.5rem; font-family:var(--font-serif); font-size:${trackSize};">
        “${escapeHtml(t)}”
      </div>
    `).join('');
    html += `
      <div style="margin-top:${html ? '1rem' : '0'};">
        <div class="meta-line" style="color:var(--accent); margin-bottom:0.65rem;">Charting Tracks</div>
        ${itemsHtml}
      </div>
    `;
  }

  return html;
}

async function postJson(url, data) {
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(data),
    cache: 'no-store'
  });
  const payload = await res.json();
  if (!res.ok) {
    throw new Error(payload.error || 'Request failed');
  }
  return payload;
}

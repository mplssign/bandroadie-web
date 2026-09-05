const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const OUT = '/sessions/magical-admiring-heisenberg/mnt/outputs';
const DEST = '/sessions/magical-admiring-heisenberg/mnt/BandRoadie/src';

// Ensure destination exists
try { fs.mkdirSync(path.join(DEST, 'app_store_screenshots'), { recursive: true }); } catch(e) {}

// ── Shared helpers ──────────────────────────────────────────────────────────
const W = 390, H = 844;

function dot_pattern() {
  return `<defs>
    <pattern id="dots" x="0" y="0" width="20" height="20" patternUnits="userSpaceOnUse">
      <circle cx="1" cy="1" r="1" fill="rgba(255,255,255,0.04)"/>
    </pattern>
  </defs>
  <rect width="${W}" height="${H}" fill="url(#dots)"/>`;
}

function phone_start(x, y, w, tilt, id) {
  const h = Math.round(w * 550 / 260);
  const cx = x, cy = y;
  return `<g transform="translate(${cx},${cy}) rotate(${tilt}, ${w/2}, ${h/2})">
    <!-- phone shadow -->
    <rect x="2" y="6" width="${w}" height="${h}" rx="${Math.round(w*36/260)}" fill="rgba(0,0,0,0.7)" filter="url(#shadow_${id})"/>
    <!-- phone bezel -->
    <rect width="${w}" height="${h}" rx="${Math.round(w*36/260)}" fill="#18181B" stroke="#3f3f46" stroke-width="1.5"/>
    <!-- dynamic island -->
    <rect x="${w/2-30}" y="8" width="60" height="18" rx="9" fill="#09090B"/>
    <!-- screen clip -->
    <clipPath id="screen_${id}">
      <rect x="2" y="2" width="${w-4}" height="${h-4}" rx="${Math.round(w*34/260)}"/>
    </clipPath>
    <g clip-path="url(#screen_${id})">`;
}

function phone_end(w, tilt, id) {
  const h = Math.round(w * 550 / 260);
  return `    </g>
    <!-- bezel overlay top -->
    <rect x="${w/2-30}" y="8" width="60" height="18" rx="9" fill="#09090B"/>
  </g>`;
}

function shadow_filter(id) {
  return `<filter id="shadow_${id}" x="-20%" y="-10%" width="140%" height="130%">
    <feDropShadow dx="0" dy="8" stdDeviation="16" flood-color="#000000" flood-opacity="0.8"/>
  </filter>`;
}

function bg_glow(cx, cy, color, opacity=0.18) {
  return `<radialGradient id="glow" cx="${cx}" cy="${cy}" r="50%" gradientUnits="objectBoundingBox">
    <stop offset="0%" stop-color="${color}" stop-opacity="${opacity}"/>
    <stop offset="100%" stop-color="${color}" stop-opacity="0"/>
  </radialGradient>
  <rect width="${W}" height="${H}" fill="url(#glow)"/>`;
}

function text_block(label, headline_line1, headline_line2, sub, y_start=680) {
  return `<!-- label pill -->
  <rect x="28" y="${y_start}" width="${label.length*8+24}" height="26" rx="4" fill="#BE123C"/>
  <text x="40" y="${y_start+17}" font-family="Inter" font-size="11" font-weight="800" fill="#FFFFFF" letter-spacing="1">${label.toUpperCase()}</text>
  <!-- headline -->
  <text x="28" y="${y_start+60}" font-family="Inter" font-size="48" font-weight="900" fill="#FFFFFF">${headline_line1}</text>
  <text x="28" y="${y_start+112}" font-family="Inter" font-size="48" font-weight="900" fill="#FFFFFF">${headline_line2}</text>
  <!-- subtext -->
  ${wrap_text(sub, 28, y_start+136, 334, 13, '#a1a1aa')}`;
}

function wrap_text(text, x, y, maxW, size, fill) {
  // Simple wrap at ~50 chars
  const words = text.split(' ');
  let lines = [], line = '';
  for (const w of words) {
    const test = line ? line + ' ' + w : w;
    if (test.length * size * 0.55 > maxW) {
      lines.push(line);
      line = w;
    } else {
      line = test;
    }
  }
  if (line) lines.push(line);
  return lines.map((l, i) =>
    `<text x="${x}" y="${y + i * (size + 5)}" font-family="Inter" font-size="${size}" font-weight="400" fill="${fill}">${l}</text>`
  ).join('\n');
}

function svg_wrap(defs_content, body_content) {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}">
<defs>
${defs_content}
</defs>
${body_content}
</svg>`;
}

// ── SLIDE 1 — DASHBOARD ─────────────────────────────────────────────────────
function slide_dashboard() {
  const PW = 240, id = 'dash';
  const PH = Math.round(PW * 550 / 260);
  const PX = (W - PW) / 2 - 15;
  const PY = -10;

  const defs = `
  ${shadow_filter(id)}
  <linearGradient id="gigGrad" x1="0%" y1="0%" x2="100%" y2="0%">
    <stop offset="0%" stop-color="#1d1d21"/>
    <stop offset="100%" stop-color="#1a1020"/>
  </linearGradient>
  <radialGradient id="glow" cx="20%" cy="100%" r="55%" gradientUnits="objectBoundingBox">
    <stop offset="0%" stop-color="#BE123C" stop-opacity="0.18"/>
    <stop offset="100%" stop-color="#BE123C" stop-opacity="0"/>
  </radialGradient>`;

  const screen = `
      <!-- Screen bg -->
      <rect width="${PW}" height="${PH}" fill="#09090B"/>
      <!-- Status bar -->
      <text x="16" y="32" font-family="Inter" font-size="10" font-weight="600" fill="#a1a1aa">9:41</text>
      <!-- Header -->
      <text x="16" y="62" font-family="Inter" font-size="17" font-weight="700" fill="#f4f4f5">Good evening, Tony</text>
      <text x="16" y="76" font-family="Inter" font-size="11" fill="#71717a">The Midnight Echoes</text>
      <!-- Next gig card -->
      <rect x="12" y="86" width="216" height="72" rx="12" fill="url(#gigGrad)" stroke="#27272a" stroke-width="1"/>
      <text x="24" y="104" font-family="Inter" font-size="8" font-weight="700" fill="#BE123C" letter-spacing="0.5">NEXT GIG</text>
      <text x="24" y="120" font-family="Inter" font-size="13" font-weight="700" fill="#f4f4f5">The Bowery Electric</text>
      <text x="24" y="134" font-family="Inter" font-size="10" fill="#a1a1aa">Fri, May 16 · 9:00 PM</text>
      <rect x="168" y="100" width="50" height="20" rx="5" fill="#BE123C"/>
      <text x="177" y="114" font-family="Inter" font-size="9" font-weight="600" fill="#fff">Details</text>
      <!-- Availability -->
      <text x="16" y="176" font-family="Inter" font-size="10" font-weight="600" fill="#71717a" letter-spacing="0.5">AVAILABILITY</text>
      <!-- Member chips -->
      <rect x="12" y="184" width="46" height="46" rx="10" fill="#1c1c1f"/>
      <circle cx="35" cy="202" r="12" fill="#3f3f46"/>
      <text x="29" y="206" font-family="Inter" font-size="9" font-weight="600" fill="#d4d4d8">TH</text>
      <text x="25" y="222" font-family="Inter" font-size="8" font-weight="600" fill="#22c55e">✓ Free</text>
      <rect x="64" y="184" width="46" height="46" rx="10" fill="#1c1c1f"/>
      <circle cx="87" cy="202" r="12" fill="#3f3f46"/>
      <text x="81" y="206" font-family="Inter" font-size="9" font-weight="600" fill="#d4d4d8">MK</text>
      <text x="74" y="222" font-family="Inter" font-size="8" font-weight="600" fill="#22c55e">✓ Free</text>
      <rect x="116" y="184" width="46" height="46" rx="10" fill="#1c1c1f"/>
      <circle cx="139" cy="202" r="12" fill="#3f3f46"/>
      <text x="133" y="206" font-family="Inter" font-size="9" font-weight="600" fill="#d4d4d8">JR</text>
      <text x="126" y="222" font-family="Inter" font-size="8" font-weight="600" fill="#ef4444">✗ Busy</text>
      <rect x="168" y="184" width="46" height="46" rx="10" fill="#1c1c1f"/>
      <circle cx="191" cy="202" r="12" fill="#3f3f46"/>
      <text x="185" y="206" font-family="Inter" font-size="9" font-weight="600" fill="#d4d4d8">AL</text>
      <text x="178" y="222" font-family="Inter" font-size="8" font-weight="600" fill="#22c55e">✓ Free</text>
      <!-- Upcoming -->
      <text x="16" y="250" font-family="Inter" font-size="10" font-weight="600" fill="#71717a" letter-spacing="0.5">UPCOMING</text>
      <rect x="12" y="258" width="216" height="54" rx="10" fill="#18181b" stroke="#27272a" stroke-width="1"/>
      <rect x="12" y="258" width="3" height="54" rx="1.5" fill="#2563eb"/>
      <text x="22" y="274" font-family="Inter" font-size="12" font-weight="600" fill="#f4f4f5">Rehearsal</text>
      <text x="22" y="288" font-family="Inter" font-size="10" fill="#71717a">Thu, May 15 · The Practice Space</text>
      <text x="22" y="302" font-family="Inter" font-size="10" fill="#a1a1aa">7:00 PM · 4 confirmed</text>
      <rect x="12" y="320" width="216" height="54" rx="10" fill="#18181b" stroke="#27272a" stroke-width="1"/>
      <rect x="12" y="320" width="3" height="54" rx="1.5" fill="#BE123C"/>
      <text x="22" y="336" font-family="Inter" font-size="12" font-weight="600" fill="#f4f4f5">The Bowery Electric</text>
      <text x="22" y="350" font-family="Inter" font-size="10" fill="#71717a">Fri, May 16 · 9:00 PM</text>
      <text x="22" y="364" font-family="Inter" font-size="10" fill="#a1a1aa">Summer Tour Set</text>
      <!-- Quick actions -->
      <text x="16" y="396" font-family="Inter" font-size="10" font-weight="600" fill="#71717a" letter-spacing="0.5">QUICK ACTIONS</text>
      <rect x="12" y="404" width="102" height="30" rx="7" fill="#18181b" stroke="#3f3f46" stroke-width="1"/>
      <text x="28" y="423" font-family="Inter" font-size="11" font-weight="500" fill="#f4f4f5">+ New Event</text>
      <rect x="122" y="404" width="106" height="30" rx="7" fill="#18181b" stroke="#3f3f46" stroke-width="1"/>
      <text x="136" y="423" font-family="Inter" font-size="11" font-weight="500" fill="#f4f4f5">+ New Setlist</text>
      <!-- Bottom nav -->
      <rect y="${PH-46}" width="${PW}" height="46" fill="#111113"/>
      <rect y="${PH-46}" width="${PW}" height="0.5" fill="#27272a"/>
      <rect x="10" y="${PH-42}" width="38" height="30" rx="6" fill="#1a1020"/>
      <text x="18" y="${PH-22}" font-family="Inter" font-size="8" font-weight="700" fill="#BE123C">HOME</text>
      <text x="62" y="${PH-22}" font-family="Inter" font-size="8" fill="#52525b">CAL</text>
      <text x="106" y="${PH-22}" font-family="Inter" font-size="8" fill="#52525b">SETS</text>
      <text x="148" y="${PH-22}" font-family="Inter" font-size="8" fill="#52525b">MBR</text>
      <text x="192" y="${PH-22}" font-family="Inter" font-size="8" fill="#52525b">MORE</text>`;

  const body = `
  <!-- dark bg -->
  <rect width="${W}" height="${H}" fill="#09090B"/>
  ${dot_pattern()}
  <rect width="${W}" height="${H}" fill="url(#glow)"/>
  ${phone_start(PX, PY, PW, -3, id)}
  ${screen}
  ${phone_end(PW, -3, id)}
  ${text_block('Dashboard', 'Your Band', 'At a Glance', 'See upcoming gigs, rehearsals, and your team\'s availability — all in one place.', 665)}`;

  return svg_wrap(defs, body);
}

// ── SLIDE 2 — SETLISTS ──────────────────────────────────────────────────────
function slide_setlists() {
  const PW = 240, id = 'sets';
  const PH = Math.round(PW * 550 / 260);
  const PX = (W - PW) / 2 + 10;
  const PY = -20;

  const defs = `
  ${shadow_filter(id)}
  <linearGradient id="sg1" x1="0%" y1="0%" x2="100%" y2="100%">
    <stop offset="0%" stop-color="#f43f5e"/>
    <stop offset="50%" stop-color="#2563eb"/>
    <stop offset="100%" stop-color="#c026d3"/>
  </linearGradient>
  <linearGradient id="sg2" x1="0%" y1="0%" x2="100%" y2="100%">
    <stop offset="0%" stop-color="#2563eb"/>
    <stop offset="50%" stop-color="#06b6d4"/>
    <stop offset="100%" stop-color="#f43f5e"/>
  </linearGradient>
  <radialGradient id="glow" cx="80%" cy="100%" r="55%" gradientUnits="objectBoundingBox">
    <stop offset="0%" stop-color="#2563eb" stop-opacity="0.16"/>
    <stop offset="100%" stop-color="#2563eb" stop-opacity="0"/>
  </radialGradient>`;

  const screen = `
      <rect width="${PW}" height="${PH}" fill="#09090B"/>
      <text x="16" y="32" font-family="Inter" font-size="10" font-weight="600" fill="#a1a1aa">9:41</text>
      <text x="16" y="62" font-family="Inter" font-size="17" font-weight="700" fill="#f4f4f5">Setlists</text>
      <rect x="198" y="50" width="30" height="20" rx="6" fill="#BE123C"/>
      <text x="207" y="64" font-family="Inter" font-size="14" font-weight="600" fill="#fff">+</text>
      <!-- Setlist card 1 gradient border -->
      <rect x="10" y="76" width="220" height="70" rx="14" fill="none" stroke="url(#sg1)" stroke-width="2"/>
      <rect x="12" y="78" width="216" height="66" rx="12" fill="#18181b"/>
      <text x="22" y="98" font-family="Inter" font-size="13" font-weight="700" fill="#f4f4f5">Summer Tour Set</text>
      <text x="22" y="114" font-family="Inter" font-size="10" fill="#71717a">12 songs · 47 mins</text>
      <text x="22" y="128" font-family="Inter" font-size="10" fill="#52525b">Last edited May 8</text>
      <!-- Setlist card 2 gradient border -->
      <rect x="10" y="154" width="220" height="70" rx="14" fill="none" stroke="url(#sg2)" stroke-width="2"/>
      <rect x="12" y="156" width="216" height="66" rx="12" fill="#18181b"/>
      <text x="22" y="176" font-family="Inter" font-size="13" font-weight="700" fill="#f4f4f5">Bowery Electric — Fri</text>
      <text x="22" y="192" font-family="Inter" font-size="10" fill="#71717a">9 songs · 38 mins</text>
      <text x="22" y="206" font-family="Inter" font-size="10" fill="#52525b">Last edited May 10</text>
      <!-- Setlist card 3 -->
      <rect x="10" y="232" width="220" height="70" rx="14" fill="#18181b" stroke="#27272a" stroke-width="1.5"/>
      <text x="22" y="252" font-family="Inter" font-size="13" font-weight="700" fill="#f4f4f5">Acoustic Set</text>
      <text x="22" y="268" font-family="Inter" font-size="10" fill="#71717a">7 songs · 29 mins</text>
      <text x="22" y="282" font-family="Inter" font-size="10" fill="#52525b">Last edited Apr 22</text>
      <!-- Song list -->
      <text x="16" y="322" font-family="Inter" font-size="10" font-weight="600" fill="#71717a" letter-spacing="0.5">SUMMER TOUR SET</text>
      <rect x="10" y="330" width="220" height="36" rx="7" fill="#18181b"/>
      <text x="22" y="348" font-family="Inter" font-size="10" fill="#52525b">1</text>
      <text x="36" y="348" font-family="Inter" font-size="12" font-weight="500" fill="#f4f4f5">Midnight Drive</text>
      <text x="36" y="360" font-family="Inter" font-size="9" fill="#71717a">132 BPM · E std · 3:42</text>
      <rect x="10" y="370" width="220" height="36" rx="7" fill="transparent"/>
      <text x="22" y="388" font-family="Inter" font-size="10" fill="#52525b">2</text>
      <text x="36" y="388" font-family="Inter" font-size="12" font-weight="500" fill="#f4f4f5">Running from the Rain</text>
      <text x="36" y="400" font-family="Inter" font-size="9" fill="#71717a">118 BPM · Eb std · 4:15</text>
      <rect x="10" y="410" width="220" height="36" rx="7" fill="#18181b"/>
      <text x="22" y="428" font-family="Inter" font-size="10" fill="#52525b">3</text>
      <text x="36" y="428" font-family="Inter" font-size="12" font-weight="500" fill="#f4f4f5">Coastline</text>
      <text x="36" y="440" font-family="Inter" font-size="9" fill="#71717a">124 BPM · D std · 3:58</text>
      <!-- Bottom nav -->
      <rect y="${PH-46}" width="${PW}" height="46" fill="#111113"/>
      <rect y="${PH-46}" width="${PW}" height="0.5" fill="#27272a"/>
      <text x="18" y="${PH-22}" font-family="Inter" font-size="8" fill="#52525b">HOME</text>
      <text x="62" y="${PH-22}" font-family="Inter" font-size="8" fill="#52525b">CAL</text>
      <rect x="96" y="${PH-42}" width="44" height="30" rx="6" fill="#1a1020"/>
      <text x="102" y="${PH-22}" font-family="Inter" font-size="8" font-weight="700" fill="#BE123C">SETS</text>
      <text x="148" y="${PH-22}" font-family="Inter" font-size="8" fill="#52525b">MBR</text>
      <text x="192" y="${PH-22}" font-family="Inter" font-size="8" fill="#52525b">MORE</text>`;

  const body = `
  <rect width="${W}" height="${H}" fill="#09090B"/>
  ${dot_pattern()}
  <rect width="${W}" height="${H}" fill="url(#glow)"/>
  ${phone_start(PX, PY, PW, 3, id)}
  ${screen}
  ${phone_end(PW, 3, id)}
  ${text_block('Setlists', 'Build the', 'Perfect Set', 'Create, reorder, and share setlists — with BPM, key, and duration built in.', 665)}`;

  return svg_wrap(defs, body);
}

// ── SLIDE 3 — CALENDAR ──────────────────────────────────────────────────────
function slide_calendar() {
  const PW = 240, id = 'cal';
  const PH = Math.round(PW * 550 / 260);
  const PX = (W - PW) / 2 - 10;
  const PY = -15;

  const defs = `
  ${shadow_filter(id)}
  <radialGradient id="glow" cx="30%" cy="100%" r="55%" gradientUnits="objectBoundingBox">
    <stop offset="0%" stop-color="#2563eb" stop-opacity="0.16"/>
    <stop offset="100%" stop-color="#2563eb" stop-opacity="0"/>
  </radialGradient>`;

  const col = (i) => 14 + i * 33;
  const dayY = (row) => 120 + row * 28;

  const screen = `
      <rect width="${PW}" height="${PH}" fill="#09090B"/>
      <text x="16" y="32" font-family="Inter" font-size="10" font-weight="600" fill="#a1a1aa">9:41</text>
      <text x="16" y="62" font-family="Inter" font-size="17" font-weight="700" fill="#f4f4f5">May 2026</text>
      <text x="198" y="62" font-family="Inter" font-size="18" fill="#52525b">‹</text>
      <text x="214" y="62" font-family="Inter" font-size="18" fill="#BE123C">›</text>
      <!-- Day headers -->
      ${['S','M','T','W','T','F','S'].map((d,i) => `<text x="${col(i)+2}" y="84" font-family="Inter" font-size="9" font-weight="600" fill="#52525b">${d}</text>`).join('')}
      <!-- Row 1 (partial) -->
      <text x="${col(4)+2}" y="${dayY(0)}" font-family="Inter" font-size="12" fill="#71717a">1</text>
      <text x="${col(5)+2}" y="${dayY(0)}" font-family="Inter" font-size="12" fill="#71717a">2</text>
      <text x="${col(6)+2}" y="${dayY(0)}" font-family="Inter" font-size="12" fill="#71717a">3</text>
      <!-- Row 2 -->
      ${[4,5,6,7,8,9,10].map((d,i) => `<text x="${col(i)+2}" y="${dayY(1)}" font-family="Inter" font-size="12" fill="#a1a1aa">${d}</text>`).join('')}
      <circle cx="${col(4)+8}" cy="${dayY(1)+4}" r="2.5" fill="#BE123C"/>
      <circle cx="${col(6)+8}" cy="${dayY(1)+4}" r="2.5" fill="#2563eb"/>
      <!-- Row 3 — TODAY: 15 -->
      ${[11,12,13,14].map((d,i) => `<text x="${col(i)+2}" y="${dayY(2)}" font-family="Inter" font-size="12" fill="#a1a1aa">${d}</text>`).join('')}
      <circle cx="${col(4)+8}" cy="${dayY(2)-8}" r="11" fill="#BE123C"/>
      <text x="${col(4)+3}" y="${dayY(2)}" font-family="Inter" font-size="12" font-weight="700" fill="#fff">15</text>
      <text x="${col(5)+2}" y="${dayY(2)}" font-family="Inter" font-size="12" fill="#a1a1aa">16</text>
      <circle cx="${col(5)+8}" cy="${dayY(2)+4}" r="2.5" fill="#BE123C"/>
      <text x="${col(6)+2}" y="${dayY(2)}" font-family="Inter" font-size="12" fill="#a1a1aa">17</text>
      <!-- Row 4 -->
      ${[18,19,20,21,22,23,24].map((d,i) => `<text x="${col(i)+(d>9?0:2)}" y="${dayY(3)}" font-family="Inter" font-size="12" fill="#a1a1aa">${d}</text>`).join('')}
      <circle cx="${col(4)+8}" cy="${dayY(3)+4}" r="2.5" fill="#2563eb"/>
      <!-- Divider -->
      <rect x="10" y="${dayY(3)+14}" width="220" height="0.5" fill="#27272a"/>
      <!-- Events -->
      <text x="16" y="${dayY(3)+32}" font-family="Inter" font-size="10" font-weight="600" fill="#71717a" letter-spacing="0.5">THU, MAY 15</text>
      <rect x="10" y="${dayY(3)+38}" width="220" height="52" rx="8" fill="#18181b" stroke="#27272a" stroke-width="1"/>
      <rect x="10" y="${dayY(3)+38}" width="3" height="52" rx="1.5" fill="#2563eb"/>
      <text x="20" y="${dayY(3)+56}" font-family="Inter" font-size="12" font-weight="600" fill="#f4f4f5">Band Rehearsal</text>
      <text x="20" y="${dayY(3)+70}" font-family="Inter" font-size="10" fill="#71717a">7:00 PM · The Practice Space</text>
      <text x="20" y="${dayY(3)+82}" font-family="Inter" font-size="10" fill="#52525b">4 of 4 confirmed</text>
      <rect x="10" y="${dayY(3)+98}" width="220" height="52" rx="8" fill="#18181b" stroke="#27272a" stroke-width="1"/>
      <rect x="10" y="${dayY(3)+98}" width="3" height="52" rx="1.5" fill="#BE123C"/>
      <text x="20" y="${dayY(3)+116}" font-family="Inter" font-size="12" font-weight="600" fill="#f4f4f5">The Bowery Electric</text>
      <text x="20" y="${dayY(3)+130}" font-family="Inter" font-size="10" fill="#71717a">9:00 PM · New York, NY</text>
      <text x="20" y="${dayY(3)+142}" font-family="Inter" font-size="10" fill="#52525b">3 of 4 confirmed</text>
      <!-- Bottom nav -->
      <rect y="${PH-46}" width="${PW}" height="46" fill="#111113"/>
      <rect y="${PH-46}" width="${PW}" height="0.5" fill="#27272a"/>
      <text x="18" y="${PH-22}" font-family="Inter" font-size="8" fill="#52525b">HOME</text>
      <rect x="54" y="${PH-42}" width="38" height="30" rx="6" fill="#1a1020"/>
      <text x="62" y="${PH-22}" font-family="Inter" font-size="8" font-weight="700" fill="#BE123C">CAL</text>
      <text x="106" y="${PH-22}" font-family="Inter" font-size="8" fill="#52525b">SETS</text>
      <text x="148" y="${PH-22}" font-family="Inter" font-size="8" fill="#52525b">MBR</text>
      <text x="192" y="${PH-22}" font-family="Inter" font-size="8" fill="#52525b">MORE</text>`;

  const body = `
  <rect width="${W}" height="${H}" fill="#09090B"/>
  ${dot_pattern()}
  <rect width="${W}" height="${H}" fill="url(#glow)"/>
  ${phone_start(PX, PY, PW, -2.5, id)}
  ${screen}
  ${phone_end(PW, -2.5, id)}
  ${text_block('Calendar', 'Never', 'Miss a Beat', 'Track every gig, rehearsal, and band event on a shared calendar the whole crew can sync to.', 668)}`;

  return svg_wrap(defs, body);
}

// ── SLIDE 4 — CONTACTS ──────────────────────────────────────────────────────
function slide_contacts() {
  const PW = 240, id = 'cont';
  const PH = Math.round(PW * 550 / 260);
  const PX = (W - PW) / 2 + 5;
  const PY = -20;

  const defs = `
  ${shadow_filter(id)}
  <radialGradient id="glow" cx="70%" cy="100%" r="55%" gradientUnits="objectBoundingBox">
    <stop offset="0%" stop-color="#9333ea" stop-opacity="0.16"/>
    <stop offset="100%" stop-color="#9333ea" stop-opacity="0"/>
  </radialGradient>`;

  const screen = `
      <rect width="${PW}" height="${PH}" fill="#09090B"/>
      <text x="16" y="32" font-family="Inter" font-size="10" font-weight="600" fill="#a1a1aa">9:41</text>
      <text x="16" y="62" font-family="Inter" font-size="17" font-weight="700" fill="#f4f4f5">Contacts</text>
      <rect x="198" y="50" width="30" height="20" rx="6" fill="#BE123C"/>
      <text x="207" y="64" font-family="Inter" font-size="14" font-weight="600" fill="#fff">+</text>
      <!-- Tabs -->
      <rect x="10" y="72" width="220" height="28" rx="7" fill="#18181b"/>
      <rect x="12" y="74" width="106" height="24" rx="6" fill="#27272a"/>
      <text x="40" y="90" font-family="Inter" font-size="11" font-weight="600" fill="#f4f4f5">Venues</text>
      <text x="150" y="90" font-family="Inter" font-size="11" fill="#71717a">People</text>
      <!-- Search -->
      <rect x="10" y="108" width="220" height="28" rx="7" fill="#18181b" stroke="#27272a" stroke-width="1"/>
      <text x="20" y="126" font-family="Inter" font-size="11" fill="#52525b">Search venues...</text>
      <!-- Section -->
      <text x="16" y="156" font-family="Inter" font-size="10" font-weight="600" fill="#71717a" letter-spacing="0.5">RECENTLY BOOKED</text>
      <!-- Venue 1 -->
      <rect x="10" y="164" width="220" height="62" rx="10" fill="#18181b" stroke="#27272a" stroke-width="1"/>
      <rect x="20" y="176" width="32" height="32" rx="7" fill="#27272a"/>
      <text x="60" y="182" font-family="Inter" font-size="12" font-weight="600" fill="#f4f4f5">The Bowery Electric</text>
      <text x="60" y="196" font-family="Inter" font-size="10" fill="#71717a">New York, NY</text>
      <text x="60" y="210" font-family="Inter" font-size="9" fill="#52525b">Cap: 300 · Last booked May 2026</text>
      <!-- Venue 2 -->
      <rect x="10" y="234" width="220" height="62" rx="10" fill="#18181b" stroke="#27272a" stroke-width="1"/>
      <rect x="20" y="246" width="32" height="32" rx="7" fill="#27272a"/>
      <text x="28" y="268" font-family="Inter" font-size="16" fill="#f4f4f5">🎵</text>
      <text x="60" y="252" font-family="Inter" font-size="12" font-weight="600" fill="#f4f4f5">Rockwood Music Hall</text>
      <text x="60" y="266" font-family="Inter" font-size="10" fill="#71717a">New York, NY</text>
      <text x="60" y="280" font-family="Inter" font-size="9" fill="#52525b">Cap: 120 · Contact: Sarah M.</text>
      <!-- People section -->
      <text x="16" y="314" font-family="Inter" font-size="10" font-weight="600" fill="#71717a" letter-spacing="0.5">INDUSTRY CONTACTS</text>
      <!-- Contact 1 -->
      <rect x="10" y="322" width="220" height="42" rx="8" fill="#18181b"/>
      <circle cx="36" cy="343" r="14" fill="#3f3f46"/>
      <text x="29" y="348" font-family="Inter" font-size="11" font-weight="600" fill="#d4d4d8">DW</text>
      <text x="58" y="338" font-family="Inter" font-size="11" font-weight="500" fill="#f4f4f5">Dave W. — Booking Agent</text>
      <text x="58" y="352" font-family="Inter" font-size="10" fill="#71717a">dave@citysound.com</text>
      <!-- Contact 2 -->
      <rect x="10" y="368" width="220" height="42" rx="8" fill="transparent"/>
      <circle cx="36" cy="389" r="14" fill="#3f3f46"/>
      <text x="30" y="394" font-family="Inter" font-size="11" font-weight="600" fill="#d4d4d8">LR</text>
      <text x="58" y="384" font-family="Inter" font-size="11" font-weight="500" fill="#f4f4f5">Lisa R. — Sound Tech</text>
      <text x="58" y="398" font-family="Inter" font-size="10" fill="#71717a">lisa@liveaudio.com</text>
      <!-- Contact 3 -->
      <rect x="10" y="414" width="220" height="42" rx="8" fill="#18181b"/>
      <circle cx="36" cy="435" r="14" fill="#3f3f46"/>
      <text x="29" y="440" font-family="Inter" font-size="11" font-weight="600" fill="#d4d4d8">MB</text>
      <text x="58" y="430" font-family="Inter" font-size="11" font-weight="500" fill="#f4f4f5">Marcus B. — Promoter</text>
      <text x="58" y="444" font-family="Inter" font-size="10" fill="#71717a">marcus@nycshows.com</text>
      <!-- Bottom nav -->
      <rect y="${PH-46}" width="${PW}" height="46" fill="#111113"/>
      <rect y="${PH-46}" width="${PW}" height="0.5" fill="#27272a"/>
      <text x="18" y="${PH-22}" font-family="Inter" font-size="8" fill="#52525b">HOME</text>
      <text x="62" y="${PH-22}" font-family="Inter" font-size="8" fill="#52525b">CAL</text>
      <text x="106" y="${PH-22}" font-family="Inter" font-size="8" fill="#52525b">SETS</text>
      <text x="148" y="${PH-22}" font-family="Inter" font-size="8" fill="#52525b">MBR</text>
      <rect x="184" y="${PH-42}" width="44" height="30" rx="6" fill="#1a1020"/>
      <text x="192" y="${PH-22}" font-family="Inter" font-size="8" font-weight="700" fill="#BE123C">MORE</text>`;

  const body = `
  <rect width="${W}" height="${H}" fill="#09090B"/>
  ${dot_pattern()}
  <rect width="${W}" height="${H}" fill="url(#glow)"/>
  ${phone_start(PX, PY, PW, -2, id)}
  ${screen}
  ${phone_end(PW, -2, id)}
  ${text_block('Contacts', 'Keep Your', 'Network Close', 'Store venues, promoters, and booking contacts — always ready when you need them.', 665)}`;

  return svg_wrap(defs, body);
}

// ── SLIDE 5 — CREATE EVENTS ─────────────────────────────────────────────────
function slide_create_events() {
  const PW = 240, id = 'evt';
  const PH = Math.round(PW * 550 / 260);
  const PX = (W - PW) / 2 - 8;
  const PY = -5;

  const defs = `
  ${shadow_filter(id)}
  <radialGradient id="glow" cx="20%" cy="100%" r="55%" gradientUnits="objectBoundingBox">
    <stop offset="0%" stop-color="#BE123C" stop-opacity="0.18"/>
    <stop offset="100%" stop-color="#BE123C" stop-opacity="0"/>
  </radialGradient>`;

  const screen = `
      <rect width="${PW}" height="${PH}" fill="#09090B"/>
      <text x="16" y="32" font-family="Inter" font-size="10" font-weight="600" fill="#a1a1aa">9:41</text>
      <text x="16" y="62" font-family="Inter" font-size="17" font-weight="700" fill="#f4f4f5">Create Event</text>
      <text x="196" y="62" font-family="Inter" font-size="13" font-weight="600" fill="#BE123C">Save</text>
      <!-- Type tabs -->
      <rect x="10" y="70" width="220" height="28" rx="7" fill="#18181b"/>
      <rect x="12" y="72" width="66" height="24" rx="6" fill="#BE123C"/>
      <text x="26" y="88" font-family="Inter" font-size="11" font-weight="700" fill="#fff">Gig</text>
      <text x="94" y="88" font-family="Inter" font-size="11" fill="#71717a">Rehearsal</text>
      <text x="174" y="88" font-family="Inter" font-size="11" fill="#71717a">Other</text>
      <!-- Venue -->
      <text x="16" y="114" font-family="Inter" font-size="9" font-weight="600" fill="#71717a" letter-spacing="0.5">VENUE NAME</text>
      <rect x="10" y="120" width="220" height="32" rx="7" fill="#18181b" stroke="#3f3f46" stroke-width="1"/>
      <text x="18" y="140" font-family="Inter" font-size="12" fill="#f4f4f5">The Bowery Electric</text>
      <!-- Date/Time -->
      <text x="16" y="168" font-family="Inter" font-size="9" font-weight="600" fill="#71717a" letter-spacing="0.5">DATE &amp; TIME</text>
      <rect x="10" y="174" width="104" height="32" rx="7" fill="#18181b" stroke="#3f3f46" stroke-width="1"/>
      <text x="18" y="194" font-family="Inter" font-size="11" fill="#f4f4f5">Fri, May 16</text>
      <rect x="122" y="174" width="108" height="32" rx="7" fill="#18181b" stroke="#3f3f46" stroke-width="1"/>
      <text x="130" y="194" font-family="Inter" font-size="11" fill="#f4f4f5">9:00 PM</text>
      <!-- Location -->
      <text x="16" y="222" font-family="Inter" font-size="9" font-weight="600" fill="#71717a" letter-spacing="0.5">LOCATION</text>
      <rect x="10" y="228" width="220" height="32" rx="7" fill="#18181b" stroke="#3f3f46" stroke-width="1"/>
      <text x="18" y="248" font-family="Inter" font-size="11" fill="#f4f4f5">327 Bowery, New York, NY</text>
      <!-- Setlist -->
      <text x="16" y="276" font-family="Inter" font-size="9" font-weight="600" fill="#71717a" letter-spacing="0.5">SETLIST (OPTIONAL)</text>
      <rect x="10" y="282" width="220" height="32" rx="7" fill="#18181b" stroke="#3f3f46" stroke-width="1"/>
      <text x="18" y="302" font-family="Inter" font-size="11" fill="#f4f4f5">Summer Tour Set</text>
      <text x="216" y="302" font-family="Inter" font-size="14" fill="#52525b">›</text>
      <!-- Notes -->
      <text x="16" y="330" font-family="Inter" font-size="9" font-weight="600" fill="#71717a" letter-spacing="0.5">NOTES</text>
      <rect x="10" y="336" width="220" height="56" rx="7" fill="#18181b" stroke="#3f3f46" stroke-width="1"/>
      <text x="18" y="354" font-family="Inter" font-size="11" fill="#f4f4f5">Load in at 7 PM. Soundcheck 8 PM.</text>
      <text x="18" y="370" font-family="Inter" font-size="11" fill="#71717a">Park on Bleecker — free after 7.</text>
      <!-- Notify toggle -->
      <rect x="10" y="402" width="220" height="32" rx="7" fill="#18181b"/>
      <text x="18" y="422" font-family="Inter" font-size="12" font-weight="500" fill="#f4f4f5">Notify band members</text>
      <rect x="170" y="410" width="36" height="20" rx="10" fill="#BE123C"/>
      <circle cx="196" cy="420" r="8" fill="#fff"/>
      <!-- Save button -->
      <rect x="10" y="446" width="220" height="38" rx="9" fill="#BE123C"/>
      <text x="44" y="469" font-family="Inter" font-size="13" font-weight="700" fill="#fff">Save &amp; Notify Band</text>`;

  const body = `
  <rect width="${W}" height="${H}" fill="#09090B"/>
  ${dot_pattern()}
  <rect width="${W}" height="${H}" fill="url(#glow)"/>
  ${phone_start(PX, PY, PW, 2.5, id)}
  ${screen}
  ${phone_end(PW, 2.5, id)}
  ${text_block('Create Events', 'Plan Your', 'Next Show', 'Schedule gigs and rehearsals, attach a setlist, and notify your whole band in one tap.', 665)}`;

  return svg_wrap(defs, body);
}

// ── Generate all ────────────────────────────────────────────────────────────
const slides = [
  { fn: slide_dashboard,     name: '01_dashboard' },
  { fn: slide_setlists,      name: '02_setlists' },
  { fn: slide_calendar,      name: '03_calendar' },
  { fn: slide_contacts,      name: '04_contacts' },
  { fn: slide_create_events, name: '05_create_events' },
];

const destDir = '/sessions/magical-admiring-heisenberg/mnt/BandRoadie/src/app_store_screenshots';

for (const { fn, name } of slides) {
  const svgPath = `${OUT}/${name}.svg`;
  const pngPath = `${destDir}/${name}.png`;
  const svg = fn();
  fs.writeFileSync(svgPath, svg, 'utf8');
  console.log(`Wrote ${svgPath}`);

  // Convert SVG → PNG at 1290x2796 (App Store 6.7" size, 3x) via cairosvg
  try {
    execSync(
      `python3 -c "import cairosvg; cairosvg.svg2png(url='${svgPath}', write_to='${pngPath}', output_width=1290, output_height=2796)"`,
      { stdio: 'inherit' }
    );
    console.log(`✓ Exported ${pngPath}`);
  } catch(e) {
    console.error(`✗ Failed ${name}:`, e.message);
  }
}

console.log('\nAll done!');

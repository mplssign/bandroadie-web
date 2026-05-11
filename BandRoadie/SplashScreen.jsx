/**
 * BandRoadie Splash Screen
 * Spray-paint stencil reveal animation.
 *
 * Usage:
 *   import SplashScreen from "./SplashScreen";
 *   <SplashScreen onComplete={() => navigate("/dashboard")} />
 *
 * Props:
 *   onComplete  () => void   Called when animation finishes (route to dashboard here)
 */
import { useEffect, useRef } from "react";

// ─── Animation timeline (ms) ──────────────────────────────────────────────────
const SPRAY_DELAY = 900;                          // pause before spray starts
const SPRAY_DUR   = 2100;                         // sweep left → right
const SPRAY_END   = SPRAY_DELAY + SPRAY_DUR;      // 3000
const PEEL_START  = SPRAY_END + 450;              // stencil begins to lift
const PEEL_DUR    = 750;                          // stencil lift duration
const PEEL_END    = PEEL_START + PEEL_DUR;
const TOTAL       = PEEL_END + 650;               // hold → call onComplete

const SVG_W = 413.69; // BandRoadie logo viewBox width

// ─── Road-case corner hardware ────────────────────────────────────────────────
function Corner({ top = false, left = false }) {
  return (
    <div
      aria-hidden="true"
      style={{
        position:    "absolute",
        [top  ? "top"    : "bottom"]: 22,
        [left ? "left"   : "right"] : 22,
        width:  30,
        height: 30,
        borderTop:    top   ? "3px solid #2c2c2c" : "none",
        borderBottom: !top  ? "3px solid #2c2c2c" : "none",
        borderLeft:   left  ? "3px solid #2c2c2c" : "none",
        borderRight:  !left ? "3px solid #2c2c2c" : "none",
        borderRadius: 2,
        opacity: 0.8,
      }}
    />
  );
}

// ─── SplashScreen ─────────────────────────────────────────────────────────────
export default function SplashScreen({ onComplete = () => {} }) {
  const canvasRef  = useRef(null); // particle canvas (full-screen)
  const clipRef    = useRef(null); // SVG <rect> inside <clipPath>
  const stencilRef = useRef(null); // stencil frame overlay
  const nozzleRef  = useRef(null); // glowing spray-head dot
  const taglineRef = useRef(null); // tagline <text> SVG element

  useEffect(() => {
    const canvas = canvasRef.current;
    const ctx    = canvas.getContext("2d");

    function sizeCanvas() {
      canvas.width  = window.innerWidth;
      canvas.height = window.innerHeight;
    }
    sizeCanvas();
    window.addEventListener("resize", sizeCanvas);

    // ── Particle pool ──────────────────────────────────────────────────────
    const particles = [];

    function emit(cx, cy) {
      const count = 22;
      for (let i = 0; i < count; i++) {
        const angle = Math.random() * Math.PI * 2;
        const speed = Math.random() * 2.2 + 0.4;
        particles.push({
          x:  cx + (Math.random() - 0.5) * 28,
          y:  cy + (Math.random() - 0.5) * canvas.height * 0.28,
          vx: Math.cos(angle) * speed * 0.9,
          vy: Math.sin(angle) * speed * 0.55 - Math.random() * 0.6, // slight upward bias
          a:  Math.random() * 0.6 + 0.2,
          r:  Math.random() * 3.8 + 0.4,
          d:  Math.random() * 0.022 + 0.014,
        });
      }
    }

    // ── Easing helpers ─────────────────────────────────────────────────────
    // ease-in-out-quad: slow start, fast middle, slow end
    function easeInOut(t) {
      return t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2;
    }
    // ease-in-cubic: accelerates (for stencil lift)
    function easeInCubic(t) {
      return t * t * t;
    }

    // ── RAF loop ───────────────────────────────────────────────────────────
    let start = null;
    let raf   = null;
    let done  = false;

    function tick(ts) {
      if (!start) start = ts;
      const e  = ts - start;
      const CW = canvas.width;
      const CH = canvas.height;

      ctx.clearRect(0, 0, CW, CH);

      // Raw spray progress 0→1
      const spRaw = e < SPRAY_DELAY ? 0
                  : e > SPRAY_END   ? 1
                  : (e - SPRAY_DELAY) / SPRAY_DUR;

      // Eased for organic feel
      const sp = easeInOut(spRaw);

      // ── Update SVG clip rect (letter reveal) ─────────────────────────────
      if (clipRef.current) {
        clipRef.current.setAttribute("width", Math.max(0, sp * SVG_W + 6).toString());
      }

      // ── Tagline fade-in near end of spray ─────────────────────────────────
      if (taglineRef.current) {
        const t = Math.max(0, Math.min(1, (spRaw - 0.82) / 0.18));
        taglineRef.current.style.opacity = t.toFixed(3);
      }

      // ── Stencil frame lifecycle ───────────────────────────────────────────
      if (stencilRef.current) {
        if (e < PEEL_START) {
          // Barely-visible hint (stencil is "there" on the dark case)
          stencilRef.current.style.opacity = "0.1";
          stencilRef.current.style.transform = "rotate(-1.9deg) translateY(0px)";
        } else {
          const pp     = Math.min(1, (e - PEEL_START) / PEEL_DUR);
          const lift   = easeInCubic(pp);
          const liftPx = -(160 * lift);
          // Briefly flashes visible as it separates from surface, then fades
          const peelOpacity = pp < 0.15
            ? 0.1 + (pp / 0.15) * 0.3          // 0.1 → 0.4
            : Math.max(0, 0.4 - ((pp - 0.15) / 0.85) * 0.4); // 0.4 → 0
          stencilRef.current.style.transform = `rotate(-1.9deg) translateY(${liftPx}px)`;
          stencilRef.current.style.opacity   = peelOpacity.toFixed(3);
        }
      }

      // ── Spray nozzle dot position ─────────────────────────────────────────
      if (nozzleRef.current) {
        const spraying = e > SPRAY_DELAY && e < SPRAY_END;
        if (spraying) {
          const logoW = Math.min(CW * 0.72, 560);
          const logoX = (CW - logoW) / 2;
          const nx    = logoX + logoW * sp;
          const ny    = CH / 2;
          nozzleRef.current.style.left    = `${nx - 7}px`;
          nozzleRef.current.style.top     = `${ny - 7}px`;
          nozzleRef.current.style.opacity = "1";
        } else {
          nozzleRef.current.style.opacity = "0";
        }
      }

      // ── Emit + draw particles ─────────────────────────────────────────────
      if (e > SPRAY_DELAY && e < SPRAY_END) {
        const logoW = Math.min(CW * 0.72, 560);
        const logoX = (CW - logoW) / 2;
        emit(logoX + logoW * sp, CH / 2);
      }

      for (let i = particles.length - 1; i >= 0; i--) {
        const p = particles[i];
        p.x += p.vx;
        p.y += p.vy;
        p.a -= p.d;
        if (p.a <= 0) { particles.splice(i, 1); continue; }
        ctx.beginPath();
        ctx.arc(p.x, p.y, p.r * (p.a * 0.35 + 0.65), 0, Math.PI * 2);
        ctx.fillStyle = `rgba(248,242,215,${p.a.toFixed(3)})`;
        ctx.fill();
      }

      if (!done && e < TOTAL) {
        raf = requestAnimationFrame(tick);
      } else if (!done) {
        done = true;
        onComplete();
      }
    }

    raf = requestAnimationFrame(tick);

    return () => {
      cancelAnimationFrame(raf);
      window.removeEventListener("resize", sizeCanvas);
    };
  }, [onComplete]);

  return (
    <div style={S.root}>
      {/* Road case surface texture */}
      <div style={S.texture} aria-hidden="true" />

      {/* Corner hardware */}
      <Corner top left />
      <Corner top />
      <Corner />
      <Corner left />

      {/* Logo + stencil area */}
      <div style={S.logoWrap}>
        {/* Stencil frame — dark card sitting on the case; lifts during peel */}
        <div
          ref={stencilRef}
          style={S.stencil}
          aria-hidden="true"
        />

        {/* BandRoadie SVG — letters revealed by spray clip path */}
        <svg
          viewBox="0 0 413.69 123"
          xmlns="http://www.w3.org/2000/svg"
          style={S.svg}
          role="img"
          aria-label="BandRoadie — Keeping Your Band in Tune... On Stage and Off."
        >
          <defs>
            <clipPath id="br-spray-clip">
              {/* This rect grows left→right as spray progresses */}
              <rect
                ref={clipRef}
                x="-5"
                y="-15"
                width="0"
                height="153"
              />
            </clipPath>
          </defs>

          {/* Tagline — fades in near end of reveal */}
          <text
            ref={taglineRef}
            transform="matrix(0.9994 -0.0334 0.0334 0.9994 16.6624 119.4254)"
            fontFamily="'Helvetica Neue', Arial, sans-serif"
            fontWeight="700"
            fontSize="16"
            fill="rgba(255,255,255,0.5)"
            style={{ opacity: 0 }}
          >
            Keeping Your Band in Tune... On Stage and Off.
          </text>

          {/* White letter paths — clipped by spray reveal */}
          <g clipPath="url(#br-spray-clip)" fill="#FFFFFF">
            {/* B */}
            <path d="M22.37,30.35l11.37-0.38l1.58,47.42l-11.37,0.38L22.37,30.35z M39.02,69.56l2.45-0.08
              c2.11-0.07,3.72-0.7,4.84-1.89c1.11-1.19,1.64-2.7,1.58-4.52c-0.06-1.82-0.69-3.29-1.88-4.4
              c-1.19-1.11-2.84-1.63-4.95-1.56l-2.45,0.08l-0.26-7.77l1.29-0.12c1.82-0.25,3.19-0.92,4.11-2.01
              c0.92-1.09,1.36-2.45,1.3-4.08c-0.01-1.58-0.52-2.89-1.54-3.91c-1.02-1.02-2.44-1.58-4.27-1.66l-1.3-0.1
              l-0.26-7.7l1.51-0.05c5.52-0.04,9.61,1.12,12.25,3.48c2.65,2.36,4.04,5.56,4.17,9.59
              c0.12,3.65-0.86,6.66-2.94,9.03c1.86,1.14,3.26,2.63,4.18,4.47c0.93,1.84,1.43,3.96,1.51,6.36
              c0.07,2.11-0.2,4.04-0.81,5.79c-0.61,1.75-1.6,3.25-2.95,4.49c-1.35,1.25-3.1,2.23-5.23,2.95
              c-2.14,0.72-4.69,1.13-7.67,1.23l-2.45,0.08L39.02,69.56z"/>
            {/* A */}
            <path d="M70.64,30.68l4.77,15.55l-2.51,9.09l5.54-0.19l2.59,8.63l-9.93,0.33L67.84,76.3l-12.02,0.4
              L70.64,30.68z M73.31,28.5l9.86-0.33l17.28,47.04l-11.95,0.4L73.31,28.5z"/>
            {/* N */}
            <path d="M110.08,27.41l27.2,46.57l-11.23,0.38L98.93,27.79L110.08,27.41z M99.16,34.62l11,18.79
              l0.72,21.44l-10.36,0.35L99.16,34.62z M125.34,26.9l10.36-0.35l1.36,40.73l-11-18.87L125.34,26.9z"/>
            {/* D */}
            <path d="M153.4,73.44l-11.44,0.38l-1.58-47.42l11.44-0.38L153.4,73.44z M157.07,64.46l1.58-0.05
              c2.73-0.09,4.67-1.34,5.82-3.76c1.14-2.42,1.63-6.21,1.46-11.39c-0.17-5.18-0.91-8.93-2.21-11.24
              c-1.3-2.31-3.32-3.42-6.05-3.33l-1.58,0.05l-0.3-8.85l1.58-0.05c3.89-0.13,7.1,0.4,9.63,1.59
              c2.54,1.19,4.57,2.85,6.11,4.98c1.54,2.13,2.63,4.62,3.27,7.45c0.65,2.84,1.02,5.84,1.13,9
              c0.11,3.17-0.07,6.2-0.52,9.09c-0.46,2.9-1.38,5.45-2.77,7.66c-1.39,2.21-3.31,4-5.76,5.38
              c-2.45,1.38-5.62,2.13-9.51,2.26l-1.58,0.05L157.07,64.46z"/>
            {/* R */}
            <path d="M191.11,24.71l11.44-0.38l1.58,47.42l-11.44,0.38L191.11,24.71z M207.22,45.57l1.22-0.04
              c2.16-0.07,3.79-0.77,4.9-2.11c1.11-1.33,1.63-2.91,1.57-4.74c-0.06-1.82-0.69-3.34-1.88-4.55
              c-1.19-1.21-2.87-1.78-5.03-1.71l-1.22,0.04l-0.28-8.28l1.22-0.04c2.97-0.1,5.56,0.16,7.77,0.79
              c2.21,0.62,4.03,1.57,5.46,2.84c1.43,1.27,2.52,2.82,3.25,4.65c0.73,1.82,1.14,3.89,1.22,6.19
              c0.09,2.59-0.28,4.9-1.1,6.92c-0.82,2.02-2.17,3.71-4.04,5.07l7.88,20.34l-11.37,0.38l-6.56-17.5
              c-0.24,0.06-0.48,0.09-0.72,0.1c-0.24,0.01-0.5,0.02-0.79,0.03l-1.22,0.04L207.22,45.57z"/>
            {/* O */}
            <path d="M226.66,47.22c-0.1-2.97,0.07-5.88,0.5-8.73c0.43-2.85,1.27-5.43,2.51-7.76
              c1.24-2.32,2.97-4.27,5.17-5.83c2.2-1.56,5.03-2.52,8.48-2.88l0.3,8.99c-1.99,0.74-3.41,2.46-4.26,5.15
              c-0.85,2.69-1.2,6.25-1.05,10.66c0.15,4.46,0.74,8.01,1.76,10.64c1.02,2.63,2.58,4.22,4.66,4.78l0.3,9.07
              c-3.51-0.12-6.42-0.89-8.72-2.3c-2.31-1.41-4.16-3.23-5.55-5.47c-1.4-2.23-2.4-4.77-3.03-7.61
              C227.12,53.1,226.76,50.2,226.66,47.22z M248.62,62.12c2.04-0.69,3.49-2.39,4.33-5.08
              c0.85-2.69,1.2-6.27,1.05-10.73c-0.15-4.46-0.74-8-1.76-10.6c-1.02-2.61-2.58-4.21-4.66-4.81l-0.3-9.07
              c3.51,0.12,6.42,0.88,8.72,2.27c2.3,1.39,4.15,3.2,5.55,5.43c1.39,2.24,2.39,4.77,2.99,7.61
              c0.6,2.84,0.95,5.77,1.05,8.79c0.1,2.97-0.06,5.9-0.46,8.77c-0.41,2.87-1.23,5.48-2.48,7.83
              c-1.24,2.35-2.97,4.3-5.17,5.86c-2.21,1.56-5.06,2.52-8.55,2.88L248.62,62.12z"/>
            {/* A */}
            <path d="M278.17,23.74l4.77,15.55l-2.51,9.09l5.54-0.19l2.59,8.63l-9.93,0.33l-3.27,12.21l-12.02,0.4
              L278.17,23.74z M280.84,21.57l9.86-0.33l17.28,47.04l-11.95,0.4L280.84,21.57z"/>
            {/* D */}
            <path d="M319.92,67.88l-11.44,0.38l-1.58-47.42l11.44-0.38L319.92,67.88z M323.58,58.9l1.58-0.05
              c2.73-0.09,4.67-1.34,5.82-3.76s1.63-6.21,1.46-11.39c-0.17-5.18-0.91-8.93-2.21-11.24
              c-1.3-2.31-3.32-3.42-6.05-3.33l-1.58,0.05l-0.3-8.85l1.58-0.05c3.89-0.13,7.1,0.4,9.63,1.59
              c2.54,1.19,4.57,2.85,6.11,4.98c1.54,2.13,2.63,4.62,3.27,7.45c0.65,2.84,1.02,5.84,1.13,9
              c0.11,3.17-0.07,6.2-0.52,9.09s-1.38,5.45-2.77,7.66c-1.39,2.21-3.31,4-5.76,5.38
              c-2.45,1.38-5.62,2.13-9.5,2.26l-1.58,0.05L323.58,58.9z"/>
            {/* I */}
            <path d="M347.33,19.49l11.44-0.38l1.58,47.42l-11.44,0.38L347.33,19.49z"/>
            {/* E */}
            <path d="M365.1,18.82l11.59-0.39l1.59,47.49l-11.59,0.39L365.1,18.82z
              M380.65,18.3l13.53-0.45l0.32,9.5l-13.53,0.45L380.65,18.3z
              M381.26,36.58l10.58-0.35l0.32,9.57l-10.58,0.35L381.26,36.58z
              M381.91,56.23l14.1-0.47l0.32,9.57l-14.1,0.47L381.91,56.23z"/>
          </g>
        </svg>
      </div>

      {/* Moving spray-head glow */}
      <div ref={nozzleRef} style={S.nozzle} aria-hidden="true" />

      {/* Full-screen particle canvas */}
      <canvas ref={canvasRef} style={S.canvas} aria-hidden="true" />
    </div>
  );
}

// ─── Styles ───────────────────────────────────────────────────────────────────
const S = {
  root: {
    position:       "fixed",
    inset:          0,
    background:     "#0e0e0e",
    display:        "flex",
    alignItems:     "center",
    justifyContent: "center",
    overflow:       "hidden",
  },
  texture: {
    position: "absolute",
    inset:    0,
    backgroundImage: [
      "repeating-linear-gradient(0deg,   transparent, transparent 3px, rgba(255,255,255,0.012) 3px, rgba(255,255,255,0.012) 4px)",
      "repeating-linear-gradient(90deg,  transparent, transparent 3px, rgba(255,255,255,0.012) 3px, rgba(255,255,255,0.012) 4px)",
    ].join(", "),
    pointerEvents: "none",
  },
  logoWrap: {
    position:  "relative",
    width:     "72%",
    maxWidth:  560,
    zIndex:    1,
  },
  // Represents the physical stencil card lying on the road case surface
  stencil: {
    position:      "absolute",
    inset:         "-6px -10px",
    border:        "1.5px solid rgba(55,55,55,0.7)",
    background:    "rgba(20,20,20,0.92)",
    boxShadow:     "0 6px 24px rgba(0,0,0,0.7)",
    borderRadius:  1,
    transform:     "rotate(-1.9deg)",
    opacity:       0.1,
    pointerEvents: "none",
    zIndex:        2,
    willChange:    "transform, opacity",
  },
  svg: {
    width:    "100%",
    height:   "auto",
    display:  "block",
    overflow: "visible",
    position: "relative",
    zIndex:   3,
  },
  // Glowing dot that tracks the spray head left → right
  nozzle: {
    position:     "absolute",
    width:        14,
    height:       14,
    borderRadius: "50%",
    background:   "rgba(255,248,200,0.85)",
    boxShadow:    "0 0 14px 5px rgba(255,248,180,0.4), 0 0 4px 2px rgba(255,255,255,0.6)",
    opacity:      0,
    pointerEvents:"none",
    zIndex:       12,
    willChange:   "left, top, opacity",
  },
  canvas: {
    position:     "absolute",
    inset:        0,
    width:        "100%",
    height:       "100%",
    pointerEvents:"none",
    zIndex:       11,
  },
};

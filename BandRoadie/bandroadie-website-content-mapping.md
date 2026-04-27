# BandRoadie Website Template Content Mapping
### GenieNova → BandRoadie Adaptation Plan
*Prepared April 2026 | Based on v1.4.0 docs, App Store listings, and template review*

---

## Overall Recommendation

**GenieNova is an excellent fit.** It's a mobile app landing page template built around phone mockups, feature cards, testimonials, app store download CTAs, and a clean dark-mode aesthetic — all of which map directly to BandRoadie's product and brand. The rose accent (#BE123C) on a dark background matches the template's existing visual language almost exactly.

The main adaptation strategy is: **swap the AI/SaaS copy for band-specific, musician-aware language, replace every abstract feature with a concrete BandRoadie use case, and replace AI assistant imagery with real app screenshots of setlists, calendars, and gig views.**

The template's pricing section needs the heaviest rethinking — BandRoadie is currently free, so that section should either be repurposed as a "What's included" value summary or a future-proofed Free vs. Pro tier placeholder. Everything else maps cleanly with minimal structural changes.

---

## Screenshot Asset Map

All screenshots are from `~/Desktop/Screenshots/`. This table shows exactly which file goes in which section. Use these filenames when handing off to the Webflow developer.

| Screenshot File | What It Shows | Assigned Section(s) |
|---|---|---|
| `Dashboard.png` | Band dashboard — Next Rehearsal, Upcoming Gigs, Quick Actions | Hero mockup · Carousel slide 1 · How It Works step 3 |
| `Add Event.png` | Add Event form — Rehearsal / **Gig** / **Block Out** tabs, date, time, duration, recurrence, setlist picker | Adding Events feature block · Blockout Dates feature block · Carousel slide 2 |
| `Add Event 2.png` | Add Event form scrolled — setlist chips, notes field | Adding Events feature block (secondary / paired) |
| `Edit Rehearsal.png` | Edit Rehearsal form — date, time, duration, location, recurrence, setlist selected | Editing Events feature block · Carousel slide 3 |
| `Edit Rehearsal 2.png` | Edit Rehearsal (larger viewport) — same fields + Delete Event button visible | Editing Events feature block (desktop view) |
| `Calendar.png` | Calendar month view + "Tony Out · Spring break" blockout in event list | Calendar feature block · Carousel slide 4 · Blockout Dates feature block |
| `Subscribe Calednar feed.png` | iCal subscription modal — URL, Gigs/Rehearsals/Block-out toggles, Apple/Google/Outlook instructions | Calendar feature deep-dive |
| `Band Contacts.png` | Contacts → Band tab — Steve Gatland, Tony Holmes with instruments, phone, email, address | Contacts feature block · Carousel slide 5 |
| `Venue Contacts.png` | Contacts → Venues tab — Gallery Cabaret, Montrose Saloon, Underground Lounge | Contacts feature block (secondary) · Carousel slide 6 |
| `Setlists.png` | Setlists list — Catalog, Gallery Cabaret, Originals, Summer Show, The Village Club | Setlists feature block |
| `Setlist Detail.png` | Setlist "Originals" — songs with BPM, duration, Half-Step tuning badges, drag handles | Setlists feature deep-dive |
| `Setlist preview.png` | Print preview — numbered song list with BPM column | Setlists feature block (print callout) |
| `Print Setlist 1/2/3.png` | Print layout variants | Setlists feature block (optional) |
| `Lyrics 1.png` / `Lryics 2.png` | Full-screen lyrics view "Never Not Forever" | Setlists feature block (bonus / optional) |
| `Edit band.png` | Edit Band — name, avatar color picker, timezone | How It Works step 2 |
| `band image.png` | Edit Band — Choose Image Source modal | How It Works step 2 (secondary) |

> ⚠️ **Missing screenshot — Potential Gig:** No screenshot currently shows the Gig tab of the Add Event form with the "potential gig" toggle visible. Take a new screenshot with the Gig tab selected and "Mark as potential" enabled. Use `Add Event.png` as a placeholder in the meantime — the Gig tab is visible in the tab row, which is sufficient for now.

---

## Scroll Animation Spec

**Use GenieNova's existing scroll animations throughout — do not replace or override them.** The template ships with Webflow Interactions already configured. When cloning or building in Webflow, preserve these interactions and apply them consistently to all BandRoadie content blocks.

### How the GenieNova animation works

The template uses a **"Scroll Into View — Fade Up"** interaction pattern:

| Property | Start state | End state |
|---|---|---|
| Opacity | 0 | 1 |
| Transform Y | 30px (down) | 0px |
| Duration | — | 600ms |
| Easing | — | Ease out |
| Trigger | Element scrolls into view (10% visible threshold) | — |

### Where it applies

- **Section headlines and subheadlines** — fade up first, then body copy follows 100ms later
- **Feature cards grid** — each card staggers with a 120ms delay between cards (left to right, top to bottom)
- **Feature deep-dive blocks** — text column and screenshot column animate in from opposite sides or both fade up simultaneously
- **Testimonial cards** — same stagger as feature cards
- **How It Works steps** — step 1 fades up, then step 2 (120ms delay), then step 3 (240ms delay)
- **FAQ items** — no scroll animation needed; accordion open/close is the interaction

### Implementation note for the Webflow developer

When adding new sections that don't exist in the original template (e.g. the "What's Included" checklist), manually apply the same "Scroll Into View" interaction from the Interactions panel. Copy the animation from an existing section element to stay consistent. Do not use CSS animations or custom JavaScript for this — Webflow Interactions keeps everything in one place.

---

## Global Messaging Direction

### Primary Headline Options

1. **"Keeping your band in tune — on stage and off."** *(recommended)*
2. "One place for your gigs, setlists, and the whole band."
3. "Stop the group text chaos. Run your band like a pro."
4. "Everything your band needs. Nothing it doesn't."

### Subheadline Options

1. "BandRoadie brings gigs, rehearsals, setlists, calendars, and members into one shared workspace. Built by a musician. No ads. No bloat."
2. "Manage your gigs, build your setlists, and keep every band member on the same page — all in one app built for real bands."
3. "Forget the group text. Forget the spreadsheet. BandRoadie is your band's shared brain."

### Primary CTA Labels
- **"Download on the App Store"** *(leads to iOS App Store)*
- **"Open the Web App"** *(leads to app.bandroadie.com)*
- **"Get it on Google Play"** *(leads to Google Play Store)*

### Secondary CTA Labels
- "Try the Web App Free"
- "Start Your Band"
- "See How It Works"
- "Get BandRoadie — It's Free"

### Brand Tone Guidance

Write like a musician talking to another musician. Concrete, unpretentious, and slightly self-aware. Avoid startup buzzwords ("streamline," "leverage," "empower"). Use specific, relatable pain points — group texts, forgetting keys, showing up to the wrong venue — not abstract concepts. Humor is welcome but keep it dry. The voice is confident and practical, not flashy. The app is built by one musician for real working bands, and that story should come through everywhere.

---

## Section-by-Section Mapping

---

### 1. Navigation Bar

**Template Purpose:**
Sticky top nav with logo on the left, 4–5 nav links in the center, and a primary CTA button on the right. Gives visitors wayfinding and a persistent download hook.

**BandRoadie Content Recommendation:**
Keep the sticky nav. The BandRoadie logo (already exists as `bandroadie-logo.svg`) goes left. Nav links should map to the page's actual sections. CTA button is the primary conversion action — use "Download Free" which opens a smooth-scroll anchor to the download section.

**Suggested Copy:**
- Logo: BandRoadie wordmark / logo
- Nav links: Features · How It Works · Screenshots · Pricing · FAQ
- CTA Button: **"Download Free"**

**Suggested Visuals:**
- BandRoadie SVG logo (already available)
- Rose accent (#BE123C) on the CTA button, consistent with brand

**CTA:** Download Free → anchors to #download section

**Notes / Changes Needed:**
- Remove any "Pricing" nav link if the pricing section becomes a value summary instead
- On mobile, collapse to hamburger with same links
- Consider "Open Web App" as a secondary nav link for users who want immediate access

---

### 2. Hero Section

**Template Purpose:**
Full-width opening section with a bold headline, supporting subheadline, two CTAs (usually App Store + Google Play or App Store + Web), and a centered or right-aligned phone mockup showing the app. This is the highest-impact section on the page.

**BandRoadie Content Recommendation:**
Lead with the tension ("group text chaos," "spreadsheets") immediately resolved by the product. The hero mockup should show the band dashboard or gig view — something immediately recognizable to a musician who manages a band. Both App Store and Google Play badges, plus a web app link.

**Suggested Copy:**

**Headline:** Keeping your band in tune — on stage and off.

**Subheadline:** BandRoadie is the shared workspace your band actually needs. Gigs, rehearsals, setlists, calendars, and members — all in one place. No group texts. No spreadsheets. No drama.

**Below subheadline (supporting proof point):** Used by 100+ bands · No ads · No data selling · Free to download

**CTA Block:**
- Primary: [App Store badge] → https://apps.apple.com/us/app/band-roadie/id6757283775
- Secondary: [Google Play badge] → https://play.google.com/store/apps/details?id=com.bandroadie.app
- Tertiary text link: Or try the web app →

**Suggested Visuals:**
- Primary phone mockup: `Dashboard.png` — shows Next Rehearsal (Fri May 1 · Gallery Cabaret), Upcoming Gigs, Quick Actions. This is the strongest opening image — instantly recognizable to any musician who manages a band.
- Optional second phone (slightly offset and behind): `Setlist Detail.png` — shows the Originals setlist with BPM and tuning tags
- Dark background (#0A0A0A), rose accent on CTAs
- Crop the macOS window chrome from both screenshots before placing in the phone frame asset
- **Scroll animation:** The hero section typically does NOT use scroll animation — it loads immediately on page open. Use a subtle entrance animation (fade in, 400ms, 0 delay) triggered on page load, not scroll.

**CTA:**
- "Download on the App Store"
- "Get it on Google Play"
- "Try the Web App"

**Notes / Changes Needed:**
- The Google Play CTA should NOT show "Coming Soon" on the website — the app is live on Google Play
- The "100+ bands" data point should be used as social proof directly in the hero — it's a real number from the docs
- Consider a subtle animated loop or scroll indicator below the hero to encourage scrolling

---

### 3. Social Proof / Logo Bar

**Template Purpose:**
A slim horizontal section below the hero showing logos of publications, featured-in outlets, or "trusted by" company logos. Provides instant credibility signals.

**BandRoadie Content Recommendation:**
BandRoadie doesn't yet have press logos. Repurpose this section as a **quick-stat trust bar** — simple numbers and badges that give credibility without needing media coverage. This is honest and effective for an indie app.

**Suggested Copy (horizontal stat bar):**

| Stat | Label |
|------|-------|
| 100+ | Active bands |
| iOS + Android + Web | Available on |
| v1.4.0 | Current version |
| Zero | Ads. Ever. |
| Your data | Never sold |

Or as a text strip:
> "100+ bands · iOS · Android · Web · No ads · No data selling · Built by a musician"

**Suggested Visuals:**
- Apple App Store badge (small)
- Google Play badge (small)
- Optional: BandRoadie icon / small band silhouette illustration

**CTA:** None — this is a passive trust signal

**Notes / Changes Needed:**
- If press coverage is obtained before launch, swap stats for media logos
- Keep it minimal — 3–5 items max, no clutter
- Could also feature the App Store rating once reviews are in (e.g. ⭐⭐⭐⭐⭐ from App Store)

---

### 4. Feature Cards / Core Features Grid

**Template Purpose:**
A 2×2 or 3-column grid of feature cards — each with an icon, a short feature name, and a 1–2 sentence description. Gives visitors a quick overview of what the app actually does.

**BandRoadie Content Recommendation:**
Use exactly 6 feature cards (2 rows of 3, or 3 rows of 2 on mobile). Each card maps to a core BandRoadie feature area. Keep copy tight — one punchy benefit per card, not a feature spec.

**Suggested Copy (6 cards):**

**Card 1 — Gigs**
Icon: 🎤 (or calendar-star)
Title: Gig Management
Body: Add gigs with dates, location, load-in time, and pay. Track which members are available and assign a setlist — all in one place.

**Card 2 — Rehearsals**
Icon: 🥁 (or clock-repeat)
Title: Rehearsal Scheduling
Body: Schedule one-off or recurring rehearsals. Assign a setlist, add a location, and make sure everyone knows when and where to show up.

**Card 3 — Setlists**
Icon: 🎵 (or list-music)
Title: Setlists & Song Catalog
Body: Build setlists from your band's song library. Drag to reorder, track BPM, duration, and tuning per song, and add set breaks.

**Card 4 — Calendar**
Icon: 📅 (or calendar)
Title: Shared Band Calendar
Body: Every gig, rehearsal, and block-out date in one view. Subscribe via iCal to sync directly with Apple, Google, or Outlook Calendar.

**Card 5 — Members & Roles**
Icon: 👥 (or users)
Title: Member Directory
Body: Invite your whole band. Assign roles — Admin, Member, or Contributor. Everyone gets access; you control what they can change.

**Card 6 — Contacts & Venues**
Icon: 📍 (or map-pin)
Title: Venues & Contacts
Body: Keep a contact book of venues, bookers, agents, and promoters per band. Never lose a venue's load-in number again.

**Suggested Visuals:**
- Clean line icons (consistent with Lucide icon set already used in the app)
- Rose accent on icon containers, dark card backgrounds
- No photography needed here — icon + copy is sufficient

**CTA:** None on individual cards. Section can end with a ghost button: "See all features →"

**Notes / Changes Needed:**
- Do NOT include BPM fetching, PKCE auth, or technical implementation details — keep all copy user-facing and musician-oriented
- If the template only supports 4 cards, prioritize: Gigs, Setlists, Calendar, Members — the other two can appear in the alternating feature section below

---

### 5. "How It Works" — Step-by-Step Section

**Template Purpose:**
A numbered 3-step walkthrough showing the user journey from first use to value. Common pattern: Step 1 (setup), Step 2 (core action), Step 3 (outcome/benefit). Helps new visitors understand the onboarding ramp.

**BandRoadie Content Recommendation:**
Map directly to the BandRoadie first-run experience. The magic-link login is a genuine differentiator (no passwords) and should appear as Step 1. Steps should match the actual flow a new user experiences.

**Suggested Copy:**

**Section Headline:** Getting started takes about 3 minutes.

**Section Subheadline:** No password required. No credit card. No nonsense.

---

**Step 1 — Log in with just your email**
We send you a magic link. Click it, and you're in. No password to forget, no account to create separately. Just your email.

**Step 2 — Create your band and invite the crew**
Name your band, upload a photo, and send invites to your bandmates by email. They click the link, join instantly, and see everything in real time.

**Step 3 — Add your gigs, setlists, and rehearsals**
Build your setlist from your song catalog. Schedule your next rehearsal. Add your upcoming gig with load-in time and pay details. Your whole band sees it the moment you hit save.

---

**Suggested Visuals:**
- 3 phone frames side by side (or a horizontal scroll on mobile) showing:
  - Step 1: The magic-link login screen / email entry
  - Step 2: The "Create Band" or Band Dashboard screen
  - Step 3: The Gig or Setlist view with populated content
- Numbered circle badges (1, 2, 3) in rose accent

**CTA:** "Start Your Band Free →" at the bottom of the section

**Notes / Changes Needed:**
- Emphasize "no password" — this is genuinely unusual and memorable
- Keep step descriptions conversational, not instructional
- If multi-band support is a selling point for the target audience (musicians in multiple bands), add a note: "BandRoadie supports multiple bands — switch between them with one tap."

---

### 6. App Screenshots Carousel / Showcase Section

**Template Purpose:**
A visually prominent section — usually full-width with a dark background — showing 4–6 actual app screenshots in a carousel or scrollable row of phone frames. This is the "show don't tell" section. It's often the highest-engagement section on a mobile app landing page.

**BandRoadie Content Recommendation:**
This section needs real screenshots — it cannot use placeholders. The order of screenshots should tell a story: you see the band, you plan the gig, you build the setlist, you see the calendar. Each screenshot should have a short caption below it.

**Confirmed Screenshot Order & Captions (exact filenames from `~/Desktop/Screenshots/`):**

| Slide | File | Caption |
|---|---|---|
| 1 | `Dashboard.png` | "Your band at a glance — next rehearsal, upcoming gigs, and quick actions." |
| 2 | `Add Event.png` | "Add a rehearsal, gig, or block-out date in seconds — with recurrence built in." |
| 3 | `Edit Rehearsal.png` | "Edit any event on the fly. Change the time, location, or attached setlist instantly." |
| 4 | `Calendar.png` | "Your full band calendar with gigs, rehearsals, and block-out dates in one view." |
| 5 | `Band Contacts.png` | "Your full band directory — instruments, phone, email, and address per member." |
| 6 | `Venue Contacts.png` | "Venues, bookers, and contacts stored per band. Never lose a number again." |

**Suggested Visuals:**
- Place each screenshot inside a phone frame asset (these are macOS window captures — crop out the window chrome and frame them in an iPhone 15 Pro mockup)
- All screenshots are dark mode — consistent, no mixing needed
- Smooth horizontal scroll carousel with dot indicators (already in GenieNova template — preserve as-is)

**Scroll animation:** Each slide entrance uses the template's existing fade-up interaction. Do not override — just apply the existing animation class to each new slide element.

**CTA:** App Store / Google Play badges pinned below the carousel

**Notes / Changes Needed:**
- `Add Event.png` is an especially strong slide — it clearly shows the Rehearsal / Gig / Block Out tab row, communicating all three event types in a single image
- `Calendar.png` shows a blockout date ("Tony Out · Spring break") in the event list — this doubles as the blockout dates proof point
- Caption text is one line max. The screenshot carries the detail.

---

### 7. Feature Deep-Dive — Alternating Content Blocks

**Template Purpose:**
2–3 alternating "feature spotlight" blocks — each one has a headline, 2–3 sentences of copy, a bullet list of specifics, and a screenshot or illustration on the opposite side. Left-text/right-image, then right-text/left-image, and so on. This section converts visitors who want more than the quick-hit feature cards.

**BandRoadie Content Recommendation:**
Expand to 6 spotlight blocks covering the features the user specifically requested: Adding Events, Editing Events, Dashboard, Calendar, Contacts, Blockout Dates, and Potential Gigs. Use alternating left/right layout. Each block uses a confirmed screenshot from `~/Desktop/Screenshots/`.

---

**Block 1 — Adding Events (text left, screenshot right)**

**Headline:** Add a gig, rehearsal, or block-out in seconds.

**Body:** Hit "+ Add Event" from the dashboard or calendar and you're one tap away from scheduling anything. Choose Rehearsal, Gig, or Block Out — fill in the details, pick a setlist, toggle recurrence, and save. Your whole band sees it immediately.

**Bullet points:**
- Rehearsals, gigs, and block-out dates from one form
- Set duration with ±15 min quick adjusters
- Make any rehearsal recurring with one toggle
- Attach a setlist directly at the time of creation
- Add notes for any event

**Screenshot file:** `Add Event.png` (primary) + `Add Event 2.png` (secondary / scrolled view showing setlist picker and notes)

**Scroll animation:** Text column fades up, screenshot fades up 150ms later.

---

**Block 2 — Editing Events (text right, screenshot left)**

**Headline:** Change plans? Update the event. Everyone's calendar updates too.

**Body:** Rehearsal moved to a different room? Load-in pushed back? Open the event, make the change, and hit Update. Your bandmates see the new details instantly — no group text required.

**Bullet points:**
- Edit date, time, duration, location, or setlist at any time
- Toggle recurring rehearsals on or off
- Delete an event when plans fall through
- Changes appear in real time for the whole band
- Setlist assignments update without re-sharing anything

**Screenshot file:** `Edit Rehearsal.png` (primary — shows date, time, duration, location, setlist selector) + `Edit Rehearsal 2.png` (desktop view showing the Delete Event button)

**Scroll animation:** Screenshot slides in from left, text fades up from right, staggered 100ms.

---

**Block 3 — Dashboard (text left, screenshot right)**

**Headline:** Open the app and know exactly what's coming up.

**Body:** The BandRoadie dashboard shows your next rehearsal, your upcoming gigs, and quick actions to add an event or start a setlist — right on the home screen. No digging, no scrolling, no hunting through a calendar. The most important information is always front and center.

**Bullet points:**
- Next rehearsal date, time, and location at a glance
- Upcoming gigs listed with date and time
- Quick action buttons: Add Event · Create Setlist
- Shared in real time — every member sees the same view
- Works on iOS, Android, and web

**Screenshot file:** `Dashboard.png` — shows "The Second Summer" band with Next Rehearsal (Fri May 1, Gallery Cabaret), Upcoming Gigs (Underground Lounge, Photo shoot), Quick Actions

**Scroll animation:** Text fades up first, then screenshot fades up 150ms later.

---

**Block 4 — Calendar & Block-out Dates (text right, screenshot left)**

**Headline:** The full picture — gigs, rehearsals, and who's out of town.

**Body:** BandRoadie's calendar shows every event your band has scheduled, plus member block-out dates so you know who's available when. Need to know if Saturday is clear before booking a gig? Check the calendar. Planning a rehearsal around a member's holiday? Block-out dates have you covered.

**Bullet points:**
- Month view with all gigs, rehearsals, and block-out dates
- Members can block dates they're unavailable (e.g. "Tony Out · Spring break")
- Subscribe via iCal — syncs to Apple, Google, or Outlook Calendar
- Choose which event types appear in your external calendar
- Calendar stays in sync as events change

**Screenshot file:** `Calendar.png` (primary — month view showing events + "Tony Out · Spring break" blockout) + `Subscribe Calednar feed.png` (secondary — iCal subscription modal with Gigs/Rehearsals/Block-out day toggles)

> **Note on the filename typo:** The file is saved as `Subscribe Calednar feed.png` (typo: "Calednar"). Use as-is in the Webflow asset panel — just reference correctly in the handoff.

**Scroll animation:** Screenshots slide in from left, text fades up from right, 100ms stagger.

---

**Block 5 — Contacts & Venues (text left, screenshot right)**

**Headline:** Your band's contact book, built into the app.

**Body:** Keep track of your band members, your regular venues, and the people who book them — all stored per band. No more scrolling through your personal phone contacts for the venue's load-in number. It's all in BandRoadie, right where you need it.

**Bullet points:**
- Band member directory with instruments, phone, email, and address
- Venue directory with address and phone per venue
- Add bookers, agents, and other contacts per venue
- Separate from your personal contacts — band-only
- Available to every member of the band

**Screenshot file:** `Band Contacts.png` (primary — shows Steve Gatland and Tony Holmes with full contact details and instrument tags) + `Venue Contacts.png` (secondary — Gallery Cabaret, Montrose Saloon, Underground Lounge)

**Scroll animation:** Text fades up, screenshot fades up 150ms later.

---

**Block 6 — Potential Gigs (text right, screenshot left)**

**Headline:** Track the bookings you're working on, not just the ones you've confirmed.

**Body:** Not every gig inquiry turns into a confirmed date. Mark a gig as "potential" to keep it on your radar without adding it to the full band calendar. When it confirms, flip the toggle and it shows up for everyone. No more sticky notes, no more "wait, did that venue get back to us?"

**Bullet points:**
- Mark any gig as potential while it's still being negotiated
- Potential gigs stay separate from confirmed events
- Convert to confirmed with one tap when it's locked in
- Keep the whole band informed about what's in the pipeline
- Useful for touring acts and busy gigging bands

**Screenshot file:** ⚠️ **MISSING — screenshot needed.** Capture the Add Event form with the "Gig" tab selected, showing the "Mark as potential" toggle enabled. Use `Add Event.png` as a temporary placeholder (the Gig tab is visible in the tab row).

**Scroll animation:** Screenshot slides in from left, text fades up from right, 100ms stagger.

---

**Suggested Visuals (all 6 blocks):**
- Phone frame screenshots at roughly 45% of the section width on desktop
- Sufficient padding (80–120px) between text and screenshot so they breathe
- Alternate background color between blocks: #0A0A0A and a very slightly lighter #111111 — creates rhythm without hard dividers

**CTA:** No CTA needed on individual blocks — let the primary download CTA at the bottom of the page carry conversion

**Notes / Changes Needed:**
- Keep all copy in musician-voice: "No more sticky notes" rather than "Track pipeline opportunities"
- Do not reference technical internals anywhere
- The block order above is recommended but can be reordered based on what resonates in user testing — Dashboard and Adding Events should always appear in the first two positions

---

### 8. Testimonials Section

**Template Purpose:**
A 3-column grid (or horizontal scroll on mobile) of quote cards. Each has a quote, the person's name, and their role/context. Builds social trust and helps prospects see themselves in the product.

**BandRoadie Content Recommendation:**
This requires actual testimonials from real BandRoadie users. With 100+ bands active as of March 2026, there are enough users to collect 3–6 strong quotes. Until real testimonials are available, use clearly marked placeholder copy that captures the voice of the eventual real quotes.

**Suggested Placeholder Copy (to be replaced with real user quotes):**

**Quote 1**
> "We used to manage everything in a group text and a shared Google sheet. BandRoadie replaced both. Our drummer actually shows up knowing what songs we're playing now."
— *[Name], guitarist, [Band Name] — [City]*

**Quote 2**
> "The setlist builder alone is worth it. I used to make ours in a Notes doc and text a photo before every gig. Now everyone just opens the app."
— *[Name], bassist, [Band Name]*

**Quote 3**
> "I run three bands. Being able to switch between them in one app and keep everything separate is the thing I didn't know I needed."
— *[Name], drummer / multi-band musician*

**Quote 4 (optional)**
> "Magic link login sounds like a small thing but it means none of my bandmates have to remember a password. That alone cut down on 'I can't log in' messages."
— *[Name], band admin, [Band Name]*

**Suggested Visuals:**
- Dark card backgrounds with a subtle rose accent border or top stripe
- Initials avatar or band photo (if users consent to photo use)
- 3 cards visible at once on desktop, single card + swipe on mobile
- Star rating row (5 stars, matching App Store rating) if reviews are available

**CTA:** Below the testimonials section — "Join 100+ bands on BandRoadie" with App Store + Play Store badges

**Notes / Changes Needed:**
- Do NOT use AI-generated testimonials on the live site — collect real ones from existing users before launching
- Ask users specifically: "What did you use before BandRoadie? What changed?" — contrast-style quotes are most persuasive
- Target diverse band types: cover bands, originals bands, tribute acts, gigging bands vs. rehearsal-only
- Include the user's instrument or role where possible — it signals to prospects that people like them are using it

---

### 9. Pricing Section

**Template Purpose:**
Typically 2–3 pricing tier cards (Free / Pro / Team) with a feature checklist per tier. This section drives conversion for freemium or paid apps. Often includes a toggle for monthly/annual billing.

**BandRoadie Content Recommendation:**
BandRoadie is currently free — there is no paid tier. The template's pricing section needs to be repurposed. Two options:

**Option A (Recommended for now): "What's Included" Section**
Reframe as a transparency / value section: "Everything's included. For free." Show a single card or checklist of everything BandRoadie includes at no cost, and use the privacy-first messaging (no ads, no data selling) as the value explanation for why it's free.

**Option B (Future-proof): Free vs. Pro Placeholder**
If a Pro tier is planned, lay out the tier structure now with "Coming soon" on Pro. This sets expectations without committing to a price.

**Recommended: Option A copy**

**Section Headline:** Everything your band needs. Free.

**Section Subheadline:** No hidden fees. No ads. No selling your data. BandRoadie is free to download and use. Full stop.

**Included feature list (single card):**
✓ Band dashboard  
✓ Unlimited gigs and rehearsals  
✓ Setlists with drag-and-drop ordering  
✓ Song catalog with BPM, tuning, and duration  
✓ Shared band calendar  
✓ iCal subscription for external calendar sync  
✓ Member directory with roles and permissions  
✓ Venues and contacts directory  
✓ Push notifications (iOS and Android)  
✓ Data backup and restore  
✓ Multi-band support  
✓ No ads. No data selling. No passwords.  

**Below the card:**
> "BandRoadie was built by a musician who wanted this tool to exist. It's free because it should be."

**Suggested Visuals:**
- Single centered card (not a 3-tier comparison) in the template's pricing component
- Rose accent checkmarks
- Clean, generous whitespace — this should feel premium, not like a freemium pitch

**CTA:** "Download Free →" (App Store badge below)

**Notes / Changes Needed:**
- Explicitly replace the pricing tier comparison UI with a single "what's included" card — do not leave the 3-tier pricing structure in place, as it implies a freemium model that doesn't exist
- If pricing is introduced in future, this section can be split easily without redesigning the page

---

### 10. FAQ Section

**Template Purpose:**
An accordion-style list of 5–8 common questions that address buyer hesitation, technical confusion, or objections. Reduces support load and increases conversion by pre-answering the questions people have before downloading.

**BandRoadie Content Recommendation:**
Focus on the questions a musician or band manager actually asks before downloading a band management app. Prioritize: platform availability, privacy, cost, and the magic-link login (which is unusual and needs explaining).

**Suggested Copy:**

**Q: Is BandRoadie really free?**
A: Yes. BandRoadie is free to download and use on iOS, Android, and web. There are no ads, no in-app purchases, and no subscription required. It was built by a musician and released as a free tool for real working bands.

**Q: What platforms is BandRoadie available on?**
A: BandRoadie is available on iPhone and iPad (iOS 16.6+), Android, and as a web app you can use from any browser at app.bandroadie.com. All platforms stay in sync in real time.

**Q: What's a magic link? Do I need a password?**
A: No password needed. When you log in, we send a one-time login link to your email. You click it, and you're in — no account creation, no password to forget or reset. It's more secure and a lot less frustrating than a traditional login.

**Q: Can I be in more than one band?**
A: Yes. BandRoadie supports multiple bands from a single account. Switch between them from the app's band selector. Each band's data is completely separate.

**Q: What happens to my band's data? Is it private?**
A: Your data is only accessible to members of your band. We don't sell user data, we don't run ads, and we don't share your information with third parties. Full details are in our Privacy Policy.

**Q: Can I sync BandRoadie with my external calendar (Google, Apple, Outlook)?**
A: Yes. BandRoadie generates an iCal (ICS) feed for your band that you can subscribe to in any calendar app. Gigs, rehearsals, and block-out dates sync automatically. Your external calendar always reflects your BandRoadie schedule.

**Q: Does my whole band need to download the app?**
A: They need the app or web access to see real-time updates, but you can invite them with just their email address. They get a link, tap it, and they're in. No account setup required on their end.

**Q: Can I back up my band's data?**
A: Yes. Band admins can export a full backup of the band's data — setlists, songs, gigs, rehearsals, members, and contacts — as a JSON file. You can restore from that backup at any time.

**Suggested Visuals:**
- Standard accordion component (one question open at a time)
- Clean typography, no icons needed
- Rose accent on the expand/collapse toggle

**CTA:** Below FAQ — "Still have questions? [Contact Support]" (mailto link or support page when available)

**Notes / Changes Needed:**
- Keep answers in plain English — no technical terms (no Supabase, PKCE, FCM, etc.)
- The magic-link FAQ is important — many users will be confused or hesitant about it
- Add a "Can I try it before inviting my band?" question if user testing shows that's a concern

---

### 11. Final CTA / Download Section

**Template Purpose:**
A high-contrast, full-width "download now" closing section — typically a bold headline, a 1-line subheadline, and the App Store + Google Play badges side by side. This is the last conversion point before the footer.

**BandRoadie Content Recommendation:**
Return to the core tension and resolution. Make the emotional appeal here — the frustration of band logistics and the relief of having it solved. Both badges plus the web app link, so no one is left without a path to get started.

**Suggested Copy:**

**Headline:** Your band runs on group texts. It doesn't have to.

**Subheadline:** BandRoadie brings your gigs, setlists, rehearsals, and members into one shared workspace — free on iOS, Android, and web.

**CTA block:**
- [Download on the App Store] → https://apps.apple.com/us/app/band-roadie/id6757283775
- [Get it on Google Play] → https://play.google.com/store/apps/details?id=com.bandroadie.app
- Or use the web app at → app.bandroadie.com

**Suggested Visuals:**
- High-contrast section — rose accent background or near-black background with rose accents
- App Store and Google Play official badges (sized to match)
- Optional: single phone mockup showing the dashboard, reinforcing product imagery
- This section should feel like an emotional close, not a transactional form

**CTA:**
- "Download on the App Store" → iOS App Store
- "Get it on Google Play" → Google Play Store
- "Open Web App" → app.bandroadie.com

**Notes / Changes Needed:**
- Both app store badges must link to real, live listings
- The web app link should be prominent — some visitors will want to try before downloading
- Do not use "Coming Soon" language for any platform that is live
- This section should not repeat feature bullets — the visitor has already seen them; just close the emotional loop

---

### 12. Footer

**Template Purpose:**
Standard footer with logo, tagline, nav links grouped by category (Product, Legal, Social), copyright line, and sometimes app store badges repeated.

**BandRoadie Content Recommendation:**
Keep it simple. BandRoadie is a single product — the footer doesn't need a multi-column product directory. A logo, a tagline, 4–5 links, and the copyright line is sufficient. Include the app store badges here so they're reachable from any scroll depth.

**Suggested Copy:**

**Logo:** BandRoadie wordmark

**Tagline:** For bands who have better things to do than manage their band.

**Links (single row or 2 columns):**
- Privacy Policy → /privacy
- Terms of Service → /terms *(needs to be created)*
- Support → /support or mailto:support@bandroadie.com *(needs to be created)*
- Web App → app.bandroadie.com

**App store badges (small):**
- App Store badge
- Google Play badge

**Copyright:** © 2026 BandRoadie. All rights reserved.

**Suggested Visuals:**
- Dark footer background (#0A0A0A or similar)
- Subdued text — no bright colors in the footer itself
- SVG logo in white or rose accent

**CTA:** App Store + Google Play badges in footer

**Notes / Changes Needed:**
- Terms of Service page does not yet exist — create a placeholder page before launch
- Support page / contact method also doesn't exist — create before launch
- Social media links can be added if BandRoadie has active profiles; otherwise omit (dead links are worse than no links)
- Footer tagline should be slightly warmer/wittier than the hero — it's the last thing they see

---

## Content Gaps

The following assets and content items need to be created or collected before this website can launch:

### Screenshots — Status

Screenshots from `~/Desktop/Screenshots/` cover most sections. The following have been confirmed usable:

| File | Status | Used In |
|---|---|---|
| `Dashboard.png` | ✅ Ready | Hero · Carousel · Dashboard block |
| `Add Event.png` | ✅ Ready | Carousel · Adding Events block |
| `Add Event 2.png` | ✅ Ready | Adding Events block (secondary) |
| `Edit Rehearsal.png` | ✅ Ready | Carousel · Editing Events block |
| `Edit Rehearsal 2.png` | ✅ Ready | Editing Events block (desktop view) |
| `Calendar.png` | ✅ Ready | Carousel · Calendar/Blockout block |
| `Subscribe Calednar feed.png` | ✅ Ready (filename has typo) | Calendar block (secondary) |
| `Band Contacts.png` | ✅ Ready | Carousel · Contacts block |
| `Venue Contacts.png` | ✅ Ready | Contacts block (secondary) |
| `Setlist Detail.png` | ✅ Ready | Hero (secondary) · Setlists block |
| `Setlists.png` | ✅ Ready | Setlists block |
| `Setlist preview.png` | ✅ Ready | Setlists block (print callout) |
| `Edit band.png` | ✅ Ready | How It Works step 2 |

**Still needed before launch:**

- [ ] **Potential Gig screenshot** — Add Event form with Gig tab selected and "Mark as potential" toggle visible. This is the only requested feature with no screenshot.
- [ ] **Magic-link login screen** — email entry / "check your email" screen for How It Works step 1
- [ ] **Gig detail view** — a confirmed gig with load-in time, member RSVP (yes/no per member), and attached setlist visible. This is distinct from the Add Event form and needed for the gig feature callout.

**Pre-use prep for all existing screenshots:**
- All are macOS window captures — crop out the window chrome (traffic lights, title bar) before placing in phone frames
- No simulator screenshots needed — existing captures are sufficient

### Testimonials (Required — collect from real users)
- [ ] Minimum 3 testimonials from real BandRoadie users before launch
- [ ] Need: quote, name, instrument/role, band name (optional), city (optional)
- [ ] Preferred format: contrast-style ("Before X, now Y")

### Missing Pages (Must exist before launch)
- [ ] Terms of Service page (`/terms`)
- [ ] Support/Contact page (`/support`) with email or contact form

### Brand Assets
- [ ] BandRoadie horizontal logo (SVG) — confirmed exists at root
- [ ] App Store badge (official Apple asset)
- [ ] Google Play badge (official Google asset)
- [ ] Favicon / PWA icon — confirm it matches brand

### Data Points to Confirm
- [ ] Exact band count (docs say "100+ bands" as of March 2026 — confirm current number)
- [ ] App Store rating and review count (once reviews accumulate)
- [ ] Any press mentions or third-party coverage

### Optional Enhancements
- [ ] A short product demo video (30–60 seconds) — would dramatically increase the hero section's conversion
- [ ] Animated app icon or lottie animation for feature icons
- [ ] Band photo or musician photography for testimonial avatars

---

## Recommended Page Flow

The GenieNova template's default section order maps well to BandRoadie with one swap (Pricing becomes "What's Included"). Recommended final order:

1. **Navbar** — sticky, persistent
2. **Hero** — headline, app badges, phone mockup
3. **Trust Bar** — band count, platforms, privacy stat
4. **Core Feature Cards** — 6-card grid
5. **How It Works** — 3-step walkthrough
6. **App Screenshots Carousel** — visual showcase
7. **Feature Deep-Dive** — 3 alternating spotlight blocks (Setlists, Gigs, Calendar)
8. **Testimonials** — 3–4 user quotes
9. **What's Included (Pricing reframe)** — everything free, listed
10. **FAQ** — 8 questions
11. **Final Download CTA** — emotional close, app badges
12. **Footer** — links, copyright, badges

---

## Final Homepage Draft

*Clean copy, in section order, ready for a designer/developer to place into the Webflow template.*

---

### [NAVBAR]

**Logo:** BandRoadie  
**Nav:** Features · How It Works · Screenshots · FAQ  
**CTA Button:** Download Free

---

### [HERO]

**Headline:**
Keeping your band in tune — on stage and off.

**Subheadline:**
BandRoadie brings gigs, rehearsals, setlists, calendars, and members into one shared workspace. No group texts. No spreadsheets. No drama.

**Supporting proof line:**
Used by 100+ bands · No ads · No data selling · Free to download

**Primary CTA:** Download on the App Store  
**Secondary CTA:** Get it on Google Play  
**Tertiary link:** Or open the web app →

---

### [TRUST BAR]

100+ active bands  ·  iOS · Android · Web  ·  No ads  ·  No data selling  ·  Built by a musician

---

### [CORE FEATURES]

**Section headline:** Everything your band needs. In one place.

**Gig Management**
Add gigs with dates, location, load-in time, and pay. Track member availability and attach your setlist — all in one screen.

**Rehearsal Scheduling**
Schedule one-off or recurring rehearsals. Assign a setlist, add a location, and make sure everyone knows when and where to be.

**Setlists & Song Catalog**
Build setlists from your song library. Drag to reorder, track BPM and tuning per song, and add set breaks.

**Shared Band Calendar**
Every gig, rehearsal, and block-out date in one view. Subscribe via iCal to sync with Apple, Google, or Outlook Calendar.

**Member Directory & Roles**
Invite your whole band by email. Assign roles — Admin, Member, or Contributor. Everyone in, everything controlled.

**Venues & Contacts**
Keep a contact book of venues, bookers, agents, and promoters. Never lose a venue's load-in number again.

---

### [HOW IT WORKS]

**Section headline:** Getting started takes about 3 minutes.  
**Subheadline:** No password required. No credit card. No nonsense.

**Step 1 — Log in with just your email**
We send you a magic link. Click it, and you're in. No password to forget, no account to create separately.

**Step 2 — Create your band and invite the crew**
Name your band, upload a photo, and invite your bandmates by email. They click, join, and see everything in real time.

**Step 3 — Add your gigs, setlists, and rehearsals**
Build your setlist. Schedule your rehearsal. Add your next gig with load-in time and pay. Your whole band sees it the moment you hit save.

**CTA:** Start Your Band Free →

---

### [SCREENSHOTS CAROUSEL]

*(No body copy — visual section)*

**Caption 1:** Your band at a glance. Upcoming gigs and rehearsals on your dashboard.  
**Caption 2:** Drag-and-drop setlists with BPM, duration, tuning, and set breaks.  
**Caption 3:** Gig details, load-in time, pay, and member RSVP — all in one screen.  
**Caption 4:** Your full band calendar: gigs, rehearsals, and block-out dates.  
**Caption 5:** Your song library with BPM, tuning, and duration per track.  
**Caption 6:** Invite your band, assign roles, manage who can do what.

---

### [FEATURE SPOTLIGHT — SETLISTS]

**Headline:** Build setlists your whole band can actually use.

Stop emailing PDFs around. BandRoadie's setlist builder lives in the app, updates in real time, and travels to every gig on every bandmate's phone. Assign a setlist directly to a gig or rehearsal so there's never confusion about which version you're playing.

- Drag-and-drop to reorder any song instantly
- BPM, duration, and tuning stored per song
- Add set breaks with custom durations
- Share as plain text via native share sheet
- Print-ready export with customizable layout

---

### [FEATURE SPOTLIGHT — GIGS]

**Headline:** Every gig detail — for everyone.

Add a gig, fill in the load-in time, the pay, the venue, and which members are required. Your band sees it the moment it's saved. They RSVP in the app, and you can see at a glance who's in and who's out. No more "wait, are we confirmed for Saturday?"

- Gig date, time, location, and load-in time
- Per-gig member availability tracking (yes/no RSVP)
- Attach your setlist directly to the gig
- Track potential gigs while bookings are in progress
- Venue and contacts stored in your band's directory

---

### [FEATURE SPOTLIGHT — CALENDAR]

**Headline:** Your band's schedule, synced to the calendar you already use.

BandRoadie's shared calendar shows every gig, rehearsal, and block-out date in one view. Subscribe via iCal to pull your schedule directly into Apple Calendar, Google Calendar, or Outlook — and it stays in sync automatically.

- Subscribe to your band's iCal feed in one tap
- Syncs gigs, rehearsals, and block-out dates
- Members can block out dates they're unavailable
- Works with Apple Calendar, Google Calendar, and Outlook
- Updates automatically as events change

---

### [TESTIMONIALS]

**Section headline:** Real bands. Real relief.

*[Testimonial 1 — to be collected from user]*  
*[Testimonial 2 — to be collected from user]*  
*[Testimonial 3 — to be collected from user]*

**Below testimonials:** Join 100+ bands on BandRoadie →

---

### [WHAT'S INCLUDED]

**Headline:** Everything's included. For free.

**Subheadline:** No hidden fees. No ads. No selling your data. BandRoadie is free to download and use.

✓ Band dashboard  
✓ Unlimited gigs and rehearsals  
✓ Setlists with drag-and-drop ordering  
✓ Song catalog with BPM, tuning, and duration  
✓ Shared band calendar  
✓ iCal subscription for external calendar sync  
✓ Member directory with roles and permissions  
✓ Venues and contacts directory  
✓ Push notifications (iOS and Android)  
✓ Data backup and restore  
✓ Multi-band support  
✓ No ads. No data selling. No passwords.

> "BandRoadie was built by a musician who wanted this tool to exist. It's free because it should be."

**CTA:** Download Free →

---

### [FAQ]

**Section headline:** Questions? We've got answers.

**Q: Is BandRoadie really free?**
Yes. BandRoadie is free to download and use on iOS, Android, and web. There are no ads, no in-app purchases, and no subscription required.

**Q: What platforms is it available on?**
iPhone and iPad (iOS 16.6+), Android, and as a web app at app.bandroadie.com. All platforms stay in sync in real time.

**Q: What's a magic link? Do I need a password?**
No password needed. We send a one-time login link to your email. Click it and you're in — no password to forget or reset.

**Q: Can I be in more than one band?**
Yes. BandRoadie supports multiple bands from a single account. Switch between them from the band selector. Each band's data is completely separate.

**Q: Is my band's data private?**
Your data is only accessible to members of your band. We don't sell user data, we don't run ads, and we don't share your information with third parties.

**Q: Can I sync my schedule with Google or Apple Calendar?**
Yes. BandRoadie generates an iCal feed for your band that you can subscribe to in any calendar app. It syncs gigs, rehearsals, and block-out dates automatically.

**Q: Does my whole band need to download the app?**
They need the app or web access to see real-time updates. Invite them with just their email — they tap the link and they're in with no setup required.

**Q: Can I back up my band's data?**
Yes. Band admins can export a full backup — setlists, songs, gigs, rehearsals, members, and contacts — as a file you can restore from at any time.

---

### [FINAL CTA]

**Headline:** Your band runs on group texts. It doesn't have to.

**Subheadline:** BandRoadie brings your gigs, setlists, rehearsals, and members into one shared workspace — free on iOS, Android, and web.

**CTA Block:**
- Download on the App Store →
- Get it on Google Play →
- Or use the web app →

---

### [FOOTER]

**Tagline:** For bands who have better things to do than manage their band.

**Links:** Privacy Policy · Terms of Service · Support · Web App

**Badges:** App Store · Google Play

**Copyright:** © 2026 BandRoadie. All rights reserved.

---

*End of content mapping document.*

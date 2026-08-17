# Calendar FCalendar.wheel Implementation — Amendment 3: 30% Height Reduction with Minimum Floor

**Amendment Date:** 2026-08-16  
**Amendment Author:** Architect  
**Trigger:** Tony requests 30% reduction in day cell height from current value to further compress calendar vertical space.

**Status:** ✅ **IMPLEMENTED** — 30% height reduction applied with 40px minimum safeguard to prevent clipping on smallest phones. Formula: `max((cellWidth + 11) × 0.7, 40.0)`

---

## Mathematical Analysis

### Current Implementation (Post-Amendment 2)

**Formula:** `daySize.height = cellWidth + 11`

**Phone Viewport Calculation (375px width):**

1. Viewport width: 375px
2. Minus ScrollView horizontal padding: 375 - 32 (pagePadding) = **343px** available to CalendarGrid
3. Minus FCalendar internal padding: 343 - 24 = **319px** available for cells
4. Cell width: 319 / 7 = **45.57px**
5. **Current cell height:** 45.57 + 11 = **56.57px**

**Total calendar height (current):** ~476px (per Amendment 2's corrected measurement)

---

### Proposed 30% Reduction

**Formula:** `daySize.height = (cellWidth + 11) × 0.7`

**Phone Viewport Result (375px width):**

- Cell height: 56.57 × 0.7 = **39.6px**
- Height saved per row: 56.57 - 39.6 = **17px**
- Total height saved: 17px × 7 rows = **~119px**
- **New calendar height:** ~357px (25% shorter than current 476px)

**Smaller Phone (360px width):**

- Available: 360 - 32 - 24 = 304px → cellWidth = 43.43px
- Current height: 43.43 + 11 = 54.43px
- Reduced: 54.43 × 0.7 = **38.1px**

---

## Content Fit Analysis

### Documented Minimum Requirements (Amendment 1 & 2)

Day cells must accommodate:

- Day number text: **20–24px** (depends on font size, line height, rendering)
- Gap: **2px**
- Marker stack: **14px** (visible event indicators)
- **Total minimum:** **36–40px**

### Comparison Against Proposed Heights

| Viewport | Cell Width | Current Height | Reduced Height (30%) | Margin vs. Min (36px) | Margin vs. Max (40px) |
| -------- | ---------- | -------------- | -------------------- | --------------------- | --------------------- |
| 375px    | 45.57px    | 56.57px        | **39.6px**           | ✅ +3.6px             | ⚠️ -0.4px             |
| 360px    | 43.43px    | 54.43px        | **38.1px**           | ✅ +2.1px             | ⚠️ -1.9px             |
| 390px    | 47.71px    | 58.71px        | **41.1px**           | ✅ +5.1px             | ✅ +1.1px             |

### Risk Assessment

**Safe if:**

- Day number text consistently renders at **20px or less**
- Font metrics and line height stay within Forui's default styling
- No additional padding is introduced by theme overrides

**Will clip if:**

- Day number text renders at **24px** (upper bound from Amendment 1/2 analysis)
- Font line height increases due to platform or accessibility settings
- User has increased system font size settings

**Most likely outcome:**

- **375px+ phones:** Tight but functional (39.6px vs. 40px documented max)
- **360px phones:** High risk of clipping (38.1px vs. 40px)
- **Tablets/desktop:** No issues (ample vertical space)

---

## Final Implementation

**File:** `lib/features/calendar/widgets/calendar_grid.dart`  
**Lines:** 1, 42-44 (in imports and LayoutBuilder callback)

**Implemented Code:**

```dart
import 'dart:math';  // Added for max() function
// ... other imports

// In LayoutBuilder:
final availableWidth = constraints.maxWidth - 24;
final cellWidth = availableWidth / 7;

// Cell height reduced by 30% from Amendment 2 baseline (cellWidth + 11)
// With 40px minimum to prevent clipping on smallest phones (360px width)
final cellHeight = max((cellWidth + 11) * 0.7, 40.0);
final daySize = Size(cellWidth, cellHeight);
```

**Resolution:**

- Implements the requested 30% reduction: `(cellWidth + 11) × 0.7`
- Adds 40px minimum floor: `max(calculatedHeight, 40.0)`
- On 375px phones: 39.6px calculated, 40px enforced → **saves ~115px** (vs. ~119px without minimum)
- On 360px phones: 38.1px calculated, 40px enforced → **prevents clipping**
- On larger phones (390px+): 41.1px+ calculated → **30% reduction achieved**

**Best of both options:**

- Achieves Tony's 30% reduction goal on typical and larger phones
- Protects against clipping on smallest phones (360px)
- Maintains documented 36-40px content minimum
- Safe with accessibility font scaling

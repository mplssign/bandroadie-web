/**
 * Utilities for grouping and managing blockout date ranges
 */

export interface BlockoutRow {
  id?: string;
  user_id: string;
  date: string; // YYYY-MM-DD format
  notes?: string;
  band_id?: string;
  reason?: string;
}

export interface BlockoutRange {
  user_id: string;
  start_date: string; // YYYY-MM-DD
  end_date: string; // YYYY-MM-DD (>= start_date)
  dayCount: number;
  sourceIds: string[]; // IDs from original rows
  notes?: string;
  reason?: string;
  band_id?: string;
}

/**
 * Convert YYYY-MM-DD string to Date object at midnight UTC
 */
function toDate(dateStr: string): Date {
  return new Date(`${dateStr}T00:00:00Z`);
}

/**
 * Convert Date to YYYY-MM-DD string
 */
function toYMD(date: Date): string {
  const year = date.getUTCFullYear();
  const month = String(date.getUTCMonth() + 1).padStart(2, '0');
  const day = String(date.getUTCDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

/**
 * Check if date b is exactly one day after date a
 */
function isNextDay(a: string, b: string): boolean {
  const dateA = toDate(a);
  const dateB = toDate(b);
  const nextDay = new Date(dateA);
  nextDay.setUTCDate(nextDay.getUTCDate() + 1);
  return toYMD(nextDay) === toYMD(dateB);
}

/**
 * Get the minimum date from an array of date strings
 */
function minDate(dates: string[]): string {
  return dates.reduce((min, curr) => (curr < min ? curr : min));
}

/**
 * Get the maximum date from an array of date strings
 */
function maxDate(dates: string[]): string {
  return dates.reduce((max, curr) => (curr > max ? curr : max));
}

/**
 * Calculate the number of days between two dates (inclusive)
 */
function daysBetween(start: string, end: string): number {
  const startDate = toDate(start);
  const endDate = toDate(end);
  const diffTime = endDate.getTime() - startDate.getTime();
  const diffDays = Math.floor(diffTime / (1000 * 60 * 60 * 24));
  return diffDays + 1; // +1 to make it inclusive
}

/**
 * Group blockout rows into contiguous date ranges per user.
 *
 * Algorithm:
 * 1. Group rows by user_id
 * 2. For each user, sort dates ascending
 * 3. Merge consecutive/overlapping dates into ranges
 * 4. Return array of BlockoutRange objects
 *
 * @param rows - Array of blockout rows from database
 * @returns Array of merged blockout ranges
 */
export function groupBlockoutsIntoRanges(rows: BlockoutRow[]): BlockoutRange[] {
  if (rows.length === 0) return [];

  // Group by user_id
  const byUser = new Map<string, BlockoutRow[]>();
  for (const row of rows) {
    if (!byUser.has(row.user_id)) {
      byUser.set(row.user_id, []);
    }
    byUser.get(row.user_id)!.push(row);
  }

  const ranges: BlockoutRange[] = [];

  // Process each user's blockouts
  byUser.forEach((userRows, userId) => {
    // Sort by date ascending
    const sorted = [...userRows].sort((a, b) => a.date.localeCompare(b.date));

    let currentRange: {
      dates: string[];
      ids: string[];
      notes?: string;
      reason?: string;
      band_id?: string;
    } | null = null;

    for (const row of sorted) {
      if (!currentRange) {
        // Start new range
        currentRange = {
          dates: [row.date],
          ids: row.id ? [row.id] : [],
          notes: row.notes,
          reason: row.reason,
          band_id: row.band_id,
        };
      } else {
        // Check if this date continues the current range
        const lastDate: string = currentRange.dates[currentRange.dates.length - 1];

        // Check if consecutive or overlapping
        if (isNextDay(lastDate, row.date) || row.date === lastDate) {
          // Extend current range
          if (row.date !== lastDate) {
            currentRange.dates.push(row.date);
          }
          if (row.id && !currentRange.ids.includes(row.id)) {
            currentRange.ids.push(row.id);
          }
          // Preserve first notes/reason if current row doesn't have them
          if (!currentRange.notes && row.notes) {
            currentRange.notes = row.notes;
          }
          if (!currentRange.reason && row.reason) {
            currentRange.reason = row.reason;
          }
        } else {
          // Gap found - finalize current range and start new one
          const startDate = minDate(currentRange.dates);
          const endDate = maxDate(currentRange.dates);
          ranges.push({
            user_id: userId,
            start_date: startDate,
            end_date: endDate,
            dayCount: daysBetween(startDate, endDate),
            sourceIds: currentRange.ids,
            notes: currentRange.notes,
            reason: currentRange.reason,
            band_id: currentRange.band_id,
          });

          // Start new range
          currentRange = {
            dates: [row.date],
            ids: row.id ? [row.id] : [],
            notes: row.notes,
            reason: row.reason,
            band_id: row.band_id,
          };
        }
      }
    }

    // Finalize last range for this user
    if (currentRange) {
      const startDate = minDate(currentRange.dates);
      const endDate = maxDate(currentRange.dates);
      ranges.push({
        user_id: userId,
        start_date: startDate,
        end_date: endDate,
        dayCount: daysBetween(startDate, endDate),
        sourceIds: currentRange.ids,
        notes: currentRange.notes,
        reason: currentRange.reason,
        band_id: currentRange.band_id,
      });
    }
  });

  // Sort ranges by start_date descending (most recent first)
  return ranges.sort((a, b) => b.start_date.localeCompare(a.start_date));
}

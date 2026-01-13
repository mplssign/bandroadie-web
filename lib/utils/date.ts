import { parseISO, isValid } from 'date-fns';

/**
 * Safely converts a value to a Date object, returning null if invalid.
 * Prevents "Invalid time value" errors by validating dates before use.
 * 
 * @param v - A string (ISO format), number (timestamp), Date object, or null/undefined
 * @returns A valid Date object or null
 */
export function toDateSafe(v: string | number | Date | null | undefined): Date | null {
  if (v == null) return null;
  
  const d = typeof v === 'string' ? parseISO(v) : new Date(v);
  return isValid(d) ? d : null;
}

/**
 * Converts a Date to YYYY-MM-DD format string.
 * 
 * @param date - A Date object
 * @returns ISO date string in YYYY-MM-DD format
 */
export function toISODate(date: Date): string {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

/**
 * Creates a date key for grouping events by day (strips time component).
 * 
 * @param date - A Date object
 * @returns Unix timestamp at midnight local time
 */
export function getDayKey(date: Date): number {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime();
}

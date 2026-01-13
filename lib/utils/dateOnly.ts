/**
 * Utilities for handling date-only values (birthdays) without timezone conversion
 * 
 * Birthdays should be treated as pure calendar dates (YYYY-MM-DD) without 
 * any time or timezone information to avoid off-by-one errors.
 */

/**
 * Format a date-only string (YYYY-MM-DD) for display without timezone conversion
 * @param dateString - Date string in YYYY-MM-DD format
 * @returns Formatted display string like "November 9" or empty string if invalid
 */
export function formatBirthdayDisplay(dateString: string | null | undefined): string {
  if (!dateString || typeof dateString !== 'string') {
    return '';
  }

  // Parse YYYY-MM-DD without creating a Date object to avoid timezone issues
  const parts = dateString.split('-');
  if (parts.length !== 3) {
    return '';
  }

  const [, monthStr, dayStr] = parts;
  const month = parseInt(monthStr, 10);
  const day = parseInt(dayStr, 10);

  // Parse year for validation
  const [yearStr] = parts;
  const year = parseInt(yearStr, 10);

  // Validate year, month and day
  if (isNaN(year) || isNaN(month) || isNaN(day) || 
      year < 1900 || year > 2100 ||
      month < 1 || month > 12 || 
      day < 1 || day > 31) {
    return '';
  }

  // Month names for display
  const monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];

  return `${monthNames[month - 1]} ${day}`;
}

/**
 * Create a date-only string (YYYY-MM-DD) from year, month, and day components
 * @param year - Full year (e.g., 1990)
 * @param month - Month (1-12)
 * @param day - Day (1-31)
 * @returns Date string in YYYY-MM-DD format
 */
export function createDateOnlyString(year: number, month: number, day: number): string {
  return `${year}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
}

/**
 * Parse a date-only string into its components without timezone conversion
 * @param dateString - Date string in YYYY-MM-DD format
 * @returns Object with year, month, day or null if invalid
 */
export function parseDateOnlyString(dateString: string): { year: number; month: number; day: number } | null {
  if (!dateString || typeof dateString !== 'string') {
    return null;
  }

  const parts = dateString.split('-');
  if (parts.length !== 3) {
    return null;
  }

  const [yearStr, monthStr, dayStr] = parts;
  const year = parseInt(yearStr, 10);
  const month = parseInt(monthStr, 10);
  const day = parseInt(dayStr, 10);

  // Validate components
  if (isNaN(year) || isNaN(month) || isNaN(day) || 
      year < 1900 || year > 2100 || 
      month < 1 || month > 12 || 
      day < 1 || day > 31) {
    return null;
  }

  return { year, month, day };
}

/**
 * Convert month name to number (1-12)
 * @param monthName - Month name like "JAN", "JANUARY", etc.
 * @returns Month number (1-12) or null if invalid
 */
export function monthNameToNumber(monthName: string): number | null {
  const monthMap: Record<string, number> = {
    'JAN': 1, 'JANUARY': 1,
    'FEB': 2, 'FEBRUARY': 2,
    'MAR': 3, 'MARCH': 3,
    'APR': 4, 'APRIL': 4,
    'MAY': 5,
    'JUN': 6, 'JUNE': 6,
    'JUL': 7, 'JULY': 7,
    'AUG': 8, 'AUGUST': 8,
    'SEP': 9, 'SEPTEMBER': 9,
    'OCT': 10, 'OCTOBER': 10,
    'NOV': 11, 'NOVEMBER': 11,
    'DEC': 12, 'DECEMBER': 12
  };

  return monthMap[monthName.toUpperCase()] || null;
}
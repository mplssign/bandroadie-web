/**
 * Formats a time range using Intl.DateTimeFormat for locale-aware output.
 *
 * @param startTime - Start time in HH:MM format (24-hour)
 * @param endTime - End time in HH:MM format (24-hour)
 * @param dateStr - Optional date string (YYYY-MM-DD) for proper date construction
 * @returns Formatted time range like "7:00 PM – 9:00 PM" with em dash
 */
export function formatTimeRange(startTime: string, endTime?: string, dateStr?: string): string {
  try {
    if (!startTime) {
      return 'Invalid time';
    }

    // Parse start time
    const [startHour, startMinute] = startTime.split(':').map(Number);
    if (isNaN(startHour) || isNaN(startMinute)) {
      return 'Invalid time';
    }

    // Use provided date or default to today for proper date construction
    const baseDate = dateStr ? new Date(`${dateStr}T00:00:00`) : new Date();

    const startDate = new Date(baseDate);
    startDate.setHours(startHour, startMinute, 0, 0);

    const formatter = new Intl.DateTimeFormat('en-US', {
      hour: 'numeric',
      minute: '2-digit',
      hour12: true,
    });

    const startFormatted = formatter.format(startDate);

    // If no end time provided, return just start time
    if (!endTime) {
      return startFormatted;
    }

    // Parse end time
    const [endHour, endMinute] = endTime.split(':').map(Number);
    if (isNaN(endHour) || isNaN(endMinute)) {
      return startFormatted; // Fallback to start time only
    }

    const endDate = new Date(baseDate);
    endDate.setHours(endHour, endMinute, 0, 0);

    const endFormatted = formatter.format(endDate);

    // Use em dash (–) as separator
    return `${startFormatted} – ${endFormatted}`;
  } catch (error) {
    console.error('Error formatting time range:', error);
    return 'Invalid time';
  }
}

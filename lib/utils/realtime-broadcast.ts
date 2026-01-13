import { RealtimeEvent } from '@/lib/types/realtime';
import { createClient } from '@/lib/supabase/server';

/**
 * Utility to broadcast real-time events to band members
 * This is imported by other API routes to trigger real-time updates
 */

// Import the broadcast function from the SSE route
import { broadcastToBand } from './realtime-connections';

let broadcastToBandFunction: ((bandId: string, event: RealtimeEvent) => void) | null = broadcastToBand;

// Initialize the broadcast function (called by the SSE route)
export function initializeBroadcast(broadcastFn: (bandId: string, event: RealtimeEvent) => void) {
  broadcastToBandFunction = broadcastFn;
}

/**
 * Broadcast a real-time event to all connected clients in a band
 */
export async function broadcastEvent(
  bandId: string,
  eventType: RealtimeEvent['type'],
  data: RealtimeEvent['data'],
  userId?: string,
  userDisplayName?: string
): Promise<void> {
  if (!broadcastToBandFunction) {
    console.warn('Broadcast function not initialized - real-time events will not be sent');
    return;
  }

  // If userId/userDisplayName not provided, try to get from current session
  let finalUserId = userId;
  let finalUserDisplayName = userDisplayName;

  if (!finalUserId || !finalUserDisplayName) {
    try {
      const supabase = createClient();
      const { data: { user } } = await supabase.auth.getUser();
      
      if (user) {
        finalUserId = finalUserId || user.id;
        
        // Get user's display name
        if (!finalUserDisplayName) {
          const { data: profile } = await supabase
            .from('users')
            .select('first_name, last_name')
            .eq('id', user.id)
            .single();
          
          if (profile) {
            finalUserDisplayName = [profile.first_name, profile.last_name]
              .filter(Boolean)
              .join(' ') || 'Unknown User';
          }
        }
      }
    } catch (error) {
      console.error('Failed to get user info for real-time event:', error);
    }
  }

  if (!finalUserId) {
    console.warn('Could not determine userId for real-time event');
    return;
  }

  const event: RealtimeEvent = {
    id: `${Date.now()}-${Math.random().toString(36).substr(2, 9)}`,
    bandId,
    userId: finalUserId,
    userDisplayName: finalUserDisplayName || 'Unknown User',
    timestamp: Date.now(),
    type: eventType,
    data
  } as RealtimeEvent;

  broadcastToBandFunction(bandId, event);
}

/**
 * Helper functions for common event types
 */

export async function broadcastGigCreated(
  bandId: string,
  gigId: string,
  gigData: { name: string; venue: string; date: string; isPotential: boolean },
  userId?: string,
  userDisplayName?: string
) {
  await broadcastEvent(bandId, 'gig:created', {
    gigId,
    ...gigData
  }, userId, userDisplayName);
}

export async function broadcastGigUpdated(
  bandId: string,
  gigId: string,
  changes: Record<string, unknown>,
  previousValues?: Record<string, unknown>,
  userId?: string,
  userDisplayName?: string
) {
  await broadcastEvent(bandId, 'gig:updated', {
    gigId,
    changes,
    previousValues
  }, userId, userDisplayName);
}

export async function broadcastGigResponse(
  bandId: string,
  gigId: string,
  memberId: string,
  response: 'yes' | 'no',
  memberName: string,
  userId?: string,
  userDisplayName?: string
) {
  await broadcastEvent(bandId, 'gig:response', {
    gigId,
    memberId,
    response,
    memberName
  }, userId, userDisplayName);
}

export async function broadcastSetlistSongAdded(
  bandId: string,
  setlistId: string,
  songId: string,
  userId?: string,
  userDisplayName?: string
) {
  await broadcastEvent(bandId, 'setlist:song:added', {
    setlistId,
    songId
  }, userId, userDisplayName);
}

export async function broadcastSetlistSongReordered(
  bandId: string,
  setlistId: string,
  newOrder: Array<{ id: string; position: number }>,
  userId?: string,
  userDisplayName?: string
) {
  await broadcastEvent(bandId, 'setlist:song:reordered', {
    setlistId,
    newOrder
  }, userId, userDisplayName);
}

export async function broadcastMemberJoined(
  bandId: string,
  memberId: string,
  memberUserId: string,
  memberName: { firstName?: string; lastName?: string },
  userId?: string,
  userDisplayName?: string
) {
  await broadcastEvent(bandId, 'member:joined', {
    memberId,
    memberUserId,
    firstName: memberName.firstName,
    lastName: memberName.lastName
  }, userId, userDisplayName);
}

export async function broadcastRehearsalUpdated(
  bandId: string,
  rehearsalId: string,
  changes: Record<string, unknown>,
  previousValues?: Record<string, unknown>,
  userId?: string,
  userDisplayName?: string
) {
  await broadcastEvent(bandId, 'rehearsal:updated', {
    rehearsalId,
    changes,
    previousValues
  }, userId, userDisplayName);
}
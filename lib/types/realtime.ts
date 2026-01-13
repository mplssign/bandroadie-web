// Real-time event types and interfaces

export interface BaseRealtimeEvent {
  id: string;
  bandId: string;
  userId: string;
  userDisplayName: string;
  timestamp: number;
}

// Gig-related events
export interface GigCreatedEvent extends BaseRealtimeEvent {
  type: 'gig:created';
  data: {
    gigId: string;
    name: string;
    venue: string;
    date: string;
    isPotential: boolean;
  };
}

export interface GigUpdatedEvent extends BaseRealtimeEvent {
  type: 'gig:updated';
  data: {
    gigId: string;
    changes: Record<string, unknown>;
    previousValues?: Record<string, unknown>;
  };
}

export interface GigDeletedEvent extends BaseRealtimeEvent {
  type: 'gig:deleted';
  data: {
    gigId: string;
  };
}

export interface GigResponseEvent extends BaseRealtimeEvent {
  type: 'gig:response';
  data: {
    gigId: string;
    memberId: string;
    response: 'yes' | 'no';
    memberName: string;
  };
}

// Rehearsal events
export interface RehearsalCreatedEvent extends BaseRealtimeEvent {
  type: 'rehearsal:created';
  data: {
    rehearsalId: string;
    name: string;
    location: string;
    startTime: string;
    endTime: string;
  };
}

export interface RehearsalUpdatedEvent extends BaseRealtimeEvent {
  type: 'rehearsal:updated';
  data: {
    rehearsalId: string;
    changes: Record<string, unknown>;
    previousValues?: Record<string, unknown>;
  };
}

export interface RehearsalDeletedEvent extends BaseRealtimeEvent {
  type: 'rehearsal:deleted';
  data: {
    rehearsalId: string;
  };
}

// Setlist events
export interface SetlistCreatedEvent extends BaseRealtimeEvent {
  type: 'setlist:created';
  data: {
    setlistId: string;
    name: string;
  };
}

export interface SetlistUpdatedEvent extends BaseRealtimeEvent {
  type: 'setlist:updated';
  data: {
    setlistId: string;
    changes: Record<string, unknown>;
  };
}

export interface SetlistDeletedEvent extends BaseRealtimeEvent {
  type: 'setlist:deleted';
  data: {
    setlistId: string;
  };
}

export interface SetlistSongEvent extends BaseRealtimeEvent {
  type: 'setlist:song:added' | 'setlist:song:removed' | 'setlist:song:updated' | 'setlist:song:reordered';
  data: {
    setlistId: string;
    songId?: string;
    changes?: Record<string, unknown>;
    newOrder?: Array<{ id: string; position: number }>;
  };
}

// Member events
export interface MemberJoinedEvent extends BaseRealtimeEvent {
  type: 'member:joined';
  data: {
    memberId: string;
    memberUserId: string;
    firstName?: string;
    lastName?: string;
  };
}

export interface MemberLeftEvent extends BaseRealtimeEvent {
  type: 'member:left';
  data: {
    memberId: string;
    memberUserId: string;
    firstName?: string;
    lastName?: string;
  };
}

export interface MemberUpdatedEvent extends BaseRealtimeEvent {
  type: 'member:updated';
  data: {
    memberId: string;
    memberUserId: string;
    changes: Record<string, unknown>;
  };
}

// Band events
export interface BandUpdatedEvent extends BaseRealtimeEvent {
  type: 'band:updated';
  data: {
    changes: Record<string, unknown>;
  };
}

// Union type for all events
export type RealtimeEvent = 
  | GigCreatedEvent
  | GigUpdatedEvent
  | GigDeletedEvent
  | GigResponseEvent
  | RehearsalCreatedEvent
  | RehearsalUpdatedEvent
  | RehearsalDeletedEvent
  | SetlistCreatedEvent
  | SetlistUpdatedEvent
  | SetlistDeletedEvent
  | SetlistSongEvent
  | MemberJoinedEvent
  | MemberLeftEvent
  | MemberUpdatedEvent
  | BandUpdatedEvent;

// Event message format for SSE/WebSocket
export interface RealtimeMessage {
  event: RealtimeEvent;
  retryCount?: number;
}

// Client-side subscription options
export interface RealtimeSubscriptionOptions {
  bandId: string;
  eventTypes?: RealtimeEvent['type'][];
  onEvent: (event: RealtimeEvent) => void;
  onError?: (error: Error) => void;
  onReconnect?: () => void;
}

// Conflict resolution types
export interface ConflictInfo {
  field: string;
  localValue: unknown;
  remoteValue: unknown;
  lastModified: {
    local: number;
    remote: number;
  };
}

export interface ConflictResolution {
  action: 'accept-remote' | 'keep-local' | 'merge';
  conflicts: ConflictInfo[];
  resolvedValues?: Record<string, unknown>;
}

// Optimistic update state
export interface OptimisticUpdate {
  id: string;
  type: string;
  timestamp: number;
  data: unknown;
  status: 'pending' | 'confirmed' | 'failed';
}
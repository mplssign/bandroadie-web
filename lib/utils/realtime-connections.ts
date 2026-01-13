import { RealtimeEvent, RealtimeMessage } from '@/lib/types/realtime';

// Connection interface
interface Connection {
  controller: ReadableStreamDefaultController<Uint8Array>;
  userId: string;
  lastHeartbeat: number;
}

// Global map to store active connections by band
const bandConnections = new Map<string, Set<Connection>>();

// Cleanup interval for stale connections
const HEARTBEAT_INTERVAL = 30000; // 30 seconds
const CONNECTION_TIMEOUT = 60000; // 1 minute

// Initialize cleanup interval
setInterval(() => {
  const now = Date.now();
  bandConnections.forEach((connections, bandId) => {
    const staleConnections = Array.from(connections).filter(
      conn => now - conn.lastHeartbeat > CONNECTION_TIMEOUT
    );
    
    staleConnections.forEach(conn => {
      try {
        conn.controller.close();
      } catch (e) {
        // Connection already closed
      }
      connections.delete(conn);
    });
    
    if (connections.size === 0) {
      bandConnections.delete(bandId);
    }
  });
}, HEARTBEAT_INTERVAL);

/**
 * Broadcast an event to all connected clients in a band
 */
export function broadcastToBand(bandId: string, event: RealtimeEvent): void {
  const connections = bandConnections.get(bandId);
  if (!connections || connections.size === 0) {
    return;
  }

  const message: RealtimeMessage = { event };
  const data = `data: ${JSON.stringify(message)}\n\n`;
  const encodedData = new TextEncoder().encode(data);

  // Send to all connections except the originating user to avoid echo
  connections.forEach((conn) => {
    if (conn.userId !== event.userId) {
      try {
        conn.controller.enqueue(encodedData);
      } catch (e) {
        // Connection closed, remove it
        connections.delete(conn);
      }
    }
  });
}

/**
 * Send a heartbeat to keep connections alive
 */
function sendHeartbeat(connections: Set<Connection>) {
  const heartbeatData = `data: ${JSON.stringify({ type: 'heartbeat', timestamp: Date.now() })}\n\n`;
  const encodedData = new TextEncoder().encode(heartbeatData);
  
  connections.forEach((conn) => {
    try {
      conn.controller.enqueue(encodedData);
      conn.lastHeartbeat = Date.now();
    } catch (e) {
      connections.delete(conn);
    }
  });
}

/**
 * Add a new connection to a band's connection pool
 */
export function addConnection(bandId: string, controller: ReadableStreamDefaultController<Uint8Array>, userId: string): Connection {
  if (!bandConnections.has(bandId)) {
    bandConnections.set(bandId, new Set());
  }
  
  const connection: Connection = {
    controller,
    userId,
    lastHeartbeat: Date.now()
  };
  
  bandConnections.get(bandId)!.add(connection);
  
  // Set up heartbeat for this connection
  const heartbeatInterval = setInterval(() => {
    if (bandConnections.get(bandId)?.has(connection)) {
      sendHeartbeat(new Set([connection]));
    } else {
      clearInterval(heartbeatInterval);
    }
  }, HEARTBEAT_INTERVAL);
  
  return connection;
}

/**
 * Remove a connection from a band's connection pool
 */
export function removeConnection(bandId: string, connection: Connection): void {
  const connections = bandConnections.get(bandId);
  if (connections) {
    connections.delete(connection);
    if (connections.size === 0) {
      bandConnections.delete(bandId);
    }
  }
}

/**
 * Get connection count for a band (for debugging)
 */
export function getConnectionCount(bandId: string): number {
  return bandConnections.get(bandId)?.size || 0;
}

/**
 * Get total connection count across all bands (for debugging)
 */
export function getTotalConnectionCount(): number {
  let total = 0;
  bandConnections.forEach(connections => {
    total += connections.size;
  });
  return total;
}
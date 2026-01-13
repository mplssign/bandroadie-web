/**
 * Security Configuration for Band Roadie PWA
 * Implements defense-in-depth security measures
 */

// Content Security Policy configuration
export const CSP_CONFIG = {
  development: {
    'default-src': "'self'",
    'script-src': "'self' 'unsafe-eval' 'unsafe-inline'", // Allow Next.js dev tools
    'style-src': "'self' 'unsafe-inline'", // Allow Tailwind inline styles
    'img-src': "'self' data: blob:",
    'font-src': "'self' data:",
    'connect-src': "'self' wss: ws:", // Allow WebSocket connections for hot reload
    'media-src': "'self'",
    'object-src': "'none'",
    'frame-src': "'none'",
    'base-uri': "'self'",
    'form-action': "'self'"
  },
  production: {
    'default-src': "'self'",
    'script-src': "'self'",
    'style-src': "'self' 'unsafe-inline'", // Required for Tailwind
    'img-src': "'self' data: https:",
    'font-src': "'self' data:",
    'connect-src': "'self' https:",
    'media-src': "'self'",
    'object-src': "'none'",
    'frame-src': "'none'",
    'base-uri': "'self'",
    'form-action': "'self'",
    'upgrade-insecure-requests': true
  }
};

// Security headers configuration
export const SECURITY_HEADERS = {
  // Prevent clickjacking
  'X-Frame-Options': 'DENY',
  
  // Prevent MIME type sniffing
  'X-Content-Type-Options': 'nosniff',
  
  // Enable XSS protection
  'X-XSS-Protection': '1; mode=block',
  
  // Strict Transport Security (HTTPS only)
  'Strict-Transport-Security': 'max-age=31536000; includeSubDomains; preload',
  
  // Referrer policy
  'Referrer-Policy': 'strict-origin-when-cross-origin',
  
  // Permissions policy
  'Permissions-Policy': 'camera=(), microphone=(), geolocation=(), payment=()',
  
  // Cross-Origin policies
  'Cross-Origin-Embedder-Policy': 'require-corp',
  'Cross-Origin-Opener-Policy': 'same-origin',
  'Cross-Origin-Resource-Policy': 'same-origin'
};

// Input sanitization utilities
export const sanitizationUtils = {
  /**
   * Sanitize HTML input to prevent XSS
   */
  sanitizeHtml: (input: string): string => {
    return input
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#x27;')
      .replace(/\//g, '&#x2F;');
  },

  /**
   * Sanitize SQL input (for dynamic queries)
   */
  sanitizeSql: (input: string): string => {
    return input.replace(/['";\\]/g, '');
  },

  /**
   * Validate and sanitize email addresses
   */
  sanitizeEmail: (email: string): string | null => {
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    const cleaned = email.trim().toLowerCase();
    return emailRegex.test(cleaned) ? cleaned : null;
  },

  /**
   * Sanitize file names for uploads
   */
  sanitizeFileName: (fileName: string): string => {
    return fileName
      .replace(/[^a-zA-Z0-9.-]/g, '_')
      .replace(/\.{2,}/g, '_')
      .substring(0, 255);
  }
};

// Rate limiting configuration
export const RATE_LIMIT_CONFIG = {
  // API endpoints
  api: {
    windowMs: 15 * 60 * 1000, // 15 minutes
    max: 100, // requests per window
    message: 'Too many requests, please try again later'
  },
  
  // Authentication endpoints
  auth: {
    windowMs: 15 * 60 * 1000, // 15 minutes
    max: 5, // login attempts per window
    message: 'Too many login attempts, please try again later'
  },
  
  // Upload endpoints
  upload: {
    windowMs: 60 * 60 * 1000, // 1 hour
    max: 10, // uploads per hour
    message: 'Upload limit exceeded, please try again later'
  }
};

// Authentication security
export const AUTH_CONFIG = {
  // Session configuration
  session: {
    httpOnly: true,
    secure: process.env.NODE_ENV === 'production',
    sameSite: 'strict' as const,
    maxAge: 24 * 60 * 60 * 1000, // 24 hours
    domain: process.env.NODE_ENV === 'production' ? '.bandroadie.com' : undefined
  },
  
  // Password requirements
  password: {
    minLength: 8,
    requireUppercase: true,
    requireLowercase: true,
    requireNumbers: true,
    requireSpecialChars: false, // Keep false for better UX
    maxLength: 128
  },
  
  // JWT configuration
  jwt: {
    algorithm: 'HS256' as const,
    expiresIn: '24h',
    issuer: 'bandroadie.com',
    audience: 'bandroadie-users'
  }
};

// Data validation schemas
export const VALIDATION_SCHEMAS = {
  // User input validation
  userInput: {
    name: /^[a-zA-Z\s'\-]{1,50}$/,
    bandName: /^[a-zA-Z0-9\s'\-&.]{1,100}$/,
    songTitle: /^[a-zA-Z0-9\s'\-&.,()!?]{1,200}$/,
    email: /^[^\s@]+@[^\s@]+\.[^\s@]+$/,
    phone: /^\+?[\d\s()-]{10,20}$/,
    url: /^https?:\/\/[^\s]+$/
  },
  
  // File upload validation
  upload: {
    allowedTypes: ['image/jpeg', 'image/png', 'image/webp'],
    maxSize: 5 * 1024 * 1024, // 5MB
    allowedExtensions: ['.jpg', '.jpeg', '.png', '.webp']
  }
};

// Environment-specific security settings
export const ENVIRONMENT_CONFIG = {
  development: {
    enableDevtools: true,
    logLevel: 'debug',
    corsOrigins: ['http://localhost:3000', 'https://localhost:3000'],
    trustProxy: false
  },
  
  production: {
    enableDevtools: false,
    logLevel: 'error',
    corsOrigins: ['https://bandroadie.com', 'https://www.bandroadie.com'],
    trustProxy: true,
    requireHttps: true
  }
};

// Security monitoring and logging
export const SECURITY_MONITORING = {
  // Events to monitor
  criticalEvents: [
    'authentication_failure',
    'authorization_failure',
    'suspicious_activity',
    'rate_limit_exceeded',
    'data_breach_attempt',
    'privilege_escalation'
  ],
  
  // Logging configuration
  logging: {
    level: process.env.NODE_ENV === 'production' ? 'warn' : 'debug',
    includeUserAgent: true,
    includeIpAddress: true,
    maskSensitiveData: true
  }
};
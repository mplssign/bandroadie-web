/**
 * Standardized Framer Motion configurations for consistent performance
 * and user experience across the application.
 */

export const SPRING_CONFIG = {
  default: {
    type: "spring" as const,
    stiffness: 300,
    damping: 30,
  },
  gentle: {
    type: "spring" as const,
    stiffness: 200,
    damping: 25,
  },
  snappy: {
    type: "spring" as const,
    stiffness: 400,
    damping: 35,
  }
};

export const TRANSFORM_ONLY_VARIANTS = {
  // Card hover effects - only transform properties for optimal performance
  cardHover: {
    initial: { scale: 1 },
    hover: { scale: 1.02 },
    tap: { scale: 0.98 }
  },
  
  // Slide in/out animations - only transforms
  slideInLeft: {
    initial: { x: -20, opacity: 0 },
    animate: { x: 0, opacity: 1 },
    exit: { x: -20, opacity: 0 }
  },
  
  slideInRight: {
    initial: { x: 20, opacity: 0 },
    animate: { x: 0, opacity: 1 },
    exit: { x: 20, opacity: 0 }
  },
  
  // Fade animations
  fade: {
    initial: { opacity: 0 },
    animate: { opacity: 1 },
    exit: { opacity: 0 }
  },
  
  // Scale animations for modals/overlays
  scaleIn: {
    initial: { scale: 0.95, opacity: 0 },
    animate: { scale: 1, opacity: 1 },
    exit: { scale: 0.95, opacity: 0 }
  }
};

/**
 * Common drag configurations for swipeable components
 */
export const DRAG_CONFIG = {
  swipeLeft: {
    drag: "x" as const,
    dragConstraints: { left: -120, right: 0 },
    dragElastic: 0.1,
    whileDrag: {
      scale: 1.02,
      // Use transform-only properties for better performance
      // Avoid boxShadow during drag - use border or background instead
    }
  }
};

/**
 * Touch-friendly configurations
 */
export const TOUCH_CONFIG = {
  // Add pan-y to allow vertical scrolling while enabling horizontal gestures
  touchAction: "pan-y" as const,
  // Increase touch targets to 44x44px minimum
  minTouchTarget: "44px"
};
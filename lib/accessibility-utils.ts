/**
 * Accessibility utilities for improved keyboard navigation, 
 * focus management, and screen reader support.
 */

// Focus management utilities
export const focusUtils = {
  /**
   * Get all focusable elements within a container
   */
  getFocusableElements: (container: HTMLElement): HTMLElement[] => {
    const focusableSelector = [
      'button:not([disabled]):not([aria-hidden="true"])',
      '[href]:not([aria-hidden="true"])',
      'input:not([disabled]):not([type="hidden"]):not([aria-hidden="true"])',
      'select:not([disabled]):not([aria-hidden="true"])',
      'textarea:not([disabled]):not([aria-hidden="true"])',
      '[tabindex]:not([tabindex="-1"]):not([aria-hidden="true"])',
      '[contenteditable]:not([aria-hidden="true"])',
      'audio[controls]:not([aria-hidden="true"])',
      'video[controls]:not([aria-hidden="true"])'
    ].join(', ');

    return Array.from(container.querySelectorAll(focusableSelector))
      .filter((el) => {
        // Additional check for visibility
        const element = el as HTMLElement;
        return element.offsetWidth > 0 && element.offsetHeight > 0;
      }) as HTMLElement[];
  },

  /**
   * Trap focus within a container (for modals/dialogs)
   */
  trapFocus: (container: HTMLElement, event: KeyboardEvent) => {
    const focusableElements = focusUtils.getFocusableElements(container);
    const firstElement = focusableElements[0];
    const lastElement = focusableElements[focusableElements.length - 1];

    if (event.key === 'Tab') {
      if (event.shiftKey && document.activeElement === firstElement) {
        event.preventDefault();
        lastElement?.focus();
      } else if (!event.shiftKey && document.activeElement === lastElement) {
        event.preventDefault();
        firstElement?.focus();
      }
    }
  },

  /**
   * Auto-focus the first focusable element in a container
   */
  autoFocusFirst: (container: HTMLElement, delay = 100) => {
    setTimeout(() => {
      const focusableElements = focusUtils.getFocusableElements(container);
      focusableElements[0]?.focus();
    }, delay);
  },

  /**
   * Return focus to the previously focused element
   */
  restoreFocus: (previousElement: HTMLElement | null) => {
    if (previousElement && document.contains(previousElement)) {
      previousElement.focus();
    }
  }
};

// Keyboard event utilities
export const keyboardUtils = {
  /**
   * Handle standard button-like keyboard interactions
   */
  handleButtonKeyDown: (event: React.KeyboardEvent, onClick: () => void) => {
    if (event.key === 'Enter' || event.key === ' ') {
      event.preventDefault();
      onClick();
    }
  },

  /**
   * Handle escape key for closing modals/dialogs
   */
  handleEscapeKey: (event: KeyboardEvent, onEscape: () => void) => {
    if (event.key === 'Escape') {
      event.preventDefault();
      onEscape();
    }
  },

  /**
   * Navigate list items with arrow keys
   */
  handleArrowNavigation: (
    event: React.KeyboardEvent,
    items: HTMLElement[],
    currentIndex: number,
    onNavigate: (newIndex: number) => void
  ) => {
    let newIndex = currentIndex;

    switch (event.key) {
      case 'ArrowDown':
        event.preventDefault();
        newIndex = (currentIndex + 1) % items.length;
        break;
      case 'ArrowUp':
        event.preventDefault();
        newIndex = currentIndex === 0 ? items.length - 1 : currentIndex - 1;
        break;
      case 'Home':
        event.preventDefault();
        newIndex = 0;
        break;
      case 'End':
        event.preventDefault();
        newIndex = items.length - 1;
        break;
      default:
        return;
    }

    items[newIndex]?.focus();
    onNavigate(newIndex);
  }
};

// Touch target utilities
export const touchUtils = {
  /**
   * Minimum touch target size for accessibility (44x44px)
   */
  MIN_TOUCH_SIZE: '44px',

  /**
   * Ensure element meets minimum touch target requirements
   */
  ensureMinTouchTarget: (styles: React.CSSProperties = {}): React.CSSProperties => ({
    minWidth: touchUtils.MIN_TOUCH_SIZE,
    minHeight: touchUtils.MIN_TOUCH_SIZE,
    display: 'inline-flex',
    alignItems: 'center',
    justifyContent: 'center',
    ...styles
  }),

  /**
   * Add padding to small interactive elements to meet touch targets
   */
  expandTouchTarget: (currentSize: number): React.CSSProperties => {
    const targetSize = 44;
    const padding = Math.max(0, (targetSize - currentSize) / 2);
    
    return {
      padding: `${padding}px`,
      margin: `-${padding}px`,
    };
  }
};

// Screen reader utilities
export const screenReaderUtils = {
  /**
   * Announce dynamic content changes to screen readers
   */
  announce: (message: string, priority: 'polite' | 'assertive' = 'polite') => {
    const announcer = document.createElement('div');
    announcer.setAttribute('aria-live', priority);
    announcer.setAttribute('aria-atomic', 'true');
    announcer.className = 'sr-only';
    announcer.textContent = message;
    
    document.body.appendChild(announcer);
    
    // Remove after announcement
    setTimeout(() => {
      document.body.removeChild(announcer);
    }, 1000);
  },

  /**
   * Generate comprehensive aria-label for complex interactions
   */
  generateLabel: (parts: (string | undefined)[]): string => {
    return parts.filter(Boolean).join(', ');
  },

  /**
   * Create description for form validation errors
   */
  createErrorDescription: (fieldName: string, error: string): string => {
    return `${fieldName} has an error: ${error}`;
  }
};

// Color contrast utilities
export const contrastUtils = {
  /**
   * Check if two colors meet WCAG contrast requirements
   */
  meetsWCAGContrast: (color1: string, color2: string, level: 'AA' | 'AAA' = 'AA'): boolean => {
    // This is a simplified check - in production, you'd use a proper color contrast library
    // For now, return true as a placeholder
    return true;
  },

  /**
   * Suggest high contrast alternatives for better accessibility
   */
  suggestHighContrast: (isDark: boolean) => ({
    background: isDark ? '#000000' : '#ffffff',
    foreground: isDark ? '#ffffff' : '#000000',
    accent: isDark ? '#00ffff' : '#0066cc',
    error: isDark ? '#ff6b6b' : '#cc0000',
    success: isDark ? '#51cf66' : '#2b8a3e',
  })
};

// Animation utilities for accessibility
export const animationUtils = {
  /**
   * Check if user prefers reduced motion
   */
  prefersReducedMotion: (): boolean => {
    return window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  },

  /**
   * Get appropriate animation duration based on user preferences
   */
  getAnimationDuration: (normalDuration: number): number => {
    return animationUtils.prefersReducedMotion() ? 0 : normalDuration;
  },

  /**
   * Create a reduced motion variant for Framer Motion
   */
  createReducedMotionVariant: (normalVariant: any) => {
    if (animationUtils.prefersReducedMotion()) {
      return {
        initial: normalVariant.animate || {},
        animate: normalVariant.animate || {},
        exit: normalVariant.animate || {},
      };
    }
    return normalVariant;
  }
};
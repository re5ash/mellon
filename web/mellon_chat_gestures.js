/* One owner for edge gestures while a fullscreen Flutter chat is mounted.
 * WebKit's history navigation otherwise moves snapshots of Map/Feed behind
 * the independently moving CupertinoPageRoute. Never alter browser history.
 */
(() => {
  'use strict';
  if (typeof window.mellonChatGestures === 'function') return;
  const edge = 32; // CSS pixels, independent of the device pixel ratio.
  const options = { capture: true, passive: false };
  let active = false;
  let restoredStyles = [];

  function touchStart(event) {
    if (!active || !event.cancelable || event.touches.length !== 1) return;
    const x = event.touches[0].clientX;
    if (x > edge && x < window.innerWidth - edge) return;
    // Cancel the browser's edge action, but still deliver every event to
    // Flutter. In particular, do not stopPropagation or synthesize a pop.
    event.preventDefault();
  }

  window.mellonChatGestures = (enabled) => {
    enabled = enabled === true;
    if (active === enabled) return;
    active = enabled;
    if (active) {
      restoredStyles = [document.documentElement, document.body]
        .filter(Boolean)
        .map(element => [element, element.style.getPropertyValue('overscroll-behavior-x'),
          element.style.getPropertyPriority('overscroll-behavior-x')]);
      for (const [element] of restoredStyles) {
        element.style.setProperty('overscroll-behavior-x', 'none');
      }
      window.addEventListener('touchstart', touchStart, options);
    } else {
      window.removeEventListener('touchstart', touchStart, options);
      for (const [element, value, priority] of restoredStyles) {
        if (element.style.getPropertyValue('overscroll-behavior-x') !== 'none') continue;
        if (value) element.style.setProperty('overscroll-behavior-x', value, priority);
        else element.style.removeProperty('overscroll-behavior-x');
      }
      restoredStyles = [];
    }
  };
})();

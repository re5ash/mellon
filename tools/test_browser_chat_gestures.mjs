import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

class Style {
  constructor() { this.values = new Map(); }
  getPropertyValue(name) { return this.values.get(name)?.[0] ?? ''; }
  getPropertyPriority(name) { return this.values.get(name)?.[1] ?? ''; }
  setProperty(name, value, priority = '') { this.values.set(name, [value, priority]); }
  removeProperty(name) { this.values.delete(name); }
}

const root = { style: new Style() };
const body = { style: new Style() };
root.style.setProperty('overscroll-behavior-x', 'contain', 'important');
globalThis.document = { documentElement: root, body, currentScript: null };
globalThis.window = new EventTarget();
window.innerWidth = 390;
globalThis.self = globalThis;

let additions = 0;
let removals = 0;
const add = window.addEventListener.bind(window);
const remove = window.removeEventListener.bind(window);
window.addEventListener = (type, fn, options) => {
  if (type === 'touchstart') {
    additions++;
    assert.equal(options.passive, false);
    assert.equal(options.capture, true);
  }
  add(type, fn, options);
};
window.removeEventListener = (type, fn, options) => {
  if (type === 'touchstart') removals++;
  remove(type, fn, options);
};
const source = fs.readFileSync(new URL('../web/mellon_chat_gestures.js', import.meta.url), 'utf8');
vm.runInThisContext(source);
let propagated = 0;
add('touchstart', () => propagated++);
const touch = (x, count = 1, cancelable = true) => {
  const event = new Event('touchstart', { cancelable });
  event.touches = Array.from({ length: count }, () => ({ clientX: x }));
  window.dispatchEvent(event);
  return event.defaultPrevented;
};

assert.equal(touch(1), false);
window.mellonChatGestures(true);
assert.equal(root.style.getPropertyValue('overscroll-behavior-x'), 'none');
assert.equal(body.style.getPropertyValue('overscroll-behavior-x'), 'none');
assert.equal(touch(1), true);
assert.equal(touch(389), true);
assert.equal(touch(150), false);
assert.equal(touch(1, 2), false);
assert.equal(touch(1, 1, false), false);
assert.equal(propagated, 6);
window.mellonChatGestures(true);
vm.runInThisContext(source); // Loading the asset twice must not duplicate listeners.
assert.equal(additions, 1);
window.mellonChatGestures(false);
assert.equal(touch(1), false);
assert.equal(removals, 1);
assert.equal(root.style.getPropertyValue('overscroll-behavior-x'), 'contain');
assert.equal(root.style.getPropertyPriority('overscroll-behavior-x'), 'important');
assert.equal(body.style.getPropertyValue('overscroll-behavior-x'), '');
window.mellonChatGestures(true);
body.style.setProperty('overscroll-behavior-x', 'auto');
window.mellonChatGestures(false);
assert.equal(body.style.getPropertyValue('overscroll-behavior-x'), 'auto');
assert.equal(touch(389), false);
console.log('PASS JS guard: edge only, both sides, propagation, multitouch, cleanup, styles');

if (process.argv[2]) {
  const guard = window.mellonChatGestures;
  window.mellonChatGestureTestActive = false;
  window.mellonChatGestures = (enabled) => {
    guard(enabled);
    window.mellonChatGestureTestActive = enabled;
  };
  window.mellonChatGestureTestDropBridge = () => {
    delete window.mellonChatGestures;
  };
  vm.runInThisContext(fs.readFileSync(process.argv[2], 'utf8'));
}

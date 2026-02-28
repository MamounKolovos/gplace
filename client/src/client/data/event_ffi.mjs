/**
 * 
 * @param {string} type 
 * @param {function(Event):void} listener 
 */
export function listen(type, listener) {
  return window.addEventListener(type, listener)
}
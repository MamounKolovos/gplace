/**
 * fallible but for now im just trusting the caller to pass a valid form id
 * @param {string} id 
 */
export function resetForm(id) {
  document.getElementById(id).reset()
}
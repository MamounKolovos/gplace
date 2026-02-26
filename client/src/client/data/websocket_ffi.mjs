/**
 * 
 * @param {string} url
 * @param {function(WebSocket):void} open 
 * @param {function(string):void} handle_message 
 * @param {function(number):void} close 
 */
export function init(url, open, handle_message, close) {
  let socket = new WebSocket(url)
  socket.onopen = () => {
    open(socket)
  }
  socket.onmessage = (event) => {
    handle_message(event.data)
  }
  socket.onclose = (event) => {
    close(event.code)
  }
  socket.onerror = (event) => {
    console.log("unhandled websocket error", event)
  }
}

/**
 * 
 * @param {WebSocket} socket 
 * @param {string} message 
 */
export function send(socket, message) {
  socket.send(message)
}

/**
 * 
 * @param {WebSocket} socket 
 */
export function close(socket) {
  socket.close()
}
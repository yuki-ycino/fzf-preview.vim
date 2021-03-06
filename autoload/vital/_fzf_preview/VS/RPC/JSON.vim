" ___vital___
" NOTE: lines between '" ___vital___' is generated by :Vitalize.
" Do not modify the code nor insert new lines before '" ___vital___'
function! s:_SID() abort
  return matchstr(expand('<sfile>'), '<SNR>\zs\d\+\ze__SID$')
endfunction
execute join(['function! vital#_fzf_preview#VS#RPC#JSON#import() abort', printf("return map({'_vital_depends': '', 'new': '', '_vital_loaded': ''}, \"vital#_fzf_preview#function('<SNR>%s_' . v:key)\")", s:_SID()), 'endfunction'], "\n")
delfunction s:_SID
" ___vital___
"
" _vital_loaded
"
function! s:_vital_loaded(V) abort
  let s:Promise = a:V.import('Async.Promise')
  let s:Job = a:V.import('VS.System.Job')
  let s:Emitter = a:V.import('VS.Event.Emitter')
endfunction

"
" _vital_depends
"
function! s:_vital_depends() abort
  return ['Async.Promise', 'VS.Event.Emitter', 'VS.System.Job']
endfunction

"
" new
"
function! s:new() abort
  return s:Connection.new()
endfunction

"
" s:Connection
"
let s:Connection = {}

"
" new
"
function! s:Connection.new() abort
  return extend(deepcopy(s:Connection), {
  \   'job': s:Job.new(),
  \   'events': s:Emitter.new(),
  \   'buffer':  '',
  \   'header_length': -1,
  \   'message_length': -1,
  \   'request_map': {},
  \ })
endfunction

"
" start
"
function! s:Connection.start(args) abort
  if !self.job.is_running()
    call self.job.events.on('stdout', self.on_stdout)
    call self.job.events.on('stderr', self.on_stderr)
    call self.job.events.on('exit', self.on_exit)
    call self.job.start(a:args)
  endif
endfunction

"
" stop
"
function! s:Connection.stop() abort
  if self.job.is_running()
    call self.job.events.off('stdout', self.on_stdout)
    call self.job.events.off('stderr', self.on_stderr)
    call self.job.events.off('exit', self.on_exit)
    call self.job.stop()
  endif
endfunction

"
" is_running
"
function! s:Connection.is_running() abort
  return self.job.is_running()
endfunction

"
" request
"
function! s:Connection.request(id, method, params) abort
  let l:ctx = {}
  function! l:ctx.callback(id, method, params, resolve, reject) abort
    let self.request_map[a:id] = { 'resolve': a:resolve, 'reject': a:reject }
    let l:message = { 'id': a:id, 'method': a:method }
    if a:params isnot# v:null
      let l:message.params = a:params
    endif
    call self.job.send(self.to_message(l:message))
  endfunction
  return s:Promise.new(function(l:ctx.callback, [a:id, a:method, a:params], self))
endfunction

"
" response
"
function! s:Connection.response(id, ...) abort
  let l:message = { 'id': a:id }
  let l:message = extend(l:message, len(a:000) > 0 ? a:000[0] : {})
  call self.job.send(self.to_message(l:message))
endfunction

"
" notify
"
function! s:Connection.notify(method, params) abort
  let l:message = { 'method': a:method }
  if a:params isnot# v:null
    let l:message.params = a:params
  endif
  call self.job.send(self.to_message(l:message))
endfunction

"
" cancel
"
function! s:Connection.cancel(id) abort
  if has_key(self.request_map, a:id)
    call remove(self.request_map, a:id)
  endif
endfunction

"
" to_message
"
function! s:Connection.to_message(message) abort
  let a:message.jsonrpc = '2.0'
  let l:message = json_encode(a:message)
  return 'Content-Length: ' . strlen(l:message) . "\r\n\r\n" . l:message
endfunction

"
" on_message
"
function! s:Connection.on_message(message) abort
  if has_key(a:message, 'id')
    " Request from server.
    if has_key(a:message, 'method')
      call self.events.emit('request', a:message)

    " Response from server.
    else
      if has_key(self.request_map, a:message.id)
        let l:request = remove(self.request_map, a:message.id)
        if has_key(a:message, 'error')
          call l:request.reject(a:message.error)
        else
          call l:request.resolve(get(a:message, 'result', v:null))
        endif
      endif
    endif

  " Notify from server.
  elseif has_key(a:message, 'method')
    call self.events.emit('notify', a:message)
  endif
endfunction

"
" flush
"
function! s:Connection.flush(data) abort
  let self.buffer .= a:data

  while self.buffer !=# ''
    " header check.
    if self.header_length == -1
      let l:header_length = stridx(self.buffer, "\r\n\r\n") + 4
      if l:header_length < 4
        return
      endif
      let self.header_length = l:header_length
      let self.message_length = self.header_length + str2nr(get(matchlist(self.buffer, '\ccontent-length:\s*\(\d\+\)'), 1, '-1'))
    endif

    " content check.
    let l:buffer_len = strlen(self.buffer)
    if l:buffer_len < self.message_length
      return
    endif

    let l:content = strpart(self.buffer, self.header_length, self.message_length - self.header_length)
    try
      call self.on_message(json_decode(l:content))
    catch /.*/
    endtry
    let self.buffer = strpart(self.buffer, self.message_length)
    let self.header_length = -1
  endwhile
endfunction

"
" on_stdout
"
function! s:Connection.on_stdout(data) abort
  call self.flush(a:data)
endfunction

"
" on_stderr
"
function! s:Connection.on_stderr(data) abort
  call self.events.emit('stderr', a:data)
endfunction

"
" on_exit
"
function! s:Connection.on_exit(code) abort
  call self.events.emit('exit', a:code)
endfunction


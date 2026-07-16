const http=require('http'),fs=require('fs');
http.createServer((q,r)=>{
  const f = q.url.startsWith('/ex') ? 'D:/ui/zaddz/_example_test.lua' : 'D:/ui/zaddz/zaddz.lua';
  try{ r.writeHead(200,{'Content-Type':'text/plain','Cache-Control':'no-store'}); r.end(fs.readFileSync(f)); }
  catch(e){ r.writeHead(500); r.end(String(e)); }
}).listen(8792,'127.0.0.1',()=>console.log('up on 8792'));

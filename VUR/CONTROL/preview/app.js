const starfield=document.getElementById('starfield');
for(let i=0;i<110;i++){
  const s=document.createElement('i');
  s.style.cssText=`position:absolute;width:${Math.random()*2+1}px;height:${Math.random()*2+1}px;border-radius:50%;background:rgba(150,170,255,${Math.random()*.55+.12});left:${Math.random()*100}%;top:${Math.random()*100}%;box-shadow:0 0 8px rgba(120,100,255,.35)`;
  starfield.appendChild(s);
}
document.querySelectorAll('.beacon').forEach(b=>b.addEventListener('click',()=>{
  document.querySelectorAll('.beacon').forEach(x=>x.classList.remove('active')); b.classList.add('active');
}));
document.querySelectorAll('.nav').forEach(b=>b.addEventListener('click',()=>{
  document.querySelectorAll('.nav').forEach(x=>x.classList.remove('active')); b.classList.add('active');
}));

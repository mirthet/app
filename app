use strict';

// Factory Empire — standalone browser idle game, without a server.
const STORAGE_KEY = 'factory-empire-save-v1';
const OFFLINE_CAP_SECONDS = 8 * 60 * 60;
const MACHINE_TYPES = [
  { name:'Werkbank', icon:'🔨', revenue:2, duration:2, cost:10, managerCost:90, managerName:'Sam de Smid' },
  { name:'Boormachine', icon:'🛠️', revenue:16, duration:4, cost:120, managerCost:750, managerName:'Bo de Bouwer' },
  { name:'CNC-machine', icon:'⚙️', revenue:115, duration:6, cost:1100, managerCost:6000, managerName:'Cees de CNC-expert' },
  { name:'Lasstraat', icon:'🔥', revenue:900, duration:9, cost:9000, managerCost:48000, managerName:'Lara de Lasser' },
  { name:'Assemblagelijn', icon:'🏗️', revenue:6600, duration:13, cost:72000, managerCost:370000, managerName:'Alex de Assembleur' },
  { name:'Robotarm', icon:'🦾', revenue:52000, duration:18, cost:570000, managerCost:3000000, managerName:'Robin de Robotexpert' },
  { name:'Smart Factory', icon:'🧠', revenue:410000, duration:25, cost:4600000, managerCost:24000000, managerName:'Kim de Data-engineer' },
  { name:'Mega-industrie', icon:'🏭', revenue:3400000, duration:35, cost:39000000, managerCost:195000000, managerName:'Max de Fabrieksbaas' },
  { name:'Nanofabriek', icon:'🔬', revenue:29000000, duration:48, cost:320000000, managerCost:1600000000, managerName:'Nina de Nano-specialist' },
  { name:'Ruimtefabriek', icon:'🚀', revenue:240000000, duration:65, cost:2700000000, managerCost:14000000000, managerName:'Nova de Ruimtebouwer' }
];
const MILESTONES = [25, 50, 100, 200, 400, 800];
const now = () => Date.now();
const $ = id => document.getElementById(id);
const money = n => `€ ${compact(n)}`;
function compact(n) {
  if (!Number.isFinite(n)) return '∞';
  if (Math.abs(n) < 1000) return Math.floor(n).toLocaleString('nl-NL');
  const marks = [['Qa',1e15],['T',1e12],['B',1e9],['M',1e6],['K',1e3]];
  const mark = marks.find(([,factor]) => n >= factor);
  if (!mark) return n.toFixed(0);
  return (n / mark[1]).toLocaleString('nl-NL',{maximumFractionDigits:2}) + ' ' + mark[0];
}
function defaultSave() {
  return {
    balance: 25,
    earned: 0,
    spent: 0,
    cycles: 0,
    machines: MACHINE_TYPES.map((_, i) => ({ level:i===0?1:0, manager:false, running:false, progress:0 })),
    updatedAt: now()
  };
}
function readSave() {
  try {
    const saved=JSON.parse(localStorage.getItem(STORAGE_KEY));
    if (!saved || !Array.isArray(saved.machines) || saved.machines.length!==MACHINE_TYPES.length) return defaultSave();
    const clean=defaultSave();
    for(const field of ['balance','earned','spent','cycles']) {
      if(Number.isFinite(saved[field]) && saved[field]>=0) clean[field]=saved[field];
    }
    clean.machines=saved.machines.map((machine,i)=>({
      level:Number.isSafeInteger(machine.level)&&machine.level>=0?machine.level:(i===0?1:0),
      manager:Boolean(machine.manager)&&Number(machine.level)>0,
      running:Boolean(machine.running)&&Number(machine.level)>0,
      progress:Number.isFinite(machine.progress)?Math.max(0,Math.min(.999999,machine.progress)):0
    }));
    clean.updatedAt=Number.isFinite(saved.updatedAt) ? Math.min(saved.updatedAt,now()):now();
    return clean;
  } catch {return defaultSave();}
}
let game=readSave();
let buyMode='1';
let activeTab='machines';
let lastTick=now();
let toastTimer;
let lastRender=0;
let lastSave=0;
let hiddenSince=null;

// Every batch milestone doubles the output of that machine.
function multiplier(level) { return 2**MILESTONES.filter(n=>level>=n).length; }
function payout(i){const m=game.machines[i],d=MACHINE_TYPES[i];return m.level*d.revenue*multiplier(m.level);}
function unitCost(i, level){return Math.ceil(MACHINE_TYPES[i].cost * Math.pow(1.16,level));}
function purchaseQuote(i,requested){
  const current=game.machines[i].level;
  let count=0,total=0;
  const maxCount=requested==='max'?10000:Number(requested);
  for(let j=0;j<maxCount;j++){
    const price=unitCost(i,current+j);
    if(!Number.isFinite(price)||total+price>game.balance) break;
    total+=price;count++;
  }
  return {count,total,nextCost:unitCost(i,current)};
}
function incomeRate(){return game.machines.reduce((sum,m,i)=>sum+(m.manager?payout(i)/MACHINE_TYPES[i].duration:0),0);}
function addMoney(amount,cycles){
  if(!amount||!Number.isFinite(amount))return;
  game.balance+=amount;game.earned+=amount;game.cycles+=cycles;
}
function updateProduction(elapsedSeconds,offlineOnly=false){
  if(elapsedSeconds<=0)return 0;
  let totalEarned=0;
  for(let i=0;i<MACHINE_TYPES.length;i++){
    const m=game.machines[i], d=MACHINE_TYPES[i];
    if(!m.manager && offlineOnly)continue;
    if(!m.running && !m.manager)continue;
    if(m.level===0)continue;
    const cyclesElapsed=elapsedSeconds/d.duration;
    if(m.manager){
      const progress=m.progress+cyclesElapsed;
      const completed=Math.floor(progress+1e-9);
      m.progress=progress-completed;
      m.running=true;
      if(completed>0){const amount=completed*payout(i);addMoney(amount,completed);totalEarned+=amount;}
    }else{
      m.progress+=cyclesElapsed;
      if(m.progress>=1){const amount=payout(i);addMoney(amount,1);totalEarned+=amount;m.running=false;m.progress=0;}
    }
  }
  return totalEarned;
}
function save(){
  try{game.updatedAt=now();localStorage.setItem(STORAGE_KEY,JSON.stringify(game));$('saveIndicator').textContent='● Opgeslagen';lastSave=now();}
  catch{$('saveIndicator').textContent='● Opslaan niet mogelijk';}
}
function notify(message){const el=$('toast');el.textContent=message;el.classList.add('show');clearTimeout(toastTimer);toastTimer=setTimeout(()=>el.classList.remove('show'),2200);}
function showOffline(amount,seconds){
  if(seconds<5||amount<=0)return;
  $('offlineAmount').textContent=`+ ${money(amount)}`;
  const h=Math.floor(seconds/3600),min=Math.floor(seconds%3600/60);
  $('offlineDuration').textContent=`${h?h+' uur en ':''}${min} minuten afwezig`;
  $('offlineLimitNote').textContent=seconds>=OFFLINE_CAP_SECONDS?'Maximaal 8 uur offline opbrengst berekend':'100% opbrengst · maximaal 8 uur';
  $('offlineModal').hidden=false;
  $('collectButton').focus();
}
function offlineCatchup(){
  const elapsed=Math.max(0,(now()-game.updatedAt)/1000);
  const allowed=Math.min(elapsed,OFFLINE_CAP_SECONDS);
  const earned=updateProduction(allowed,true);
  game.updatedAt=now();lastTick=now();
  save();
  showOffline(earned,elapsed);
}
function tick(){
  if(document.hidden)return;
  const current=now();
  let delta=Math.max(0,(current-lastTick)/1000);
  lastTick=current;
  // Browsers may throttle timers. A time jump counts as offline time for managed machines.
  if(delta>8){const earned=updateProduction(Math.min(delta,OFFLINE_CAP_SECONDS),true);if(earned>0)showOffline(earned,delta);}
  else updateProduction(delta,false);
  if(current-lastRender>120){renderDynamic();lastRender=current;}
  if(current-lastSave>2000)save();
}
function buy(i){
  const quote=purchaseQuote(i,buyMode);
  if(!quote.count){notify('Niet genoeg geld voor deze upgrade.');return;}
  game.balance-=quote.total;game.spent+=quote.total;game.machines[i].level+=quote.count;
  save();renderAll();notify(`${MACHINE_TYPES[i].name}: +${quote.count} gekocht!`);
}
function start(i){
  const m=game.machines[i];
  if(!m.level||m.running||m.manager)return;
  m.running=true;m.progress=0;save();renderAll();
}
function hire(i){
  const m=game.machines[i],d=MACHINE_TYPES[i];
  if(!m.level||m.manager||game.balance<d.managerCost){notify('Deze manager kun je nog niet aannemen.');return;}
  game.balance-=d.managerCost;game.spent+=d.managerCost;m.manager=true;m.running=true;
  save();renderAll();notify(`${d.managerName} is aangenomen!`);
}
function setupEvents(){
  document.querySelectorAll('[data-tab]').forEach(b=>b.addEventListener('click',()=>{
    activeTab=b.dataset.tab;
    document.querySelectorAll('[data-tab]').forEach(el=>{
      const selected=el.dataset.tab===activeTab;
      el.classList.toggle('active',selected);el.setAttribute('aria-selected',String(selected));
    });
    for(const tab of ['Machines','Managers','Stats']) $('panel'+tab).hidden=tab.toLowerCase()!==activeTab;
    renderAll();
  }));
  document.querySelectorAll('[data-buy]').forEach(b=>b.addEventListener('click',()=>{
    buyMode=b.dataset.buy;
    document.querySelectorAll('[data-buy]').forEach(el=>el.classList.toggle('selected',el.dataset.buy===buyMode));
    renderMachines();
  }));
  $('machines').addEventListener('click',event=>{
    const b=event.target.closest('button[data-action]');if(!b)return;
    const i=Number(b.dataset.index);
    if(b.dataset.action==='buy')buy(i);
    else if(b.dataset.action==='start')start(i);
  });
  $('managers').addEventListener('click',event=>{
    const b=event.target.closest('button[data-hire]');if(b)hire(Number(b.dataset.hire));
  });
  $('collectButton').addEventListener('click',()=>{$('offlineModal').hidden=true;});
  $('resetButton').addEventListener('click',()=>{
    if(!confirm('Weet je zeker dat je alle voortgang wilt verwijderen?'))return;
    game=defaultSave();lastTick=now();save();renderAll();notify('Nieuw spel gestart.');
  });
  document.addEventListener('visibilitychange',()=>{
    if(document.hidden){save();hiddenSince=now();}
    else{const elapsed=Math.max(0,(now()-game.updatedAt)/1000);const earned=updateProduction(Math.min(elapsed,OFFLINE_CAP_SECONDS),true);lastTick=now();save();renderAll();showOffline(earned,elapsed);hiddenSince=null;}
  });
  window.addEventListener('pagehide',save);
}
function renderMachines(){
  $('machines').innerHTML=MACHINE_TYPES.map((d,i)=>{
    const m=game.machines[i],q=purchaseQuote(i,buyMode);
    const buttonText=buyMode==='max' ? `KOOP MAX ${q.count?`(x${q.count})`:''}` : `KOOP x${buyMode}`;
    const price=q.count?money(q.total):money(q.nextCost);
    const next=MILESTONES.find(v=>v>m.level);
    return `<article class="machine-card ${m.level===0?'locked':''}">
      <div class="machine-top"><div class="machine-icon" aria-hidden="true">${d.icon}</div>
      <div class="machine-info"><h3>${d.name}</h3><div class="machine-sub">Level ${compact(m.level)} · ${d.duration} sec/cyclus</div></div>
      <div class="machine-value"><strong>${money(payout(i))}</strong><small>per cyclus</small></div></div>
      <div class="progress-track" role="progressbar" aria-label="Voortgang ${d.name}" aria-valuemin="0" aria-valuemax="100" aria-valuenow="${Math.round(m.progress*100)}"><div id="progress${i}" class="progress-fill" style="width:${m.progress*100}%"></div></div>
      <div class="machine-actions"><button data-action="start" data-index="${i}" type="button" class="start-btn ${m.manager?'auto':''}" ${!m.level||m.running||m.manager?'disabled':''}>${m.manager?'✓ AUTOMATISCH':m.running?'⏳ BEZIG...':'▶ START PRODUCTIE'}</button>
      <button data-action="buy" data-index="${i}" type="button" class="upgrade-btn" ${!q.count?'disabled':''}>${buttonText} · ${price}</button></div>
      ${m.level===0?'<div class="unlock-note">🔒 Koop je eerste machine om te beginnen.</div>':''}
      <div class="milestones">${m.manager?'🟢 Manager actief':'👔 Nog geen manager'} ${next?` · Volgende verdubbeling bij level <b>${next}</b>`:' · Alle mijlpalen behaald'}</div>
    </article>`;
  }).join('');
}
function renderManagers(){
  $('managers').innerHTML=MACHINE_TYPES.map((d,i)=>{
    const m=game.machines[i];
    return `<article class="manager-card"><div class="manager-avatar" aria-hidden="true">👷</div><div class="manager-info"><h3>${d.managerName}</h3><p>Automatiseert de ${d.name.toLowerCase()}. ${m.manager?'Verdient ook offline geld.':'Start iedere cyclus automatisch opnieuw.'}</p></div><button data-hire="${i}" type="button" class="manager-buy ${m.manager?'hired':''}" ${m.manager||m.level===0||game.balance<d.managerCost?'disabled':''}>${m.manager?'✓ AANGENOMEN':money(d.managerCost)}</button></article>`;
  }).join('');
}
function renderDynamic(){
  $('cash').textContent=money(game.balance);
  $('income').textContent=`${money(incomeRate())} / seconde automatisch`;
  $('ownedCount').textContent=compact(game.machines.reduce((a,m)=>a+m.level,0));
  $('managerCount').textContent=`${game.machines.filter(m=>m.manager).length} / ${MACHINE_TYPES.length}`;
  $('statEarned').textContent=money(game.earned);
  $('statSpent').textContent=money(game.spent);
  $('statCycles').textContent=compact(game.cycles);
  $('statRate').textContent=money(incomeRate())+' / sec';
  if(activeTab==='machines'){
    for(let i=0;i<MACHINE_TYPES.length;i++){
      const progress=$('progress'+i);
      if(progress){progress.style.width=(game.machines[i].progress*100)+'%';progress.parentElement.setAttribute('aria-valuenow',String(Math.round(game.machines[i].progress*100)));}
    }
    // Costs / affordance are refreshed at a lower cadence, avoiding DOM churn each frame.
    if(now()-lastMachineRender>600){renderMachines();lastMachineRender=now();}
  }
  if(activeTab==='managers' && now()-lastManagerRender>900){renderManagers();lastManagerRender=now();}
}
let lastMachineRender=0,lastManagerRender=0;
function renderAll(){renderMachines();renderManagers();renderDynamic();lastMachineRender=now();lastManagerRender=now();}
setupEvents();
offlineCatchup();
renderAll();
setInterval(tick,100);

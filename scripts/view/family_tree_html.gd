class_name FamilyTreeHtml
extends RefCounted
## 自包含离线文档。仅接受只读谱系与画布布局，不访问模拟入口。

static func render(tree: Dictionary, nation_name: String, current: int, nation_alive: bool, day: int, rects: Dictionary, state: GameState = null, nation_id: int = -1) -> String:
	var people: Array = []
	var members: Dictionary = tree.get("members", {})
	var ids := members.keys()
	ids.sort()
	for id in ids:
		var member: Dictionary = members[id]
		var rect: Rect2 = rects.get(id, Rect2())
		var badges: Array[String] = []
		if bool(member.get("taizu", false)): badges.append("太祖")
		if bool(member.get("crown", false)) and bool(member.get("alive", true)): badges.append("继承人")
		if state != null:
			var affiliation := FamilyTree.affiliation_label(state, member, nation_id)
			if not affiliation.is_empty(): badges.append(affiliation)
		if str(member.get("accession_source", "")) == "remote": badges.append("远支入继")
		elif bool(member.get("synthetic_ancestor", false)): badges.append("补录")
		if not bool(member.get("alive", true)): badges.append("已故")
		elif int(id) == current: badges.append("在位" if nation_alive else "末任")
		people.append({
			"id": int(id), "parent": int(member.get("parent_id", -1)),
			"name": str(member.get("name", "？")),
			"title": FamilyTree.display_title(member, int(id), int(tree.get("root_person_id", -1)), state),
			"title_history": FamilyTree.title_history_lines(member),
			"titles": member.get("titles", []), "badges": badges, "emperor": FamilyTree.was_emperor(member),
			"rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y],
		})
	var data := JSON.stringify({"nation": nation_name, "day": day, "current": current, "people": people})
	# JSON 嵌入 script 时必须转义 <，包括姓名中的 </script>，浏览器才不会提前结束数据块。
	data = data.replace("<", "\\u003c").replace(">", "\\u003e").replace("&", "\\u0026")
	return DOCUMENT.replace("__PAGE_TITLE__", (nation_name + "家族树").xml_escape()).replace("__FAMILY_DATA__", data)

static func save(path: String, html: String) -> Error:
	if html.is_empty(): return ERR_INVALID_DATA
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_string(html)
	file.flush()
	var error := file.get_error()
	file.close()
	return error

const DOCUMENT := """<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>__PAGE_TITLE__</title>
<style>
:root { --paper:#efe2c5; --ink:#483723; --red:#922e28; }
* { box-sizing:border-box; }
body { margin:0; height:100vh; display:flex; flex-direction:column; background:var(--paper); color:#000; font:bold 16px FangSong,"仿宋",STFangsong,serif; }
button,input { font:inherit; color:#000; background:#faf3e3; border:1px solid var(--ink); padding:8px 12px; }
button { cursor:pointer; }
button:hover { background:#e7d4ab; }
button:focus-visible,input:focus-visible,canvas:focus-visible { outline:3px solid var(--red); outline-offset:2px; }
header { padding:12px 16px; border-bottom:2px solid var(--ink); }
h1 { font-size:22px; margin:0 0 8px; overflow-wrap:anywhere; }
h2 { font-size:18px; margin:12px 0; overflow-wrap:anywhere; }
p { margin:8px 0; line-height:1.6; overflow-wrap:anywhere; }
.toolbar { display:flex; flex-wrap:wrap; gap:8px; align-items:center; }
#stamp,#hint { font-size:14px; }
main { display:flex; min-height:0; flex:1; }
#viewport { flex:1; min-width:0; position:relative; overflow:hidden; }
canvas { display:block; width:100%; height:100%; touch-action:none; cursor:grab; }
canvas:active { cursor:grabbing; }
aside { width:300px; overflow:auto; padding:12px; border-left:1px solid var(--ink); }
input { width:100%; }
.people { display:flex; flex-direction:column; gap:6px; margin-top:8px; }
.people button { text-align:left; overflow-wrap:anywhere; }
#results { max-height:240px; overflow:auto; }
@media(max-width:700px) { body { height:100dvh; } main { flex-direction:column; } #viewport { min-height:240px; } aside { width:100%; max-height:38vh; border-left:0; border-top:1px solid var(--ink); } }
</style>
</head>
<body>
<header>
<h1>__PAGE_TITLE__</h1>
<div class="toolbar">
<button id="zoom-in" aria-label="放大家族树">放大</button>
<button id="zoom-out" aria-label="缩小家族树">缩小</button>
<button id="current">定位当前君主</button>
<button id="fit">全谱总览</button>
<span id="stamp"></span>
</div>
<p id="hint">双线框为历任皇帝，红色顶边为当前君主 · 拖动或滚轮平移 · Ctrl＋滚轮缩放 · 点击人物查看父子关系 · 方向键平移</p>
</header>
<main>
<div id="viewport"><canvas id="tree" tabindex="0" aria-label="家族树图谱，可拖动缩放；也可通过右侧姓名搜索浏览人物"></canvas></div>
<aside>
<label for="search">搜索姓名或爵位</label>
<input id="search" type="search" placeholder="输入姓名、继承人、晋王等">
<p id="matches" role="status"></p>
<div id="results" class="people"></div>
<section id="details" aria-live="polite"></section>
</aside>
</main>
<noscript>请启用浏览器 JavaScript 来查看此离线家族树。</noscript>
<script id="family-data" type="application/json">__FAMILY_DATA__</script>
<script>
(() => {
  'use strict';
  const data = JSON.parse(document.getElementById('family-data').textContent);
  const people = data.people, byId = new Map(people.map(p => [p.id,p]));
  const children = new Map(), rows = new Map();
  let extent = [520,260];
  for (const p of people) {
    if (!children.has(p.parent)) children.set(p.parent,[]);
    children.get(p.parent).push(p);
    const [x,y,w,h] = p.rect;
    if (!rows.has(y)) rows.set(y,[]);
    rows.get(y).push(p);
    extent[0] = Math.max(extent[0],x+w+56); extent[1] = Math.max(extent[1],y+h+32);
  }
  const canvas = document.getElementById('tree'), ctx = canvas.getContext('2d');
  const viewport = document.getElementById('viewport'), details = document.getElementById('details');
  const search = document.getElementById('search'), results = document.getElementById('results');
  let scale = 1, ox = 0, oy = 0, selected = data.current, frame = 0, drag = null;
  document.getElementById('stamp').textContent = `第${data.day}天 · 全谱${people.length}人 · 离线快照`;
  function requestDraw() { if (!frame) frame = requestAnimationFrame(draw); }
  function clippedText(text,x,y,width,font) {
    ctx.font = `bold ${font}px FangSong,"仿宋",STFangsong,serif`;
    let label = String(text);
    if (ctx.measureText(label).width > width) {
      while (label.length && ctx.measureText(label+'…').width > width) label = label.slice(0,-1);
      label += '…';
    }
    ctx.fillText(label,x,y);
  }
  function draw() {
    frame = 0;
    const width = viewport.clientWidth, height = viewport.clientHeight, dpr = window.devicePixelRatio || 1;
    if (canvas.width !== Math.round(width*dpr) || canvas.height !== Math.round(height*dpr)) {
      canvas.width = Math.round(width*dpr); canvas.height = Math.round(height*dpr);
    }
    ctx.setTransform(dpr,0,0,dpr,0,0); ctx.clearRect(0,0,width,height);
    ctx.translate(ox,oy); ctx.scale(scale,scale);
    const left = -ox/scale, top = -oy/scale, right = left+width/scale, bottom = top+height/scale;
    ctx.lineWidth = 1.5; ctx.strokeStyle = '#847259';
    for (const [parentId,kids] of children) {
      const parent = byId.get(parentId); if (!parent || !kids.length) continue;
      const [x,y,w,h] = parent.rect, py = y+h, joint = py+32;
      const first = kids[0].rect, last = kids[kids.length-1].rect;
      if (last[0]+last[2] < left || first[0] > right || py > bottom || joint+32 < top) continue;
      ctx.beginPath(); ctx.moveTo(x+w/2,py); ctx.lineTo(x+w/2,joint);
      ctx.moveTo(first[0]+first[2]/2,joint); ctx.lineTo(last[0]+last[2]/2,joint);
      for (const kid of kids) {
        const [kx,ky,kw] = kid.rect;
        if (kx+kw < left || kx > right) continue;
        ctx.moveTo(kx+kw/2,joint); ctx.lineTo(kx+kw/2,ky);
      }
      ctx.stroke();
    }
    for (const [y,row] of rows) {
      if (y+72 < top || y > bottom) continue;
      for (const p of row) {
        const [x,py,w,h] = p.rect; if (!w || x+w < left || x > right) continue;
        ctx.fillStyle = p.emperor ? '#f7e8c2' : '#f5e7c4'; ctx.fillRect(x,py,w,h);
        ctx.strokeStyle = p.id === selected ? '#922e28' : '#483723';
        ctx.lineWidth = p.id === selected ? 3 : 1.5; ctx.strokeRect(x,py,w,h);
        if (p.emperor) { ctx.strokeStyle = '#7a5721'; ctx.lineWidth = 2; ctx.strokeRect(x+5,py+5,w-10,h-10); }
        if (p.id === data.current) { ctx.fillStyle = '#922e28'; ctx.fillRect(x+2,py+2,w-4,3); }
        if (scale < .2) continue;
        ctx.fillStyle = '#000'; ctx.textAlign = 'center';
        clippedText(p.name,x+w/2,py+31,w-16,16);
        clippedText(p.title,x+w/2,py+56,w-16,13);
        ctx.textAlign = 'right'; clippedText(p.badges.join(' · '),x+w-8,py+14,w-16,10);
      }
    }
    if (!people.length) { ctx.setTransform(dpr,0,0,dpr,0,0); ctx.fillStyle='#000'; ctx.textAlign='left'; clippedText('暂无谱系记录',24,48,width-48,18); }
  }
  function personButton(p) {
    const b = document.createElement('button');
    b.textContent = `${p.name} · ${p.title}（编号${p.id}）`;
    b.addEventListener('click',() => locate(p.id)); return b;
  }
  function showDetails() {
    details.replaceChildren(); const p = byId.get(selected); if (!p) return;
    const h = document.createElement('h2'); h.textContent=p.name; details.append(h);
    const info = document.createElement('p'); info.textContent = [p.title,...p.badges].join(' · '); details.append(info);
    const titles = document.createElement('p'); titles.textContent='历封：'+(p.titles.join('、') || '无'); details.append(titles);
    for (const record of p.title_history) { const line=document.createElement('p'); line.textContent=record; details.append(line); }
    const parent = byId.get(p.parent), label = document.createElement('p');
    label.textContent = parent ? '父辈' : '父辈未载'; details.append(label);
    if (parent) details.append(personButton(parent));
    const kids = children.get(p.id) || [], count = document.createElement('p');
    count.textContent=`子嗣：${kids.length}人`; details.append(count);
    const list = document.createElement('div'); list.className='people'; details.append(list);
    for (const kid of kids) list.append(personButton(kid));
  }
  function locate(id) {
    const p = byId.get(id); if (!p) return;
    selected=id; scale=1;
    ox=viewport.clientWidth/2-(p.rect[0]+p.rect[2]/2); oy=viewport.clientHeight/2-(p.rect[1]+p.rect[3]/2);
    showDetails(); requestDraw();
  }
  function zoom(factor,x=viewport.clientWidth/2,y=viewport.clientHeight/2) {
    const next = Math.max(.00001,Math.min(3,scale*factor)), ratio=next/scale;
    ox=x-(x-ox)*ratio; oy=y-(y-oy)*ratio; scale=next; requestDraw();
  }
  function fit() {
    scale=Math.max(.00001,Math.min(1,(viewport.clientWidth-32)/extent[0],(viewport.clientHeight-32)/extent[1]));
    ox=(viewport.clientWidth-extent[0]*scale)/2; oy=(viewport.clientHeight-extent[1]*scale)/2; requestDraw();
  }
  let matches=[], shown=0;
  function appendResults() {
    const end=Math.min(shown+50,matches.length);
    for (;shown<end;shown++) results.append(personButton(matches[shown]));
    if (shown<matches.length) {
      const more=document.createElement('button'); more.textContent='加载更多';
      more.addEventListener('click',() => { more.remove(); appendResults(); }); results.append(more);
    }
  }
  function find() {
    const q=search.value.trim();
    matches=people.filter(p => !q || p.name.includes(q) || p.title.includes(q) || p.badges.some(b => b.includes(q)));
    document.getElementById('matches').textContent=`找到${matches.length}人`; results.replaceChildren(); shown=0; appendResults();
  }
  search.addEventListener('input',find);
  document.getElementById('current').addEventListener('click',() => locate(data.current));
  document.getElementById('fit').addEventListener('click',fit);
  document.getElementById('zoom-in').addEventListener('click',() => zoom(1.3));
  document.getElementById('zoom-out').addEventListener('click',() => zoom(1/1.3));
  canvas.addEventListener('wheel',e => {
    e.preventDefault();
    if (e.ctrlKey) { const r=canvas.getBoundingClientRect(); zoom(Math.exp(-e.deltaY*.002),e.clientX-r.left,e.clientY-r.top); }
    else { ox-=e.deltaX; oy-=e.deltaY; requestDraw(); }
  },{passive:false});
  canvas.addEventListener('pointerdown',e => {
    if (e.button!==0) return;
    canvas.focus(); canvas.setPointerCapture(e.pointerId); drag={x:e.clientX,y:e.clientY,ox,oy,moved:false};
  });
  canvas.addEventListener('pointermove',e => {
    if (!drag) return;
    const dx=e.clientX-drag.x,dy=e.clientY-drag.y;
    drag.moved=drag.moved || Math.abs(dx)+Math.abs(dy)>4; ox=drag.ox+dx; oy=drag.oy+dy; requestDraw();
  });
  canvas.addEventListener('pointerup',e => {
    if (!drag) return;
    if (!drag.moved) {
      const r=canvas.getBoundingClientRect(),x=(e.clientX-r.left-ox)/scale,y=(e.clientY-r.top-oy)/scale;
      const p=people.find(p => x>=p.rect[0] && x<=p.rect[0]+p.rect[2] && y>=p.rect[1] && y<=p.rect[1]+p.rect[3]);
      if (p) { selected=p.id; showDetails(); requestDraw(); }
    }
    drag=null;
  });
  canvas.addEventListener('pointercancel',() => { drag=null; });
  canvas.addEventListener('keydown',e => {
    const moves={ArrowLeft:[64,0],ArrowRight:[-64,0],ArrowUp:[0,64],ArrowDown:[0,-64]};
    if (moves[e.key]) { e.preventDefault(); ox+=moves[e.key][0]; oy+=moves[e.key][1]; requestDraw(); }
  });
  new ResizeObserver(requestDraw).observe(viewport);
  find(); if (byId.has(data.current)) locate(data.current); else fit();
})();
</script>
</body>
</html>
"""

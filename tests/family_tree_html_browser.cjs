// Run with Playwright available on NODE_PATH:
// node tests/family_tree_html_browser.cjs exported.html [large.html] [screenshot.png]
const assert = require('node:assert/strict');
const {pathToFileURL} = require('node:url');
const {chromium} = require('playwright');

(async () => {
  const [file, large, screenshot] = process.argv.slice(2);
  assert(file, 'provide a generated HTML file');
  const browser = await chromium.launch({headless:true, ...(process.env.FAMILY_HTML_BROWSER_CHANNEL ? {channel:process.env.FAMILY_HTML_BROWSER_CHANNEL} : {})});
  try {
    const page = await browser.newPage({viewport:{width:1440,height:900}});
    const errors = [], remote = [];
    page.on('pageerror',e => errors.push(e.message));
    page.on('console',m => { if (m.type() === 'error') errors.push(m.text()); });
    page.on('request',r => { if (!r.url().startsWith('file:')) remote.push(r.url()); });
    for (const path of [...new Set([file,large].filter(Boolean))]) {
      const started = Date.now();
      await page.goto(pathToFileURL(path).href);
      await page.locator('#details h2').waitFor();
      const data = await page.locator('#family-data').textContent().then(JSON.parse);
      assert.equal(new Set(data.people.map(p => p.id)).size,data.people.length,'all people have distinct identities');
      assert(data.people.every(p => p.rect[2]>0 && p.rect[3]>0),'all exported people have a positioned card');
      assert(data.people.some(p => p.parent>=0),'parent links are preserved');
      assert(data.people.filter(p => p.emperor).length>1,'past and present emperors have special frames');
      assert.equal(await page.locator('#details h2').textContent(),data.people.find(p => p.id===data.current).name);
      assert.equal(await page.evaluate(() => window.injected),undefined,'special names cannot execute scripts');
      assert((await page.locator('#matches').textContent()).includes(String(data.people.length)));
      assert((await page.locator('#results button').count())<=51,'search results remain paginated');
      await page.getByRole('button',{name:'全谱总览',exact:true}).click();
      await page.getByRole('button',{name:'放大家族树',exact:true}).click();
      await page.getByRole('button',{name:'缩小家族树',exact:true}).click();
      const special=data.people.find(p => p.name.includes('</script>')) || data.people[0];
      await page.getByRole('searchbox').fill(special.name);
      await page.locator('#results button').first().click();
      assert.equal(await page.locator('#details h2').textContent(),special.name,'a distant/special person is searchable');
      if (special.parent>=0) {
        const parent=data.people.find(p => p.id===special.parent);
        await page.locator('#details > button').click();
        assert.equal(await page.locator('#details h2').textContent(),parent.name,'parent navigation works');
      }
      await page.getByRole('button',{name:'定位当前君主',exact:true}).click();
      assert.equal(await page.locator('#details h2').textContent(),data.people.find(p => p.id===data.current).name);
      await page.locator('#tree').focus(); await page.keyboard.press('ArrowRight'); await page.keyboard.press('ArrowDown');
      const box=await page.locator('#tree').boundingBox();
      await page.mouse.move(box.x+box.width/2,box.y+box.height/2);
      await page.mouse.down(); await page.mouse.move(box.x+box.width/2+80,box.y+box.height/2+40); await page.mouse.up();
      await page.getByRole('button',{name:'定位当前君主',exact:true}).click();
      await page.getByRole('searchbox').fill('找不到的人物XYZ');
      assert.equal(await page.locator('#matches').textContent(),'找到0人');
      await page.getByRole('searchbox').fill('');
      console.log(`FAMILY_HTML_BROWSER people=${data.people.length} load_and_interact_ms=${Date.now()-started}`);
    }
    if (screenshot) await page.screenshot({path:screenshot});
    for (const width of [320,768,1024,1440]) {
      await page.setViewportSize({width,height:900});
      await page.getByRole('button',{name:'定位当前君主',exact:true}).click();
      assert(await page.locator('#tree').evaluate(c => c.clientHeight>=240 && c.clientWidth>0));
      assert(await page.evaluate(() => document.documentElement.scrollWidth<=window.innerWidth),'no horizontal page overflow');
      const style=await page.locator('#details').evaluate(e => ({color:getComputedStyle(e).color,font:getComputedStyle(e).fontFamily,weight:getComputedStyle(e).fontWeight}));
      assert.equal(style.color,'rgb(0, 0, 0)'); assert(style.font.includes('FangSong')); assert(+style.weight>=700);
    }
    assert.deepEqual(errors,[],'browser console is clean');
    assert.deepEqual(remote,[],'offline document makes no remote requests');
    console.log('FAMILY_HTML_BROWSER_OK');
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode=1; });

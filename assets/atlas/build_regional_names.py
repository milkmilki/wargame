"""Rebuild the static, disjoint regional naming vocabulary (UTF-8).

Preferred roots are curated geographic/name characters. Extension roots are
stable basic-Han characters, partitioned once at build time, never at runtime.
"""
import json
from pathlib import Path

SEEDS = {
    'farm': '秦楚齐晋鲁宋郑卫周汉唐魏燕赵陈蔡许邓吴越梁蜀郑郯莒曹滕薛纪邾徐邢霍虞虢芮息随申吕曾郧庸夔鄢郜戴沈舒桐皖豫雍冀兖青扬荆益徐洛汴颍颌偃洛宛邺邯淮泗睢濮汝涡洺邠鄠郿岐丰镐亳安平昌宁康泰兴盛永长承启建开成济德义礼仁信和正元文武宣昭明景隆庆寿祯祥瑞嘉福裕富丰稷穗禾麦粟黍稻谷桑麻棉田畴圃苑园阡陌耕耘苗芽花柳桃李梨枣杏槐榆榕柏梓楸',
    'nomad': '胡狄戎羌匈鲜乌桓突厥柔敕铁勒回纥契丹奚肃慎靺鞨蒙鞑瓦剌哈萨柯兀颜哲里阿尔鄂斡孛赤帖木穆罕塔喀赛图布巴达纳额苏鲁岱托朵亦乃蛮蔑乞弘吉剌博速不察虎豹狼鹰雕鹫鹘隼鹞鹗骏骁骥骊骅骝骐驹骃骖骋骇驰腾骜骓骛骆驼鹿麋羚獐羯羝羔牦牯犍犊犀兽毡帐穹庐牧猎射骑鞍辔镫缰弓弩箭矢铎锋锐铠盔戈矛戟刀剑盾旌旗旄旆旐旒旛旂旃旜碛漠沙瀚旷原野荒旱燥朔塞陲垣烽燧垒旻昊苍昴奎轸参翼氐亢娄毕觜奎胄',
    'sea': '沧瀛溟溱潮澜澎湃涛浪波汐澳湾港浦泊津渡舶帆航艇舰舟舸舷艄舵桅楫棹橹篙艘船滨涯汀渚洲屿礁岬岫岛崖崂岬岱岚岑嵊甬鄞瓯闽粤琼儋崖汕湛茂雷廉莆湄濠沪申浙澥沽涌滘渔鲛鲸鲲鲵鲳鲷鲈鲻鲔鲣鲭鲨鳐鳗鳕鳟鳜鲋鲚鳎鲽鳍鳞鳃蚌蛤蚝蚶蜃螺螯蟹虾玳瑁瑚珊珠贝玑珀琥玫瑰珑璇璟璐琪琦瑶碧璃玲琅玦璧璜珩玟瑜珺瑛璨璞珍盐卤藻苔蓬莱瀛瀚湮淼澈潋滟潇泠滔漾潺澄澹瀰浔浒泺沅浣湍沱滂澧涟溆濡浚淙溶滢滉',
    'highland': '昆仑祁连岷蜀嵩岳岱华衡恒泰崇峻峰岭峦嶂嵯峨峒峪嵘峥嵬巍崆峣嶙嶷峤崃岢岣崮岍崞峙嵋岐岖岌岿岷崌崀嶒崾峁岜嵝崖磐岩磊砺砥砦砀砾碣硖碛硐硌碉磬磴硗硎砧砣碇碚礅礞硭礓硒硼硅钙镁铬钛铝锰钨钼铅锡钒铂钴镍铜锌矿锷铿锵锽锺钟岷羌藏蕃羯僰彝俅僳羌湟洮湔汶岷汶绛赭丹紫玄黛黝皑皓雪霜雹雾霰霭霏霁霞霓晖曦曙暄曜耀晟昱昶昕昀昉昽昂峒峤嵚崤岘嵛嶓岓岄岅',
    'river': '江河川汾渭浊清湘资沅澧汉沔漳漯淄汶沂沭沧沁沛滹沱洨滏滦泾洛滁滠汀瓠荥济淇洹滈滉涑洧汴渤汜浍浊汨汩漉滗泓泮涓滴渺涣溉漕渠漳淞湫涧沟滩滩滩堤坝堰圩埭垱堰塘池泉井灌润泽沐沆沣沄沁泌澍浥潼涞溯涸溢濂浏浯洙涿濯瀑濑濒滇洱滓渌溧泗泖泸洵溱洺淝漪漣湑浠沚汊汶津湾濆浐灞泔湔浃漈漳渟潆沋汴堰潞浑渝滇滁淦溴洭灏瀣濞浡泐涠浈濉淬淅濮沤沥涅淖滃溏漩潴漭滦濛漯澴洌淩溦漴潏淀沔',
    'lake': '洞庭鄱彭蠡巢太滆震笠笋荷莲芙蓉菱芡菰蒲芦荻芷萍苹苇菖蓼茭藕荇蘋葭蕖蘅蕙菡萏莞蕨菟茹茵蒹葑茈莼菹苧荼蓁蕴苒茸蘩薇蓓菀茜茉茗茧蓬蕃芬芳馨馥菊兰蒿荛荸荠葶萋萱芊芥蓿苜苞苎苾荭菪葚蒺藜蕺藓莎苫荽茯芩茱萸苕荞苣苋蓣蓂蓄蓐蘘蘧茑薰薷薯莳莪莠荁芫苘蕲蓊蕞荜葎菥莰荬芃荏萆莨菔菅苠苡鸥鹭鹤鹳鹬鹜鸬鹚鸭鹅凫鸳鸯鹈鹕雁鸿鹄鹮鹛鹆鹨鹪鹩鹎鹱鹲鹣鸨鸺鹠鸱鸲鸫鹑鸻鴷鶄鵁',
    'forest': '松杉桦枫栎樟檀楠楝椿椴樗榛榧榉榄榭槭桧桤梧梣桉栲柞柽橡榔榈楮桫椤桡榽椰楂棠橘柚柑柠橙樱柿柘枳枰柯柢桁梭桷栋楹椽榫楯杞杳枥枣樨檎柰楷槎桓杼椐榆柀槲樵薪樽檐栩栀柟栊檑森木林树枝杈根杖材板机架框栅栏栈梢梗椅棣棕杻枨栒栟栳桴棓棂棼檄橇榱槁槿栾欒榘梳枯槐柒札朵本朴术朱朽杷枇栐樾櫆橐樑棋楫桀梨橄桃柄枢枋枧梵梃梽楔槠樯橥橼棱棹桐梁梅林叶竹筠篁箬箐箕箫箴篆篝簇箦箧箜篌筱筐簟簧筝筏笛篾笙笠篷籁箩筒笺筮竺箸籽篱笋簪筼',
}
ENDINGS = {
    'farm':['安','阳','邑','丰','陵','宁','昌','平','成','原'],
    'nomad':['原','野','庭','陉','垣','台','塞','谷','甸','漠'],
    'sea':['浦','津','湾','港','屿','澳','滨','崖','汀','洲'],
    'highland':['岭','峰','关','峪','岩','陇','垣','山','岚','崖'],
    'river':['川','河','津','堤','溪','渡','渠','洲','泉','源'],
    'lake':['泽','湖','塘','渚','浦','池','陂','汀','荡','湾'],
    'forest':['林','溪','岭','谷','岚','岑','坞','丘','樵','坪'],
}

NOMAD_PREFERRED = '''桂由 贵由 拖雷 托雷 铁木真 铁木尔 窝阔台 蒙哥 忽必烈 阿里不哥 术赤 察合台 合撒儿 合赤温 别勒古台 也速该 诃额伦 孛儿帖 弘吉剌 速不台 者勒蔑 博尔术 博尔忽 木华黎 失吉忽秃 赤老温 扎木合 塔塔统阿 哲别 别速台 兀良合 纳牙阿 速亦别额 巴鲁剌 豁儿赤 阿术 伯颜 阿合马 阿塔海 阔阔出 阔阔真 海都 昔里吉 乃颜 真金 甘麻剌 完者笃 和世拉 图帖睦尔 妥欢帖睦尔 脱脱 察罕帖木儿 扩廓帖木儿 脱欢 也先 达延 巴图蒙克 满都海 俺答 辛爱 黄台吉 兀鲁斯 博迪 达赉 哈萨尔 孛罗 合丹 八邻 斡亦剌 帖木哥 别儿哥 旭烈兀 阿八哈 阿鲁浑 海山 爱育黎拔力八达 硕德八剌 也孙铁木儿 阿速 阿鲁台 也速帖木儿 桑哥 忙哥剌 阔端 兀赤斡儿 托克托 也不干 额森 哈丹 察干 巴特尔 巴图 巴雅尔 阿古拉 阿日斯兰 额尔敦 乌力吉 苏和 宝音 赛罕 乌兰 娜仁 其木格 萨日娜 斯琴 高娃 格根 达来 达日汗 德勒格尔 嘎拉 森格 卓里克图 俄木布 和硕 昆都仑 哈喇 昭莫多 哈斯 额尔德尼 鄂齐尔 玛哈 穆麟 图门 阿剌知院 孛来 马可古儿 摩伦 阿勒坦 格勒博罗 赛因 孟克 珊丹 呼和 伊拉 阿木古郎 敖特根 纳日松 苏日格 科尔沁 哈勒图 巴音 傲拉 希拉 卓索 乌恩 吉雅 乌日根 图雅 洪郭尔 岱钦 特古斯 呼日查 乌日图'''.split()
NOMAD_TOWNS = '''锡林 呼伦 海拉尔 库伦 哈拉和林 克鲁伦 鄂尔多斯 阿拉善 乌拉特 阿巴嘎 巴尔虎 察哈尔 苏尼特 扎鲁特 翁牛特 敖汉 喀喇沁 土默特 杜尔伯特 伊克昭 巴彦诺尔 科布多 乌里雅苏台 额济纳 呼图壁 阿尔泰 扎兰屯 伊敏 达尔罕 阿尔山 索伦 满洲里 呼和浩特 包克图 乌兰察布 巴彦淖尔 霍林郭勒 锡尼 布尔罕 额尔古纳 乌珠穆沁 伊勒都 巴彦塔拉 哈拉哈 纳林 卓资 沙尔沁 敖鲁古雅 莫尔道嘎 阿鲁科尔沁 巴彦浩特 乌海 希拉穆仁'''.split()

def nomad_vocabulary():
    preferred = [name for name in dict.fromkeys(NOMAD_PREFERRED) if 2 <= len(name) <= 4]
    assert len(preferred) >= 128
    towns = [name for name in dict.fromkeys(NOMAD_TOWNS) if name not in preferred]
    used = set(preferred + towns)
    prefixes = '阿 额 乌 布 巴 托 拖 哈 合 察 扎 忽 莫 蒙 库 达 苏 索 博 哲 泰 图 满 克 郭 鄂 伊 奇 纳 呼 勒 穆 赛 伯 塔 尼 斡 孛 兀 海 里 雅 敖'.split()
    suffixes = '古 鲁 力 雷 台 敦 罕 尔 拉 图 伦 兰 海 温 木 真 仁 钦 格 思 日 穆 纳 勒 和 察 苏 索 莫 胡 术 速 脱 特 颜 沁 诺 博 秃 哥 烈 班 赤 兀 孛 达 戈 合 斡 拙'.split()
    generated = []
    for prefix in prefixes:
        for suffix in suffixes:
            name = prefix + suffix
            if prefix != suffix and name not in used:
                generated.append(name); used.add(name)
    extension = generated[:1024-len(preferred)]
    towns += generated[len(extension):len(extension)+1024-len(towns)]
    assert len(preferred)+len(extension)==1024 and len(towns)==1024
    assert len(set(preferred+extension+towns))==2048
    return {'preferred':preferred,'extension':extension,'towns':towns}

def build():
    preferred = {kind: [] for kind in SEEDS}
    used = set()
    # Allocate curated characters before extensions, preserving stable order.
    for kind, text in SEEDS.items():
        for char in text:
            if char not in used and '一' <= char <= '鿿':
                preferred[kind].append(char); used.add(char)
    assert all(len(chars) >= 128 for chars in preferred.values()), {k:len(v) for k,v in preferred.items()}
    available = [chr(code) for code in range(0x4e00,0xa000) if chr(code) not in used and chr(code) not in '国部汗王军']
    pools = {}
    cursor = 0
    for kind, chars in preferred.items():
        extension = available[cursor:cursor+1024-len(chars)]
        cursor += len(extension)
        pools[kind] = {'preferred': ''.join(chars), 'extension': ''.join(extension), 'endings':ENDINGS[kind]}
    all_roots = ''.join(p['preferred']+p['extension'] for p in pools.values())
    assert len(all_roots) == len(set(all_roots)) == 7168
    output = Path(__file__).with_name('regional_names.json')
    output.write_text(json.dumps({'version':'regional-names-v2','pools':pools,'nomad_names':nomad_vocabulary()},ensure_ascii=False,indent=2)+'\n',encoding='utf8')
    print({k:len(v) for k,v in preferred.items()})

if __name__ == '__main__': build()

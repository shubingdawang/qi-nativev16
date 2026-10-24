// 甜品屋的内容表：食材、坯底、奶油口味、装饰、客人、装修、升级、等级解锁。
// 口味标签（tags）：sweet 甜、sour 酸、rich 浓郁、fresh 清爽、fruity 果香、floral 花香、bitter 微苦、crunchy 酥脆、cute 可爱、classic 经典
'use strict';

const TAG_NAMES = { sweet: '甜', sour: '酸', rich: '浓郁', fresh: '清爽', fruity: '果香', floral: '花香', bitter: '微苦', crunchy: '酥脆', cute: '可爱', classic: '经典' };

// 食材：价格（每份）、几级解锁、带来的口味、季节（这个季节便宜）
const INGREDIENTS = {
  flour:      { name: '面粉',   price: 2,  lv: 1, tags: {},                         color: '#efe6d6' },
  butter:     { name: '黄油',   price: 3,  lv: 1, tags: { rich: 1 },                color: '#f1dca0' },
  egg:        { name: '鸡蛋',   price: 1,  lv: 1, tags: {},                         color: '#f3e3c4' },
  sugar:      { name: '砂糖',   price: 1,  lv: 1, tags: { sweet: 1 },               color: '#faf6ef' },
  milk:       { name: '牛奶',   price: 2,  lv: 1, tags: { classic: .5 },            color: '#f7f4ee' },
  cream:      { name: '淡奶油', price: 4,  lv: 1, tags: { rich: .5, sweet: .5 },    color: '#fbf6ee' },
  strawberry: { name: '草莓',   price: 4,  lv: 1, tags: { fruity: 1, sweet: .5, cute: .5 }, color: '#d9566b', season: 'spring' },
  blueberry:  { name: '蓝莓',   price: 4,  lv: 1, tags: { fruity: 1, fresh: .5 },   color: '#4d5a8c', season: 'summer' },
  cocoa:      { name: '可可',   price: 3,  lv: 1, tags: { rich: 1, bitter: .5 },    color: '#6b4a3a' },
  lemon:      { name: '柠檬',   price: 3,  lv: 2, tags: { sour: 1, fresh: 1 },      color: '#ead27a', season: 'summer' },
  matcha:     { name: '抹茶',   price: 5,  lv: 2, tags: { bitter: 1, fresh: .5, classic: .3 }, color: '#93a86e' },
  mint:       { name: '薄荷',   price: 2,  lv: 2, tags: { fresh: 1 },               color: '#8fb894' },
  cheese:     { name: '奶油奶酪', price: 5, lv: 3, tags: { rich: 1, sour: .3 },     color: '#f4ead2' },
  mango:      { name: '芒果',   price: 5,  lv: 3, tags: { fruity: 1, sweet: .7 },   color: '#ecb24a', season: 'summer' },
  nuts:       { name: '杏仁',   price: 4,  lv: 3, tags: { crunchy: 1, classic: .3 }, color: '#c99a6a', season: 'autumn' },
  caramel:    { name: '焦糖',   price: 3,  lv: 4, tags: { sweet: 1, rich: .5 },     color: '#c7894a' },
  peach:      { name: '桃子',   price: 5,  lv: 4, tags: { fruity: 1, sweet: .5, cute: .3 }, color: '#f2b5a0', season: 'summer' },
  sakura:     { name: '樱花',   price: 6,  lv: 5, tags: { floral: 1, cute: 1 },     color: '#f3c4cf', season: 'spring' },
  chestnut:   { name: '栗子',   price: 6,  lv: 5, tags: { rich: 1, classic: .5 },   color: '#8a5a3c', season: 'autumn' },
  rose:       { name: '玫瑰',   price: 7,  lv: 6, tags: { floral: 1.2 },            color: '#d98a9a' },
  sprinkles:  { name: '彩色糖针', price: 2, lv: 2, tags: { cute: 1, sweet: .5 },    color: '#f0a8c0' },
  goldleaf:   { name: '金箔',   price: 12, lv: 7, tags: { classic: .5 },            color: '#d8b45a' },
};

// 坯底：要哪些食材（一份料做 4 个）、本身的口味、大概值多少钱
const BASES = {
  sponge:  { name: '戚风蛋糕', lv: 1, need: { flour: 1, egg: 2, sugar: 1, milk: 1 }, tags: { classic: 1, sweet: .5 }, value: 14 },
  cupcake: { name: '纸杯蛋糕', lv: 1, need: { flour: 1, butter: 1, egg: 1, sugar: 1 }, tags: { cute: 1, sweet: .5 }, value: 10 },
  tart:    { name: '水果挞',   lv: 1, need: { flour: 1, butter: 1, sugar: 1, egg: 1 }, tags: { crunchy: .7, classic: .5 }, value: 12 },
  cookie:  { name: '曲奇',     lv: 2, need: { flour: 1, butter: 1, sugar: 1 }, tags: { crunchy: 1, sweet: .5 }, value: 7 },
  choux:   { name: '泡芙',     lv: 2, need: { flour: 1, butter: 1, egg: 2, milk: 1 }, tags: { classic: .5, cute: .3 }, value: 11 },
  roll:    { name: '蛋糕卷',   lv: 3, need: { flour: 1, egg: 2, sugar: 1, cream: 1 }, tags: { classic: .5, sweet: .3 }, value: 15 },
  macaron: { name: '马卡龙',   lv: 4, need: { egg: 2, sugar: 2, nuts: 1 }, tags: { cute: 1, sweet: 1 }, value: 12 },
  crepe:   { name: '千层蛋糕', lv: 5, need: { flour: 1, egg: 2, milk: 2, cream: 1 }, tags: { rich: .5, classic: .5 }, value: 20 },
};

// 奶油 / 内馅口味：要哪些食材、什么颜色
const CREAMS = {
  plain:      { name: '原味奶油',   lv: 1, need: { cream: 1, sugar: 1 }, color: '#fbf5ea', tags: { sweet: .5 } },
  strawberry: { name: '草莓奶油',   lv: 1, need: { cream: 1, strawberry: 1 }, color: '#f2c3c8', tags: { fruity: .7, cute: .5 } },
  choco:      { name: '巧克力甘纳许', lv: 1, need: { cream: 1, cocoa: 1 }, color: '#7a5240', tags: { rich: 1, bitter: .4 } },
  lemon:      { name: '柠檬凝乳',   lv: 2, need: { lemon: 1, egg: 1, sugar: 1 }, color: '#f1dd8e', tags: { sour: 1, fresh: .7 } },
  matcha:     { name: '抹茶奶油',   lv: 2, need: { cream: 1, matcha: 1 }, color: '#bccb9c', tags: { bitter: .7, fresh: .5 } },
  cheese:     { name: '芝士奶油',   lv: 3, need: { cream: 1, cheese: 1 }, color: '#f6efdc', tags: { rich: .8, sour: .3 } },
  mango:      { name: '芒果奶油',   lv: 3, need: { cream: 1, mango: 1 }, color: '#f5d48a', tags: { fruity: .8, sweet: .5 } },
  caramel:    { name: '海盐焦糖',   lv: 4, need: { cream: 1, caramel: 1 }, color: '#d9a46c', tags: { sweet: .7, rich: .5 } },
  sakura:     { name: '樱花奶油',   lv: 5, need: { cream: 1, sakura: 1 }, color: '#f6d3da', tags: { floral: .8, cute: .7 } },
  chestnut:   { name: '栗子蓉',     lv: 5, need: { chestnut: 1, cream: 1 }, color: '#b48a68', tags: { rich: .8, classic: .5 } },
  rose:       { name: '玫瑰荔枝',   lv: 6, need: { cream: 1, rose: 1 }, color: '#efc3cc', tags: { floral: 1, fruity: .3 } },
};

// 装饰：用掉哪种食材（一份能摆几个）、颜色（算配色用）
const TOPPINGS = {
  strawberry: { name: '草莓',     uses: 'strawberry', per: 12, hue: 'red' },
  halfberry:  { name: '半颗草莓', uses: 'strawberry', per: 20, hue: 'red' },
  blueberry:  { name: '蓝莓',     uses: 'blueberry', per: 30, hue: 'blue' },
  mint:       { name: '薄荷叶',   uses: 'mint', per: 20, hue: 'green' },
  lemon:      { name: '柠檬片',   uses: 'lemon', per: 10, hue: 'yellow' },
  mango:      { name: '芒果丁',   uses: 'mango', per: 16, hue: 'yellow' },
  peach:      { name: '桃子片',   uses: 'peach', per: 10, hue: 'orange' },
  curl:       { name: '巧克力卷', uses: 'cocoa', per: 20, hue: 'brown' },
  nut:        { name: '杏仁片',   uses: 'nuts', per: 30, hue: 'brown' },
  chestnut:   { name: '糖渍栗子', uses: 'chestnut', per: 8, hue: 'brown' },
  sakura:     { name: '樱花',     uses: 'sakura', per: 15, hue: 'pink' },
  petal:      { name: '玫瑰花瓣', uses: 'rose', per: 20, hue: 'pink' },
  sprinkle:   { name: '糖针',     uses: 'sprinkles', per: 15, hue: 'rainbow' },
  pearl:      { name: '糖珠',     uses: 'sugar', per: 40, hue: 'white' },
  gold:       { name: '金箔',     uses: 'goldleaf', per: 20, hue: 'gold' },
};

// 装饰之外的手法
const TOOLS = {
  pipe:    { name: '裱花' },
  drizzle: { name: '淋酱' },
  dust:    { name: '筛糖粉' },
};

// 口味搭得好的组合：做出来额外加分
const PAIRS = [
  ['strawberry', 'cream', 6], ['matcha', 'strawberry', 8], ['lemon', 'blueberry', 8], ['cocoa', 'strawberry', 6],
  ['caramel', 'nuts', 8], ['cheese', 'blueberry', 7], ['mango', 'mint', 6], ['sakura', 'strawberry', 7],
  ['chestnut', 'cocoa', 6], ['rose', 'peach', 8], ['lemon', 'mint', 6], ['cocoa', 'nuts', 5], ['peach', 'cream', 5],
];

// 客人：预算、喜欢什么（权重）、讨厌什么、开口时会说的话（说得不清不楚，要她猜）
const CUSTOMER_TYPES = {
  student: {
    name: '学生', budget: [12, 26], patience: 26, likes: { sweet: 1, cute: 1, fruity: .7 }, dislikes: { bitter: 1 },
    lines: ['有没有甜甜的、看着就开心的？', '想要可爱一点的，拍照好看的那种～', '零花钱不多……有便宜又好吃的吗？', '想吃水果味的！'],
    look: { hair: ['#3b2a24', '#5b3a2e', '#2d2a2e'], top: ['#a9c1d9', '#f2c3c8', '#c7bcd8'], bottom: ['#5b6475', '#7a6a8a'] },
  },
  office: {
    name: '上班族', budget: [22, 42], patience: 18, likes: { rich: 1, bitter: .8, classic: .5 }, dislikes: { cute: .4 },
    lines: ['来点不那么甜的，配咖啡。', '加班续命，要浓一点的。', '有没有成熟一点的口味？', '随便，好吃就行……快一点。'],
    look: { hair: ['#2d2a2e', '#3b2a24'], top: ['#f4f1ea', '#d9dde3'], bottom: ['#3e4552', '#5a5560'] },
  },
  granny: {
    name: '奶奶', budget: [15, 32], patience: 40, likes: { classic: 1.2, sweet: .5, rich: .3 }, dislikes: { bitter: .8, sour: .5 },
    lines: ['给孙女带一块，要老派一点的。', '年纪大了，要软软的、别太酸。', '你们这儿有像以前那种蛋糕吗？', '慢慢来，不着急～'],
    look: { hair: ['#d8d2c8', '#c9c2b8'], top: ['#b48a68', '#a9b89a', '#c9a27c'], bottom: ['#6b5a50'] },
  },
  couple: {
    name: '情侣', budget: [30, 62], patience: 24, likes: { cute: .8, floral: 1, fruity: .5 }, dislikes: {}, pretty: 1.2,
    lines: ['今天纪念日，挑一个最好看的！', '有没有粉粉的、浪漫一点的？', '她喜欢花，有花香的吗？', '要拍照发朋友圈的那种～'],
    look: { hair: ['#5b3a2e', '#2d2a2e', '#8a5a3c'], top: ['#f2c3c8', '#f4f1ea', '#e8b4b8'], bottom: ['#c7bcd8', '#5b6475'] },
  },
  kid: {
    name: '小朋友', budget: [8, 18], patience: 14, likes: { sweet: 1.2, cute: 1 }, dislikes: { bitter: 1.5, sour: .8 },
    lines: ['我要彩色的！！', '最甜最甜的那个！', '妈妈说只能买一个……', '有没有小兔子那么可爱的？'],
    look: { hair: ['#3b2a24', '#6c4636'], top: ['#f1dca0', '#a9d0c4', '#f2b5a0'], bottom: ['#6f8fb0', '#e8b4b8'] },
  },
  athlete: {
    name: '健身的姐姐', budget: [18, 36], patience: 20, likes: { fresh: 1.2, sour: .8, fruity: .8 }, dislikes: { sweet: .6, rich: .6 },
    lines: ['刚跑完步，想要清爽一点的。', '不要太甜！酸酸的最好。', '有水果多一点的吗？', '今天允许自己吃一块，要好吃的。'],
    look: { hair: ['#2d2a2e', '#5b3a2e'], top: ['#a9c9b6', '#c7d9e8'], bottom: ['#3e4552'] },
  },
  critic: {
    name: '美食评论家', budget: [55, 110], patience: 22, likes: { classic: .6, rich: .6, floral: .4 }, dislikes: {}, strict: true, minLv: 3,
    lines: ['请给我这家店的招牌。', '我只尝一口，就知道值不值得写。', '让我看看你的手艺。'],
    look: { hair: ['#2d2a2e', '#d8d2c8'], top: ['#3e4552', '#6b4a3a'], bottom: ['#2d2a2e'] },
  },
};

// 常客：每种客人里会反复来的那一位，有名字、有好感，好感到了会讲自己的事、送东西
const REGULARS = [
  { id: 'xiaoyu', type: 'student', name: '小雨', hair: '#3b2a24', top: '#a9c1d9',
    story: ['小雨在附近读高三，每天放学都路过这里。', '她说考试考砸了的那天，吃了你的蛋糕就没那么难过了。', '小雨考上了想去的学校！她送了你一包彩色糖针。'],
    gifts: [null, null, { money: 0, ingredient: 'sprinkles', n: 10 }] },
  { id: 'lin', type: 'granny', name: '林奶奶', hair: '#d8d2c8', top: '#a9b89a',
    story: ['林奶奶以前也开过一家点心铺，在老街那头。', '她说你揉面的样子，跟她年轻时候一模一样。', '林奶奶把压箱底的栗子蓉方子教给了你。'],
    gifts: [null, null, { unlockCream: 'chestnut' }] },
  { id: 'azhe', type: 'office', name: '阿哲', hair: '#2d2a2e', top: '#f4f1ea',
    story: ['阿哲在对面写字楼上班，总是最后一个走。', '他说这周终于不用加班了，想买一块犒劳自己。', '阿哲升职了，拉着整个部门来订下午茶。'],
    gifts: [null, null, { money: 180 }] },
  { id: 'tangtang', type: 'kid', name: '糖糖', hair: '#6c4636', top: '#f1dca0',
    story: ['糖糖每次都踮着脚趴在展示柜上看。', '她给 clawd 画了一张画，说他像一块方糖。', '糖糖过生日，妈妈在你这儿订了蛋糕，还送了你一盆花。'],
    gifts: [null, { decor: 'drawing' }, { decor: 'flowerpot' }] },
  { id: 'susu', type: 'couple', name: '苏苏和阿洛', hair: '#5b3a2e', top: '#f2c3c8',
    story: ['苏苏和阿洛第一次约会就是在你店里。', '阿洛偷偷问你，求婚的时候能不能帮忙做一个蛋糕。', '他们订婚了！送了你一束玫瑰，以后玫瑰进货便宜一成。'],
    gifts: [null, null, { discount: 'rose' }] },
  { id: 'xia', type: 'athlete', name: '夏姐', hair: '#2d2a2e', top: '#a9c9b6',
    story: ['夏姐每天早上绕着小区跑五公里。', '她说你的柠檬挞是她唯一不算热量的甜点。', '夏姐带跑团的朋友们来，在门口挂了一面小旗子。'],
    gifts: [null, null, { decor: 'pennant' }] },
  { id: 'xue', type: 'critic', name: '雪先生', hair: '#d8d2c8', top: '#3e4552',
    story: ['雪先生是本地美食杂志的专栏作者，说话很少。', '他在专栏里提了一句你的店，这周客人明显多了。', '雪先生把你的店写成了整整一版。名气大涨！'],
    gifts: [null, { fame: 40 }, { fame: 120 }] },
];

// 装修：放在地上 / 墙上，加多少氛围，偏向吸引哪种客人
const DECOR = {
  table:     { name: '小圆桌',   place: 'floor', price: 60,  lv: 1, cozy: 4, likes: 'student', w: 70 },
  armchair:  { name: '丝绒扶手椅', place: 'floor', price: 120, lv: 2, cozy: 6, likes: 'office', w: 52 },
  plant:     { name: '龟背竹',   place: 'floor', price: 50,  lv: 1, cozy: 3, likes: 'athlete', w: 46 },
  flowerpot: { name: '一盆花',   place: 'floor', price: 40,  lv: 1, cozy: 3, likes: 'couple', w: 34 },
  bookshelf: { name: '小书架',   place: 'floor', price: 140, lv: 3, cozy: 6, likes: 'student', w: 60 },
  gramophone:{ name: '留声机',   place: 'floor', price: 220, lv: 4, cozy: 8, likes: 'granny', w: 46 },
  cakestand: { name: '三层点心架', place: 'floor', price: 160, lv: 3, cozy: 5, likes: 'couple', w: 40 },
  teddy:     { name: '泰迪熊',   place: 'floor', price: 80,  lv: 2, cozy: 4, likes: 'kid', w: 38 },
  frame:     { name: '小油画',   place: 'wall',  price: 70,  lv: 1, cozy: 3, likes: 'granny', w: 44 },
  clock:     { name: '挂钟',     place: 'wall',  price: 90,  lv: 2, cozy: 3, likes: 'office', w: 40 },
  wreath:    { name: '花环',     place: 'wall',  price: 80,  lv: 2, cozy: 4, likes: 'couple', w: 44 },
  mirror:    { name: '拱形镜',   place: 'wall',  price: 150, lv: 4, cozy: 5, likes: 'couple', w: 40 },
  garland:   { name: '小灯串',   place: 'wall',  price: 100, lv: 3, cozy: 6, likes: 'kid', w: 90 },
  drawing:   { name: '糖糖的画', place: 'wall',  price: 0,   lv: 99, cozy: 5, likes: 'kid', w: 36, gift: true },
  pennant:   { name: '跑团小旗', place: 'wall',  price: 0,   lv: 99, cozy: 4, likes: 'athlete', w: 50, gift: true },
  trophy:    { name: '比赛奖杯', place: 'wall',  price: 0,   lv: 99, cozy: 8, likes: 'critic', w: 32, gift: true },
};
const WALLPAPERS = {
  cream:  { name: '奶油条纹', price: 0,   lv: 1, a: '#f6ece0', b: '#f1e3d3', kind: 'stripe' },
  rose:   { name: '玫瑰碎花', price: 160, lv: 2, a: '#f6e6e4', b: '#e9c3c4', kind: 'floral' },
  sage:   { name: '鼠尾草格纹', price: 160, lv: 3, a: '#e8ede0', b: '#d4ddc6', kind: 'check' },
  lilac:  { name: '丁香波点', price: 200, lv: 4, a: '#ece6f1', b: '#d6cbe3', kind: 'dot' },
  damask: { name: '复古大马士革', price: 320, lv: 6, a: '#efe4d4', b: '#dbc7a9', kind: 'damask' },
};
const FLOORS = {
  oak:     { name: '橡木地板', price: 0,   lv: 1, a: '#d8bb98', b: '#cdae89', kind: 'plank' },
  checker: { name: '黑白格',   price: 180, lv: 2, a: '#efe9df', b: '#6e625a', kind: 'checker' },
  herring: { name: '人字拼',   price: 240, lv: 4, a: '#caa47c', b: '#b98f66', kind: 'herring' },
  terrazzo:{ name: '水磨石',   price: 260, lv: 5, a: '#ece6dc', b: '#cbbfae', kind: 'terrazzo' },
};

// 升级
const UPGRADES = {
  oven:    { name: '烤箱', levels: [{ desc: '一炉 4 个', batch: 4 }, { desc: '一炉 6 个，烤得更快', batch: 6, price: 300, lv: 2 }, { desc: '一炉 9 个，火候更稳', batch: 9, price: 800, lv: 4 }, { desc: '一炉 12 个，专业石板烤箱', batch: 12, price: 1800, lv: 7 }] },
  mixer:   { name: '搅拌', levels: [{ desc: '手动搅拌' }, { desc: '台式搅拌机：批量做时口感不打折', price: 260, lv: 2 }, { desc: '专业厨师机：批量做口感 +5', price: 900, lv: 5 }] },
  case:    { name: '展示柜', levels: [{ desc: '6 格', slots: 6 }, { desc: '9 格', slots: 9, price: 400, lv: 3 }, { desc: '12 格', slots: 12, price: 1200, lv: 6 }] },
  sign:    { name: '门口招牌', levels: [{ desc: '手写小黑板' }, { desc: '木质招牌：客人多一成', price: 220, lv: 2 }, { desc: '霓虹灯牌：客人多两成半', price: 700, lv: 5 }] },
  fridge:  { name: '冷藏柜', levels: [{ desc: '没有：卖不完的第二天降价' }, { desc: '冷藏柜：卖不完的第二天照原价', price: 500, lv: 4 }] },
};

// 等级：名气多少升一级
const LEVELS = [0, 60, 160, 320, 560, 900, 1350, 1950, 2700, 3600];

// 周末甜品大赛的题目
const CONTESTS = [
  { name: '春日樱花', want: { floral: 1, cute: 1 }, note: '要有花香、要可爱' },
  { name: '夏日清凉', want: { fresh: 1, sour: .7, fruity: .7 }, note: '清爽、带点酸、水果' },
  { name: '秋收', want: { rich: 1, crunchy: .7, classic: .5 }, note: '浓郁、酥脆、经典' },
  { name: '冬夜暖甜', want: { rich: 1, sweet: .8 }, note: '浓郁、甜' },
  { name: '复古下午茶', want: { classic: 1.2, floral: .5 }, note: '经典、优雅' },
  { name: '孩子们的派对', want: { cute: 1.2, sweet: 1 }, note: '可爱、甜、彩色' },
];

const SEASONS = ['spring', 'summer', 'autumn', 'winter'];
const SEASON_NAMES = { spring: '春', summer: '夏', autumn: '秋', winter: '冬' };
const WEATHERS = {
  sunny:  { name: '晴', traffic: 1.1 },
  cloudy: { name: '多云', traffic: 1 },
  rain:   { name: '小雨', traffic: .75 },
  snow:   { name: '下雪', traffic: .7 },
  hot:    { name: '炎热', traffic: .95 },
};

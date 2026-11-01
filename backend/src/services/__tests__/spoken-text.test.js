const { toSpoken } = require('../spoken-text');

describe('toSpoken', () => {
  test('对子按中国牌手的叫法念', () => {
    expect(toSpoken('我拿QQ')).toBe('我拿圈圈');
    expect(toSpoken('JJ也不错')).toBe('勾勾也不错');
    expect(toSpoken('口袋44')).toBe('口袋一对四');
    expect(toSpoken('QQ+的range')).toBe('圈圈以上的range');
  });

  test('两张牌的组合逐张念，带同花/杂色', () => {
    expect(toSpoken('AKo在枪口')).toBe('AK杂色在枪口');
    expect(toSpoken('A5s')).toBe('A五同花');
    expect(toSpoken('72o，这锅我不碰')).toBe('七二杂色，这锅我不碰');
    expect(toSpoken('拿QJ')).toBe('拿圈勾');
  });

  test('带花色的单张和牌面连写', () => {
    expect(toSpoken('这张Kh')).toBe('这张红桃K');
    expect(toSpoken('2d白板')).toBe('方块二白板');
    expect(toSpoken('翻牌K-9-4')).toBe('翻牌K九四');
    expect(toSpoken('板面K94很干')).toBe('板面K九四很干');
    expect(toSpoken('KsJs撞上Kd')).toBe('黑桃K黑桃勾撞上方块K');
    expect(toSpoken('我拿9♠5♥')).toBe('我拿黑桃九红桃五');
  });

  test('后面写了同花/不同花的数字组合也当牌念，不重复', () => {
    expect(toSpoken('我拿94不同花')).toBe('我拿九四不同花');
    expect(toSpoken('KJs同花')).toBe('K勾同花');
  });

  test('单独的Q/J/T', () => {
    expect(toSpoken('顶对J')).toBe('顶对勾');
  });

  test('下注术语、位置和盲注', () => {
    expect(toSpoken('4-bet到2500')).toBe('四bet到2500');
    expect(toSpoken('c-bet太小')).toBe('C bet太小');
    expect(toSpoken('check-raise然后all-in')).toBe('check raise然后all in');
    expect(toSpoken('UTG位开3BB')).toBe('枪口位开3个大盲');
    expect(toSpoken('BTN的3-bet')).toBe('按钮位的三bet');
  });

  test('会被内容审核误判的黑话换成平实说法，枪口位不动', () => {
    expect(toSpoken('湿板我更不能让你免费看')).toBe('听牌很多的牌面我更不能让你免费看');
    expect(toSpoken('三枪你都接了')).toBe('三条街你都接了');
    expect(toSpoken('转牌我开一枪')).toBe('转牌我下了一注');
    expect(toSpoken('UTG开池')).toBe('枪口位开池');
  });

  test('普通数字、百分比和表情不受影响', () => {
    expect(toSpoken('跟注300，底池2300')).toBe('跟注300，底池2300');
    expect(toSpoken('胜率35%')).toBe('胜率35%');
    expect(toSpoken('嘿嘿我加注哦～😜')).toBe('嘿嘿我加注哦');
  });
});

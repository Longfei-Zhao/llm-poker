import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poker_app/constants.dart';
import 'package:poker_app/models/player.dart';
import 'package:poker_app/utils/player_merge.dart';

Player _player(
  String id, {
  String name = 'Player',
  int position = 1,
  int chips = 1000,
  int bet = 0,
  String? aiModel,
  Color? modelColor,
}) {
  return Player(
    id: id,
    name: name,
    position: position,
    chips: chips,
    bet: bet,
    aiModel: aiModel,
    modelColor: modelColor,
  );
}

void main() {
  group('mergePlayers', () {
    test('已存在玩家保留aiModel/modelColor/position，其余取后端最新值', () {
      final existing = [
        _player('p1',
            name: 'Claude',
            position: 3,
            chips: 1000,
            aiModel: 'Claude',
            modelColor: Colors.orange),
      ];
      // 后端返回的同一玩家：位置和模型信息丢失，筹码有更新
      final incoming = [
        _player('p1', name: 'Claude', position: 7, chips: 850, bet: 50),
      ];

      final merged = mergePlayers(existing, incoming);

      expect(merged.length, 1);
      expect(merged[0].position, 3); // 保留本地位置
      expect(merged[0].aiModel, 'Claude'); // 保留本地模型
      expect(merged[0].modelColor, Colors.orange); // 保留本地颜色
      expect(merged[0].chips, 850); // 使用后端筹码
      expect(merged[0].bet, 50); // 使用后端下注
    });

    test('后端返回空列表时保留本地玩家', () {
      final existing = [_player('p1'), _player('p2', position: 2)];
      final merged = mergePlayers(existing, []);
      expect(merged, existing);
    });

    test('双方都为空时返回空列表', () {
      expect(mergePlayers([], []), isEmpty);
    });

    test('新玩家缺少aiModel时从名称推断并补充颜色', () {
      final merged = mergePlayers([], [
        _player('p1', name: 'DeepSeek'),
      ]);

      expect(merged[0].aiModel, 'DeepSeek');
      expect(merged[0].modelColor, GameConstants.aiModelColors['DeepSeek']);
    });

    test('新玩家名称无法推断模型时保持原样', () {
      final merged = mergePlayers([], [
        _player('p1', name: '路人甲'),
      ]);

      expect(merged[0].aiModel, isNull);
      expect(merged[0].modelColor, isNull);
    });

    test('新玩家已有aiModel时不覆盖', () {
      final merged = mergePlayers([], [
        _player('p1', name: 'Claude', aiModel: 'Grok'),
      ]);
      expect(merged[0].aiModel, 'Grok');
    });

    test('本地aiModel为空时采用后端提供的模型', () {
      final existing = [_player('p1', position: 2)];
      final incoming = [_player('p1', aiModel: 'Gemini')];

      final merged = mergePlayers(existing, incoming);
      expect(merged[0].aiModel, 'Gemini');
      expect(merged[0].position, 2);
    });

    test('本地不存在的玩家直接加入结果', () {
      final existing = [_player('p1', aiModel: 'Claude')];
      final incoming = [
        _player('p1', chips: 500),
        _player('p2', name: 'Qwen', position: 2),
      ];

      final merged = mergePlayers(existing, incoming);
      expect(merged.length, 2);
      expect(merged[0].aiModel, 'Claude');
      expect(merged[1].id, 'p2');
      expect(merged[1].aiModel, 'Qwen'); // 从名称推断
    });

    test('本地已被移除的玩家不会回到结果中', () {
      final existing = [_player('p1'), _player('p2', position: 2)];
      final incoming = [_player('p2', position: 2)];

      final merged = mergePlayers(existing, incoming);
      expect(merged.length, 1);
      expect(merged[0].id, 'p2');
    });
  });
}

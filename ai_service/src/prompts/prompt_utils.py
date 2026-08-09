from typing import Dict, List, Optional, Any, Tuple
import json
import re  # 全局导入re模块，确保所有函数都使用这个模块而不是局部变量
from ..exceptions import DecisionError
from .card_formatter import format_hand_readable

def get_position_name(position: int, dealer_index: int, total_players: int) -> str:
    """获取玩家相对位置名称
    
    Args:
        position: 玩家位置（从1开始）
        dealer_index: 庄家位置索引（从0开始）
        total_players: 玩家总数
        
    Returns:
        str: 位置名称（BTN、SB、BB等）
    """
    # 计算相对位置（相对于庄家）
    relativePos = (position - 1 - dealer_index + total_players) % total_players
    
    # 位置映射
    positionNames = {
        0: "BTN", # 庄家/按钮位
        1: "SB",  # 小盲
        2: "BB",  # 大盲
    }
    
    # 根据玩家数量动态计算其他位置
    if total_players <= 3:
        return positionNames.get(relativePos, f"P{relativePos}")
    else:
        if relativePos >= 3:
            # 3人以上桌子的其他位置
            positions = ["UTG", "UTG+1", "MP", "HJ", "CO"]
            index = relativePos - 3
            if index < len(positions):
                return positions[index]
            else:
                return f"P{relativePos}"
        else:
            return positionNames.get(relativePos, f"P{relativePos}")

def format_game_state(game_state: Dict, player_id: str) -> str:
    """格式化游戏状态
    
    Args:
        game_state: 游戏状态字典
        player_id: 玩家ID
            
    Returns:
        str: 格式化后的游戏状态描述
        
    Raises:
        ValueError: 在游戏状态中找不到当前玩家
    """
    # 获取当前玩家
    current_player = next(
        (p for p in game_state["players"] if p["id"] == player_id),
        None
    )
    if not current_player:
        raise ValueError("在游戏状态中找不到当前玩家")
        
    # 获取其他玩家
    other_players = [
        p for p in game_state["players"]
        if p["id"] != player_id and p["isActive"]
    ]
    
    # 获取总玩家数和庄家索引
    total_players = len(game_state["players"])
    dealer_index = game_state["dealerIndex"]
    
    # 获取当前玩家的位置名称
    current_position_name = get_position_name(
        current_player["position"], 
        dealer_index, 
        total_players
    )

    # 格式化玩家手牌为可读格式
    readable_hand = format_hand_readable(current_player['cards'])
    
    # 格式化公共牌为可读格式
    community_cards = game_state['communityCards']
    readable_community_cards = format_hand_readable(community_cards) if community_cards else 'none'

    # 构建状态描述
    description = f"""
small blind: {game_state['smallBlind']}
big blind: {game_state['bigBlind']}
pot: {game_state['pot']}
current bet: {game_state['currentBet']}
button position: {game_state['dealerIndex'] + 1}

your information:
- name: {current_player['name']}
- chips: {current_player['chips']}
- bet: {current_player['bet']}
- hand: {readable_hand}
- position: {current_player['position']} ({current_position_name})

community cards: {readable_community_cards}

other players:
"""
    
    for player in other_players:
        # 获取该玩家的位置名称
        position_name = get_position_name(
            player["position"], 
            dealer_index, 
            total_players
        )
        
        description += f"""
- name: {player['name']}
- chips: {player['chips']}
- bet: {player['bet']}
- position: {player['position']} ({position_name})
"""
        
    return description

def format_action_history(game_state: Dict) -> str:
    """格式化行动历史
    
    Args:
        game_state: 游戏状态字典
            
    Returns:
        str: 格式化后的行动历史描述
    """
    if not game_state.get("actionHistory"):
        return "action history: none"
    
    # 创建玩家ID到名称的映射
    player_map = {p["id"]: p["name"] for p in game_state["players"]}
    
    history_description = "action history:\n"
    
    # 阶段名称映射
    stage_names = {
        "preflop": "Pre-Flop", 
        "flop": "Flop", 
        "turn": "Turn", 
        "river": "River",
        "showdown": "Showdown"
    }
    
    for stage_history in game_state["actionHistory"]:
        stage = stage_history["stage"]
        stage_name = stage_names.get(stage, stage.capitalize())
        
        history_description += f"\n## {stage_name}\n"
        
        if not stage_history.get("actions"):
            history_description += "No actions recorded\n"
            continue
        
        for action in stage_history["actions"]:
            player_id = action["playerId"]
            player_name = player_map.get(player_id, f"Player {player_id}")
            position = action.get("playerPosition", "")
            action_type = action["action"]
            amount = action.get("amount", 0)
            is_all_in = action.get("isAllIn", False)
            
            # 格式化行动描述
            if position:
                player_info = f"{player_name} ({position})"
            else:
                player_info = player_name
                
            if action_type == "fold":
                action_description = "folds"
            elif action_type == "check":
                action_description = "checks"
            elif action_type == "call":
                action_description = f"calls {amount}"
            elif action_type == "raise":
                action_description = f"raises to {amount}"
            elif action_type == "smallBlind":
                action_description = f"posts small blind {amount}"
            elif action_type == "bigBlind":
                action_description = f"posts big blind {amount}"
            else:
                action_description = f"{action_type} {amount}"
                
            if is_all_in:
                action_description += " (ALL-IN)"
                
            history_description += f"- {player_info}: {action_description}\n"
    
    return history_description

def build_prompt(
    game_state: Dict,
    player_id: str,
    valid_actions: List[str],
    min_bet: int,
    max_bet: int
) -> str:
    """构建决策提示词
    
    Args:
        game_state: 游戏状态
        player_id: 玩家ID
        valid_actions: 有效的动作列表
        min_bet: 最小下注额
        max_bet: 最大下注额
        
    Returns:
        str: 决策提示词
    """
    state_description = format_game_state(game_state, player_id)
    
    # 构建行动历史描述
    action_history_description = format_action_history(game_state)
    
    prompt = f"""
You are a professional Texas Hold'em player.
You are playing in a 8-player Texas Hold'em game.
Assess the current situation and decide what kind of action to make.

game state:
{state_description}

{action_history_description}

you can take actions:
{', '.join(valid_actions)}

if you choose raise, the range of bet is:
- min: {min_bet} (this is the minimum total bet amount on the table)
- max: {max_bet} (this is your maximum possible total bet amount)

Please note that these are TOTAL bet amounts, not additional amounts. Your current bet is included in these numbers.

Please output your decision in JSON format, as follows:
{{
  "thinking": "record your thinking process in Chinese",
  "action": "fold|check|call|raise|allin",
  "amount": number (only when action is raise)
}}

Note:
1. Only choose the given valid actions
2. If 'check' is available in your valid actions, you should prefer it over 'fold'
3. If you choose raise, the amount must be in the range of min and max bet
4. Must output valid JSON format, and include detailed thinking process
"""
    
    # 打印完整提示词到控制台
    print("\n" + "="*50)
    print("⭐️ LLM接收到的完整提示词:")
    print("="*50)
    print(prompt)
    print("="*50 + "\n")
    
    return prompt

def parse_response(response_text: str, valid_actions=None, min_bet=None, max_bet=None) -> Tuple[str, Optional[int], Optional[str]]:
    """
    解析LLM响应，提取动作和下注金额
    
    参数:
        response_text: LLM返回的文本响应
        valid_actions: 有效的动作列表
        min_bet: 最小下注金额
        max_bet: 最大下注金额
        
    返回:
        tuple: (动作, 金额, 思考过程)
    """
    # 在函数开始处定义regex_module，避免变量未定义错误
    import re as regex_module
    
    thinking = None
    action = None
    amount = None
    
    print("\n" + "="*50)
    print("🔍 标准响应解析过程:")
    print("="*50)
    print(f"解析响应长度: {len(response_text)} 字符")
    
    # 先尝试解析为JSON
    try:
        # 尝试解析为JSON
        if "```json" in response_text:
            print("📋 检测到```json```代码块格式")
            json_text = response_text.split("```json")[1].split("```")[0].strip()
            print(f"提取的JSON: {json_text[:100]}..." if len(json_text) > 100 else f"提取的JSON: {json_text}")
            response_data = json.loads(json_text)
        elif "```" in response_text:
            print("📋 检测到```代码块格式")
            json_text = response_text.split("```")[1].split("```")[0].strip()
            try:
                print(f"尝试解析代码块内容: {json_text[:100]}..." if len(json_text) > 100 else f"尝试解析代码块内容: {json_text}")
                response_data = json.loads(json_text)
            except:
                print("⚠️ 代码块内容不是有效JSON，尝试解析完整文本")
                # 可能是其他代码块格式，继续尝试解析完整文本
                response_data = json.loads(response_text)
        else:
            print("📋 无代码块格式，尝试解析完整文本为JSON")
            response_data = json.loads(response_text)
            
        print(f"✅ JSON解析成功: {response_data}")
        
        action = response_data.get("action", "").lower()
        amount = response_data.get("amount")
        thinking = response_data.get("thinking")
        
        print(f"从JSON提取的字段 - action: {action}, amount: {amount}")
        print(f"thinking字段存在: {'是' if thinking else '否'}")
        
        # 如果提取到JSON但没有thinking字段，保留原始响应
        if thinking is None and "thinking" not in response_data:
            # 清理响应文本，移除所有Markdown代码块标记
            cleaned_response = response_text
            if "```" in cleaned_response:
                # 移除所有Markdown代码块标记
                cleaned_response = regex_module.sub(r'```(?:json)?[\r\n]?', '', cleaned_response)
                cleaned_response = cleaned_response.replace('```', '')
            thinking = cleaned_response
            print("未找到thinking字段，使用清理后的原始响应作为思考过程")
        
    except Exception as e:
        # JSON解析失败，尝试从文本中提取
        # 输出调试信息
        print(f"❌ JSON解析失败: {str(e)}，尝试使用正则表达式解析")
        print(f"原始响应片段: {response_text[:150]}...")  # 显示部分响应以便调试
        
        # 清理响应文本，移除所有Markdown代码块标记
        cleaned_response = response_text
        if "```" in cleaned_response:
            # 移除所有Markdown代码块标记
            cleaned_response = regex_module.sub(r'```(?:json)?[\r\n]?', '', cleaned_response)
            cleaned_response = cleaned_response.replace('```', '')
        
        # 将清理后的响应设为思考过程
        thinking = cleaned_response
        print("使用清理后的响应作为思考过程")
        
        # 增强的正则表达式模式
        # 1. 先尝试从结构化形式中提取
        try:
            # 提取动作 (更灵活的模式)
            action_patterns = [
                r"action[\"']?\s*[:=]\s*[\"']?([a-z]+)[\"']?",  # action: "fold"
                r"我?(选择|决定)(进行)?[\s:：]?([a-z]+)",      # 我选择fold
                r"我的(决策|行动|动作)是[\s:：]?([a-z]+)",     # 我的决策是fold
                r"([a-z]+)[\s,，\.。]",                    # fold.
                r"I (choose|decide to) ([a-z]+)",          # I choose fold
                r"最终决策[:：]\s*([a-z]+)",               # 最终决策：fold
                r"决定([弃牌|跟注|加注])",                 # 决定加注
                r"(弃牌|跟注|加注)"                       # 直接中文动作名
            ]
            
            # 中文动作映射
            cn_action_map = {
                "弃牌": "fold",
                "跟注": "call",
                "加注": "raise",
                "提高": "raise",  # 有时模型会用"提高"表示raise
                "让牌": "check"   # 如果游戏支持check动作
            }
            
            print(f"🔍 尝试{len(action_patterns)}种模式匹配动作...")
            
            for i, pattern in enumerate(action_patterns):
                print(f"  模式{i+1}: {pattern}")
                action_match = regex_module.search(pattern, response_text, regex_module.IGNORECASE)
                if action_match:
                    match_text = response_text[action_match.start():action_match.end()]
                    print(f"  ✓ 匹配成功: '{match_text}'")
                    
                    # 根据匹配组的位置获取动作
                    action = action_match.group(1) if len(action_match.groups()) == 1 else action_match.group(-1)
                    action = action.lower()
                    print(f"  提取的动作文本: '{action}'")
                    
                    # 检查是否是中文动作
                    if action in cn_action_map:
                        action = cn_action_map[action]
                        print(f"  中文动作转换: {action}")
                    
                    # 检查是否是有效动作名称的一部分
                    if valid_actions:
                        for valid_action in valid_actions:
                            if valid_action in action or action in valid_action:
                                action = valid_action
                                print(f"  匹配到有效动作: {action}")
                                break
                    break
                else:
                    print(f"  ✗ 无匹配")
                
            # 处理自然语言中的特殊情况
            if not action:
                print("尝试从文本中查找动作关键词...")
                # 检查所有可能的动作关键词
                for cn_action, en_action in cn_action_map.items():
                    if cn_action in response_text:
                        action = en_action
                        print(f"  从文本中检测到中文动作: {cn_action} -> {action}")
                        break
                
                # 再检查英文动作关键词
                if not action and "fold" in response_text.lower():
                    action = "fold"
                    print("  从文本中检测到'fold'")
                elif not action and ("call" in response_text.lower() or "跟注" in response_text):
                    action = "call"
                    print("  从文本中检测到'call'或'跟注'")
                elif not action and ("raise" in response_text.lower() or "加注" in response_text or "提高" in response_text):
                    action = "raise"
                    print("  从文本中检测到'raise'或'加注'或'提高'")
                
                print(f"从文本中提取的动作: {action}")
                
            # 提取金额 (更灵活的模式)
            amount_patterns = [
                r"amount[\"']?\s*[:=]\s*(\d+)",           # amount: 100
                r"([加提]注|raise)[\s:：]?(\d+)",           # 加注100
                r"([加提]注|raise)\s?to\s?(\d+)",          # 加注to 100
                r"(\d+)\s?筹码",                          # 100筹码
                r"金额[\s:：]?(\d+)",                     # 金额：100
                r"(\d+)\s?(chips|金额)",                  # 100 chips
                r"最终决策[\s:：]?[a-z]+\s+(\d+)",         # 最终决策：raise 100
                r"加注.*?(\d+)",                         # 加注...100
                r"下注.*?(\d+)"                          # 下注...100
            ]
            
            print(f"\n🔍 尝试{len(amount_patterns)}种模式匹配金额...")
            
            for i, pattern in enumerate(amount_patterns):
                print(f"  模式{i+1}: {pattern}")
                amount_match = regex_module.search(pattern, response_text, regex_module.IGNORECASE)
                if amount_match:
                    match_text = response_text[amount_match.start():amount_match.end()]
                    print(f"  ✓ 匹配成功: '{match_text}'")
                    try:
                        # 金额通常在最后一个捕获组
                        amount = int(amount_match.group(-1))
                        print(f"  提取的金额: {amount}")
                        break
                    except:
                        print(f"  ✗ 无法转换为数字")
                        continue
                else:
                    print(f"  ✗ 无匹配")
            
            # 如果是raise但没找到金额，尝试提取任意数字
            if action == "raise" and amount is None:
                print("\n🔢 尝试查找任意数字...")
                all_numbers = regex_module.findall(r'(\d+)', response_text)
                if all_numbers:
                    # 尝试使用最后一个数字
                    try:
                        amount = int(all_numbers[-1])
                        print(f"从响应中提取到数字: {amount}")
                    except:
                        print("无法转换提取的数字为整数")
                else:
                    print("未找到任何数字")
                    
            # 处理思考过程
            if thinking is None:
                # 检查是否包含thinking、思考过程等相关词
                thinking_patterns = [
                    r"思考过程[:：]?\s*([\s\S]+?)(?=\n\s*(?:动作|行动|决策|Action|我决定|我选择|最终|result)|\Z)",
                    r"理由[:：]?\s*([\s\S]+?)(?=\n\s*(?:动作|行动|决策|Action|我决定|我选择|最终|result)|\Z)",
                    r"分析[:：]?\s*([\s\S]+?)(?=\n\s*(?:动作|行动|决策|Action|我决定|我选择|最终|result)|\Z)",
                    r"thinking[:：]?\s*([\s\S]+?)(?=\n\s*(?:action|decision|result)|\Z)",
                    r"analysis[:：]?\s*([\s\S]+?)(?=\n\s*(?:action|decision|result)|\Z)"
                ]
                
                for pattern in thinking_patterns:
                    match = regex_module.search(pattern, response_text, regex_module.IGNORECASE | regex_module.DOTALL)
                    if match:
                        thinking = match.group(1).strip()
                        print(f"从文本中提取思考过程: {thinking[:50]}...")
                        break
                
                # 如果仍未提取到思考过程，使用清理后的响应作为思考过程
                if thinking is None:
                    thinking = cleaned_response
            
            # 格式化思考过程
            if thinking:
                # 清理思考过程中的代码块标记
                thinking = regex_module.sub(r'```(?:json|javascript|python)?[\r\n]?', '', thinking)
                thinking = thinking.replace('```', '')
                # 移除多余的空行
                thinking = regex_module.sub(r'\n\s*\n', '\n\n', thinking)
                # 移除单独的{}行
                thinking = regex_module.sub(r'^\s*[\{\}]\s*$', '', thinking, flags=regex_module.MULTILINE)
            
        except Exception as e:
            print(f"❌ 正则表达式解析失败: {str(e)}")
    
    # 确保动作有效
    if valid_actions and action and action not in valid_actions:
        print(f"\n⚠️ 提取到的动作'{action}'不在有效动作列表中: {valid_actions}")
        closest_action = None
        for valid_action in valid_actions:
            if valid_action in action or action in valid_action:
                closest_action = valid_action
                break
        
        if closest_action:
            print(f"修正动作 '{action}' 为 '{closest_action}'")
            action = closest_action
        else:
            print(f"无法找到匹配的有效动作，使用默认动作")
            # 按优先级选择默认动作：check > call > fold
            if 'check' in valid_actions:
                action = 'check'
                print(f"选择'check'作为默认动作")
            elif 'call' in valid_actions:
                action = 'call'
                print(f"选择'call'作为默认动作")
            elif 'fold' in valid_actions:
                action = 'fold'
                print(f"选择'fold'作为默认动作")
            else:
                action = valid_actions[0]
                print(f"使用第一个有效动作'{action}'作为默认")
    
    # 如果仍然没有提取到有效动作
    if not action and valid_actions:
        print(f"\n⚠️ 未能提取到有效动作，使用默认动作")
        # 按优先级选择默认动作
        if 'check' in valid_actions:
            action = 'check'
            print(f"选择'check'作为默认动作")
        elif 'call' in valid_actions:
            action = 'call'
            print(f"选择'call'作为默认动作")
        elif 'fold' in valid_actions:
            action = 'fold'
            print(f"选择'fold'作为默认动作")
        else:
            action = valid_actions[0]  # 使用第一个有效动作作为默认值
            print(f"使用第一个有效动作'{action}'作为默认")
    
    # 验证金额
    if action == "raise" and amount is not None:
        if min_bet is not None and amount < min_bet:
            print(f"\n⚠️ 下注金额{amount}小于最小下注金额{min_bet}，调整为最小下注额")
            amount = min_bet
        if max_bet is not None and amount > max_bet:
            print(f"\n⚠️ 下注金额{amount}大于最大下注金额{max_bet}，调整为最大下注额")
            amount = max_bet
    
    # 确保raise动作必须有金额
    if action == "raise" and amount is None and min_bet is not None:
        print(f"raise动作没有指定金额，使用最小下注额: {min_bet}")
        amount = min_bet
    
    # 最终清理思考过程内容，移除所有Markdown格式
    if thinking:
        # 移除所有Markdown代码块标记和格式化字符
        # 使用前面重命名的regex_module而不是局部导入re
        thinking = regex_module.sub(r'```(?:json|javascript|python)?[\r\n]?', '', thinking)
        thinking = thinking.replace('```', '')
        # 移除多余的空行
        thinking = regex_module.sub(r'\n\s*\n', '\n\n', thinking)
        # 清理任何残留的JSON格式字符
        thinking = regex_module.sub(r'^\s*[\{\}]\s*$', '', thinking, flags=regex_module.MULTILINE)
        # 修剪开头和结尾的空白
        thinking = thinking.strip()
        
    print(f"\n✅ 最终解析结果: 动作={action}, 金额={amount}")
    print(f"思考过程长度: {len(thinking) if thinking else 0} 字符")
    print("="*50 + "\n")
    
    return action, amount, thinking 
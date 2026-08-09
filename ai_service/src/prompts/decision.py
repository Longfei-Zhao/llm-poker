from typing import Dict, List

def get_decision_prompt(
    state_description: str,
    valid_actions: List[str],
    min_bet: int,
    max_bet: int,
    decision_history: List[Dict]
) -> str:
    """
    生成决策提示词。
    
    Args:
        state_description: 游戏状态描述
        valid_actions: 有效的行动列表
        min_bet: 最小下注额
        max_bet: 最大下注额
        decision_history: 决策历史
        
    Returns:
        str: 决策提示词
    """
    # 构建基础提示词
    prompt = f"""你是一个德州扑克AI玩家。请根据以下游戏状态做出最优决策。

{state_description}

可选行动：
"""
    
    # 添加可选行动说明
    for action in valid_actions:
        if action == 'fold':
            prompt += "- fold（弃牌）\n"
        elif action == 'call':
            prompt += "- call（跟注）\n"
        elif action == 'raise':
            prompt += f"- raise（加注，范围：{min_bet}-{max_bet}）\n"
    
    # 添加决策历史（如果有）
    if decision_history:
        prompt += "\n最近的决策历史：\n"
        for i, record in enumerate(decision_history[-3:]):  # 只显示最近3条
            prompt += f"{i+1}. 在{record['game_state']['state']}阶段，"
            prompt += f"胜率{record['win_probability']:.2%}时，"
            prompt += f"选择了{record['decision']['action']}"
            if record['decision'].get('amount'):
                prompt += f"（金额：{record['decision']['amount']}）"
            prompt += "\n"
    
    # 添加决策要求，包括思考过程
    prompt += """
首先，请详细分析当前情况并思考你的决策过程。考虑手牌强度、位置、底池赔率、对手行为等因素。
这个思考过程将被记录并显示给用户，帮助他们理解你的决策逻辑。

然后，以JSON格式返回你的思考和决策，格式如下：
{
    "thinking": "你的详细思考过程",
    "action": "行动类型",
    "amount": 下注金额（仅在raise时需要）
}

在做出决策时，请考虑以下因素：
1. 当前手牌强度和获胜概率
2. 位置和底池赔率
3. 其他玩家的行为模式
4. 自己的筹码情况
5. 决策历史的连续性

请确保返回的JSON格式正确，且决策在有效范围内。"""
    
    return prompt 
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class ActionPanel extends StatefulWidget {
  final List<String> validActions;
  final int currentBet;
  final int minBet;
  final int maxBet;
  final Function(String action, {int? amount}) onAction;
  
  const ActionPanel({
    Key? key,
    required this.validActions,
    required this.currentBet,
    required this.minBet,
    required this.maxBet,
    required this.onAction,
  }) : super(key: key);
  
  @override
  _ActionPanelState createState() => _ActionPanelState();
}

class _ActionPanelState extends State<ActionPanel> {
  
  @override
  void initState() {
    super.initState();
  }
  
  @override
  void didUpdateWidget(ActionPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.minBet != widget.minBet || oldWidget.maxBet != widget.maxBet) {
      setState(() {
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    theme.extension<PokerThemeExtension>();
    
    return Container(
      padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.black87,
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 10,
            spreadRadius: 0,
            offset: Offset(0, -3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 标题栏
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '您的回合',
                style: TextStyle(
                  color: Colors.amber,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              Text(
                '当前下注: ${widget.currentBet}',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          // 操作按钮
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              if (widget.validActions.contains('fold'))
                _buildActionButton(
                  context,
                  '弃牌',
                  Icons.cancel_outlined,
                  Colors.red.shade700,
                  () => widget.onAction('fold'),
                ),
              if (widget.validActions.contains('check'))
                _buildActionButton(
                  context,
                  '让牌',
                  Icons.check_circle_outline,
                  Colors.green.shade700,
                  () => widget.onAction('check'),
                ),
              if (widget.validActions.contains('call'))
                _buildActionButton(
                  context,
                  '跟注\n${widget.currentBet}',
                  Icons.call_outlined,
                  Colors.blue.shade700,
                  () => widget.onAction('call'),
                ),
              if (widget.validActions.contains('allin'))
                _buildActionButton(
                  context,
                  '全押',
                  Icons.all_inclusive,
                  Colors.purple.shade700,
                  () => widget.onAction('allin'),
                ),
              if (widget.validActions.contains('raise'))
                _buildActionButton(
                  context,
                  widget.currentBet > 0 ? '加注' : '下注',
                  Icons.arrow_circle_up_outlined,
                  Colors.amber.shade700,
                  () => _showBetDialog(context),
                ),
            ],
          ),
          // 如果有加注选项，显示快速加注按钮
          if (widget.validActions.contains('raise') && widget.maxBet > widget.minBet)
            Padding(
              padding: EdgeInsets.only(top: 12),
              child: _buildQuickBetButtons(),
            ),
        ],
      ),
    );
  }
  
  Widget _buildActionButton(
    BuildContext context,
    String label,
    IconData icon,
    Color color,
    VoidCallback onPressed,
  ) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        elevation: 3,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 24),
          SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildQuickBetButtons() {
    final potSize = widget.currentBet * 2;
    
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildQuickBetButton('最小', widget.minBet),
        _buildQuickBetButton('底池1/2', potSize ~/ 2),
        _buildQuickBetButton('底池', potSize),
        _buildQuickBetButton('全压', widget.maxBet),
      ],
    );
  }
  
  Widget _buildQuickBetButton(String label, int amount) {
    final isEnabled = amount >= widget.minBet && amount <= widget.maxBet;
    
    return TextButton(
      onPressed: isEnabled ? () => widget.onAction('raise', amount: amount) : null,
      style: TextButton.styleFrom(
        backgroundColor: isEnabled ? Colors.black54 : Colors.black38,
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: BorderSide(
            color: isEnabled ? Colors.amber.withOpacity(0.5) : Colors.grey.withOpacity(0.3),
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isEnabled ? Colors.white : Colors.white60,
            ),
          ),
          Text(
            amount.toString(),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: isEnabled ? Colors.amber : Colors.white38,
            ),
          ),
        ],
      ),
    );
  }
  
  void _showBetDialog(BuildContext context) {
    int betAmount = widget.minBet;
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: Colors.black87,
              title: Text(
                '选择加注金额',
                style: TextStyle(
                  color: Colors.amber,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('最小: ${widget.minBet}', style: TextStyle(color: Colors.grey)),
                      Text('最大: ${widget.maxBet}', style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                  SizedBox(height: 10),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: Colors.amber,
                      inactiveTrackColor: Colors.grey.shade800,
                      thumbColor: Colors.amber,
                      overlayColor: Colors.amber.withOpacity(0.3),
                      valueIndicatorColor: Colors.amber,
                      valueIndicatorTextStyle: TextStyle(color: Colors.black),
                    ),
                    child: Slider(
                      value: betAmount.toDouble(),
                      min: widget.minBet.toDouble(),
                      max: widget.maxBet.toDouble(),
                      divisions: widget.maxBet - widget.minBet > 0 ? widget.maxBet - widget.minBet : 1,
                      label: betAmount.toString(),
                      onChanged: (value) {
                        setState(() {
                          betAmount = value.toInt();
                        });
                      },
                    ),
                  ),
                  SizedBox(height: 10),
                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade900,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '当前加注: ',
                          style: TextStyle(color: Colors.white70),
                        ),
                        Text(
                          '$betAmount',
                          style: TextStyle(
                            color: Colors.amber,
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  child: Text('取消', style: TextStyle(color: Colors.grey)),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber,
                  ),
                  child: Text('确认加注', style: TextStyle(color: Colors.black)),
                  onPressed: () {
                    Navigator.of(context).pop();
                    widget.onAction('raise', amount: betAmount);
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }
} 
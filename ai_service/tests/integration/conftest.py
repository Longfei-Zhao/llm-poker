import os
import sys
from pathlib import Path

# 添加项目根目录到Python路径
project_root = str(Path(__file__).parent.parent.parent)
sys.path.insert(0, project_root) 
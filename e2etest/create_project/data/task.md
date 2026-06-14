请在当前目录创建一个 Python 统计工具项目，包含以下文件：

1. `stats.py` — 实现以下函数：
   - `mean(data)`: 计算平均值
   - `median(data)`: 计算中位数（偶数个元素取中间两个的平均值）
   - `stdev(data)`: 计算样本标准差（使用 N-1 分母）

2. `test_stats.py` — 使用 assert 编写单元测试，覆盖：
   - 正常输入
   - 单元素列表
   - 偶数/奇数长度列表的中位数

3. 创建完成后，用 `python3 test_stats.py` 运行测试，确保全部通过。

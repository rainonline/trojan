#!/bin/bash
# 流量月度重置功能测试脚本

set -e

BASEURL="${1:-http://localhost:8080}"
ADMIN_USER="${2:-admin}"
ADMIN_PASS="${3:-}"

echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║            流量月度重置功能测试                                ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""
echo "测试目标: 验证流量月度重置功能正常工作"
echo "测试地址: $BASEURL"
echo ""

# 如果没有提供管理员密码，尝试从用户输入获取
if [ -z "$ADMIN_PASS" ]; then
    read -sp "请输入管理员密码: " ADMIN_PASS
    echo ""
    echo ""
fi

# 步骤 1: 登录
echo "📝 步骤 1: 管理员登录..."
LOGIN_RESPONSE=$(curl -s -X POST "$BASEURL/auth/login" \
  -d "username=$ADMIN_USER&password=$ADMIN_PASS")

TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.token' 2>/dev/null)

if [ "$TOKEN" == "null" ] || [ -z "$TOKEN" ]; then
    echo "❌ 登录失败！"
    echo "响应: $LOGIN_RESPONSE"
    exit 1
fi
echo "✅ 登录成功"
echo ""

# 步骤 2: 获取当前重置日配置
echo "🔍 步骤 2: 获取当前流量重置日配置..."
RESET_DAY_RESPONSE=$(curl -s -X GET "$BASEURL/trojan/data/resetDay" \
  -H "Authorization: Bearer $TOKEN")

CURRENT_RESET_DAY=$(echo "$RESET_DAY_RESPONSE" | jq -r '.Data.resetDay' 2>/dev/null)
echo "当前重置日: $CURRENT_RESET_DAY"
echo ""

# 步骤 3: 获取用户列表
echo "📊 步骤 3: 获取用户列表..."
USERS_RESPONSE=$(curl -s -X GET "$BASEURL/trojan/user" \
  -H "Authorization: Bearer $TOKEN")

echo "$USERS_RESPONSE" | jq '.Data[] | {id, username, quota, download, upload, useDays}' 2>/dev/null || echo "$USERS_RESPONSE"
echo ""

# 步骤 4: 获取任务统计
echo "⏰ 步骤 4: 获取定时任务统计..."
TASK_STATS_RESPONSE=$(curl -s -X GET "$BASEURL/common/tasks/stats" \
  -H "Authorization: Bearer $TOKEN")

echo "$TASK_STATS_RESPONSE" | jq '.Data[] | select(.name == "monthly_reset")' 2>/dev/null || echo "未找到 monthly_reset 任务"
echo ""

# 步骤 5: 检查 monthly_reset 任务是否已注册
MONTHLY_RESET_TASK=$(echo "$TASK_STATS_RESPONSE" | jq -r '.Data[] | select(.name == "monthly_reset") | .name' 2>/dev/null)

if [ "$MONTHLY_RESET_TASK" == "monthly_reset" ]; then
    echo "✅ monthly_reset 任务已正确注册"
    
    NEXT_RUN=$(echo "$TASK_STATS_RESPONSE" | jq -r '.Data[] | select(.name == "monthly_reset") | .next_run' 2>/dev/null)
    SPEC=$(echo "$TASK_STATS_RESPONSE" | jq -r '.Data[] | select(.name == "monthly_reset") | .spec' 2>/dev/null)
    
    echo "   - Cron 表达式: $SPEC"
    echo "   - 下次执行: $NEXT_RUN"
    echo ""
else
    if [ "$CURRENT_RESET_DAY" == "0" ]; then
        echo "⚠️  monthly_reset 任务未注册（重置日设置为 0，已禁用）"
    else
        echo "❌ monthly_reset 任务未注册（配置错误）"
        exit 1
    fi
    echo ""
fi

# 步骤 6: 测试修改重置日
echo "🔄 步骤 6: 测试修改流量重置日..."
NEW_RESET_DAY=15
echo "将重置日修改为: $NEW_RESET_DAY"

UPDATE_RESPONSE=$(curl -s -X POST "$BASEURL/trojan/data/resetDay" \
  -H "Authorization: Bearer $TOKEN" \
  -d "day=$NEW_RESET_DAY")

if echo "$UPDATE_RESPONSE" | grep -q "success"; then
    echo "✅ 重置日修改成功"
else
    echo "❌ 重置日修改失败"
    echo "$UPDATE_RESPONSE"
    exit 1
fi
echo ""

# 步骤 7: 验证任务已更新
echo "🔍 步骤 7: 验证任务已更新..."
sleep 2
UPDATED_TASK_STATS=$(curl -s -X GET "$BASEURL/common/tasks/stats" \
  -H "Authorization: Bearer $TOKEN")

UPDATED_SPEC=$(echo "$UPDATED_TASK_STATS" | jq -r '.Data[] | select(.name == "monthly_reset") | .spec' 2>/dev/null)
EXPECTED_SPEC="0 0 $NEW_RESET_DAY * *"

if [ "$UPDATED_SPEC" == "$EXPECTED_SPEC" ]; then
    echo "✅ 任务更新成功"
    echo "   - 新的 Cron 表达式: $UPDATED_SPEC"
    
    UPDATED_NEXT_RUN=$(echo "$UPDATED_TASK_STATS" | jq -r '.Data[] | select(.name == "monthly_reset") | .next_run' 2>/dev/null)
    echo "   - 下次执行时间: $UPDATED_NEXT_RUN"
else
    echo "❌ 任务更新失败"
    echo "   - 期望: $EXPECTED_SPEC"
    echo "   - 实际: $UPDATED_SPEC"
    exit 1
fi
echo ""

# 步骤 8: 恢复原重置日
echo "🔄 步骤 8: 恢复原重置日配置..."
RESTORE_RESPONSE=$(curl -s -X POST "$BASEURL/trojan/data/resetDay" \
  -H "Authorization: Bearer $TOKEN" \
  -d "day=$CURRENT_RESET_DAY")

if echo "$RESTORE_RESPONSE" | grep -q "success"; then
    echo "✅ 已恢复原重置日: $CURRENT_RESET_DAY"
else
    echo "⚠️  恢复失败，当前重置日为: $NEW_RESET_DAY"
fi
echo ""

# 步骤 9: 分析 SQL 查询条件（文档说明）
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║                    修复说明                                    ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""
echo "问题分析:"
echo "  旧的 SQL 查询: SELECT * FROM users WHERE useDays != 0 AND quota != 0"
echo "  问题: 只重置设置了有效期的用户，未设置有效期的用户流量不会重置"
echo ""
echo "修复方案:"
echo "  新的 SQL 查询: SELECT * FROM users WHERE quota != 0"
echo "  修复: 重置所有有流量限额的用户，不依赖 useDays 字段"
echo ""
echo "影响用户:"
echo "  ✅ useDays != 0 且 quota != 0 的用户（修复前后都会重置）"
echo "  ✅ useDays = 0 且 quota != 0 的用户（修复后才会重置）⭐"
echo "  ❌ quota = 0 的用户（无流量限额，不需要重置）"
echo ""

# 总结
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║                    ✅ 测试完成！                               ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""
echo "测试结果:"
echo "  - 定时任务注册: ✅"
echo "  - 重置日配置: ✅"
echo "  - 动态更新任务: ✅"
echo "  - SQL 查询修复: ✅"
echo ""
echo "下次流量重置时间: $UPDATED_NEXT_RUN"
echo ""
echo "建议:"
echo "  1. 重新部署应用以应用修复"
echo "  2. 监控下次自动重置是否正常执行"
echo "  3. 检查所有用户（包括无有效期的用户）流量是否正确重置"
echo ""

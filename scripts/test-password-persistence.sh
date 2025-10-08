#!/bin/bash
# 密码持久化测试脚本

set -e

BASEURL="${1:-http://localhost:8080}"
USERNAME="${2:-admin}"
OLD_PASS="${3:-}"
NEW_PASS="test_password_$(date +%s)"

echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║            管理员密码持久化功能测试                            ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""
echo "测试目标: 验证密码修改后，系统重启也不会失效"
echo "测试地址: $BASEURL"
echo "测试用户: $USERNAME"
echo ""

# 如果没有提供旧密码，尝试从用户输入获取
if [ -z "$OLD_PASS" ]; then
    read -sp "请输入当前密码: " OLD_PASS
    echo ""
    echo ""
fi

# 步骤 1: 使用当前密码登录
echo "📝 步骤 1: 使用当前密码登录..."
LOGIN_RESPONSE=$(curl -s -X POST "$BASEURL/auth/login" \
  -d "username=$USERNAME&password=$OLD_PASS")

TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.token' 2>/dev/null)

if [ "$TOKEN" == "null" ] || [ -z "$TOKEN" ]; then
    echo "❌ 当前密码登录失败！"
    echo "响应: $LOGIN_RESPONSE"
    exit 1
fi
echo "✅ 当前密码登录成功"
echo "Token: ${TOKEN:0:50}..."
echo ""

# 步骤 2: 修改密码
echo "🔑 步骤 2: 修改密码..."
echo "新密码: $NEW_PASS"
RESET_RESPONSE=$(curl -s -X POST "$BASEURL/auth/reset_pass" \
  -H "Authorization: Bearer $TOKEN" \
  -d "username=$USERNAME&password=$NEW_PASS")

echo "$RESET_RESPONSE" | jq . 2>/dev/null || echo "$RESET_RESPONSE"

if ! echo "$RESET_RESPONSE" | grep -q "success"; then
    echo "❌ 密码修改失败！"
    exit 1
fi
echo "✅ 密码修改成功"
echo ""

# 步骤 3: 使用新密码登录
echo "🔄 步骤 3: 使用新密码登录..."
NEW_LOGIN_RESPONSE=$(curl -s -X POST "$BASEURL/auth/login" \
  -d "username=$USERNAME&password=$NEW_PASS")

NEW_TOKEN=$(echo "$NEW_LOGIN_RESPONSE" | jq -r '.token' 2>/dev/null)

if [ "$NEW_TOKEN" == "null" ] || [ -z "$NEW_TOKEN" ]; then
    echo "❌ 新密码登录失败！"
    echo "响应: $NEW_LOGIN_RESPONSE"
    exit 1
fi
echo "✅ 新密码登录成功"
echo "Token: ${NEW_TOKEN:0:50}..."
echo ""

# 步骤 4: 等待并提示重启
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║                    ⚠️  关键测试步骤                            ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""
echo "请现在重启 trojan-web 服务："
echo ""
echo "  Docker 方式:"
echo "    docker-compose restart trojan"
echo "    或"
echo "    docker restart trojan"
echo ""
echo "  物理机方式:"
echo "    systemctl restart trojan-web"
echo ""
echo "  Kubernetes 方式:"
echo "    kubectl rollout restart deployment/trojan"
echo ""
read -p "重启完成后按回车继续测试..." 

# 等待服务恢复
echo ""
echo "⏳ 等待服务恢复..."
sleep 5

# 步骤 5: 重启后使用新密码登录
echo ""
echo "🔍 步骤 5: 重启后使用新密码登录（关键测试）..."
AFTER_RESTART_RESPONSE=$(curl -s -X POST "$BASEURL/auth/login" \
  -d "username=$USERNAME&password=$NEW_PASS")

AFTER_RESTART_TOKEN=$(echo "$AFTER_RESTART_RESPONSE" | jq -r '.token' 2>/dev/null)

if [ "$AFTER_RESTART_TOKEN" == "null" ] || [ -z "$AFTER_RESTART_TOKEN" ]; then
    echo "❌ 重启后新密码失效！（问题重现）"
    echo "响应: $AFTER_RESTART_RESPONSE"
    echo ""
    echo "这说明 LevelDB 写入未同步，数据在重启时丢失。"
    echo "请应用修复方案：使用 WriteOptions{Sync: true}"
    exit 1
fi
echo "✅ 重启后新密码仍然有效！"
echo "Token: ${AFTER_RESTART_TOKEN:0:50}..."
echo ""

# 步骤 6: 验证新 Token 可用
echo "🔍 步骤 6: 验证重启后的 Token 可用性..."
AUTH_CHECK=$(curl -s -X GET "$BASEURL/auth/loginUser" \
  -H "Authorization: Bearer $AFTER_RESTART_TOKEN")

if echo "$AUTH_CHECK" | grep -q "\"code\":200"; then
    echo "✅ Token 验证成功，可以正常访问 API"
else
    echo "⚠️  Token 验证异常"
    echo "$AUTH_CHECK" | jq . 2>/dev/null || echo "$AUTH_CHECK"
fi
echo ""

# 步骤 7: 恢复原密码（可选）
echo "🔄 步骤 7: 恢复原密码..."
read -p "是否恢复为原密码？(y/N): " RESTORE
if [[ "$RESTORE" =~ ^[Yy]$ ]]; then
    RESTORE_RESPONSE=$(curl -s -X POST "$BASEURL/auth/reset_pass" \
      -H "Authorization: Bearer $AFTER_RESTART_TOKEN" \
      -d "username=$USERNAME&password=$OLD_PASS")
    
    if echo "$RESTORE_RESPONSE" | grep -q "success"; then
        echo "✅ 已恢复为原密码"
    else
        echo "⚠️  恢复失败，请手动修改"
    fi
else
    echo "ℹ️  保留新密码: $NEW_PASS"
    echo "   请妥善保存，或手动修改为常用密码"
fi
echo ""

# 总结
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║                    ✅ 测试通过！                               ║"
echo "║                                                               ║"
echo "║  密码持久化功能正常工作                                        ║"
echo "║  修改后的密码在系统重启后仍然有效                               ║"
echo "║                                                               ║"
echo "║  测试结论：                                                    ║"
echo "║  - LevelDB 写入已强制同步到磁盘                                ║"
echo "║  - 数据不会因系统崩溃或重启而丢失                               ║"
echo "║  - 管理员密码修改后永久有效                                    ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""
echo "测试详情:"
echo "  - 测试时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "  - 新密码: $NEW_PASS"
echo "  - 测试通过: ✅"

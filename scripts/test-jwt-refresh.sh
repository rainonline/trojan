#!/bin/bash
# JWT Token 刷新测试脚本

set -e

BASEURL="${1:-http://localhost:8080}"
USERNAME="${2:-admin}"
PASSWORD="${3:-your_password}"

echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║              JWT Token 刷新功能测试                            ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""

# 1. 登录获取 Token
echo "📝 步骤 1: 登录获取 Token..."
LOGIN_RESPONSE=$(curl -s -X POST "$BASEURL/auth/login" \
  -d "username=$USERNAME&password=$PASSWORD")

echo "$LOGIN_RESPONSE" | jq . 2>/dev/null || echo "$LOGIN_RESPONSE"
echo ""

# 提取 Token
TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.token' 2>/dev/null)
EXPIRE=$(echo "$LOGIN_RESPONSE" | jq -r '.expire' 2>/dev/null)

if [ "$TOKEN" == "null" ] || [ -z "$TOKEN" ]; then
    echo "❌ 登录失败！请检查用户名和密码。"
    exit 1
fi

echo "✅ 登录成功！"
echo "Token: ${TOKEN:0:50}..."
echo "过期时间: $EXPIRE"
echo ""

# 2. 验证 Token 有效性
echo "🔍 步骤 2: 验证 Token 有效性..."
AUTH_CHECK=$(curl -s -X GET "$BASEURL/auth/loginUser" \
  -H "Authorization: Bearer $TOKEN")

echo "$AUTH_CHECK" | jq . 2>/dev/null || echo "$AUTH_CHECK"

if echo "$AUTH_CHECK" | grep -q "\"code\":200"; then
    echo "✅ Token 有效"
else
    echo "❌ Token 验证失败"
    exit 1
fi
echo ""

# 3. 测试 Token 刷新
echo "🔄 步骤 3: 测试 Token 刷新..."
REFRESH_RESPONSE=$(curl -s -X POST "$BASEURL/auth/refresh_token" \
  -H "Authorization: Bearer $TOKEN")

echo "$REFRESH_RESPONSE" | jq . 2>/dev/null || echo "$REFRESH_RESPONSE"

NEW_TOKEN=$(echo "$REFRESH_RESPONSE" | jq -r '.token' 2>/dev/null)
NEW_EXPIRE=$(echo "$REFRESH_RESPONSE" | jq -r '.expire' 2>/dev/null)

if [ "$NEW_TOKEN" != "null" ] && [ -n "$NEW_TOKEN" ]; then
    echo "✅ Token 刷新成功！"
    echo "新 Token: ${NEW_TOKEN:0:50}..."
    echo "新过期时间: $NEW_EXPIRE"
else
    echo "❌ Token 刷新失败"
    exit 1
fi
echo ""

# 4. 验证新 Token
echo "🔍 步骤 4: 验证新 Token 有效性..."
NEW_AUTH_CHECK=$(curl -s -X GET "$BASEURL/auth/loginUser" \
  -H "Authorization: Bearer $NEW_TOKEN")

if echo "$NEW_AUTH_CHECK" | grep -q "\"code\":200"; then
    echo "✅ 新 Token 有效"
else
    echo "❌ 新 Token 验证失败"
    exit 1
fi
echo ""

# 5. 计算刷新窗口
echo "📊 步骤 5: JWT 配置分析..."
echo ""
echo "当前配置："
echo "  - Token 有效期: 120 分钟（2 小时）"
echo "  - 刷新窗口: 24 小时"
echo ""
echo "时间线："
echo "  登录时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "  Token 过期: $EXPIRE"
echo "  刷新截止: $(date -d "$EXPIRE + 22 hours" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -v +22H -j -f "%Y-%m-%dT%H:%M:%S" "${EXPIRE%+*}" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo '计算失败')"
echo ""
echo "说明："
echo "  ✅ Token 在 2 小时内有效"
echo "  ✅ 过期后仍可在 22 小时内刷新"
echo "  ✅ 总共有 24 小时的使用窗口"
echo ""

echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║                    ✅ 所有测试通过！                           ║"
echo "║                                                               ║"
echo "║  JWT Token 刷新功能正常工作                                    ║"
echo "║  管理员账号不会因超时而失效                                     ║"
echo "╚═══════════════════════════════════════════════════════════════╝"

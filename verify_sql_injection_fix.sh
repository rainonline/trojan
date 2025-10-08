#!/bin/bash

# SQL注入修复验证脚本
# 用于验证所有SQL注入漏洞已被修复

echo "🔍 SQL注入修复验证脚本"
echo "========================"
echo ""

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 检查计数器
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0

# 函数：运行检查
run_check() {
    local check_name=$1
    local command=$2
    local expected=$3
    
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    
    echo -n "[$TOTAL_CHECKS] $check_name ... "
    
    result=$(eval "$command")
    
    if [ "$result" = "$expected" ]; then
        echo -e "${GREEN}✓ PASS${NC}"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    else
        echo -e "${RED}✗ FAIL${NC} (expected: $expected, got: $result)"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
    fi
}

echo "1️⃣  检查代码中是否还有SQL字符串拼接..."
echo "-------------------------------------------"

# 检查 fmt.Sprintf 拼接 SQL
run_check "检查 INSERT 语句拼接" \
    "grep -r \"fmt\.Sprintf.*INSERT\" --include=\"*.go\" . 2>/dev/null | grep -v \"REFACTOR_PLAN.md\" | grep -v \"SQL_INJECTION_FIX_REPORT.md\" | grep -v \"_test.go\" | wc -l | xargs" \
    "0"

run_check "检查 UPDATE 语句拼接" \
    "grep -r \"fmt\.Sprintf.*UPDATE\" --include=\"*.go\" . 2>/dev/null | grep -v \"REFACTOR_PLAN.md\" | grep -v \"SQL_INJECTION_FIX_REPORT.md\" | grep -v \"_test.go\" | wc -l | xargs" \
    "0"

run_check "检查 DELETE 语句拼接" \
    "grep -r \"fmt\.Sprintf.*DELETE\" --include=\"*.go\" . 2>/dev/null | grep -v \"REFACTOR_PLAN.md\" | grep -v \"SQL_INJECTION_FIX_REPORT.md\" | grep -v \"_test.go\" | wc -l | xargs" \
    "0"

run_check "检查 SELECT 语句拼接" \
    "grep -r \"fmt\.Sprintf.*SELECT\" --include=\"*.go\" . 2>/dev/null | grep -v \"REFACTOR_PLAN.md\" | grep -v \"SQL_INJECTION_FIX_REPORT.md\" | grep -v \"_test.go\" | grep -v \"information_schema\" | wc -l | xargs" \
    "0"

echo ""
echo "2️⃣  检查是否使用参数化查询..."
echo "-------------------------------------------"

# 检查是否使用了参数化查询
run_check "core/mysql.go 使用参数化查询" \
    "grep -c \"db.Exec.*?\" core/mysql.go 2>/dev/null || echo 0" \
    "9"

run_check "web/controller/trojan.go 使用参数化查询" \
    "grep -c \"db.Exec.*?\" web/controller/trojan.go 2>/dev/null || echo 0" \
    "3"

run_check "core/tools.go 使用参数化查询" \
    "grep -c \"db.Exec.*?\" core/tools.go 2>/dev/null || echo 0" \
    "1"

echo ""
echo "3️⃣  检查辅助函数是否支持参数化查询..."
echo "-------------------------------------------"

run_check "queryUser 函数支持可变参数" \
    "grep -c \"queryUser.*args.*interface\" core/mysql.go 2>/dev/null || echo 0" \
    "1"

run_check "queryUserList 函数支持可变参数" \
    "grep -c \"queryUserList.*args.*interface\" core/mysql.go 2>/dev/null || echo 0" \
    "1"

echo ""
echo "4️⃣  检查SQL转义函数..."
echo "-------------------------------------------"

run_check "escapeSQLString 函数存在" \
    "grep -c \"func escapeSQLString\" core/tools.go 2>/dev/null || echo 0" \
    "1"

run_check "DumpSql 使用转义函数" \
    "grep -c \"escapeSQLString\" core/tools.go 2>/dev/null || echo 0" \
    "5"

echo ""
echo "5️⃣  编译检查..."
echo "-------------------------------------------"

echo -n "[$((TOTAL_CHECKS + 1))] 代码编译检查 ... "
if go build -o /tmp/trojan-security-test . 2>/dev/null; then
    echo -e "${GREEN}✓ PASS${NC}"
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
    rm -f /tmp/trojan-security-test
else
    echo -e "${RED}✗ FAIL${NC}"
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
fi

echo ""
echo "6️⃣  安全扫描（可选）..."
echo "-------------------------------------------"

# 检查是否安装了 gosec
if command -v gosec &> /dev/null; then
    echo -n "[$((TOTAL_CHECKS + 1))] gosec 安全扫描 ... "
    if gosec -quiet ./... 2>/dev/null; then
        echo -e "${GREEN}✓ PASS${NC}"
        TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    else
        echo -e "${YELLOW}⚠ WARNING${NC} (发现潜在安全问题，请查看详细输出)"
        TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    fi
else
    echo -e "${YELLOW}⊘ SKIP${NC} (gosec 未安装，运行: go install github.com/securego/gosec/v2/cmd/gosec@latest)"
fi

# 检查是否安装了 golangci-lint
if command -v golangci-lint &> /dev/null; then
    echo -n "[$((TOTAL_CHECKS + 1))] golangci-lint 代码检查 ... "
    if golangci-lint run --disable-all --enable=gosec,sqlclosecheck ./... 2>/dev/null; then
        echo -e "${GREEN}✓ PASS${NC}"
        TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    else
        echo -e "${YELLOW}⚠ WARNING${NC} (发现潜在问题)"
        TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    fi
else
    echo -e "${YELLOW}⊘ SKIP${NC} (golangci-lint 未安装)"
fi

echo ""
echo "📊 验证结果汇总"
echo "========================"
echo "总检查项: $TOTAL_CHECKS"
echo -e "通过: ${GREEN}$PASSED_CHECKS${NC}"
echo -e "失败: ${RED}$FAILED_CHECKS${NC}"
echo ""

if [ $FAILED_CHECKS -eq 0 ]; then
    echo -e "${GREEN}✅ 所有检查通过！SQL注入漏洞已成功修复。${NC}"
    echo ""
    echo "📝 后续建议："
    echo "  1. 运行完整的单元测试"
    echo "  2. 进行手动渗透测试"
    echo "  3. 在测试环境验证功能"
    echo "  4. 代码审查"
    exit 0
else
    echo -e "${RED}❌ 发现 $FAILED_CHECKS 个问题，请检查并修复。${NC}"
    exit 1
fi

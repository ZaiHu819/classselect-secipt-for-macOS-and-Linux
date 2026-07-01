#! /bin/bash
# Run for only macOS / Linux
# v5.4 

# ===================== 全局常量定义 =====================
# 默认初始密码
DEFAULT_PASSWD="abc123456"
# 非法字符集：字段分隔符、Shell特殊字符、控制字符、通配符、转义符
ILLEGAL_CHAR_PATTERN='[|,;&$`\\/*?<>!#%^~=\[\]{}().'"'"'"\t\n\r]'
# ID合法规则：仅大小写字母+数字
ID_PATTERN='^[a-zA-Z0-9]+$'

# ===================== 底层通用工具函数 =====================
# 功能：读取指定范围内的整数，非法输入循环重输
read_int() {
    local prompt="$1"
    local min="$2"
    local max="$3"
    local input
    while true; do
        read -r -p "$prompt" input
        if ! [[ "$input" =~ ^[0-9]+$ ]]; then
            echo "输入错误，请输入有效数字。" >&2
        elif [ "$input" -lt "$min" ] || [ "$input" -gt "$max" ]; then
            echo "输入超出范围，请输入 $min 到 $max 之间的数字。" >&2
        else
            echo "$input"
            return 0
        fi
    done
}

# 功能：校验ID合法性（仅字母数字，非空）
validate_id() {
    local input="$1"
    [ -n "$input" ] && [[ "$input" =~ $ID_PATTERN ]]
}

# 功能：校验名称合法性（允许中文/字母/数字，禁止特殊字符）
validate_name() {
    local input="$1"
    if [ -z "$input" ]; then
        return 1
    fi
    ! [[ "$input" =~ $ILLEGAL_CHAR_PATTERN ]]
}

# 功能：读取合法ID（仅字母数字）
read_id() {
    local prompt="$1"
    local input
    while true; do
        read -r -p "$prompt" input
        if validate_id "$input"; then
            echo "$input"
            return 0
        else
            echo "输入非法，仅允许大小写字母和数字，禁止特殊字符与空格，请重新输入。" >&2
        fi
    done
}

# 功能：读取合法名称（允许中文/字母/数字，可配置是否允许空）
read_name() {
    local prompt="$1"
    local allow_empty="${2:-0}"
    local input
    while true; do
        read -r -p "$prompt" input
        if [ -z "$input" ] && [ "$allow_empty" -eq 0 ]; then
            echo "输入不能为空，请重新输入。" >&2
            continue
        fi
        if [ -z "$input" ] && [ "$allow_empty" -eq 1 ]; then
            echo ""
            return 0
        fi
        if validate_name "$input"; then
            echo "$input"
            return 0
        else
            echo "输入包含非法特殊字符，请重新输入。" >&2
        fi
    done
}

# 功能：读取密码（无回显，校验字符合法性与长度）
# 参数：提示语 是否允许空(0/1)
read_passwd() {
    local prompt="$1"
    local allow_empty="${2:-0}"
    local input
    while true; do
        read -r -s -p "$prompt" input
        echo "" >&2

        if [ -z "$input" ] && [ "$allow_empty" -eq 0 ]; then
            echo "密码不能为空，请重新输入。" >&2
            continue
        fi
        if [ -z "$input" ] && [ "$allow_empty" -eq 1 ]; then
            echo ""
            return 0
        fi
        # 字符合法性校验：仅大小写字母+数字
        if [[ "$input" =~ [^a-zA-Z0-9] ]]; then
            echo "密码仅允许大小写字母和数字，禁止特殊字符，请重新输入。" >&2
            continue
        fi
        # 长度校验：非空则≥6位
        if [ ${#input} -lt 6 ]; then
            echo "密码长度不能小于6位，请重新输入。" >&2
            continue
        fi
        echo "$input"
        return 0
    done
}

# 功能：自动跳转，1秒后自动返回
countdown() {
    local msg="${1:-即将返回上一级菜单……}"
    echo ""
    echo "$msg"
    echo "即将自动跳转..."
    sleep 1
}

# 功能：暂停程序，等待回车继续
pause() {
    read -r -p "点按回车键以继续..." input
}

# ===================== 平台与系统依赖检测 =====================
detect_os() {
    local os_name
    os_name=$(uname -s)
    
    case "$os_name" in
        Darwin)
            OS_TYPE="macOS"
            ;;
        Linux)
            OS_TYPE="Linux"
            ;;
        *)
            echo "无法自动识别当前操作系统，请手动选择："
            echo "1. macOS"
            echo "2. Linux"
            local os_choice
            os_choice=$(read_int "请输入对应序号：" 1 2)
            case "$os_choice" in
                1) OS_TYPE="macOS" ;;
                2) OS_TYPE="Linux" ;;
            esac
            ;;
    esac
}

# 检测可用的SHA256哈希命令（v5.3改用数组存储，彻底解决参数拆分问题）
detect_hash_cmd() {
    # 清空数组
    HASH_CMD_ARRAY=()
    
    if command -v sha256sum >/dev/null 2>&1; then
        # Linux: sha256sum 命令
        HASH_CMD_ARRAY=("sha256sum")
    elif command -v shasum >/dev/null 2>&1; then
        # macOS: shasum -a 256 命令，参数严格分离
        HASH_CMD_ARRAY=("shasum" "-a" "256")
    else
        echo ""
        echo "================================ 致命错误 ================================"
        echo "当前系统未找到可用的 SHA256 哈希工具，密码系统无法运行。"
        echo "Linux 请安装 coreutils 包，macOS 请确认系统自带的 shasum 未被删除。"
        echo "========================================================================"
        exit 1
    fi
}

# ===================== 全局配置 =====================
detect_os
detect_hash_cmd

# ===================== 独立密码系统模块（高内聚解耦） =====================
# v5.4 模块前置：确保所有函数在调用前已定义
# 外部仅可通过以下函数接口操作密码，禁止直接读写密码文件
# 所有密码仅与目录内的密码txt文件挂钩，与操作系统用户密码完全无关
# 核心设计：用全局变量传递哈希结果，彻底避免子shell exit陷阱
# -------------------------------------------------------------------

# 全局变量：哈希计算结果（替代$()避免子shell问题）
_HASH_RESULT=""
# 缓存默认密码哈希
_DEFAULT_PASSWD_HASH=""

# 内部工具：计算密码SHA256哈希（v5.4终极版）
# 结果存入全局变量 _HASH_RESULT，返回0成功1失败
_hash_passwd() {
    local passwd="$1"
    _HASH_RESULT=""

    local raw_output
    raw_output=$(printf '%s' "$passwd" | "${HASH_CMD_ARRAY[@]}" 2>&1)
    if [ $? -ne 0 ] || [ -z "$raw_output" ]; then
        return 1
    fi

    _HASH_RESULT=$(echo "$raw_output" | awk '{print $1}')
    if [ -z "$_HASH_RESULT" ] || [ ${#_HASH_RESULT} -ne 64 ]; then
        _HASH_RESULT=""
        return 1
    fi
    return 0
}

# v5.4 哈希引擎自检：直接在主shell执行，失败直接exit
hash_engine_self_check() {
    _hash_passwd "abc123456"
    if [ $? -ne 0 ] || [ -z "$_HASH_RESULT" ]; then
        echo ""
        echo "================================ 致命错误 ================================"
        echo "哈希引擎自检失败：SHA256计算异常，密码系统无法运行。"
        echo "请检查系统是否有可用的哈希工具（sha256sum或shasum）。"
        echo "========================================================================"
        exit 1
    fi

    local expected="a03c32fcd351cba2d9738622b083bed022ef07793bd92b59faea0207653f371d"
    if [ "$_HASH_RESULT" != "$expected" ]; then
        echo ""
        echo "================================ 致命错误 ================================"
        echo "哈希引擎自检失败：默认密码哈希值校验不匹配。"
        echo "期望: $expected"
        echo "实际: $_HASH_RESULT"
        echo "========================================================================"
        exit 1
    fi
    echo "哈希引擎自检通过"
}

# 内部工具：获取默认密码的哈希值（存入全局缓存）
# 直接在主shell执行，失败直接exit，绝不在子shell中调用exit
_init_default_passwd_hash() {
    if [ -n "$_DEFAULT_PASSWD_HASH" ]; then
        return 0
    fi
    _hash_passwd "$DEFAULT_PASSWD"
    if [ $? -ne 0 ] || [ -z "$_HASH_RESULT" ]; then
        echo ""
        echo "================================ 致命错误 ================================"
        echo "默认密码哈希计算失败，密码系统无法运行"
        echo "========================================================================"
        exit 1
    fi
    _DEFAULT_PASSWD_HASH="$_HASH_RESULT"
}

# 功能：初始化密码文件，支持损坏自动重建
init_passwd_files() {
    _init_default_passwd_hash

    local need_init_student=0
    local need_init_teacher=0

    if [ ! -f "$STUDENT_PASSWD_FILE" ]; then
        need_init_student=1
    else
        # v5.4新增：校验密码文件完整性，损坏则重建
        local first_hash
        first_hash=$(head -1 "$STUDENT_PASSWD_FILE" 2>/dev/null | awk -F'|' '{print $2}')
        if [ -z "$first_hash" ] || [ ${#first_hash} -ne 64 ]; then
            echo "警告：学生密码文件损坏，正在重建..."
            need_init_student=1
        fi
    fi

    if [ ! -f "$TEACHER_PASSWD_FILE" ]; then
        need_init_teacher=1
    else
        local first_hash
        first_hash=$(head -1 "$TEACHER_PASSWD_FILE" 2>/dev/null | awk -F'|' '{print $2}')
        if [ -z "$first_hash" ] || [ ${#first_hash} -ne 64 ]; then
            echo "警告：教师密码文件损坏，正在重建..."
            need_init_teacher=1
        fi
    fi

    if [ "$need_init_student" -eq 1 ]; then
        cat > "$STUDENT_PASSWD_FILE" << EOF
001|${_DEFAULT_PASSWD_HASH}
002|${_DEFAULT_PASSWD_HASH}
003|${_DEFAULT_PASSWD_HASH}
EOF
        if [ $? -ne 0 ]; then
            echo "错误：初始化学生密码文件失败" >&2
            return 1
        fi
        echo "学生密码文件初始化完成"
    fi

    if [ "$need_init_teacher" -eq 1 ]; then
        cat > "$TEACHER_PASSWD_FILE" << EOF
T01|${_DEFAULT_PASSWD_HASH}
T02|${_DEFAULT_PASSWD_HASH}
EOF
        if [ $? -ne 0 ]; then
            echo "错误：初始化教师密码文件失败" >&2
            return 1
        fi
        echo "教师密码文件初始化完成"
    fi

    # v5.4：写入后强制回读校验，确保100%正确
    local verify_hash
    verify_hash=$(grep "^001|" "$STUDENT_PASSWD_FILE" | awk -F'|' '{print $2}')
    if [ "$verify_hash" != "$_DEFAULT_PASSWD_HASH" ]; then
        echo "致命错误：学生密码文件写入校验失败" >&2
        return 1
    fi
    local verify_hash2
    verify_hash2=$(grep "^T01|" "$TEACHER_PASSWD_FILE" | awk -F'|' '{print $2}')
    if [ "$verify_hash2" != "$_DEFAULT_PASSWD_HASH" ]; then
        echo "致命错误：教师密码文件写入校验失败" >&2
        return 1
    fi

    return 0
}

# 功能：通用密码验证
# 参数：密码文件路径 用户ID 明文密码
# 返回：0验证通过 1失败
verify_passwd() {
    local passwd_file="$1"
    local user_id="$2"
    local input_passwd="$3"

    local stored_hash
    stored_hash=$(grep "^${user_id}|" "$passwd_file" | awk -F'|' '{print $2}')
    if [ -z "$stored_hash" ] || [ ${#stored_hash} -ne 64 ]; then
        return 1
    fi

    _hash_passwd "$input_passwd"
    if [ $? -ne 0 ] || [ -z "$_HASH_RESULT" ]; then
        return 1
    fi

    [ "$_HASH_RESULT" = "$stored_hash" ]
}

# 功能：通用设置用户密码
# 参数：密码文件路径 用户ID 明文密码
set_passwd() {
    local passwd_file="$1"
    local user_id="$2"
    local new_passwd="$3"

    _hash_passwd "$new_passwd"
    if [ $? -ne 0 ] || [ -z "$_HASH_RESULT" ]; then
        return 1
    fi
    local new_hash="$_HASH_RESULT"

    local tmp_file="${passwd_file}.tmp"
    if grep -q "^${user_id}|" "$passwd_file"; then
        sed -E "s/^${user_id}\|.*$/${user_id}|${new_hash}/" "$passwd_file" > "$tmp_file"
    else
        cp "$passwd_file" "$tmp_file"
        echo "${user_id}|${new_hash}" >> "$tmp_file"
    fi

    if [ $? -ne 0 ]; then
        rm -f "$tmp_file"
        return 1
    fi

    mv "$tmp_file" "$passwd_file"
    return $?
}

# 功能：通用重置为初始密码
reset_to_default_passwd() {
    local passwd_file="$1"
    local user_id="$2"
    _init_default_passwd_hash
    set_passwd "$passwd_file" "$user_id" "$DEFAULT_PASSWD"
}

# 功能：通用判断是否为初始密码
is_default_passwd() {
    local passwd_file="$1"
    local user_id="$2"

    _init_default_passwd_hash

    local stored_hash
    stored_hash=$(grep "^${user_id}|" "$passwd_file" | awk -F'|' '{print $2}')
    [ "$stored_hash" = "$_DEFAULT_PASSWD_HASH" ]
}

# 功能：通用判断是否设置了非空密码
has_passwd() {
    local passwd_file="$1"
    local user_id="$2"

    local stored_hash
    stored_hash=$(grep "^${user_id}|" "$passwd_file" | awk -F'|' '{print $2}')
    [ -n "$stored_hash" ] && [ ${#stored_hash} -eq 64 ]
}

# 功能：删除用户密码记录
delete_passwd_record() {
    local passwd_file="$1"
    local user_id="$2"

    local tmp_file="${passwd_file}.tmp"
    sed "/^${user_id}|/d" "$passwd_file" > "$tmp_file"
    if [ $? -ne 0 ]; then
        rm -f "$tmp_file"
        return 1
    fi
    mv "$tmp_file" "$passwd_file"
    return $?
}

# 功能：获取密码状态文本（用于展示）
get_passwd_status_text() {
    local passwd_file="$1"
    local user_id="$2"

    if ! has_passwd "$passwd_file" "$user_id"; then
        echo "空密码"
    elif is_default_passwd "$passwd_file" "$user_id"; then
        echo "初始密码"
    else
        echo "已设置"
    fi
}
# -------------------------------------------------------------------
# 密码系统模块结束

# 哈希引擎自检（在密码系统模块定义完成后执行）
hash_engine_self_check
# 预计算默认密码哈希（确保后续使用时已就绪）
_init_default_passwd_hash

WORK_DIR="$HOME/Desktop/classselect"
LOG_DIR="$WORK_DIR/log"
STUDENT_FILE="$WORK_DIR/学生信息.txt"
TEACHER_FILE="$WORK_DIR/教师信息.txt"
COURSE_FILE="$WORK_DIR/课程信息.txt"
STUDENT_PASSWD_FILE="$WORK_DIR/学生密码.txt"
TEACHER_PASSWD_FILE="$WORK_DIR/教师密码.txt"
SYSTEM_LOG="$LOG_DIR/system.log"
USER_LOG="$LOG_DIR/user.log"

# 跨平台 sed 原地编辑兼容
if [ "$OS_TYPE" = "macOS" ]; then
    SED_INPLACE=(-i '')
else
    SED_INPLACE=(-i)
fi

# ===================== 表格输出与通用打印函数 =====================
print_course_table_header() {
    printf "%-10s %-22s %-12s\n" "课程编号" "课程名称" "选课状态(已选/上限)"
    echo "------------------------------------------------------------"
}

print_course_table_row() {
    local cid=$1
    local cname=$2
    local count=$3
    local max=$4
    printf "%-10s %-22s %-12s\n" "$cid" "$cname" "${count}/${max}"
}

# 通用：打印完整课程列表
print_all_courses() {
    awk -F'|' '{printf "%-10s %-22s %-12s\n", $1, $2, $3"/"$4}' "$COURSE_FILE"
}

print_student_table_header() {
    printf "%-8s %-12s %-30s %-10s\n" "学号" "姓名" "所选课程" "密码状态"
    echo "------------------------------------------------------------------------"
}

print_student_table_row() {
    local sid=$1
    local sname=$2
    local courses=$3
    local pass_status=$4
    printf "%-8s %-12s %-30s %-10s\n" "$sid" "$sname" "${courses:-未选课}" "$pass_status"
}

print_teacher_table_header() {
    printf "%-8s %-12s %-10s\n" "工号" "姓名" "密码状态"
    echo "----------------------------------------"
}

print_teacher_table_row() {
    local tid=$1
    local tname=$2
    local pass_status=$3
    printf "%-8s %-12s %-10s\n" "$tid" "$tname" "$pass_status"
}

print_my_course_header() {
    printf "%-10s %-22s %-12s\n" "课程编号" "课程名称" "选课状态"
    echo "------------------------------------------------------------"
}

# ===================== 日志与数据同步核心函数 =====================
write_log() {
    local log_msg=$1
    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] $log_msg" >> "$SYSTEM_LOG"
}

# 同步学生记录
sync_student_record() {
    local stu_id=$1
    local stu_name=$2
    local course=$3
    sed -E "${SED_INPLACE[@]}" "s/^${stu_id}\|.*\|.*$/${stu_id}|${stu_name}|${course}/" "$STUDENT_FILE"
    return $?
}

# 同步课程记录（含人数上限）
sync_course_record() {
    local course_id=$1
    local course_name=$2
    local count=$3
    local max=$4
    sed -E "${SED_INPLACE[@]}" "s/^${course_id}\|.*\|.*\|.*$/${course_id}|${course_name}|${count}|${max}/" "$COURSE_FILE"
    return $?
}

# 同步教师记录
sync_teacher_record() {
    local tea_id=$1
    local tea_name=$2
    sed -E "${SED_INPLACE[@]}" "s/^${tea_id}\|.*$/${tea_id}|${tea_name}/" "$TEACHER_FILE"
    return $?
}

get_course_name() {
    local cid=$1
    grep "^${cid}|" "$COURSE_FILE" | awk -F'|' '{print $2}'
}

get_course_count() {
    local cid=$1
    grep "^${cid}|" "$COURSE_FILE" | awk -F'|' '{print $3}'
}

get_course_max() {
    local cid=$1
    grep "^${cid}|" "$COURSE_FILE" | awk -F'|' '{print $4}'
}

# 更新课程选课人数
update_course_count() {
    local cid=$1
    local delta=$2
    local cname
    cname=$(get_course_name "$cid")
    local old_count
    old_count=$(get_course_count "$cid")
    local max
    max=$(get_course_max "$cid")
    local new_count=$((old_count + delta))
    
    # 人数边界保护
    if [ $new_count -lt 0 ]; then
        new_count=0
    fi
    if [ $new_count -gt "$max" ]; then
        return 1
    fi
    
    sync_course_record "$cid" "$cname" "$new_count" "$max"
    return $?
}

# ===================== 选课操作底层通用函数 =====================
# 功能：判断学生是否已选某门课程（公共复用，消除重复遍历）
has_student_course() {
    local stu_id=$1
    local cid=$2
    local current_courses
    current_courses=$(grep "^${stu_id}|" "$STUDENT_FILE" | awk -F'|' '{print $3}')
    
    if [ -z "$current_courses" ]; then
        return 1
    fi
    
    local IFS=','
    local arr
    read -ra arr <<< "$current_courses"
    for c in "${arr[@]}"; do
        [ "$c" = "$cid" ] && return 0
    done
    return 1
}

# 返回值：0成功 1已选该课程 2课程已满 3写入异常
add_student_course() {
    local stu_id=$1
    local stu_name=$2
    local cid=$3
    
    # 检查课程容量
    local current_count
    current_count=$(get_course_count "$cid")
    local max_count
    max_count=$(get_course_max "$cid")
    if [ "$current_count" -ge "$max_count" ]; then
        return 2
    fi
    
    # 校验是否已选
    if has_student_course "$stu_id" "$cid"; then
        return 1
    fi
    
    # 获取学生当前选课列表
    local current_courses
    current_courses=$(grep "^${stu_id}|" "$STUDENT_FILE" | awk -F'|' '{print $3}')
    
    # 拼接新选课列表
    local new_courses
    if [ -z "$current_courses" ]; then
        new_courses="$cid"
    else
        new_courses="${current_courses},${cid}"
    fi
    
    # 双文件同步
    sync_student_record "$stu_id" "$stu_name" "$new_courses" || return 3
    update_course_count "$cid" 1
    return $?
}

# 移除学生单门课程
# 返回值：0成功 1未选该课程 3写入异常
remove_student_course() {
    local stu_id=$1
    local stu_name=$2
    local cid=$3
    
    local current_courses
    current_courses=$(grep "^${stu_id}|" "$STUDENT_FILE" | awk -F'|' '{print $3}')
    if [ -z "$current_courses" ]; then
        return 1
    fi
    
    # 遍历过滤目标课程
    local found=0
    local new_courses=""
    local IFS=','
    local arr
    read -ra arr <<< "$current_courses"
    for c in "${arr[@]}"; do
        if [ "$c" = "$cid" ]; then
            found=1
        else
            if [ -z "$new_courses" ]; then
                new_courses="$c"
            else
                new_courses="${new_courses},${c}"
            fi
        fi
    done
    
    if [ $found -eq 0 ]; then
        return 1
    fi
    
    # 双文件同步
    sync_student_record "$stu_id" "$stu_name" "$new_courses" || return 3
    update_course_count "$cid" -1
    return $?
}

# 清空学生所有选课
clear_student_all_courses() {
    local stu_id=$1
    local stu_name=$2
    
    local current_courses
    current_courses=$(grep "^${stu_id}|" "$STUDENT_FILE" | awk -F'|' '{print $3}')
    if [ -z "$current_courses" ]; then
        return 0
    fi
    
    # 所有关联课程人数-1
    local IFS=','
    local arr
    read -ra arr <<< "$current_courses"
    for c in "${arr[@]}"; do
        [ -z "$c" ] && continue
        update_course_count "$c" -1
    done
    
    sync_student_record "$stu_id" "$stu_name" ""
    return $?
}

# 全局移除某门课程的所有学生选课记录（AWK统一处理，无边界问题）
remove_course_from_all_students() {
    local target_cid=$1
    local tmp_file="${STUDENT_FILE}.tmp"
    
    awk -F'|' -v target="$target_cid" '
    BEGIN {OFS="|"}
    {
        n = split($3, arr, ",")
        new_courses = ""
        for (i=1; i<=n; i++) {
            if (arr[i] != target && arr[i] != "") {
                if (new_courses == "") {
                    new_courses = arr[i]
                } else {
                    new_courses = new_courses "," arr[i]
                }
            }
        }
        $3 = new_courses
        print $0
    }
    ' "$STUDENT_FILE" > "$tmp_file"
    
    if [ $? -ne 0 ]; then
        rm -f "$tmp_file"
        return 1
    fi
    
    mv "$tmp_file" "$STUDENT_FILE"
    return $?
}

# ===================== 系统环境初始化（含错误兜底） =====================
prepare_environment() {
    echo ""
    echo "==================== 系统正在初始化，请稍候 ===================="
    echo "步骤A：查看当前工作目录"
    pwd
    echo ""
    echo "步骤B：初始化工作目录与日志目录"
    
    mkdir -p "$WORK_DIR" || { echo "错误：无法创建工作目录 $WORK_DIR，程序终止"; exit 1; }
    mkdir -p "$LOG_DIR" || { echo "错误：无法创建日志目录 $LOG_DIR，程序终止"; exit 1; }
    
    cd "$WORK_DIR" || { echo "错误：无法进入工作目录，程序终止"; exit 1; }
    echo "工作目录已设置：$(pwd)"
    echo "日志目录已设置：$LOG_DIR"
    echo ""
    echo "步骤C：初始化数据文件（仅首次启动创建，不覆盖已有数据）"
    
    # 学生信息：学号|姓名|所选课程
    if [ ! -f "$STUDENT_FILE" ]; then
        cat > "$STUDENT_FILE" << 'EOF'
001|student1|
002|student2|
003|student3|
EOF
        [ $? -ne 0 ] && { echo "错误：创建学生信息文件失败"; exit 1; }
        echo "学生信息文件创建完成，预存3条初始数据"
        write_log "系统初始化：创建学生信息文件，预存3条数据"
    else
        echo "学生信息文件已存在，读取历史数据"
    fi
    
    # 教师信息：工号|姓名
    if [ ! -f "$TEACHER_FILE" ]; then
        cat > "$TEACHER_FILE" << 'EOF'
T01|teacher1
T02|teacher2
EOF
        [ $? -ne 0 ] && { echo "错误：创建教师信息文件失败"; exit 1; }
        echo "教师信息文件创建完成，预存2条初始数据"
        write_log "系统初始化：创建教师信息文件，预存2条数据"
    else
        echo "教师信息文件已存在，读取历史数据"
    fi
    
    # 课程信息：课程号|课程名称|选课人数|人数上限
    if [ ! -f "$COURSE_FILE" ]; then
        cat > "$COURSE_FILE" << 'EOF'
C01|计算机导论|0|30
C02|C语言程序设计|0|30
C03|数据结构|0|30
C04|操作系统|0|30
C05|计算机网络|0|30
C06|数据库原理|0|30
C07|Python编程|0|30
C08|Java编程|0|30
C09|人工智能|0|30
C10|软件工程|0|30
EOF
        [ $? -ne 0 ] && { echo "错误：创建课程信息文件失败"; exit 1; }
        echo "课程信息文件创建完成，预存10条初始数据，默认上限30人"
        write_log "系统初始化：创建课程信息文件，预存10条数据"
    else
        echo "课程信息文件已存在，读取历史数据"
        # 兼容旧版本数据：补全人数上限字段
        local field_count
        field_count=$(head -1 "$COURSE_FILE" | awk -F'|' '{print NF}')
        if [ "$field_count" -eq 3 ]; then
            echo "检测到旧版本课程数据，自动补全人数上限字段（默认30人）"
            local tmp_file="${COURSE_FILE}.tmp"
            awk -F'|' 'BEGIN{OFS="|"}{print $1,$2,$3,30}' "$COURSE_FILE" > "$tmp_file"
            mv "$tmp_file" "$COURSE_FILE"
            write_log "系统初始化：自动升级课程数据格式，补全人数上限字段"
        fi
    fi
    
    # 初始化密码文件
    echo ""
    echo "步骤D：初始化密码系统"
    init_passwd_files || { echo "错误：密码系统初始化失败"; exit 1; }
    echo "密码系统初始化完成，所有用户初始密码：$DEFAULT_PASSWD"
    echo "提示：脚本密码完全独立于系统用户密码，仅保存在当前目录的密码文件中"
    
    echo ""
    echo "步骤E：配置定时任务"
    local cron_task="0 12 * * * who >> $USER_LOG"
    if ! crontab -l 2>/dev/null | grep -F "who >> $USER_LOG" >/dev/null 2>&1; then
        (crontab -l 2>/dev/null; echo "$cron_task") | crontab -
        if [ $? -eq 0 ]; then
            echo "定时任务配置完成：每日12点记录登录用户至 $USER_LOG"
            write_log "系统初始化：配置每日12点用户登录日志定时任务"
        else
            echo "警告：定时任务配置失败，不影响核心功能使用"
            write_log "系统初始化：定时任务配置失败"
        fi
    else
        echo "定时任务已存在，无需重复配置"
    fi
    
    echo "==================== 系统初始化完成 ===================="
    write_log "系统启动完成，进入主菜单"
    echo "当前版本号：5.2.0"
    countdown "初始化完成，即将进入系统主菜单……"
    clear
}

# ===================== 身份验证函数 =====================
verify_student_id() {
    local stu_id=$1
    grep -q "^${stu_id}|" "$STUDENT_FILE"
    return $?
}

verify_teacher_id() {
    local tea_id=$1
    grep -q "^${tea_id}|" "$TEACHER_FILE"
    return $?
}

# 根据学号获取学生姓名
get_student_name() {
    local stu_id=$1
    grep "^${stu_id}|" "$STUDENT_FILE" | awk -F'|' '{print $2}'
}

# 根据工号获取教师姓名
get_teacher_name() {
    local tea_id=$1
    grep "^${tea_id}|" "$TEACHER_FILE" | awk -F'|' '{print $2}'
}

# ===================== 学生功能模块 =====================
student_add_course_menu() {
    local stu_id=$1
    local stu_name
    stu_name=$(get_student_name "$stu_id")
    
    while true; do
        clear
        echo ""
        echo "========================== 添加选课 =========================="
        print_course_table_header
        print_all_courses
        echo "------------------------------------------------------------"
        echo "1、输入课程编号添加选课"
        echo "2、返回选课管理菜单"
        
        local choice
        choice=$(read_int "请输入选项：" 1 2)
        case $choice in
            1)
                local cid
                cid=$(read_id "请输入要添加的课程编号：")
                if ! grep -q "^${cid}|" "$COURSE_FILE"; then
                    echo "课程编号不存在。"
                    countdown "即将返回添加选课菜单……"
                    continue
                fi
                
                add_student_course "$stu_id" "$stu_name" "$cid"
                local result=$?
                local cname
                cname=$(get_course_name "$cid")
                
                case $result in
                    0)
                        echo "选课添加成功：$cid $cname"
                        write_log "学生 $stu_id($stu_name) 添加选课：$cid $cname"
                        ;;
                    1) echo "你已选择该课程，无需重复添加。" ;;
                    2) echo "选课失败：该课程人数已满。" ;;
                    *) echo "选课失败：数据写入异常，请重试。"
                       write_log "学生 $stu_id 添加选课失败：数据写入错误" ;;
                esac
                countdown "即将返回添加选课菜单……"
                ;;
            2)
                echo "返回选课管理菜单"
                return
                ;;
        esac
    done
}

student_modify_course_menu() {
    local stu_id=$1
    local stu_name
    stu_name=$(get_student_name "$stu_id")
    
    while true; do
        clear
        local current_courses
        current_courses=$(grep "^${stu_id}|" "$STUDENT_FILE" | awk -F'|' '{print $3}')
        
        echo ""
        echo "======================== 修改我的选课 ========================"
        print_my_course_header
        if [ -z "$current_courses" ]; then
            echo "你还没有选课哦"
        else
            local IFS=','
            local c_arr
            read -ra c_arr <<< "$current_courses"
            for cid in "${c_arr[@]}"; do
                [ -z "$cid" ] && continue
                local cname count max
                cname=$(get_course_name "$cid")
                count=$(get_course_count "$cid")
                max=$(get_course_max "$cid")
                printf "%-10s %-22s %-12s\n" "$cid" "$cname" "${count}/${max}"
            done
        fi
        echo "------------------------------------------------------------"
        echo "1、输入课程编号退课"
        echo "2、一键清空所有选课"
        echo "3、返回我的选课情况"
        
        local choice
        choice=$(read_int "请输入选项：" 1 3)
        case $choice in
            1)
                if [ -z "$current_courses" ]; then
                    echo "你当前没有选课，无法退课。"
                    countdown "即将返回修改选课菜单……"
                    continue
                fi
                
                local cid
                cid=$(read_id "请输入要退课的课程编号：")
                
                # 复用公共校验函数，消除重复遍历
                if ! has_student_course "$stu_id" "$cid"; then
                    echo "你没有选择该课程，无法退课。"
                    countdown "即将返回修改选课菜单……"
                    continue
                fi
                
                local cname
                cname=$(get_course_name "$cid")
                local confirm
                read -r -p "确认要退选课程 $cid $cname 吗？(y/n): " confirm
                if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
                    if remove_student_course "$stu_id" "$stu_name" "$cid"; then
                        echo "退课成功，课程已移除。"
                        write_log "学生 $stu_id($stu_name) 退课：$cid $cname"
                    else
                        echo "退课失败：数据更新异常。"
                    fi
                else
                    echo "已取消退课操作。"
                fi
                countdown "即将返回修改选课菜单……"
                ;;
            2)
                if [ -z "$current_courses" ]; then
                    echo "你当前没有选课，无需清空。"
                    countdown "即将返回修改选课菜单……"
                    continue
                fi
                
                echo "警告：清空后所有已选课程都将被取消，操作不可恢复！"
                local confirm
                read -r -p "确认要一键清空所有选课吗？(y/n): " confirm
                if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
                    clear_student_all_courses "$stu_id" "$stu_name"
                    echo "所有选课已清空。"
                    write_log "学生 $stu_id($stu_name) 一键清空所有选课"
                else
                    echo "已取消清空操作。"
                fi
                countdown "即将返回修改选课菜单……"
                ;;
            3)
                echo "返回我的选课情况"
                return
                ;;
        esac
    done
}

student_course_manage() {
    local stu_id=$1
    local stu_name
    stu_name=$(get_student_name "$stu_id")
    
    while true; do
        clear
        local current_courses
        current_courses=$(grep "^${stu_id}|" "$STUDENT_FILE" | awk -F'|' '{print $3}')
        
        echo ""
        echo "======================== 我的选课情况 ========================"
        print_my_course_header
        if [ -z "$current_courses" ]; then
            echo "你还没有选课哦"
        else
            local IFS=','
            local c_arr
            read -ra c_arr <<< "$current_courses"
            for cid in "${c_arr[@]}"; do
                [ -z "$cid" ] && continue
                local cname count max
                cname=$(get_course_name "$cid")
                count=$(get_course_count "$cid")
                max=$(get_course_max "$cid")
                printf "%-10s %-22s %-12s\n" "$cid" "$cname" "${count}/${max}"
            done
        fi
        echo "------------------------------------------------------------"
        
        echo "1、添加选课"
        echo "2、修改/退课"
        echo "3、返回学生菜单"
        
        local choice
        choice=$(read_int "请输入选项：" 1 3)
        case $choice in
            1) student_add_course_menu "$stu_id" ;;
            2) student_modify_course_menu "$stu_id" ;;
            3) echo "返回学生菜单"; return ;;
        esac
    done
}

student_view_course_status() {
    local stu_id=$1
    while true; do
        clear
        echo ""
        echo "====================== 实时课程选课状态 ======================"
        print_course_table_header
        print_all_courses
        echo "------------------------------------------------------------"
        echo "1、返回学生菜单"
        echo "2、跳转到选课管理"
        
        local choice
        choice=$(read_int "请输入选项：" 1 2)
        case $choice in
            1) echo "返回学生菜单"; return ;;
            2) student_course_manage "$stu_id"; return ;;
        esac
    done
}

student_view_info() {
    local stu_id=$1
    clear
    local stu_name course_id pass_status
    stu_name=$(get_student_name "$stu_id")
    course_id=$(grep "^${stu_id}|" "$STUDENT_FILE" | awk -F'|' '{print $3}')
    pass_status=$(get_passwd_status_text "$STUDENT_PASSWD_FILE" "$stu_id")
    
    echo ""
    echo "======================== 学生个人信息 ========================"
    print_student_table_header
    print_student_table_row "$stu_id" "$stu_name" "$course_id" "$pass_status"
    
    write_log "学生 $stu_id($stu_name) 查看个人信息"
    echo ""
    pause
}

# 学生修改密码
student_change_password() {
    local stu_id=$1
    local stu_name
    stu_name=$(get_student_name "$stu_id")
    
    clear
    echo ""
    echo "======================== 修改密码 ========================"
    echo "学号：$stu_id  姓名：$stu_name"
    echo "密码规则：仅大小写字母和数字，长度≥6位"
    echo ""
    
    local pass1 pass2
    pass1=$(read_passwd "请输入新密码：" 0)
    pass2=$(read_passwd "请再次输入新密码：" 0)
    
    if [ "$pass1" != "$pass2" ]; then
        echo "两次输入的密码不一致，修改失败。"
        countdown
        return
    fi
    
    if set_passwd "$STUDENT_PASSWD_FILE" "$stu_id" "$pass1"; then
        echo "密码修改成功。"
        write_log "学生 $stu_id($stu_name) 修改了登录密码"
    else
        echo "密码修改失败：数据写入异常。"
    fi
    countdown
}

student_menu() {
    local stu_id=$1
    local stu_name
    stu_name=$(get_student_name "$stu_id")
    
    write_log "学生 $stu_id($stu_name) 登录系统"
    
    # 初始密码安全提示
    if is_default_passwd "$STUDENT_PASSWD_FILE" "$stu_id"; then
        echo ""
        echo "⚠️  安全提示：您正在使用初始密码，建议尽快修改以保障账号安全"
        sleep 1
    fi
    
    while true; do
        clear
        echo ""
        echo "------------------ 欢迎使用选课管理系统（学生）------------------"
        echo "｜                    1、选课管理                              ｜"
        echo "｜                    2、查看实时选课状态                      ｜"
        echo "｜                    3、查看个人信息                          ｜"
        echo "｜                    4、修改登录密码                          ｜"
        echo "｜                    5、学生退出系统                          ｜"
        echo "-----------------------------------------------------------------"
        local choice
        choice=$(read_int "请输入功能序号：" 1 5)
        case $choice in
            1) student_course_manage "$stu_id" ;;
            2) student_view_course_status "$stu_id" ;;
            3) student_view_info "$stu_id" ;;
            4) student_change_password "$stu_id" ;;
            5)
                echo "退出学生系统，返回主菜单"
                write_log "学生 $stu_id($stu_name) 退出登录"
                countdown "即将返回系统主菜单……"
                return
                ;;
        esac
    done
}

# ===================== 教师功能模块 =====================
# ---------- 课程管理子模块 ----------
course_manage_menu() {
    while true; do
        clear
        echo ""
        echo "------------------------ 课程管理 ---------------------------"
        echo "｜                      1、添加课程                         ｜"
        echo "｜                      2、删除课程                         ｜"
        echo "｜                      3、修改课程                         ｜"
        echo "｜                      4、查询课程                         ｜"
        echo "｜                      5、返回上级菜单                     ｜"
        echo "-------------------------------------------------------------"
        local choice
        choice=$(read_int "请输入功能序号：" 1 5)
        case $choice in
            1) teacher_add_course ;;
            2) teacher_delete_course ;;
            3) teacher_update_course ;;
            4) teacher_query_course ;;
            5) echo "返回教师主菜单"; return ;;
        esac
    done
}

teacher_add_course() {
    clear
    local course_id
    course_id=$(read_id "请输入新课程编号：")
    if grep -q "^$course_id|" "$COURSE_FILE"; then
        echo "该课程编号已存在，添加失败"
        countdown "即将返回课程管理菜单……"
        return
    fi
    
    local course_name
    course_name=$(read_name "请输入新课程名称：")
    local max_count
    max_count=$(read_int "请输入选课人数上限：" 1 9999)
    
    echo "${course_id}|${course_name}|0|${max_count}" >> "$COURSE_FILE"
    if [ $? -ne 0 ]; then
        echo "课程添加失败：文件写入异常"
        countdown "即将返回课程管理菜单……"
        return
    fi
    
    echo "课程添加成功："
    print_course_table_header
    print_course_table_row "$course_id" "$course_name" 0 "$max_count"
    write_log "教师添加课程：$course_id $course_name，上限${max_count}人"
    countdown "即将返回课程管理菜单……"
}

teacher_delete_course() {
    clear
    echo ""
    echo "当前课程列表："
    print_course_table_header
    print_all_courses
    echo ""
    
    local course_id
    course_id=$(read_id "请输入要删除的课程编号：")
    if ! grep -q "^$course_id|" "$COURSE_FILE"; then
        echo "未找到对应课程，删除失败"
        countdown "即将返回课程管理菜单……"
        return
    fi
    
    local course_name
    course_name=$(get_course_name "$course_id")
    echo "警告：删除课程将同时清空所有学生的该课程选课记录，操作不可恢复！"
    local confirm
    read -r -p "确认删除课程 $course_id $course_name 吗？(y/n): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo "已取消删除操作。"
        countdown "即将返回课程管理菜单……"
        return
    fi
    
    # 删除课程记录
    local tmp_file="${COURSE_FILE}.tmp"
    sed "/^${course_id}|/d" "$COURSE_FILE" > "$tmp_file"
    if [ $? -ne 0 ]; then
        rm -f "$tmp_file"
        echo "删除失败：文件操作异常"
        countdown "即将返回课程管理菜单……"
        return
    fi
    mv "$tmp_file" "$COURSE_FILE"
    
    # 同步清理所有学生选课
    remove_course_from_all_students "$course_id"
    if [ $? -ne 0 ]; then
        echo "警告：学生选课记录清理异常，请手动检查数据"
        write_log "删除课程 $course_id 时学生选课清理异常"
    fi
    
    echo "课程 $course_id $course_name 删除成功，学生对应选课记录已同步清空"
    write_log "教师删除课程：$course_id $course_name"
    countdown "即将返回课程管理菜单……"
}

teacher_update_course() {
    clear
    local course_id
    course_id=$(read_id "请输入要修改的课程编号：")
    if ! grep -q "^$course_id|" "$COURSE_FILE"; then
        echo "未找到对应课程，修改失败"
        countdown "即将返回课程管理菜单……"
        return
    fi
    
    local old_name old_count old_max
    old_name=$(get_course_name "$course_id")
    old_count=$(get_course_count "$course_id")
    old_max=$(get_course_max "$course_id")
    
    echo ""
    echo "当前课程信息（课程编号不可修改）："
    print_course_table_header
    print_course_table_row "$course_id" "$old_name" "$old_count" "$old_max"
    echo ""
    
    local new_name new_max
    new_name=$(read_name "请输入新课程名称（回车保持不变）：" 1)
    [ -z "$new_name" ] && new_name="$old_name"
    
    local change_max
    read -r -p "是否修改选课人数上限？(y/n): " change_max
    if [ "$change_max" = "y" ] || [ "$change_max" = "Y" ]; then
        new_max=$(read_int "请输入新的人数上限：" "$old_count" 9999)
    else
        new_max="$old_max"
    fi
    
    sync_course_record "$course_id" "$new_name" "$old_count" "$new_max"
    if [ $? -eq 0 ]; then
        echo "课程信息修改成功，更新后："
        print_course_table_header
        print_course_table_row "$course_id" "$new_name" "$old_count" "$new_max"
        write_log "教师修改课程：$course_id 名称从 $old_name 改为 $new_name，上限调整为${new_max}"
    else
        echo "修改失败：数据写入异常"
    fi
    countdown "即将返回课程管理菜单……"
}

teacher_query_course() {
    clear
    echo ""
    echo "==================== 课程信息统计 ===================="
    print_course_table_header
    print_all_courses
    write_log "教师查询全部课程信息"
    echo ""
    pause
}

# ---------- 学生管理子模块 ----------
student_manage_menu() {
    local current_tea_id=$1
    while true; do
        clear
        echo ""
        echo "------------------------ 学生管理 --------------------------"
        echo "｜                     1、添加学生                         ｜"
        echo "｜                     2、删除学生                         ｜"
        echo "｜                     3、修改学生信息                     ｜"
        echo "｜                     4、重置学生密码                     ｜"
        echo "｜                     5、查询学生                         ｜"
        echo "｜                     6、返回上级菜单                     ｜"
        echo "-------------------------------------------------------------"
        local choice
        choice=$(read_int "请输入功能序号：" 1 6)
        case $choice in
            1) teacher_add_student ;;
            2) teacher_delete_student ;;
            3) teacher_update_student ;;
            4) teacher_reset_student_passwd "$current_tea_id" ;;
            5) teacher_query_student ;;
            6) echo "返回教师主菜单"; return ;;
        esac
    done
}

teacher_add_student() {
    clear
    local stu_id
    stu_id=$(read_id "请输入新学生学号：")
    if grep -q "^$stu_id|" "$STUDENT_FILE"; then
        echo "该学号已存在，添加失败"
        countdown "即将返回学生管理菜单……"
        return
    fi
    
    local stu_name
    stu_name=$(read_name "请输入新学生姓名：")
    
    echo "${stu_id}|${stu_name}|" >> "$STUDENT_FILE"
    if [ $? -ne 0 ]; then
        echo "学生添加失败：文件写入异常"
        countdown "即将返回学生管理菜单……"
        return
    fi
    
    # 设置初始密码
    set_passwd "$STUDENT_PASSWD_FILE" "$stu_id" "$DEFAULT_PASSWD"
    
    echo "学生添加成功："
    print_student_table_header
    print_student_table_row "$stu_id" "$stu_name" "" "初始密码"
    write_log "教师添加学生：学号 $stu_id，姓名 $stu_name"
    countdown "即将返回学生管理菜单……"
}

teacher_delete_student() {
    clear
    local stu_id
    stu_id=$(read_id "请输入要删除的学生学号：")
    if ! grep -q "^$stu_id|" "$STUDENT_FILE"; then
        echo "未找到该学生，删除失败"
        countdown "即将返回学生管理菜单……"
        return
    fi
    
    local course_id stu_name
    course_id=$(grep "^$stu_id|" "$STUDENT_FILE" | awk -F'|' '{print $3}')
    stu_name=$(get_student_name "$stu_id")
    
    echo "警告：删除学生将同步清空其所有选课记录，操作不可恢复！"
    local confirm
    read -r -p "确认删除学生 $stu_id $stu_name 吗？(y/n): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo "已取消删除操作。"
        countdown "即将返回学生管理菜单……"
        return
    fi
    
    # 同步减少课程人数
    if [ -n "$course_id" ]; then
        local IFS=','
        local c_arr
        read -ra c_arr <<< "$course_id"
        for cid in "${c_arr[@]}"; do
            [ -z "$cid" ] && continue
            update_course_count "$cid" -1
        done
    fi
    
    # 删除学生记录
    local tmp_file="${STUDENT_FILE}.tmp"
    sed "/^${stu_id}|/d" "$STUDENT_FILE" > "$tmp_file"
    if [ $? -ne 0 ]; then
        rm -f "$tmp_file"
        echo "删除失败：文件操作异常"
        countdown "即将返回学生管理菜单……"
        return
    fi
    mv "$tmp_file" "$STUDENT_FILE"
    
    # 删除密码记录
    delete_passwd_record "$STUDENT_PASSWD_FILE" "$stu_id"
    
    echo "学生 $stu_id $stu_name 删除成功"
    write_log "教师删除学生：学号 $stu_id $stu_name"
    countdown "即将返回学生管理菜单……"
}

teacher_update_student() {
    clear
    local stu_id
    stu_id=$(read_id "请输入要修改的学生学号：")
    if ! grep -q "^$stu_id|" "$STUDENT_FILE"; then
        echo "未找到该学生，修改失败"
        countdown "即将返回学生管理菜单……"
        return
    fi
    
    local old_name old_course
    old_name=$(get_student_name "$stu_id")
    old_course=$(grep "^$stu_id|" "$STUDENT_FILE" | awk -F'|' '{print $3}')
    
    echo ""
    echo "当前学生信息（学号不可修改）："
    print_student_table_header
    print_student_table_row "$stu_id" "$old_name" "$old_course" "-"
    echo ""
    
    local new_name
    new_name=$(read_name "请输入新姓名（回车保持不变）：" 1)
    [ -z "$new_name" ] && new_name="$old_name"
    
    sync_student_record "$stu_id" "$new_name" "$old_course"
    if [ $? -eq 0 ]; then
        echo "学生信息修改成功，更新后："
        print_student_table_header
        print_student_table_row "$stu_id" "$new_name" "$old_course" "-"
        write_log "教师修改学生：学号 $stu_id 姓名从 $old_name 改为 $new_name"
    else
        echo "修改失败：数据写入异常"
    fi
    countdown "即将返回学生管理菜单……"
}

teacher_reset_student_passwd() {
    local current_tea_id=$1
    clear
    local stu_id
    stu_id=$(read_id "请输入要重置密码的学生学号：")
    
    if ! verify_student_id "$stu_id"; then
        echo "未找到该学生，重置失败"
        countdown "即将返回学生管理菜单……"
        return
    fi
    
    local stu_name
    stu_name=$(get_student_name "$stu_id")
    
    echo ""
    echo "⚠️  重置警告：学生 $stu_id($stu_name) 的密码将被重置为初始密码 $DEFAULT_PASSWD"
    echo "此操作不可恢复，请验证您的身份后继续"
    echo ""
    
    local verify_pass
    verify_pass=$(read_passwd "请输入您当前的登录密码：" 0)
    
    if ! verify_passwd "$TEACHER_PASSWD_FILE" "$current_tea_id" "$verify_pass"; then
        echo "身份验证失败，已取消重置操作。"
        write_log "教师 $current_tea_id 重置学生密码失败：身份验证失败"
        countdown
        return
    fi
    
    if reset_to_default_passwd "$STUDENT_PASSWD_FILE" "$stu_id"; then
        echo "密码重置成功，该学生现在可使用初始密码登录。"
        write_log "教师 $current_tea_id 重置学生 $stu_id 的密码为初始密码"
    else
        echo "密码重置失败：数据写入异常"
    fi
    countdown
}

teacher_query_student() {
    clear
    echo ""
    echo "======================== 学生信息统计 ========================"
    print_student_table_header
    
    while IFS='|' read -r sid sname courses; do
        local pass_status
        pass_status=$(get_passwd_status_text "$STUDENT_PASSWD_FILE" "$sid")
        printf "%-8s %-12s %-30s %-10s\n" "$sid" "$sname" "${courses:-未选课}" "$pass_status"
    done < "$STUDENT_FILE"
    
    write_log "教师查询全部学生信息"
    echo ""
    pause
}

# ---------- 教师管理子模块 ----------
teacher_manage_menu() {
    local current_tea_id=$1
    while true; do
        clear
        echo ""
        echo "------------------------- 教师管理 --------------------------"
        echo "｜                       1、添加教师                        ｜"
        echo "｜                       2、删除教师                        ｜"
        echo "｜                       3、修改教师信息                    ｜"
        echo "｜                       4、重置教师密码                    ｜"
        echo "｜                       5、查询教师                        ｜"
        echo "｜                       6、修改自身信息                    ｜"
        echo "｜                       7、返回上级菜单                    ｜"
        echo "-------------------------------------------------------------"
        local choice
        choice=$(read_int "请输入功能序号：" 1 7)
        case $choice in
            1) teacher_add_teacher "$current_tea_id" ;;
            2) teacher_delete_teacher "$current_tea_id" ;;
            3) teacher_update_teacher "$current_tea_id" ;;
            4) teacher_reset_teacher_passwd "$current_tea_id" ;;
            5) teacher_query_teacher ;;
            6) teacher_update_self "$current_tea_id" ;;
            7) echo "返回教师主菜单"; return ;;
        esac
    done
}

teacher_add_teacher() {
    local current_tea_id=$1
    clear
    local tea_id
    tea_id=$(read_id "请输入新教师工号：")
    if grep -q "^$tea_id|" "$TEACHER_FILE"; then
        echo "该工号已存在，添加失败"
        countdown "即将返回教师管理菜单……"
        return
    fi
    
    local tea_name
    tea_name=$(read_name "请输入新教师姓名：")
    
    echo "${tea_id}|${tea_name}" >> "$TEACHER_FILE"
    if [ $? -ne 0 ]; then
        echo "教师添加失败：文件写入异常"
        countdown "即将返回教师管理菜单……"
        return
    fi
    
    set_passwd "$TEACHER_PASSWD_FILE" "$tea_id" "$DEFAULT_PASSWD"
    
    echo "教师添加成功："
    print_teacher_table_header
    print_teacher_table_row "$tea_id" "$tea_name" "初始密码"
    write_log "教师 $current_tea_id 添加账号：工号 $tea_id，姓名 $tea_name"
    countdown "即将返回教师管理菜单……"
}

teacher_delete_teacher() {
    local current_tea_id=$1
    clear
    local tea_id
    tea_id=$(read_id "请输入要删除的教师工号：")
    
    if ! grep -q "^$tea_id|" "$TEACHER_FILE"; then
        echo "未找到该教师，删除失败"
        countdown "即将返回教师管理菜单……"
        return
    fi
    
    if [ "$tea_id" = "$current_tea_id" ]; then
        echo "不能删除自己的账号，请选择其他教师。"
        countdown "即将返回教师管理菜单……"
        return
    fi
    
    local tea_name
    tea_name=$(get_teacher_name "$tea_id")
    
    echo "警告：删除教师账号操作不可恢复！"
    local confirm
    read -r -p "确认删除教师 $tea_id $tea_name 吗？(y/n): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo "已取消删除操作。"
        countdown "即将返回教师管理菜单……"
        return
    fi
    
    local tmp_file="${TEACHER_FILE}.tmp"
    sed "/^${tea_id}|/d" "$TEACHER_FILE" > "$tmp_file"
    if [ $? -ne 0 ]; then
        rm -f "$tmp_file"
        echo "删除失败：文件操作异常"
        countdown "即将返回教师管理菜单……"
        return
    fi
    mv "$tmp_file" "$TEACHER_FILE"
    
    delete_passwd_record "$TEACHER_PASSWD_FILE" "$tea_id"
    
    echo "教师 $tea_id $tea_name 删除成功"
    write_log "教师 $current_tea_id 删除账号：工号 $tea_id $tea_name"
    countdown "即将返回教师管理菜单……"
}

teacher_update_teacher() {
    local current_tea_id=$1
    clear
    local tea_id
    tea_id=$(read_id "请输入要修改的教师工号：")
    
    if ! grep -q "^$tea_id|" "$TEACHER_FILE"; then
        echo "未找到该教师，修改失败"
        countdown "即将返回教师管理菜单……"
        return
    fi
    
    local old_name
    old_name=$(get_teacher_name "$tea_id")
    
    if [ "$tea_id" = "$current_tea_id" ]; then
        echo "请使用「修改自身信息」功能修改本人账号。"
        countdown "即将返回教师管理菜单……"
        return
    fi
    
    echo ""
    echo "当前教师信息（工号不可修改，仅可修改姓名）："
    print_teacher_table_header
    print_teacher_table_row "$tea_id" "$old_name" "-"
    echo ""
    
    local new_name
    new_name=$(read_name "请输入新姓名（回车保持不变）：" 1)
    [ -z "$new_name" ] && new_name="$old_name"
    
    sync_teacher_record "$tea_id" "$new_name"
    if [ $? -eq 0 ]; then
        echo "教师信息修改成功，更新后："
        print_teacher_table_header
        print_teacher_table_row "$tea_id" "$new_name" "-"
        write_log "教师 $current_tea_id 修改账号：工号 $tea_id 姓名从 $old_name 改为 $new_name"
    else
        echo "修改失败：数据写入异常"
    fi
    countdown "即将返回教师管理菜单……"
}

teacher_reset_teacher_passwd() {
    local current_tea_id=$1
    clear
    local tea_id
    tea_id=$(read_id "请输入要重置密码的教师工号：")
    
    if ! verify_teacher_id "$tea_id"; then
        echo "未找到该教师，重置失败"
        countdown "即将返回教师管理菜单……"
        return
    fi
    
    if [ "$tea_id" = "$current_tea_id" ]; then
        echo "请使用「修改自身信息」功能修改本人密码。"
        countdown "即将返回教师管理菜单……"
        return
    fi
    
    local tea_name
    tea_name=$(get_teacher_name "$tea_id")
    
    echo ""
    echo "⚠️  重置警告：教师 $tea_id($tea_name) 的密码将被重置为初始密码 $DEFAULT_PASSWD"
    echo "此操作不可恢复，请验证您的身份后继续"
    echo ""
    
    local verify_pass
    verify_pass=$(read_passwd "请输入您当前的登录密码：" 0)
    
    if ! verify_passwd "$TEACHER_PASSWD_FILE" "$current_tea_id" "$verify_pass"; then
        echo "身份验证失败，已取消重置操作。"
        write_log "教师 $current_tea_id 重置教师密码失败：身份验证失败"
        countdown
        return
    fi
    
    if reset_to_default_passwd "$TEACHER_PASSWD_FILE" "$tea_id"; then
        echo "密码重置成功，该教师现在可使用初始密码登录。"
        write_log "教师 $current_tea_id 重置教师 $tea_id 的密码为初始密码"
    else
        echo "密码重置失败：数据写入异常"
    fi
    countdown
}

# 修改自身信息（姓名+密码）
teacher_update_self() {
    local current_tea_id=$1
    local old_name
    old_name=$(get_teacher_name "$current_tea_id")
    
    while true; do
        clear
        echo ""
        echo "======================== 个人信息维护 ========================"
        echo "工号：$current_tea_id（不可修改）"
        echo "姓名：$old_name"
        echo "密码状态：$(get_passwd_status_text "$TEACHER_PASSWD_FILE" "$current_tea_id")"
        echo "------------------------------------------------------------"
        echo "1、修改姓名"
        echo "2、修改登录密码"
        echo "3、返回教师管理菜单"
        
        local choice
        choice=$(read_int "请输入选项：" 1 3)
        case $choice in
            1)
                local new_name
                new_name=$(read_name "请输入新姓名：" 0)
                sync_teacher_record "$current_tea_id" "$new_name"
                if [ $? -eq 0 ]; then
                    echo "姓名修改成功。"
                    old_name="$new_name"
                    write_log "教师 $current_tea_id 修改本人姓名为 $new_name"
                else
                    echo "修改失败：数据写入异常"
                fi
                countdown
                ;;
            2)
                echo ""
                echo "密码规则：仅大小写字母和数字，长度≥6位"
                local pass1 pass2
                pass1=$(read_passwd "请输入新密码：" 0)
                pass2=$(read_passwd "请再次输入新密码：" 0)
                
                if [ "$pass1" != "$pass2" ]; then
                    echo "两次输入的密码不一致，修改失败。"
                    countdown
                    continue
                fi
                
                if set_passwd "$TEACHER_PASSWD_FILE" "$current_tea_id" "$pass1"; then
                    echo "密码修改成功。"
                    write_log "教师 $current_tea_id 修改了登录密码"
                else
                    echo "密码修改失败：数据写入异常。"
                fi
                countdown
                ;;
            3)
                echo "返回教师管理菜单"
                return
                ;;
        esac
    done
}

teacher_query_teacher() {
    clear
    echo ""
    echo "======================== 教师信息统计 ========================"
    print_teacher_table_header
    
    while IFS='|' read -r tid tname; do
        local pass_status
        pass_status=$(get_passwd_status_text "$TEACHER_PASSWD_FILE" "$tid")
        printf "%-8s %-12s %-10s\n" "$tid" "$tname" "$pass_status"
    done < "$TEACHER_FILE"
    
    write_log "教师查询全部教师信息"
    echo ""
    pause
}

# ---------- 选课管理子模块 ----------
teacher_modify_student_course_menu() {
    local stu_id=$1
    local stu_name=$2
    local operator_id=$3
    
    while true; do
        clear
        local current_courses
        current_courses=$(grep "^${stu_id}|" "$STUDENT_FILE" | awk -F'|' '{print $3}')
        
        echo ""
        echo "==================== 学生 $stu_id $stu_name 选课管理 ===================="
        print_my_course_header
        if [ -z "$current_courses" ]; then
            echo "该学生暂未选课"
        else
            local IFS=','
            local c_arr
            read -ra c_arr <<< "$current_courses"
            for cid in "${c_arr[@]}"; do
                [ -z "$cid" ] && continue
                local cname count max
                cname=$(get_course_name "$cid")
                count=$(get_course_count "$cid")
                max=$(get_course_max "$cid")
                printf "%-10s %-22s %-12s\n" "$cid" "$cname" "${count}/${max}"
            done
        fi
        echo "------------------------------------------------------------"
        echo "1、为学生添加课程"
        echo "2、删除指定课程（退课）"
        echo "3、一键清空所有选课"
        echo "4、返回选课管理菜单"
        
        local choice
        choice=$(read_int "请输入选项：" 1 4)
        case $choice in
            1)
                clear
                echo "可选课程列表："
                print_course_table_header
                print_all_courses
                echo ""
                
                local cid
                cid=$(read_id "请输入要添加的课程编号：")
                if ! grep -q "^${cid}|" "$COURSE_FILE"; then
                    echo "课程编号不存在。"
                    countdown "即将返回选课管理菜单……"
                    continue
                fi
                
                add_student_course "$stu_id" "$stu_name" "$cid"
                local result=$?
                local cname
                cname=$(get_course_name "$cid")
                
                case $result in
                    0)
                        echo "课程添加成功。"
                        write_log "教师 $operator_id 为学生 $stu_id 添加课程：$cid $cname"
                        ;;
                    1) echo "该学生已选择此课程，无需重复添加。" ;;
                    2) echo "添加失败：该课程人数已满。" ;;
                    *) echo "添加失败：数据写入异常。" ;;
                esac
                countdown "即将返回选课管理菜单……"
                ;;
            2)
                if [ -z "$current_courses" ]; then
                    echo "该学生当前没有选课，无法删除。"
                    countdown "即将返回选课管理菜单……"
                    continue
                fi
                
                local cid
                cid=$(read_id "请输入要删除的课程编号：")
                local cname
                cname=$(get_course_name "$cid")
                
                if remove_student_course "$stu_id" "$stu_name" "$cid"; then
                    echo "课程删除成功。"
                    write_log "教师 $operator_id 为学生 $stu_id 删除课程：$cid $cname"
                else
                    echo "该学生未选择此课程，无法删除。"
                fi
                countdown "即将返回选课管理菜单……"
                ;;
            3)
                if [ -z "$current_courses" ]; then
                    echo "该学生当前没有选课，无需清空。"
                    countdown "即将返回选课管理菜单……"
                    continue
                fi
                
                echo "警告：清空后该学生所有已选课程都将被取消！"
                local confirm
                read -r -p "确认要一键清空该学生的所有选课吗？(y/n): " confirm
                if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
                    clear_student_all_courses "$stu_id" "$stu_name"
                    echo "所有选课已清空。"
                    write_log "教师 $operator_id 清空学生 $stu_id 的所有选课"
                else
                    echo "已取消清空操作。"
                fi
                countdown "即将返回选课管理菜单……"
                ;;
            4)
                echo "返回选课管理菜单"
                return
                ;;
        esac
    done
}

course_select_manage_menu() {
    local current_tea_id=$1
    while true; do
        clear
        echo ""
        echo "------------------------- 选课管理 --------------------------"
        echo "｜                    1、查询课程选课名单                   ｜"
        echo "｜                    2、修改学生选课信息                   ｜"
        echo "｜                    3、返回上级菜单                       ｜"
        echo "-------------------------------------------------------------"
        local choice
        choice=$(read_int "请输入功能序号：" 1 3)
        case $choice in
            1) teacher_query_course_students ;;
            2)
                local stu_id
                stu_id=$(read_id "请输入学生学号：")
                if ! grep -q "^$stu_id|" "$STUDENT_FILE"; then
                    echo "未找到该学生。"
                    countdown "即将返回选课管理菜单……"
                else
                    local stu_name
                    stu_name=$(get_student_name "$stu_id")
                    teacher_modify_student_course_menu "$stu_id" "$stu_name" "$current_tea_id"
                fi
                ;;
            3) echo "返回教师主菜单"; return ;;
        esac
    done
}

teacher_query_course_students() {
    clear
    local course_id
    course_id=$(read_id "请输入要查询的课程编号：")
    if ! grep -q "^$course_id|" "$COURSE_FILE"; then
        echo "未找到该课程，查询失败"
        countdown "即将返回选课管理菜单……"
        return
    fi
    
    local course_name count max
    course_name=$(get_course_name "$course_id")
    count=$(get_course_count "$course_id")
    max=$(get_course_max "$course_id")
    
    echo ""
    echo "==================== 课程 $course_id $course_name 选课学生名单（共 $count/$max 人）===================="
    print_student_table_header
    
    awk -F'|' -v cid="$course_id" '$3 ~ cid {print $0}' "$STUDENT_FILE" | while IFS='|' read -r sid sname courses; do
        local pass_status
        pass_status=$(get_passwd_status_text "$STUDENT_PASSWD_FILE" "$sid")
        printf "%-8s %-12s %-30s %-10s\n" "$sid" "$sname" "$courses" "$pass_status"
    done
    
    write_log "教师查询课程 $course_id 的选课学生名单"
    echo ""
    pause
}

# ---------- 教师主菜单 ----------
teacher_menu() {
    local tea_id=$1
    local tea_name
    tea_name=$(get_teacher_name "$tea_id")
    
    write_log "教师 $tea_id($tea_name) 登录系统"
    
    # 初始密码安全提示
    if is_default_passwd "$TEACHER_PASSWD_FILE" "$tea_id"; then
        echo ""
        echo "⚠️  安全提示：您正在使用初始密码，建议尽快修改以保障账号安全"
        sleep 1
    fi
    
    while true; do
        clear
        echo ""
        echo "----------------- 欢迎使用选课管理系统（教师）-----------------"
        echo "｜                    1、课程管理                            ｜"
        echo "｜                    2、学生管理                            ｜"
        echo "｜                    3、教师管理                            ｜"
        echo "｜                    4、选课管理                            ｜"
        echo "｜                    5、教师退出系统                        ｜"
        echo "---------------------------------------------------------------"
        local choice
        choice=$(read_int "请输入功能序号：" 1 5)
        case $choice in
            1) course_manage_menu ;;
            2) student_manage_menu "$tea_id" ;;
            3) teacher_manage_menu "$tea_id" ;;
            4) course_select_manage_menu "$tea_id" ;;
            5)
                echo "退出教师系统，返回主菜单"
                write_log "教师 $tea_id($tea_name) 退出登录"
                countdown "即将返回系统主菜单……"
                return
                ;;
        esac
    done
}

# ===================== 系统主菜单 =====================
main_menu() {
    while true; do
        clear
        echo ""
        echo "-------------------- 欢迎使用选课管理系统 ----------------------"
        echo "｜                   1、学生身份登录系统                      ｜"
        echo "｜                   2、教师身份登录系统                      ｜"
        echo "｜                   3、退出选课管理系统                      ｜"
        echo "----------------------------------------------------------------"
        local choice
        choice=$(read_int "请输入功能序号：" 1 3)
        case $choice in
            1)
                local stu_id
                stu_id=$(read_id "请输入学生学号：")
                if ! verify_student_id "$stu_id"; then
                    echo "登录失败，未找到该学号对应的学生账号"
                    write_log "登录失败：学生学号 $stu_id 不存在"
                    countdown "即将返回主菜单……"
                    continue
                fi
                
                local stu_pass
                stu_pass=$(read_passwd "请输入登录密码：" 1)
                if ! verify_passwd "$STUDENT_PASSWD_FILE" "$stu_id" "$stu_pass"; then
                    echo "登录失败，密码错误"
                    write_log "登录失败：学生 $stu_id 密码错误"
                    countdown "即将返回主菜单……"
                    continue
                fi
                
                echo "登录成功，欢迎学生 $stu_id"
                countdown "即将进入学生系统……"
                student_menu "$stu_id"
                ;;
            2)
                local tea_id
                tea_id=$(read_id "请输入教师工号：")
                if ! verify_teacher_id "$tea_id"; then
                    echo "登录失败，未找到该工号对应的教师账号"
                    write_log "登录失败：教师工号 $tea_id 不存在"
                    countdown "即将返回主菜单……"
                    continue
                fi
                
                local tea_pass
                tea_pass=$(read_passwd "请输入登录密码：" 1)
                if ! verify_passwd "$TEACHER_PASSWD_FILE" "$tea_id" "$tea_pass"; then
                    echo "登录失败，密码错误"
                    write_log "登录失败：教师 $tea_id 密码错误"
                    countdown "即将返回主菜单……"
                    continue
                fi
                
                echo "登录成功，欢迎教师 $tea_id"
                countdown "即将进入教师系统……"
                teacher_menu "$tea_id"
                ;;
            3)
                echo "退出学生选课系统，感谢使用"
                write_log "系统正常退出"
                countdown "即将退出系统……"
                exit 0
                ;;
        esac
    done
}

# ===================== 程序入口 =====================
prepare_environment
main_menu

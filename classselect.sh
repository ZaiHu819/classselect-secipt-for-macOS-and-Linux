#! /bin/bash

# 学生选课管理系统
# 纯文件化数据存储，所有资源限定在 classselect 目录内
# 兼容 macOS / Linux 系统

# ===================== 平台检测（条件编译式跨平台处理）=====================
# 功能：自动识别操作系统，识别失败则由用户手动选择，适配不同系统的命令差异
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

# ===================== 全局配置（所有路径均限定在工作目录内）=====================
detect_os

# 工作目录与数据文件路径
WORK_DIR="$HOME/Desktop/classselect"
LOG_DIR="$WORK_DIR/log"
STUDENT_FILE="$WORK_DIR/学生信息.txt"
TEACHER_FILE="$WORK_DIR/教师信息.txt"
COURSE_FILE="$WORK_DIR/课程信息.txt"
SYSTEM_LOG="$LOG_DIR/system.log"
USER_LOG="$LOG_DIR/user.log"

# 跨平台 sed 原地编辑参数兼容
if [ "$OS_TYPE" = "macOS" ]; then
    SED_INPLACE=(-i '')
else
    SED_INPLACE=(-i)
fi

# ===================== 通用工具函数 =====================
# 功能：读取指定范围内的整数，非法输入循环重输
# 参数：提示语 最小值 最大值
read_int() {
    local prompt="$1"
    local min="$2"
    local max="$3"
    local input
    while true; do
        read -r -p "$prompt" input
        if ! [[ "$input" =~ ^[0-9]+$ ]]; then
            echo "输入错误，请输入有效数字。"
        elif [ "$input" -lt "$min" ] || [ "$input" -gt "$max" ]; then
            echo "输入超出范围，请输入 $min 到 $max 之间的数字。"
        else
            echo "$input"
            return 0
        fi
    done
}

# 功能：读取字符串，可设置是否允许为空
# 参数：提示语 是否允许空（1允许，0不允许，默认0）
read_str() {
    local prompt="$1"
    local allow_empty="${2:-0}"
    local input
    while true; do
        read -r -p "$prompt" input
        if [ -z "$input" ] && [ "$allow_empty" -eq 0 ]; then
            echo "输入不能为空，请重新输入。"
        else
            echo "$input"
            return 0
        fi
    done
}

# 功能：暂停程序，等待用户按回车继续
pause() {
    read -r -p "按回车键继续..." input
}

# ===================== 表格输出函数（统一格式，可复用）=====================
# 功能：打印课程信息表格表头
print_course_table_header() {
    printf "%-10s %-22s %-10s\n" "课程编号" "课程名称" "选课人数"
    echo "---------------------------------------------"
}

# 功能：打印单条课程信息行
print_course_table_row() {
    local cid=$1
    local cname=$2
    local count=$3
    printf "%-10s %-22s %-10d\n" "$cid" "$cname" "$count"
}

# 功能：打印学生信息表格表头
print_student_table_header() {
    printf "%-8s %-12s %-30s\n" "学号" "姓名" "所选课程"
    echo "--------------------------------------------------------"
}

# 功能：打印单条学生信息行
print_student_table_row() {
    local sid=$1
    local sname=$2
    local courses=$3
    printf "%-8s %-12s %-30s\n" "$sid" "$sname" "${courses:-未选课}"
}

# 功能：打印教师信息表格表头
print_teacher_table_header() {
    printf "%-8s %-12s\n" "工号" "姓名"
    echo "--------------------"
}

# 功能：打印单条教师信息行
print_teacher_table_row() {
    local tid=$1
    local tname=$2
    printf "%-8s %-12s\n" "$tid" "$tname"
}

# 功能：打印学生个人选课列表表头
print_my_course_header() {
    printf "%-10s %-22s\n" "课程编号" "课程名称"
    echo "------------------------------"
}

# ===================== 日志与数据同步核心函数 =====================
# 功能：写入带时间戳的系统操作日志
write_log() {
    local log_msg=$1
    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] $log_msg" >> "$SYSTEM_LOG"
}

# 功能：同步单条学生记录到文件（覆盖式更新）
sync_student_record() {
    local stu_id=$1
    local stu_name=$2
    local course=$3
    sed -E "${SED_INPLACE[@]}" "s/^${stu_id}\|.*\|.*$/${stu_id}|${stu_name}|${course}/" "$STUDENT_FILE"
}

# 功能：同步单条课程记录到文件（覆盖式更新）
sync_course_record() {
    local course_id=$1
    local course_name=$2
    local count=$3
    sed -E "${SED_INPLACE[@]}" "s/^${course_id}\|.*\|.*$/${course_id}|${course_name}|${count}/" "$COURSE_FILE"
}

# 功能：同步单条教师记录到文件（覆盖式更新）
sync_teacher_record() {
    local tea_id=$1
    local tea_name=$2
    sed -E "${SED_INPLACE[@]}" "s/^${tea_id}\|.*$/${tea_id}|${tea_name}/" "$TEACHER_FILE"
}

# 功能：根据课程号获取课程名称
get_course_name() {
    local cid=$1
    grep "^${cid}|" "$COURSE_FILE" | awk -F'|' '{print $2}'
}

# 功能：根据课程号获取当前选课人数
get_course_count() {
    local cid=$1
    grep "^${cid}|" "$COURSE_FILE" | awk -F'|' '{print $3}'
}

# 功能：更新单门课程的选课人数
# 参数：课程号 增量(+1/-1)
update_course_count() {
    local cid=$1
    local delta=$2
    local cname
    cname=$(get_course_name "$cid")
    local old_count
    old_count=$(get_course_count "$cid")
    local new_count=$((old_count + delta))
    sync_course_record "$cid" "$cname" "$new_count"
}

# ===================== 选课操作底层通用函数（学生/教师复用）=====================
# 功能：给指定学生添加一门课程，操作后立即同步学生文件与课程人数
# 参数：学号 学生姓名 课程编号
# 返回：0成功 1失败（已选该课程）
add_student_course() {
    local stu_id=$1
    local stu_name=$2
    local cid=$3
    
    # 获取学生当前选课列表
    local current_courses
    current_courses=$(grep "^${stu_id}|" "$STUDENT_FILE" | awk -F'|' '{print $3}')
    
    # 校验是否已选该课程
    if [ -n "$current_courses" ]; then
        IFS=',' read -ra arr <<< "$current_courses"
        for c in "${arr[@]}"; do
            if [ "$c" = "$cid" ]; then
                return 1
            fi
        done
    fi
    
    # 拼接新的选课列表
    local new_courses
    if [ -z "$current_courses" ]; then
        new_courses="$cid"
    else
        new_courses="${current_courses},${cid}"
    fi
    
    # 双文件垂直同步
    sync_student_record "$stu_id" "$stu_name" "$new_courses"
    update_course_count "$cid" 1
    return 0
}

# 功能：给指定学生移除一门课程，操作后立即同步学生文件与课程人数
# 参数：学号 学生姓名 课程编号
# 返回：0成功 1失败（未选该课程）
remove_student_course() {
    local stu_id=$1
    local stu_name=$2
    local cid=$3
    
    # 获取学生当前选课列表
    local current_courses
    current_courses=$(grep "^${stu_id}|" "$STUDENT_FILE" | awk -F'|' '{print $3}')
    if [ -z "$current_courses" ]; then
        return 1
    fi
    
    # 遍历移除目标课程
    local found=0
    local new_courses=""
    IFS=',' read -ra arr <<< "$current_courses"
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
    
    # 双文件垂直同步
    sync_student_record "$stu_id" "$stu_name" "$new_courses"
    update_course_count "$cid" -1
    return 0
}

# 功能：清空指定学生的所有选课，操作后立即同步学生文件与所有相关课程人数
# 参数：学号 学生姓名
clear_student_all_courses() {
    local stu_id=$1
    local stu_name=$2
    
    # 获取学生当前选课列表
    local current_courses
    current_courses=$(grep "^${stu_id}|" "$STUDENT_FILE" | awk -F'|' '{print $3}')
    if [ -z "$current_courses" ]; then
        return 0
    fi
    
    # 所有关联课程人数-1
    IFS=',' read -ra arr <<< "$current_courses"
    for c in "${arr[@]}"; do
        [ -z "$c" ] && continue
        update_course_count "$c" -1
    done
    
    # 同步学生文件
    sync_student_record "$stu_id" "$stu_name" ""
    return 0
}

# ===================== 系统环境初始化 =====================
# 功能：创建工作目录、初始化数据文件、配置定时任务，仅首次启动创建初始数据
prepare_environment() {
    echo ""
    echo "===== 系统正在初始化，请稍候 ====="

    echo "步骤A：查看当前工作目录"
    pwd
    echo ""

    echo "步骤B：初始化工作目录与日志目录"
    mkdir -p "$WORK_DIR"
    mkdir -p "$LOG_DIR"
    cd "$WORK_DIR" || { echo "错误：无法进入工作目录"; exit 1; }
    echo "工作目录已设置：$(pwd)"
    echo "日志目录已设置：$LOG_DIR"
    echo ""

    echo "步骤C：初始化数据文件（仅首次启动创建，不覆盖已有数据）"
    
    # 学生信息格式：学号|姓名|所选课程(逗号分隔)
    if [ ! -f "$STUDENT_FILE" ]; then
        cat > "$STUDENT_FILE" << 'EOF'
001|student1|
002|student2|
003|student3|
EOF
        echo "学生信息文件创建完成，预存3条初始数据"
        write_log "系统初始化：创建学生信息文件，预存3条数据"
    else
        echo "学生信息文件已存在，读取历史数据"
    fi

    # 教师信息格式：工号|姓名
    if [ ! -f "$TEACHER_FILE" ]; then
        cat > "$TEACHER_FILE" << 'EOF'
T01|teacher1
T02|teacher2
EOF
        echo "教师信息文件创建完成，预存2条初始数据"
        write_log "系统初始化：创建教师信息文件，预存2条数据"
    else
        echo "教师信息文件已存在，读取历史数据"
    fi

    # 课程信息格式：课程号|课程名称|选课人数
    if [ ! -f "$COURSE_FILE" ]; then
        cat > "$COURSE_FILE" << 'EOF'
C01|计算机导论|0
C02|C语言程序设计|0
C03|数据结构|0
C04|操作系统|0
C05|计算机网络|0
C06|数据库原理|0
C07|Python编程|0
C08|Java编程|0
C09|人工智能|0
C10|软件工程|0
EOF
        echo "课程信息文件创建完成，预存10条初始数据"
        write_log "系统初始化：创建课程信息文件，预存10条数据"
    else
        echo "课程信息文件已存在，读取历史数据"
    fi
    echo ""

    echo "步骤D：配置定时任务"
    local cron_task="0 12 * * * who >> $USER_LOG"
    if ! crontab -l 2>/dev/null | grep -F "who >> $USER_LOG" >/dev/null 2>&1; then
        (crontab -l 2>/dev/null; echo "$cron_task") | crontab -
        echo "定时任务配置完成：每日12点记录登录用户至 $USER_LOG"
        write_log "系统初始化：配置每日12点用户登录日志定时任务"
    else
        echo "定时任务已存在，无需重复配置"
    fi

    echo "===== 系统初始化完成 ====="
    write_log "系统启动完成，进入主菜单"
    echo ""
}

# ===================== 身份验证函数 =====================
# 功能：验证学生账号是否存在
verify_student() {
    local username=$1
    grep -q "|$username|" "$STUDENT_FILE"
    return $?
}

# 功能：验证教师账号是否存在
verify_teacher() {
    local username=$1
    grep -q "|$username|" "$TEACHER_FILE"
    return $?
}

# ===================== 学生功能模块 =====================
# 功能：学生添加选课程子菜单，每次添加实时同步文件
student_add_course_menu() {
    local username=$1
    local stu_id
    stu_id=$(grep "|$username|" "$STUDENT_FILE" | awk -F'|' '{print $1}')
    
    while true; do
        echo ""
        echo "===== 添加选课 ====="
        print_course_table_header
        awk -F'|' '{printf "%-10s %-22s %-10d\n", $1, $2, $3}' "$COURSE_FILE"
        echo "-----------------------------"
        echo "1、输入课程编号添加选课"
        echo "2、返回选课管理菜单"
        
        local choice
        choice=$(read_int "请输入选项：" 1 2)
        case $choice in
            1)
                local cid
                cid=$(read_str "请输入要添加的课程编号：")
                # 校验课程是否存在
                if ! grep -q "^${cid}|" "$COURSE_FILE"; then
                    echo "课程编号不存在，请重新输入。"
                    pause
                    continue
                fi
                # 执行添加
                if add_student_course "$stu_id" "$username" "$cid"; then
                    local cname
                    cname=$(get_course_name "$cid")
                    echo "选课添加成功：$cid $cname"
                    write_log "学生 $username 添加选课：$cid $cname"
                else
                    echo "你已选择该课程，无需重复添加。"
                fi
                pause
                ;;
            2)
                echo "返回选课管理菜单"
                return
                ;;
        esac
    done
}

# 功能：学生修改选课子菜单（单条退课+一键清空），操作实时同步文件
student_modify_course_menu() {
    local username=$1
    local stu_id
    stu_id=$(grep "|$username|" "$STUDENT_FILE" | awk -F'|' '{print $1}')
    
    while true; do
        # 实时读取并打印当前选课表格
        local current_courses
        current_courses=$(grep "^${stu_id}|" "$STUDENT_FILE" | awk -F'|' '{print $3}')
        
        echo ""
        echo "===== 修改我的选课 ====="
        print_my_course_header
        if [ -z "$current_courses" ]; then
            echo "你还没有选课哦"
        else
            IFS=',' read -ra c_arr <<< "$current_courses"
            for cid in "${c_arr[@]}"; do
                [ -z "$cid" ] && continue
                local cname
                cname=$(get_course_name "$cid")
                printf "%-10s %-22s\n" "$cid" "$cname"
            done
        fi
        echo "------------------------"
        echo "1、输入课程编号退课"
        echo "2、一键清空所有选课"
        echo "3、取消修改并返回"
        
        local choice
        choice=$(read_int "请输入选项：" 1 3)
        case $choice in
            1)
                # 单条退课逻辑
                local cid
                cid=$(read_str "请输入要退课的课程编号：")
                
                # 校验是否已选该课程
                local found=0
                if [ -n "$current_courses" ]; then
                    IFS=',' read -ra arr <<< "$current_courses"
                    for c in "${arr[@]}"; do
                        if [ "$c" = "$cid" ]; then
                            found=1
                            break
                        fi
                    done
                fi
                
                if [ $found -eq 0 ]; then
                    echo "你没有选择该课程，无法退课。"
                    pause
                    continue
                fi
                
                # 二次确认
                local cname
                cname=$(get_course_name "$cid")
                read -r -p "确认要退选课程 $cid $cname 吗？(y/n): " confirm
                if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
                    remove_student_course "$stu_id" "$username" "$cid"
                    echo "退课成功，课程已移除。"
                    write_log "学生 $username 退课：$cid $cname"
                else
                    echo "已取消退课操作。"
                fi
                pause
                ;;
            2)
                # 一键清空逻辑
                if [ -z "$current_courses" ]; then
                    echo "你当前没有选课，无需清空。"
                    pause
                    continue
                fi
                
                echo "警告：清空后所有已选课程都将被取消，操作不可恢复！"
                read -r -p "确认要一键清空所有选课吗？(y/n): " confirm
                if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
                    clear_student_all_courses "$stu_id" "$username"
                    echo "所有选课已清空。"
                    write_log "学生 $username 一键清空所有选课"
                else
                    echo "已取消清空操作。"
                fi
                pause
                ;;
            3)
                echo "取消修改，返回选课管理菜单"
                return
                ;;
        esac
    done
}

# 功能：学生选课管理主入口，整合添加、修改、返回功能
student_course_manage() {
    local username=$1
    local stu_id
    stu_id=$(grep "|$username|" "$STUDENT_FILE" | awk -F'|' '{print $1}')
    
    while true; do
        # 实时读取并展示当前选课状态
        local current_courses
        current_courses=$(grep "^${stu_id}|" "$STUDENT_FILE" | awk -F'|' '{print $3}')
        
        echo ""
        echo "===== 我的选课情况 ====="
        print_my_course_header
        if [ -z "$current_courses" ]; then
            echo "你还没有选课哦"
        else
            IFS=',' read -ra c_arr <<< "$current_courses"
            for cid in "${c_arr[@]}"; do
                [ -z "$cid" ] && continue
                local cname
                cname=$(get_course_name "$cid")
                printf "%-10s %-22s\n" "$cid" "$cname"
            done
        fi
        echo "------------------------"
        
        echo "1、添加选课"
        echo "2、修改/退课"
        echo "3、返回学生菜单"
        
        local choice
        choice=$(read_int "请输入选项：" 1 3)
        case $choice in
            1)
                student_add_course_menu "$username"
                ;;
            2)
                student_modify_course_menu "$username"
                ;;
            3)
                echo "返回学生菜单"
                return
                ;;
        esac
    done
}

# 功能：学生查看实时课程选课状态（所有课程的选课人数），可跳转选课管理
student_view_course_status() {
    local username=$1
    echo ""
    echo "===== 实时课程选课状态 ====="
    print_course_table_header
    awk -F'|' '{printf "%-10s %-22s %-10d\n", $1, $2, $3}' "$COURSE_FILE"
    echo "-----------------------------"
    echo "1、返回学生菜单"
    echo "2、跳转到选课管理"
    
    local choice
    choice=$(read_int "请输入选项：" 1 2)
    case $choice in
        1) 
            echo "返回学生菜单"
            return
            ;;
        2)
            student_course_manage "$username"
            return
            ;;
    esac
}

# 功能：学生查看个人信息与选课信息
student_view_info() {
    local username=$1
    local stu_info
    stu_info=$(grep "|$username|" "$STUDENT_FILE")
    local stu_id stu_name course_id
    stu_id=$(echo "$stu_info" | awk -F'|' '{print $1}')
    stu_name=$(echo "$stu_info" | awk -F'|' '{print $2}')
    course_id=$(echo "$stu_info" | awk -F'|' '{print $3}')

    echo ""
    echo "===== 学生个人信息 ====="
    print_student_table_header
    print_student_table_row "$stu_id" "$stu_name" "$course_id"
    
    write_log "学生 $username 查看个人信息"
    echo ""
    pause
}

# 功能：学生功能主菜单
student_menu() {
    local username=$1
    write_log "学生 $username 登录系统"
    while true; do
        echo ""
        echo "-----------------欢迎使用学生选课系统（学生）------------------"
        echo "｜                  1、选课管理                            ｜"
        echo "｜                  2、查看实时选课状态                     ｜"
        echo "｜                  3、查看个人信息                         ｜"
        echo "｜                  4、学生退出系统                         ｜"
        echo "-----------------------------------------------------------"
        local choice
        choice=$(read_int "请输入功能序号：" 1 4)

        case $choice in
            1) student_course_manage "$username" ;;
            2) student_view_course_status "$username" ;;
            3) student_view_info "$username" ;;
            4)
                echo "退出学生系统，返回主菜单"
                write_log "学生 $username 退出登录"
                break
                ;;
        esac
    done
}

# ===================== 教师功能模块 =====================
# ---------- 课程管理子模块 ----------
# 功能：课程管理子菜单
course_manage_menu() {
    while true; do
        echo ""
        echo "-----------------------课程管理-------------------------"
        echo "｜                  1、添加课程                        ｜"
        echo "｜                  2、删除课程                        ｜"
        echo "｜                  3、修改课程                        ｜"
        echo "｜                  4、查询课程                        ｜"
        echo "｜                  5、返回上级菜单                     ｜"
        echo "-------------------------------------------------------"
        local choice
        choice=$(read_int "请输入功能序号：" 1 5)

        case $choice in
            1) teacher_add_course ;;
            2) teacher_delete_course ;;
            3) teacher_update_course ;;
            4) teacher_query_course ;;
            5) echo "返回教师主菜单"; break ;;
        esac
    done
}

# 功能：教师添加新课程
teacher_add_course() {
    local course_id
    course_id=$(read_str "请输入新课程编号：")
    if grep -q "^$course_id|" "$COURSE_FILE"; then
        echo "该课程编号已存在，添加失败"
        pause
        return
    fi

    local course_name
    course_name=$(read_str "请输入新课程名称：")

    echo "${course_id}|${course_name}|0" >> "$COURSE_FILE"
    echo "课程添加成功："
    print_course_table_header
    print_course_table_row "$course_id" "$course_name" 0
    write_log "教师添加课程：$course_id $course_name"
    echo ""
    pause
}

# 功能：教师删除课程，同步清空学生选课记录
teacher_delete_course() {
    echo ""
    echo "当前课程列表："
    print_course_table_header
    awk -F'|' '{printf "%-10s %-22s %-10d\n", $1, $2, $3}' "$COURSE_FILE"
    echo ""

    local course_id
    course_id=$(read_str "请输入要删除的课程编号：")
    if ! grep -q "^$course_id|" "$COURSE_FILE"; then
        echo "未找到对应课程，删除失败"
        pause
        return
    fi

    local course_name
    course_name=$(get_course_name "$course_id")
    # 删除课程记录
    sed "${SED_INPLACE[@]}" "/^${course_id}|/d" "$COURSE_FILE"
    # 同步清空所有学生的该课程选课记录
    sed -E "${SED_INPLACE[@]}" "s/,${course_id}//g" "$STUDENT_FILE"
    sed -E "${SED_INPLACE[@]}" "s/^([^|]*|[^|]*|)${course_id},/\1/" "$STUDENT_FILE"
    sed -E "${SED_INPLACE[@]}" "s/^([^|]*|[^|]*|)${course_id}$/\1/" "$STUDENT_FILE"

    echo "课程 $course_id $course_name 删除成功，学生对应选课记录已同步清空"
    write_log "教师删除课程：$course_id"
    pause
}

# 功能：教师修改课程名称
teacher_update_course() {
    local course_id
    course_id=$(read_str "请输入要修改的课程编号：")
    if ! grep -q "^$course_id|" "$COURSE_FILE"; then
        echo "未找到对应课程，修改失败"
        pause
        return
    fi

    local old_name old_count
    old_name=$(get_course_name "$course_id")
    old_count=$(get_course_count "$course_id")

    echo "当前课程信息："
    print_course_table_header
    print_course_table_row "$course_id" "$old_name" "$old_count"
    
    local new_name
    new_name=$(read_str "请输入新课程名称（回车保持不变）：" 1)
    [ -z "$new_name" ] && new_name="$old_name"

    sync_course_record "$course_id" "$new_name" "$old_count"
    echo "课程信息修改成功，更新后："
    print_course_table_header
    print_course_table_row "$course_id" "$new_name" "$old_count"
    write_log "教师修改课程：$course_id 名称从 $old_name 改为 $new_name"
    echo ""
    pause
}

# 功能：教师查询所有课程信息
teacher_query_course() {
    echo ""
    echo "===== 课程信息统计 ====="
    print_course_table_header
    awk -F'|' '{printf "%-10s %-22s %-10d\n", $1, $2, $3}' "$COURSE_FILE"
    write_log "教师查询全部课程信息"
    echo ""
    pause
}

# ---------- 学生管理子模块 ----------
# 功能：学生管理子菜单
student_manage_menu() {
    while true; do
        echo ""
        echo "----------------------学生管理--------------------------"
        echo "｜                  1、添加学生                        ｜"
        echo "｜                  2、删除学生                        ｜"
        echo "｜                  3、修改学生                        ｜"
        echo "｜                  4、查询学生                        ｜"
        echo "｜                  5、返回上级菜单                     ｜"
        echo "-------------------------------------------------------"
        local choice
        choice=$(read_int "请输入功能序号：" 1 5)

        case $choice in
            1) teacher_add_student ;;
            2) teacher_delete_student ;;
            3) teacher_update_student ;;
            4) teacher_query_student ;;
            5) echo "返回教师主菜单"; break ;;
        esac
    done
}

# 功能：教师添加新学生账号
teacher_add_student() {
    local stu_id
    stu_id=$(read_str "请输入新学生学号：")
    if grep -q "^$stu_id|" "$STUDENT_FILE"; then
        echo "该学号已存在，添加失败"
        pause
        return
    fi

    local stu_name
    stu_name=$(read_str "请输入新学生姓名：")
    if grep -q "|$stu_name|" "$STUDENT_FILE"; then
        echo "该学生姓名已存在，添加失败"
        pause
        return
    fi

    echo "${stu_id}|${stu_name}|" >> "$STUDENT_FILE"
    echo "学生添加成功："
    print_student_table_header
    print_student_table_row "$stu_id" "$stu_name" ""
    write_log "教师添加学生：学号 $stu_id，姓名 $stu_name"
    echo ""
    pause
}

# 功能：教师删除学生账号，同步更新课程选课人数
teacher_delete_student() {
    local stu_id
    stu_id=$(read_str "请输入要删除的学生学号：")
    if ! grep -q "^$stu_id|" "$STUDENT_FILE"; then
        echo "未找到该学生，删除失败"
        pause
        return
    fi

    local course_id
    course_id=$(grep "^$stu_id|" "$STUDENT_FILE" | awk -F'|' '{print $3}')
    local stu_name
    stu_name=$(grep "^$stu_id|" "$STUDENT_FILE" | awk -F'|' '{print $2}')
    
    # 同步减少对应课程的选课人数
    if [ -n "$course_id" ]; then
        IFS=',' read -ra c_arr <<< "$course_id"
        for cid in "${c_arr[@]}"; do
            [ -z "$cid" ] && continue
            update_course_count "$cid" -1
        done
    fi

    sed "${SED_INPLACE[@]}" "/^${stu_id}|/d" "$STUDENT_FILE"
    echo "学生 $stu_id $stu_name 删除成功"
    write_log "教师删除学生：学号 $stu_id"
    pause
}

# 功能：教师修改学生基本信息
teacher_update_student() {
    local stu_id
    stu_id=$(read_str "请输入要修改的学生学号：")
    if ! grep -q "^$stu_id|" "$STUDENT_FILE"; then
        echo "未找到该学生，修改失败"
        pause
        return
    fi

    local old_name old_course
    old_name=$(grep "^$stu_id|" "$STUDENT_FILE" | awk -F'|' '{print $2}')
    old_course=$(grep "^$stu_id|" "$STUDENT_FILE" | awk -F'|' '{print $3}')

    echo "当前学生信息："
    print_student_table_header
    print_student_table_row "$stu_id" "$old_name" "$old_course"
    
    local new_name
    new_name=$(read_str "请输入新姓名（回车保持不变）：" 1)
    [ -z "$new_name" ] && new_name="$old_name"

    sync_student_record "$stu_id" "$new_name" "$old_course"
    echo "学生信息修改成功，更新后："
    print_student_table_header
    print_student_table_row "$stu_id" "$new_name" "$old_course"
    write_log "教师修改学生：学号 $stu_id 姓名从 $old_name 改为 $new_name"
    echo ""
    pause
}

# 功能：教师查询所有学生信息
teacher_query_student() {
    echo ""
    echo "===== 学生信息统计 ====="
    print_student_table_header
    awk -F'|' '{printf "%-8s %-12s %-30s\n", $1, $2, ($3==""?"未选课":$3)}' "$STUDENT_FILE"
    write_log "教师查询全部学生信息"
    echo ""
    pause
}

# ---------- 教师管理子模块 ----------
# 功能：教师管理子菜单，传入当前登录教师名，禁止修改自己
teacher_manage_menu() {
    local current_user=$1
    while true; do
        echo ""
        echo "----------------------教师管理--------------------------"
        echo "｜                  1、添加教师                        ｜"
        echo "｜                  2、删除教师                        ｜"
        echo "｜                  3、修改教师                        ｜"
        echo "｜                  4、查询教师                        ｜"
        echo "｜                  5、返回上级菜单                    ｜"
        echo "------------------------------------------------------"
        local choice
        choice=$(read_int "请输入功能序号：" 1 5)

        case $choice in
            1) teacher_add_teacher "$current_user" ;;
            2) teacher_delete_teacher "$current_user" ;;
            3) teacher_update_teacher "$current_user" ;;
            4) teacher_query_teacher ;;
            5) echo "返回教师主菜单"; break ;;
        esac
    done
}

# 功能：教师添加新教师账号
teacher_add_teacher() {
    local current_user=$1
    local tea_id
    tea_id=$(read_str "请输入新教师工号：")
    if grep -q "^$tea_id|" "$TEACHER_FILE"; then
        echo "该工号已存在，添加失败"
        pause
        return
    fi

    local tea_name
    tea_name=$(read_str "请输入新教师姓名：")
    if grep -q "|$tea_name|" "$TEACHER_FILE"; then
        echo "该教师姓名已存在，添加失败"
        pause
        return
    fi

    echo "${tea_id}|${tea_name}" >> "$TEACHER_FILE"
    echo "教师添加成功："
    print_teacher_table_header
    print_teacher_table_row "$tea_id" "$tea_name"
    write_log "教师 $current_user 添加账号：工号 $tea_id，姓名 $tea_name"
    echo ""
    pause
}

# 功能：教师删除教师账号，禁止删除自己
teacher_delete_teacher() {
    local current_user=$1
    local tea_id
    tea_id=$(read_str "请输入要删除的教师工号：")
    if ! grep -q "^$tea_id|" "$TEACHER_FILE"; then
        echo "未找到该教师，删除失败"
        pause
        return
    fi

    local tea_name
    tea_name=$(grep "^$tea_id|" "$TEACHER_FILE" | awk -F'|' '{print $2}')
    if [ "$tea_name" = "$current_user" ]; then
        echo "不能删除自己的账号，请选择其他教师。"
        pause
        return
    fi

    sed "${SED_INPLACE[@]}" "/^${tea_id}|/d" "$TEACHER_FILE"
    echo "教师 $tea_id $tea_name 删除成功"
    write_log "教师 $current_user 删除账号：工号 $tea_id"
    pause
}

# 功能：教师修改教师信息，禁止修改自己
teacher_update_teacher() {
    local current_user=$1
    local tea_id
    tea_id=$(read_str "请输入要修改的教师工号：")
    if ! grep -q "^$tea_id|" "$TEACHER_FILE"; then
        echo "未找到该教师，修改失败"
        pause
        return
    fi

    local old_name
    old_name=$(grep "^$tea_id|" "$TEACHER_FILE" | awk -F'|' '{print $2}')
    if [ "$old_name" = "$current_user" ]; then
        echo "不能修改自己的账号信息，请选择其他教师。"
        pause
        return
    fi

    echo "当前教师信息："
    print_teacher_table_header
    print_teacher_table_row "$tea_id" "$old_name"
    
    local new_name
    new_name=$(read_str "请输入新姓名（回车保持不变）：" 1)
    [ -z "$new_name" ] && new_name="$old_name"

    sync_teacher_record "$tea_id" "$new_name"
    echo "教师信息修改成功，更新后："
    print_teacher_table_header
    print_teacher_table_row "$tea_id" "$new_name"
    write_log "教师 $current_user 修改账号：工号 $tea_id 姓名从 $old_name 改为 $new_name"
    echo ""
    pause
}

# 功能：教师查询所有教师信息
teacher_query_teacher() {
    echo ""
    echo "===== 教师信息统计 ====="
    print_teacher_table_header
    awk -F'|' '{printf "%-8s %-12s\n", $1, $2}' "$TEACHER_FILE"
    write_log "教师查询全部教师信息"
    echo ""
    pause
}

# ---------- 选课管理子模块 ----------
# 功能：教师修改学生选课子菜单（单条增删+一键清空），复用底层函数，操作实时同步
teacher_modify_student_course_menu() {
    local stu_id=$1
    local stu_name=$2
    local operator=$3
    
    while true; do
        # 实时读取并打印学生当前选课
        local current_courses
        current_courses=$(grep "^${stu_id}|" "$STUDENT_FILE" | awk -F'|' '{print $3}')
        
        echo ""
        echo "===== 学生 $stu_id $stu_name 选课管理 ====="
        print_my_course_header
        if [ -z "$current_courses" ]; then
            echo "该学生暂未选课"
        else
            IFS=',' read -ra c_arr <<< "$current_courses"
            for cid in "${c_arr[@]}"; do
                [ -z "$cid" ] && continue
                local cname
                cname=$(get_course_name "$cid")
                printf "%-10s %-22s\n" "$cid" "$cname"
            done
        fi
        echo "----------------------------------------"
        echo "1、为学生添加课程"
        echo "2、删除指定课程（退课）"
        echo "3、一键清空所有选课"
        echo "4、返回选课管理菜单"
        
        local choice
        choice=$(read_int "请输入选项：" 1 4)
        case $choice in
            1)
                # 添加课程
                echo ""
                echo "可选课程列表："
                print_course_table_header
                awk -F'|' '{printf "%-10s %-22s %-10d\n", $1, $2, $3}' "$COURSE_FILE"
                echo ""
                
                local cid
                cid=$(read_str "请输入要添加的课程编号：")
                if ! grep -q "^${cid}|" "$COURSE_FILE"; then
                    echo "课程编号不存在。"
                    pause
                    continue
                fi
                
                if add_student_course "$stu_id" "$stu_name" "$cid"; then
                    local cname
                    cname=$(get_course_name "$cid")
                    echo "课程添加成功。"
                    write_log "教师 $operator 为学生 $stu_id 添加课程：$cid $cname"
                else
                    echo "该学生已选择此课程，无需重复添加。"
                fi
                pause
                ;;
            2)
                # 删除指定课程
                local cid
                cid=$(read_str "请输入要删除的课程编号：")
                if remove_student_course "$stu_id" "$stu_name" "$cid"; then
                    local cname
                    cname=$(get_course_name "$cid")
                    echo "课程删除成功。"
                    write_log "教师 $operator 为学生 $stu_id 删除课程：$cid $cname"
                else
                    echo "该学生未选择此课程，无法删除。"
                fi
                pause
                ;;
            3)
                # 一键清空
                if [ -z "$current_courses" ]; then
                    echo "该学生当前没有选课，无需清空。"
                    pause
                    continue
                fi
                
                echo "警告：清空后该学生所有已选课程都将被取消！"
                read -r -p "确认要一键清空该学生的所有选课吗？(y/n): " confirm
                if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
                    clear_student_all_courses "$stu_id" "$stu_name"
                    echo "所有选课已清空。"
                    write_log "教师 $operator 清空学生 $stu_id 的所有选课"
                else
                    echo "已取消清空操作。"
                fi
                pause
                ;;
            4)
                echo "返回选课管理菜单"
                return
                ;;
        esac
    done
}

# 功能：选课管理子菜单
course_select_manage_menu() {
    local current_user=$1
    while true; do
        echo ""
        echo "----------------------选课管理-------------------------"
        echo "｜              1、查询课程选课名单                     ｜"
        echo "｜              2、修改学生选课信息                     ｜"
        echo "｜              3、返回上级菜单                        ｜"
        echo "-----------------------------------------------------"
        local choice
        choice=$(read_int "请输入功能序号：" 1 3)

        case $choice in
            1) teacher_query_course_students ;;
            2)
                local stu_id
                stu_id=$(read_str "请输入学生学号：")
                if ! grep -q "^$stu_id|" "$STUDENT_FILE"; then
                    echo "未找到该学生。"
                    pause
                else
                    local stu_name
                    stu_name=$(grep "^$stu_id|" "$STUDENT_FILE" | awk -F'|' '{print $2}')
                    teacher_modify_student_course_menu "$stu_id" "$stu_name" "$current_user"
                fi
                ;;
            3) echo "返回教师主菜单"; break ;;
        esac
    done
}

# 功能：教师查询单门课程的选课学生名单
teacher_query_course_students() {
    local course_id
    course_id=$(read_str "请输入要查询的课程编号：")
    if ! grep -q "^$course_id|" "$COURSE_FILE"; then
        echo "未找到该课程，查询失败"
        pause
        return
    fi

    local course_name count
    course_name=$(get_course_name "$course_id")
    count=$(get_course_count "$course_id")

    echo ""
    echo "===== 课程 $course_id $course_name 选课学生名单（共 $count 人）====="
    print_student_table_header
    awk -F'|' -v cid="$course_id" '$3 ~ cid {printf "%-8s %-12s %-30s\n", $1, $2, $3}' "$STUDENT_FILE"
    write_log "教师查询课程 $course_id 的选课学生名单"
    echo ""
    pause
}

# ---------- 教师主菜单 ----------
# 功能：教师功能主菜单，传入当前登录教师名
teacher_menu() {
    local username=$1
    write_log "教师 $username 登录系统"
    while true; do
        echo ""
        echo "---------------欢迎使用学生选课系统（教师）--------------------"
        echo "｜                  1、课程管理                            ｜"
        echo "｜                  2、学生管理                            ｜"
        echo "｜                  3、教师管理                            ｜"
        echo "｜                  4、选课管理                            ｜"
        echo "｜                  5、教师退出系统                        ｜"
        echo "----------------------------------------------------------"
        local choice
        choice=$(read_int "请输入功能序号：" 1 5)

        case $choice in
            1) course_manage_menu ;;
            2) student_manage_menu ;;
            3) teacher_manage_menu "$username" ;;
            4) course_select_manage_menu "$username" ;;
            5)
                echo "退出教师系统，返回主菜单"
                write_log "教师 $username 退出登录"
                break
                ;;
        esac
    done
}

# ===================== 系统主菜单 =====================
# 功能：系统入口主菜单，选择登录身份
main_menu() {
    while true; do
        echo ""
        echo "------------------欢迎使用学生选课系统----------------------"
        echo "｜                1、学生身份登录系统                      ｜"
        echo "｜                2、教师身份登录系统                      ｜"
        echo "｜                3、退出学生选课系统                      ｜"
        echo "---------------------------------------------------------"
        local choice
        choice=$(read_int "请输入功能序号：" 1 3)

        case $choice in
            1)
                local stu_name
                stu_name=$(read_str "请输入学生用户名：")
                if verify_student "$stu_name"; then
                    echo "登录成功，欢迎学生 $stu_name"
                    student_menu "$stu_name"
                else
                    echo "登录失败，未找到该学生账号"
                    write_log "登录失败：学生账号 $stu_name 不存在"
                fi
                ;;
            2)
                local tea_name
                tea_name=$(read_str "请输入教师用户名：")
                if verify_teacher "$tea_name"; then
                    echo "登录成功，欢迎教师 $tea_name"
                    teacher_menu "$tea_name"
                else
                    echo "登录失败，未找到该教师账号"
                    write_log "登录失败：教师账号 $tea_name 不存在"
                fi
                ;;
            3)
                echo "退出学生选课系统，感谢使用"
                write_log "系统正常退出"
                exit 0
                ;;
        esac
    done
}

# ===================== 程序入口 =====================
prepare_environment
main_menu

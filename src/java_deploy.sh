#!/bin/bash

# ===================================== 参数定义 =====================================

app_name=$app_name
app_path=$APP_PATH/$app_name
app_env=$app_env
app_port=$app_port
host_ip=$(hostname -I | awk -F " " '{print $1}')
docker_image=$docker_image
check_times=$check_times
JAVA_OPTS=$JAVA_OPTS
docker_run_memory=$DOCKER_RUN_MEMORY
docker_stop_time=$DOCKER_STOP_TIME
app_down_sleep=$APP_DOWN_SLEEP

DEFAULT_DOCKER_IMAGE=$DEFAULT_DOCKER_IMAGE

# 参数校验

if [[ ! "${app_docker_name}" ]]; then
    app_docker_name=$app_env-$app_name;
fi

if [[ ! ${docker_stop_time} ]]; then
    docker_stop_time=10;
fi

if [[ ! ${docker_image} ]]; then
    docker_image=${DEFAULT_DOCKER_IMAGE}
fi

# ===================================== 函数定义 =====================================

function log() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') $@"
}

# 安装 curl 命令
function install_curl() {
    dpkg -l | grep curl &>/dev/null
    if [ $? -ne 0 ]; then
        sudo apt install -y curl
    fi
}

# 启动检查
function check_startup() {
    sleep 10s
    install_curl
    check_times=0
      up_success=0
      while [ "$check_times" -le "$1" ];
      do
          check_times=$(expr $check_times + 1)
          check_code=$(curl -I -m 10 -o /dev/null -s -w %{http_code} localhost:$app_port)
          if [ $check_code -ne 000 ]; then
              log "$host_ip 服务器: $app_name 应用启动成功"
                up_success=1
                break
          else
              log "第 $check_times 次 $host_ip 服务器: $app_name 应用启动检测 $check_code"
              sleep 10s
          fi
      done

      if [ $up_success -eq 0 ]; then
          log "$host_ip 服务器: $app_name 应用发布失败"
          return 0
      fi
      return 1
}

# ===================================== 流程处理 =====================================

# 解压
log "查找.jar文件"

app_jar_file=$app_path/app.jar
cd ${app_path}/

# 寻找jar包, 复制当前目录下
find ./ -maxdepth 5 -name "*.jar" -type f | xargs -i {} cp -rf {} ${app_path}/
# 排除source.jar
find ./ -name "*-sources.jar" -type f | xargs -i {} rm -rf {}

jar_num=$(find ./ -maxdepth 1 -name "*.jar" -type f | wc -l);
if [ "$jar_num" -gt 1 ]; then
    log "解压构建包异常! 包含多个jar文件!";
    exit 1;
fi
find ./ -maxdepth 5 -name "*.jar" -type f | xargs -i {} cp -rf {} ${app_jar_file}

# 处理docker -e
str_docker_e=""

# 处理docker -m
if [[ ${docker_run_memory} || ${docker_run_memory} != "0m" ]]; then
    log "${app_docker_name} 容器配置使用内存: ${docker_run_memory}"
    str_docker_e="$str_docker_e -m ${docker_run_memory}"
fi

# 处理java启动
java_start="java ${JAVA_OPTS} -Dspring.profiles.active=${app_env} -jar ${app_jar_file}";

log "容器环境变量配置: \n${str_docker_e}"
log "容器使用镜像: \n${docker_image}"
log "Java启动命令: \n${java_start}"

# 停止docker服务
docker stop --time=${docker_stop_time} ${app_docker_name}
docker rm ${app_docker_name}
log "${app_docker_name} 旧容器删除成功!"

# 启动docker
docker run --cap-add=SYS_PTRACE -d --log-opt max-size=512m --log-opt max-file=10 --restart=on-failure:3 --network host \
    --name ${app_docker_name} --mount type=bind,source=${app_path},target=${app_path} \
    -v /home/opoa/run/data/${app_name}/:/home/opoa/run/data/ \
    -v /home/logs/${app_name}/:/home/opoa/logs/ \
    ${str_docker_e} \
    ${docker_image} \
    ${java_start}

log "${app_docker_name} 启动中..."
# 判断是否启动成功, 失败返回
check_startup ${check_times}
if [ $? -eq 0 ]; then
    exit 1;
else
    sleep 3;
fi

log "$host_ip 服务器: ${app_docker_name} 应用发布完成"
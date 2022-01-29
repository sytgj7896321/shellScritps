#!/bin/bash
#Author shiyitao@sheca.com
#定义function
function echoe () {
  echo -e "\033[34;1m$1\033[0m"
}

function echoen () {
  echo -e -n "\033[34;1m$1\033[0m"
}

function package_test () {
  package="$1"
  package_dir="$(tar -ztf $package 2>/dev/null|head -1)"
  if [ "$?" != 0 ];then
    echoe "包$package解压失败，请确认文件完整性，退出脚本"
    rm -rf "${package_dir%/*}" &>/dev/null
    exit 1
  fi
}

function install_zookeeper () {
  tar -zxf "$zookeeper" -C /usr/local/
  mv "/usr/local/${zookeeper%.tar.gz}" /usr/local/apache-zookeeper
  init_zookeeper
  start_service 'zookeeper'
}

function init_zookeeper () {
  mkdir -p /data/apache/zookeeper;chown -R root:root /data/apache/zookeeper
  chown -R root:root /usr/local/apache-zookeeper
  mv /usr/local/apache-zookeeper/conf/zoo_sample.cfg /usr/local/apache-zookeeper/conf/zoo.cfg
  #修改配置文件
  sed -i 's/^dataDir.*/dataDir=\/data\/apache\/zookeeper/g' /usr/local/apache-zookeeper/conf/zoo.cfg
  if [ "$cluster_mode" == "yes" ]
    then
      for i in "${!cluster_addr[@]}"
        do
          cluster_addr_jointed="${cluster_addr_jointed}server.${i}=${cluster_addr[${i}]}:2888:3888\n"
      done
      sed -i '/^clientPort/a '$cluster_addr_jointed'' /usr/local/apache-zookeeper/conf/zoo.cfg
      unset cluster_addr_jointed
      echo "$postion" > /data/apache/zookeeper/myid
  fi
  #创建systemd脚本并添加环境变量
  cat <<SYSTEMD> /usr/lib/systemd/system/zookeeper.service
[Unit]
Description=Zookeeper Server
After=network-online.target
Wants=network-online.target

[Service]
Type=forking
SuccessExitStatus=143
WorkingDirectory=/usr/local/apache-zookeeper
Environment="JAVA_HOME=$jdk_path"
ExecStart=/usr/local/apache-zookeeper/bin/zkServer.sh start /usr/local/apache-zookeeper/conf/zoo.cfg
ExecStop=/usr/local/apache-zookeeper/bin/zkServer.sh stop
ExecReload=/usr/local/apache-zookeeper/bin/zkServer.sh restart
PIDFile=/data/apache/zookeeper/zookeeper_server.pid
TimeoutSec=30s

[Install]
WantedBy=multi-user.target
SYSTEMD
  echoe "\033[35mzookeeper\033[34;1m的systemd管理脚本已创建"
  sleep 1
}

function install_kafka () {
  tar -zxf "$kafka" -C /usr/local/
  mv "/usr/local/${kafka%.tgz}" /usr/local/apache-kafka
  init_kafka
  start_service 'kafka'
}

function init_kafka () {
  chown -R root:root /usr/local/apache-kafka
  #修改配置文件
  echo "delete.topic.enable=true" >> /usr/local/apache-kafka/config/server.properties
  sed -i 's/-server -XX:+UseG1GC/-server -XX:+UnlockExperimentalVMOptions -XX:+UseG1GC/g' /usr/local/apache-kafka/bin/kafka-run-class.sh
  sed -i 's/^log\.dirs=.*/log\.dirs=\.\/kafka-logs/g' /usr/local/apache-kafka/config/server.properties
  sed -i 's/^zookeeper\.connect=.*/zookeeper\.connect=localhost:2181\/kafka/g' /usr/local/apache-kafka/config/server.properties
  if [ "$cluster_mode" == "yes" ]
    then
      for i in "${cluster_addr[@]}"
        do
          cluster_addr_jointed="${cluster_addr_jointed}${i}:2181,"
      done
      cluster_addr_jointed="zookeeper.connect=${cluster_addr_jointed%,}/kafka"
      cluster_addr_jointed="${cluster_addr_jointed//./\\.}"
      cluster_addr_jointed="${cluster_addr_jointed//\//\\/}"
      sed -i 's/^zookeeper\.connect=.*/'$cluster_addr_jointed'/g' /usr/local/apache-kafka/config/server.properties
      sed -i 's/^broker\.id.*/broker\.id='$postion'/g' /usr/local/apache-kafka/config/server.properties
      sed -i '/^#listeners=.*/a listeners=PLAINTEXT:\/\/'${cluster_addr[$postion]}':9092' /usr/local/apache-kafka/config/server.properties
      sed -i '/^#advertised\.listeners=.*/a advertised\.listeners=PLAINTEXT:\/\/'${cluster_addr[$postion]}':9092' /usr/local/apache-kafka/config/server.properties
      sed -i 's/^num\.partitions=.*/num\.partitions='${#cluster_addr[@]}'/g' /usr/local/apache-kafka/config/server.properties
      sed -i 's/^offsets\.topic\.replication\.factor=.*/offsets\.topic\.replication\.factor='${#cluster_addr[@]}'/g' /usr/local/apache-kafka/config/server.properties
      sed -i '/^num\.partitions=.*/a default.replication.factor='${#cluster_addr[@]}'' /usr/local/apache-kafka/config/server.properties
  fi
  #创建systemd脚本并添加环境变量
  cat <<SYSTEMD> /usr/lib/systemd/system/kafka.service
[Unit]
Description=Kafka Server
After=network-online.target zookeeper.service
Wants=network-online.target zookeeper.service

[Service]
Type=exec
SuccessExitStatus=143
WorkingDirectory=/usr/local/apache-kafka
Environment="JAVA_HOME=$jdk_path"
ExecStart=/usr/local/apache-kafka/bin/kafka-server-start.sh /usr/local/apache-kafka/config/server.properties
TimeoutSec=30s

[Install]
WantedBy=multi-user.target
SYSTEMD
  echoe "\033[35mkafka\033[34;1m的systemd管理脚本已创建"
  sleep 1
}

function start_service () {
  service="$1"
  echoe "开始启动\033[35m$service"
  sleep 1
  systemctl daemon-reload
  systemctl enable "$service" &>/dev/null
  systemctl start "$service"
  if [ "$?" != 0 ]
    then
      echoe "\033[35m$service\033[34;1m启动失败，请排查原因"
      systemctl status "$service" -l
      exit 1
  else
    OLD_IFS=$IFS
    IFS=$'\n'
    echoe "\033[35m$service\033[34;1m服务已启动，并已经设置开机自启"
    declare -a array
    array=($(systemctl status $service -l))
    array[0]="$(echo -n ${array[0]}|sed 's/●/\\033[32;1m●\\033[0m/g')"
    array[2]="$(echo -n ${array[2]}|sed 's/active (running)/\\033[32;1mactive (running)\\033[0m/g')"
    for i in "${!array[@]}"
      do
        echo -e "${array[$i]}"
    done
    IFS=$OLD_IFS
  fi
  sleep 1
}

function check_ip_addr () {
  ckStep1=`echo $1 | awk -F"." '{print NF}'`
  if [ "$ckStep1" -eq 4 ]
    then
      ckStep2=`echo $1 | awk -F"." '{if ($1!=0 && $NF!=0) split ($0,IPNUM,".")} END \
        { for (k in IPNUM) if (IPNUM[k]==0) print IPNUM[k]; else if (IPNUM[k]!=0 && IPNUM[k]!~/[a-z|A-Z]/ && length(IPNUM[k])<=3 &&
IPNUM[k]<255 && IPNUM[k]!~/^0/) print IPNUM[k]}'| wc -l`
      if [ "$ckStep2" -eq "$ckStep1" ]
      then
              echo 0
      else
              echo 1
      fi
  else
    echo 1
  fi
}

#检测用户
if [ "$UID" != 0 ]
  then
    echoe "请使用root用户执行该脚本！！！"
    exit 1
fi

cluster_mode=no
cluster_mode=no
declare -a cluster_addr
declare -i postion
while getopts "c:p:h" arg
do
  case "$arg" in
       c)
          cluster_mode=yes
          cluster_addr=($OPTARG)
          for i in "${cluster_addr[@]}"
          do
            check_result="$(check_ip_addr $i)"
            if [ "$check_result" -eq 1 ]
              then
                echoe "存在非法ip地址，请检查你的参数"
                echoe "退出脚本"
                exit 1
            fi
          done
          ;;
       p)
          postion="$OPTARG"
          ;;
       h)
          echoe "帮助："
          echoe "-c 开启集群安装模式\n   用法：例如-c '192.168.123.100 192.168.123.101 192.168.123.102'，单引号不可省略，ip为集群所有节点的ip，用空格间隔，并且在不同节点上执行脚本时，ip传入顺序不可打乱\033[35m（指定-c执行脚本时必须同时指定-p的参数）"
          echoe "-p 标识本节点ip在-c所指定参数中的位置，起始位置为0\n   用法：例如本机ip为192.168.123.100，在-c指定参数中的位置是0，那传-p 0即可\033[35m（指定-p执行脚本时必须同时指定-c的参数）"
          exit 0
          ;;
       ?)
          exit 1
          ;;
  esac
done

if [[ "$cluster_addr" != "" && "$postion" == "" ]] || [[ "$postion" != "" && "$cluster_addr" == "" ]]
  then
    echoe "请同时指定-c和-p的参数"
    echoe "退出脚本"
    exit 1 
fi

#检测jdk是否已经安装
jdk_path="$(echo $JAVA_HOME)"
if [ "$jdk_path" == "" ]
  then
    jdk_path="$(grep -w -o 'JAVA_HOME=.*' /etc/profile|tail -1|awk '{print $1}')";jdk_path="${jdk_path#JAVA_HOME=}"
    if [ "$jdk_path" == "" ]
      then
        jdk_path="$(realpath -P $(which java 2>/dev/null) 2>/dev/null)";jdk_path="${jdk_path%/bin/java}"
        if [ "$jdk_path" == "" ]
          then
            echoe "未检测到Java运行环境，请先运行jdk安装脚本"
            exit 1
        fi
    fi
fi

#检测是否安装
if [ -f '/usr/lib/systemd/system/zookeeper.service' ]
  then
    echoe "检测到zookeeper服务已安装"
    sleep 1
    if [ -f '/usr/lib/systemd/system/kafka.service' ]
      then
        echoe "检测到kafka服务已安装"
        echoe "退出脚本"
        exit 1
    else
      #安装kafka
      kafka="$(ls kafka_*.tgz 2>/dev/null|sort -Vr|awk 'NR == 1')"
      package_test "$kafka"
      if [ "$cluster_mode" == "yes" ]
      then
        echoe "开始以集群模式安装\033[35mkafka"
      else
        echoe "开始安装\033[35mkafka"
      fi
      install_kafka
    fi
else
  #安装zookeeper
  zookeeper="$(ls apache-zookeeper-*-bin.tar.gz 2>/dev/null|sort -Vr|awk 'NR == 1')"
  package_test "$zookeeper"
  if [ "$cluster_mode" == "yes" ]
    then
      echoe "开始以集群模式安装\033[35mzookeeper"
  else
    echoe "开始安装\033[35mzookeeper"
  fi
  install_zookeeper
  
  #安装kafka
  kafka="$(ls kafka_*.tgz 2>/dev/null|sort -Vr|awk 'NR == 1')"
  package_test "$kafka"
  if [ "$cluster_mode" == "yes" ]
    then
      echoe "开始以集群模式安装\033[35mkafka"
  else
    echoe "开始安装\033[35mkafka"
  fi
  install_kafka
fi


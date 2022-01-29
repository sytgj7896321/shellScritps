#!/bin/bash
#Author shiyitao@sheca.com
#定义function
function echoe () {
  echo -e "\033[34;1m$1\033[0m"
}

function echoen () {
  echo -e -n "\033[34;1m$1\033[0m"
}

function srtc () {
  bao="${1%.tar.gz}"
  rm -rf "$bao" 2>/dev/null
  tar zxf "$bao".tar.gz 2>/dev/null
  if [ "$?" != 0 ];then
    echoe "$2包解压失败，请确认文件完整性，退出脚本"
    exit 1
  else
    cd "$bao"
  fi
}

function test_network () {
  echoe "开始检测与$2连通性，用时在半分钟以内，请稍等..."
  declare -i loop=8
  declare -i count=0
  while [ "$((loop--))" != 0 ]
  do
    return_code=`timeout 4 curl -I -o /dev/null -s -w %{http_code} "$1"`
    if [[ "$return_code" == "200" || "$return_code" == "301" ]]; then
      count=count+1
    fi
  done
  if [ "$count" -gt 0 ]; then
    echoe "与$2连通性检测\033[35m通过"
  else
    echoe "与$2连通\033[35m失败\033[34;1m，退出安装脚本"
    exit 1
  fi
}

function change_repo () {
  mv /etc/yum.repos.d/CentOS-Base.repo /etc/yum.repos.d/CentOS-Base.repo.bbbaaakkk &>/dev/null
  cat <<'CENTOS_REPO'> /etc/yum.repos.d/CentOS-Base.repo
# CentOS-Base.repo
#
# The mirror system uses the connecting IP address of the client and the
# update status of each mirror to pick mirrors that are updated to and
# geographically close to the client.  You should use this for CentOS updates
# unless you are manually picking other mirrors.
#
# If the mirrorlist= does not work for you, as a fall back you can try the
# remarked out baseurl= line instead.
#
#

[base]
name=CentOS-$releasever - Base
#mirrorlist=http://mirrorlist.centos.org/?release=$releasever&arch=$basearch&repo=os&infra=$infra
baseurl=https://mirror.tuna.tsinghua.edu.cn/centos/$releasever/os/$basearch/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7

#released updates
[updates]
name=CentOS-$releasever - Updates
#mirrorlist=http://mirrorlist.centos.org/?release=$releasever&arch=$basearch&repo=updates&infra=$infra
baseurl=https://mirror.tuna.tsinghua.edu.cn/centos/$releasever/updates/$basearch/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7

#additional packages that may be useful
[extras]
name=CentOS-$releasever - Extras
#mirrorlist=http://mirrorlist.centos.org/?release=$releasever&arch=$basearch&repo=extras&infra=$infra
baseurl=https://mirror.tuna.tsinghua.edu.cn/centos/$releasever/extras/$basearch/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7

#additional packages that extend functionality of existing packages
[centosplus]
name=CentOS-$releasever - Plus
#mirrorlist=http://mirrorlist.centos.org/?release=$releasever&arch=$basearch&repo=centosplus&infra=$infra
baseurl=https://mirror.tuna.tsinghua.edu.cn/centos/$releasever/centosplus/$basearch/
gpgcheck=1
enabled=0
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7
CENTOS_REPO
}

function recover_repo () {
  rm -f '/etc/yum.repos.d/CentOS-Base.repo'
  mv /etc/yum.repos.d/CentOS-Base.repo.bbbaaakkk /etc/yum.repos.d/CentOS-Base.repo &>/dev/null
}

function init_redis () {
#创建配置文件
declare -i space=`cat /proc/meminfo |grep MemTotal|awk '{print $2}'`/20*9*1024

cp -p ./redis.conf /usr/local/redis/etc/redis.conf
sed -i 's/^daemonize no/daemonize yes/g' /usr/local/redis/etc/redis.conf
sed -i 's/^supervised no/supervised systemd/g' /usr/local/redis/etc/redis.conf
sed -i 's/^bind 127.0.0.1/bind 0.0.0.0/g' /usr/local/redis/etc/redis.conf
sed -i 's/^dir \.\//dir \/data\/redis/g' /usr/local/redis/etc/redis.conf
sed -i 's/^# maxmemory <bytes>/maxmemory '"$space"'/g' /usr/local/redis/etc/redis.conf
sed -i 's/^# maxmemory-policy noeviction/maxmemory-policy allkeys-lru/g' /usr/local/redis/etc/redis.conf
if [ "$1" == "cluster" ]
  then
  sed -i 's/^# cluster-enabled yes/cluster-enabled yes/g' /usr/local/redis/etc/redis.conf
fi

echoe "已配置Redis可使用内存为最大内存\033[35m45%"
sleep 1

#创建systemd脚本并添加环境变量
cat <<'SYSTEMD'> /usr/lib/systemd/system/redis.service
[Unit]
Description=redis
After=network.target
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
User=redis
Group=redis
ExecStart=/usr/local/redis/bin/redis-server /usr/local/redis/etc/redis.conf --supervised systemd
ExecStop=/usr/local/redis/bin/redis-cli -h 127.0.0.1 -p 6379 shutdown

[Install]
WantedBy=multi-user.target
SYSTEMD
echoe "Redis的systemd管理脚本已创建"
sleep 1

cat <<'PROFILE'>> /etc/profile
REDIS=/usr/local/redis/bin
PATH=$PATH:$REDIS
export PATH
PROFILE
echo -e "\033[34;1mRedis环境变量已添加，重新登录后或手动执行\033[35msource /etc/profile\033[34;1m立即生效\033[0m"
sleep 1
}

function create_slave () {
  #复制并修改配置文件
  if ! test -s /usr/local/redis/etc/redis2.conf;then
    mkdir -p /data/redis2
    chown redis:redis /data/redis2
    cp -p /usr/local/redis/etc/redis.conf /usr/local/redis/etc/redis2.conf
    sed -i 's/^port.*/port 6380/g' /usr/local/redis/etc/redis2.conf
    sed -i 's/^dir.*/dir \/data\/redis2/g' /usr/local/redis/etc/redis2.conf
    sed -i 's/^pidfile.*/pidfile \/var\/run\/redis_6380\.pid/g' /usr/local/redis/etc/redis2.conf
    sed -i 's/^cluster-config-file.*/cluster-config-file nodes-6380\.conf/g' /usr/local/redis/etc/redis2.conf
    #创建slave的systemd脚本
    cat <<'SYSTEMD'> /usr/lib/systemd/system/redis2.service
[Unit]
Description=redis2
After=network.target
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
User=redis
Group=redis
ExecStart=/usr/local/redis/bin/redis-server /usr/local/redis/etc/redis2.conf --supervised systemd
ExecStop=/usr/local/redis/bin/redis-cli -h 127.0.0.1 -p 6380 shutdown

[Install]
WantedBy=multi-user.target
SYSTEMD
echoe "Redis2的systemd管理脚本已创建"
  else
    echoe "Redis2的服务已存在，退出安装脚本"
    exit 1
  fi
sleep 1
}

function install_redis () {
  echoe "开始安装Redis"
  srtc "$version" "Redis源码"
  sleep 2
  make
  if [ "$?" != 0 ]
    then
      echoe "编译失败，退出脚本，请排查原因"
      exit 1
  fi
  make install PREFIX='/usr/local/redis'
  echoe "Redis安装成功"
  init_redis "$1"
  systemctl daemon-reload
  systemctl enable redis 1>/dev/null 2>&1
  systemctl start redis
  if [ "$?" != 0 ]
    then
      echoe "Redis启动失败，请排查原因"
      systemctl status redis -l
      exit 1
  else  
    echoe "Redis服务已启动，并已经设置开机自启"
    systemctl status redis -l
  fi
}
function download_package () {  
  declare -i d_count=1
  while [ "$d_count" -ne 0 ];do
    curl -C - -o "$1".part "$3"
    if [ "$?" != 0 ];then
      echoe "$2下载失败"
      if [ "$((d_count%3))" -eq 0 ];then
        echoen "总计已经尝试下载\033[35m$d_count\033[34;1m次，是否继续尝试？（直接回车继续，输入任意值回车退出）:"
        read d_choice
        if [ "$d_choice" == "" ];then
          echoen "好的，继续"
        else
          exit 1
        fi
      fi
      echoe "尝试断点续传"
      d_count=d_count+1
    else
      echoe "$2下载完成"
      mv "$1".part "$1"
      d_count=0
    fi
  done
}

#检测用户
if [ "$UID" != 0 ]
  then
    echoe "请使用root用户执行该脚本！！！"
    exit 1
fi

#检测redis是否已经安装
if [ "$1" != "create_slave" ]
  then
    pid=`ps -ef|grep -v grep|grep redis-server|awk '{print $2}'`
    redis-server -v 1>/dev/null 2>&1
    if [[ "$?" == 0 || "$pid" != "" || -x '/usr/local/redis/bin/redis-server' ]]
    then
      echoe "Redis服务已存在，退出安装脚本"
      exit 1
  fi
else
  create_slave
  systemctl daemon-reload
  systemctl enable redis2 1>/dev/null 2>&1
  systemctl start redis2
  if [ "$?" != 0 ]
    then
      echoe "Redis2启动失败，请排查原因"
      systemctl status redis2 -l
      exit 1
  else  
    echoe "Redis2服务已启动，并已经设置开机自启"
    systemctl status redis2 -l
    exit 0
  fi
fi

#创建redis用户和redis落地目录
user=`compgen -u | grep -w 'redis'`
if [ -z "$user" ]
  then
    useradd -d '/var/lib/redis' -s '/sbin/nologin' -c 'Redis Database Server' redis
fi
mkdir -p '/data/redis'
chown redis:redis '/data/redis'

#判断gcc是否安装
domain='mirror.tuna.tsinghua.edu.cn'
gcc -v 1>/dev/null 2>&1
if [ "$?" != 0 ];then
  echoe "未找到gcc，开始尝试从离线RPM包安装gcc"
  sleep 2
  zgcc=`ls gcc-*.tar.gz 2> /dev/null|sort -Vr|awk 'NR == 1'`
  if test -s "$zgcc"
    then
      srtc "$zgcc" "gcc安装"
      yum localinstall -y *.rpm
      if [ "$?" != 0 ] 
        then
          echoe "gcc安装失败，请排查原因"
          exit 1
      else
        echoe "gcc安装成功" && cd ..
      fi
  else
    echoe "gcc离线RPM包不存在，开始尝试在线安装gcc"
    sleep 2
    test_network "$domain" "国内镜像源"
    change_repo
    sleep 2
    yum install -y --disablerepo=* --enablerepo=base --enablerepo=updates --enablerepo=extras gcc systemd-devel
    if [ "$?" != 0 ]
      then
        echoe "gcc安装失败，请排查原因"
        recover_repo
        exit 1
    else
      echoe "gcc安装成功" 
      recover_repo
      sleep 1
    fi
  fi
fi

#安装redis
mkdir -p '/usr/local/redis/etc'
domain='download.redis.io'
install_version="redis-6.2.6.tar.gz"
version=`ls redis-*.tar.gz 2> /dev/null|sort -Vr|awk 'NR == 1'`
if ! test -s "$version";then
  echoe "本地未找到Redis源码包，开始尝试下载Redis源码包到本地"
  test_network "$domain" "Redis官方源码仓库"
  download_package "$install_version" "Redis源码包" "http://$domain/releases/$install_version"
  version=`ls redis-*.tar.gz 2> /dev/null|sort -Vr|awk 'NR == 1'`
  install_redis "$1"
else
  install_redis "$1"
fi


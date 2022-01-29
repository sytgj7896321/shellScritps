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

function init_config () {
  echoe "变更MySQL数据存放目录到\033[35m/data/mysql"
  mkdir '/data/mysql' -p
  chown mysql:mysql /data/mysql
  cat <<'MYSQL_CONFIG'> /etc/my.cnf
[mysql]
default-character-set=utf8mb4
[mysqld]
datadir=/data/mysql
socket=/var/lib/mysql/mysql.sock
symbolic-links=0
log-error=/var/log/mysqld.log
pid-file=/var/run/mysqld/mysqld.pid
max_connections=4096
character-set-server=utf8mb4
collation-server=utf8mb4_general_ci
MYSQL_CONFIG
}

function init_mysql () {
password_init=`grep 'A temporary password is generated for root@localhost:' /var/log/mysqld.log |tail -n 1|awk '{print $NF}'`
echoe "MySQL初始root密码为：\033[35m$password_init"
echoen "请输入MySQL的新root密码，长度最低4位（Crtl+Backspace键删除字符）："
read password_new
while [ "${#password_new}" -lt 4 ]
do
  echoen "请输入长度最低4位的密码！！！："
  read password_new
done
sleep 1

cat <<PASSWORD_INIT> ~/.my.cnf
[mysql]
user=root
password="$password_init"
default-character-set=utf8mb4
PASSWORD_INIT

mysql --connect-expired-password -e "set global validate_password_policy=0; set global validate_password_length=4; alter user 'root'@'localhost' identified by '$password_new';"
echoe "密码修改完毕，新密码：\033[35m$password_new"

cat <<PASSWORD_NEW> ~/.my.cnf
[mysql]
user=root
password="$password_new"
default-character-set=utf8mb4
PASSWORD_NEW

mysql --connect-expired-password -e "create user 'root'@'%' identified by '$password_new'; grant all on *.* TO 'root'@'%'; flush privileges;"
echoe "远程登录root账户已创建，密码同本地账户"
echoe "本地免密登录已设置"
}

#检测用户
if [ "$UID" != 0 ]
  then
    echoe "请使用root用户执行该脚本！！！"
    exit 1
fi

#检测mysql是否已经安装
pid=`ps -ef|grep -v grep|grep mysqld|awk '{print $2}'`
mysqld --version 1>/dev/null 2>&1
if [[ "$?" == "0" || "$pid" != "" || -x '/usr/sbin/mysqld' ]]
  then
    echoe "MySQL数据库已存在，退出安装脚本"
    exit 1
fi

#安装Mysql
setenforce 0 1>/dev/null 2>&1
install_version='5.7.32-1.el7.x86_64.rpm'
domain='mirror.tuna.tsinghua.edu.cn'
version=`ls mysql-*.tar.gz 2> /dev/null|sort -Vr|awk 'NR == 1'`
if test -s "$version"; then
  echoe "开始安装MySQL"
  sleep 1
  srtc "$version" "MySQL安装"
  yum localinstall -y *.rpm
  if [ "$?" != 0 ]; then
    echoe "MySQL安装失败，退出脚本，请排查原因"
    exit 1
  else    
    echoe "MySQL安装完成"
    init_config
    systemctl enable mysqld 1>/dev/null 2>&1
    systemctl start mysqld
    if [ "$?" != 0 ]; then
      echoe "MySQL启动失败，退出脚本，请排查原因"
      exit 1
    else    
      echoe "MySQL已启动，并已设置开机自启"
      systemctl status mysqld -l
      sleep 1
      init_mysql
    fi
  fi
else
  echoe "MySQL本地安装包不存在，开始尝试在线安装"
  test_perl=`perl -v 2>&1>/dev/null|tr -d ' '`;test_perl="${test_perl:0-15}"
  test_netstat=`netstat --version 2>&1>/dev/null|tr -d ' '`;test_netstat="${test_netstat:0-15}"
  test_libaio=`rpm -qa|grep libaio`
  if [[ "$test_perl" == 'commandnotfound' || "$test_netstat" == 'commandnotfound' || "$test_libaio" == "" ]];then
    echoe "检测到未安装MySQL依赖包，一并安装"
    flag=1
  fi
  test_network "$domain" "国内镜像源"
  if [ "$flag" == "1" ];then
    change_repo
  fi
  install_array=(mysql-community-client mysql-community-common mysql-community-libs mysql-community-libs-compat mysql-community-server)
  front_part="${install_version:0:3}";front_part="http://$domain/mysql/yum/mysql-$front_part-community-el7-x86_64"
  yum install -y --disablerepo=* --enablerepo=base --enablerepo=updates --enablerepo=extras \
  "$front_part/${install_array[0]}-$install_version" \
  "$front_part/${install_array[1]}-$install_version" \
  "$front_part/${install_array[2]}-$install_version" \
  "$front_part/${install_array[3]}-$install_version" \
  "$front_part/${install_array[4]}-$install_version"
  if [ "$?" != 0 ]; then
    echoe "MySQL安装失败，退出脚本，请排查原因"
    if [ "$flag" == "1" ];then
      recover_repo
    fi
    exit 1
  else
    echoe "MySQL安装完成"
    if [ "$flag" == "1" ];then
      recover_repo
    fi
    init_config
    systemctl enable mysqld 1>/dev/null 2>&1
    systemctl start mysqld
    if [ "$?" != 0 ]; then
      echoe "MySQL启动失败，退出脚本，请排查原因"
      exit 1
    else    
      echoe "MySQL已启动，并已设置开机自启"
      systemctl status mysqld -l
      sleep 1
      init_mysql
    fi
  fi
fi

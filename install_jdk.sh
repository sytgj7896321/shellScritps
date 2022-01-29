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
  tar -ztf "$package" &>/dev/null
  if [ "$?" != 0 ];then
    echoe "JDK包解压失败，请确认文件完整性，退出脚本"
    tmp="$(tar -ztf $package 2>/dev/null |head -1)"
    rm -rf "${tmp%/*}" &>/dev/null
    exit 1
  fi
}

function change_version () {
  check="$(cat /etc/profile|grep '^JAVA_HOME'|tail -1)"
    if [ "$check" != "" ]; then
      echoen "检测到JDK全局环境变量已存在，是否要更新环境变量指向当前JDK：\033[35m$jdk_dir\033[34;1m Y/N："
      read choose 2>/dev/null
      until [[ "$choose" == "Y" || "$choose" == "N" ]]
      do
        echoen "请输入Y或者N："
        read choose 2>/dev/null
      done
      if [ "$choose" == "Y" ]
        then
          cd /usr/local;ln -snf "$jdk_dir" jdk;cd "$OLDPWD"
          echoe "JDK全局环境变量指向已改变"
          exit 0
      else
        exit 0
      fi
    fi 
}

function quick_change () {
  declare -a array
  show_jdk
  read choose 2>/dev/null
  until [[ "$choose" -gt 0 && "$choose" -le "${#array[@]}" ]] 2>/dev/null
  do
    show_jdk
    read choose 2>/dev/null
  done
  cd /usr/local;ln -snf "${array[$((choose-1))]}" jdk;cd "$OLDPWD"
  echoe "JDK全局环境变量指向已改变"
  exit 0
}

function show_jdk () {
  array=(`ls /usr/local/|grep '^jdk'|grep -wv 'jdk'|xargs`)
  if [ "$array" == "" ]
    then
      echoe "未检测到JDK，退出脚本"
      exit 1
  fi
  for i in "${!array[@]}"
    do
      echoen "$((i+1)) "
      echo -e "\033[35m${array[$i]}\033[0m"
  done
  echoen "请选择要切换到哪个JDK："
}

#检测用户
if [ "$UID" != 0 ]
  then
    echoe "请使用root用户执行该脚本！！！"
    exit 1
fi

#参数处理
fix=no
change_mode=no
jdk="$(ls jdk-*.tar.gz 2> /dev/null|sort -Vr|awk 'NR == 1')"
while getopts "i:cfh" arg
do
  case "$arg" in
       i)
          jdk="$OPTARG"
          ;;
       c)
          change_mode=yes
          ;;
       f)
          echoe "进入JDK修复安装模式"
          fix=yes
          ;;
       h)
          echoe "帮助：" 
          echoe "-i JDK二进制压缩包路径（不用-i指定，脚本会自动查找同一目录下最新的JDK包）"
          echoe "-c 用于快速选择并修改/etc/profile里JAVA_HOME的指向（脚本会自动读取安装到/usr/local下并以'jdk'为前缀的目录）"
          echoe "-f 修复安装模式，适用于已安装完的JDK，文件意外丢失修复（不会覆盖已存在文件）"
          exit 0
          ;;
       ?)
          exit 1
          ;;
  esac
done

if [ "$change_mode" == "yes" ]
  then
    quick_change
fi

#安装jdk
package_test "$jdk"
jdk_dir="$(tar -ztf $jdk |head -1)";jdk_dir="${jdk_dir%/*}"
find_java_home="$(grep -w -o 'JAVA_HOME=.*' /etc/profile|tail -1|awk '{print $1}')";find_java_home="${find_java_home#JAVA_HOME=}";find_java_home="$(realpath $find_java_home 2>/dev/null)"
test_java="$(java -version 2>&1|awk 'NR == 1'|awk '{print $3}')";test_java="${test_java#\"}";test_java="${test_java%\"}"
if [[ "$test_java" == "${jdk_dir#jdk}" || "$(echo $find_java_home|grep $jdk_dir)" || "$(ls /usr/local|grep $jdk_dir)" ]]
  then
    if [ "$fix" == "yes" ]
      then
        tar --skip-old-files -zxf "$jdk" -C /usr/local/ && echoe "JDK：\033[35m$jdk_dir\033[34;1m修复完成" || echoe "JDK：\033[35m$jdk_dir\033[34;1m修复失败"
        exit 0
    else
      echoe "已经安装相同版本JDK"
      change_version
      exit 0
    fi
else
  echoe "开始安装JDK"
  tar -zxf "$jdk" -C "/usr/local/"
  cd /usr/local/;ln -snf "$jdk_dir" jdk;cd "$OLDPWD"
  echoe "JDK安装完成"
  #添加环境变量
  change_version
  cat <<'JAVA_HOME'>> /etc/profile 
#JAVE_HOME
JAVA_HOME=/usr/local/jdk
PATH=$JAVA_HOME/bin:$PATH
export PATH JAVA_HOME
JAVA_HOME
echo -e "\033[34;1mJDK全局环境变量已添加，重新登录后或手动执行\033[35msource /etc/profile\033[34;1m立即生效\033[0m"
fi

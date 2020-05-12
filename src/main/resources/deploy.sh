#!/bin/bash
BASE_PATH=/app
SERVER_ONE_PATH=$BASE_PATH/server1/
SERVER_TWO_PATH=$BASE_PATH/server2/

SERVER_ONE_JAR=server-one-spring.jar
SERVER_TWO_JAR=server-two-spring.jar

TARGET_PORT=8080
TARGET_PROFILE="dev"

BUILD_PATH=$(ls $BASE_PATH/*.jar)
JAR_NAME=$(basename $BUILD_PATH)

echo "> build 파일명: $JAR_NAME"



TARGET_ONE="none"
TARGET_TWO="none"

RES_CODE=$(curl -o /dev/null -w "%{http_code}" "http://localhost:8080")
if [ $RES_CODE -eq 200 ];
then
  echo "OKOK"
  TARGET_ONE="live"
fi


RES_CODE=$(curl -o /dev/null -w "%{http_code}" "http://localhost:8081")
 if [ $RES_CODE -eq 200 ];
  then
   TARGET_TWO="live"
  fi


echo $TARGET


if [ $TARGET_ONE ==  "live" ] && [ $TARGET_TWO == "live" ];
then
 echo "> 둘다 살았음 "
 FIRST_PATH=$SERVER_ONE_PATH
 FIRST_JAR=$SERVER_ONE_JAR
 SECOND_PATH=$SERVER_TWO_PATH
 SECOND_JAR=$SERVER_TWO_JAR
 
 IDLE_PID=$(pgrep -f $FIRST_JAR)
 
 if [ -z $IDLE_PID ]
then
  echo "> 현재 구동중인 애플리케이션이 없으므로 종료하지 않습니다."
else
  echo "> kill -15 $IDLE_PID"
  kill -15 $IDLE_PID
  sleep 5
fi
 
elif [ $TARGET_ONE ==  "live" ] && [ $TARGET_TWO == "none" ];
then
 echo "> 서버 1번만 살아있음 "
 FIRST_PATH=$SERVER_TWO_PATH
 FIRST_JAR=$SERVER_TWO_JAR
 SECOND_PATH=$SERVER_ONE_PATH
 SECOND_JAR=$SERVER_ONE_JAR
 TARGET_PORT=8081
 TARGET_PROFILE="prd"
elif [ $TARGET_ONE == "none" ] && [ $TARGET_TWO == "live" ];
then
 echo "> 서버 2번만 살아있음 "
	FIRST_PATH=$SERVER_ONE_PATH
	FIRST_JAR=$SERVER_ONE_JAR
	SECOND_PATH=$SERVER_TWO_PATH
	SECOND_JAR=$SERVER_TWO_JAR
	TARGET_PORT=8080
	TARGET_PROFILE="dev"
else
 echo "there is no alive server"
	FIRST_PATH=$SERVER_ONE_PATH
	FIRST_JAR=$SERVER_ONE_JAR
	SECOND_PATH=$SERVER_TWO_PATH
	SECOND_JAR=$SERVER_TWO_JAR
	TARGET_PORT=8080
fi

echo "> 첫번째 경로 -> $FIRST_PATH  JAR 명 -> $FIRST_JAR"
echo "> 두번째 경로 -> $SECOND_PATH  JAR 명 -> $SECOND_JAR"

cp -rf *.jar $FIRST_PATH/
mv -f $FIRST_PATH/$JAR_NAME  $FIRST_PATH/$FIRST_JAR
rm -rf $FIRST_PATH/$JAR_NAME

echo "> 첫번째 경로  배포!!  -> $FIRST_PATH  JAR 명 -> $FIRST_JAR"
nohup java -jar -Dspring.profiles.active=$TARGET_PROFILE $FIRST_PATH/$FIRST_JAR &

echo "> 배포 완료 확인 체크 시작"


sleep 10
for retry_count in {1..10}
do
	RES_CODE=$(curl -o /dev/null -w "%{http_code}" "http://localhost:$TARGET_PORT")
	if [ $RES_CODE -eq 200 ];
	then
	  echo "> $FIRST_JAR  배포 완료!!"
	  break
	fi
	
	if [ $retry_count -eq 10 ];
	then
		echo "> Health check 실패. "
		echo "> Nginx에 연결하지 않고 배포를 종료합니다."
		exit 1
	fi
	
	echo "> Health check 연결 실패. 재시도..."
	sleep 10
	
done



if [ $TARGET_PROFILE == "dev" ];
then
	TARGET_PROFILE="prd"
elif [ $TARGET_PROFILE == "prd" ];
then
	TARGET_PROFILE="dev"
fi

IDLE_PID=$(pgrep -f $SECOND_JAR)
 
		 if [ -z $IDLE_PID ]
		then
		  echo "> 현재 구동중인 애플리케이션이 없으므로 종료하지 않습니다."
		else
		  echo "> kill -15 $IDLE_PID"
		  kill -15 $IDLE_PID
		  sleep 5
		fi
	  
		cp -rf *.jar $SECOND_PATH/
		mv -f $SECOND_PATH/$JAR_NAME  $SECOND_PATH/$SECOND_JAR
		rm -rf $SECOND_PATH/$JAR_NAME
		echo "> 두번째 경로  배포!!  -> $SECOND_PATH  JAR 명 -> $SECOND_JAR"
		nohup java -jar -Dspring.profiles.active=$TARGET_PROFILE $SECOND_PATH/$SECOND_JAR &
		
		sleep 10
		
		if [ $TARGET_PORT -eq 8080 ];
		then
			TARGET_PORT=8081
		elif [ $TARGET_PORT -eq 8081 ];
		then
			TARGET_PORT=8080
		fi


sleep 10
for retry_count in {1..10}
do
	RES_CODE=$(curl -o /dev/null -w "%{http_code}" "http://localhost:$TARGET_PORT")
	if [ $RES_CODE -eq 200 ];
	then
	  echo "> $SECOND_JAR  배포 완료!!"
	  break
	fi
	
	if [ $retry_count -eq 10 ];
	then
		echo "> Health check 실패. "
		echo "> Nginx에 연결하지 않고 배포를 종료합니다."
		exit 1
	fi
	
	echo "> Health check 연결 실패. 재시도..."
	sleep 10
	
done




# spring-boot-deploy

## Spring Boot 어플리케이션을 Nginx 를 활용하여 무중단 배포 테스트

무중단 배포 테스트를 위하여 동일 application 에 application.yml 파일을 두개로 구분한다.

JAR 파일 실행은 ``` nohup java -jar -Dspring.profiles.active=profile명 파일명.jar ``` 이렇게 실행한다.

각 profile 마다 서버 port 를 구분한다. 

- application.dev -> server.port : 8080
- application.prd -> server.port : 8081

어떤 profile 로 실행 되었는지 확인하기 위해 RestController 클래스 하나 생성해주자

```java
package com.example.springbootdeploy;

import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.core.env.Environment;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Arrays;

@RestController
@Slf4j
public class HomController {

    @Autowired
    private Environment env;

    @GetMapping("/")
    public String home() {
        return Arrays.stream(env.getActiveProfiles()).findFirst().orElse("");
    }
}

```

루트 도메인을 호출하게 되면 현재 어플리케이션이 실행된 profile 을 response 해주도록 하고 

> dev profile 은 "dev" 가 response 로 가도록, 
> prd profile 은 "prd" 가 response 로 가도록, 

해당 어플리케이션을 JAR 로 패키징하고 서버에 배포후 

nginx 가 설치되어 있는 서버에서 무중단 배포를 위한 스크립트를 하나 만들어보자..

아래 파일은 테스트 용이기에.. 하드코딩이 조금있다..^^;;

무중단 배포를 위한 서버 로드 확인은 HTTP Response Code 로 확인한다..


1. 현재 구동중인 어플리케이션을 확인
2. 한대만 구동중인지, 둘다 구동중인지, 모두 구동중이 아닌지 체크한다.
3. 구동중상태에 따라 처음 배포할 타겟 PATH 와 JAR 파일명을 정하고 알맞은 경로에 복사
4. 복사 후 JAR 실행
5. 실행된 JAR 가 정상적으로 구동이 되었는지 sleep 10 간격으로 health check 를 실행한다.
6. 정상 200 코드를 받게 되면 두번째 타겟 PATH 에 JAR 를 복사한다.
7. 복사 후 JAR 실행
8. 다시 실행된 JAR 가 정상적으로 구동이 되었는지 sleep 10 간격으로 health check 를 실행한다.
9. 200 OK 코드를 받게되면 배포 정상 완료
10. 200 OK 를 못받으면 10번의 try (Health Check) 이후 배포 실패로 간주하고 종료한다.


> deploy.sh 

```sh
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


```

> nginx 설정 파일

```java
user  nginx;
worker_processes  1;

error_log  /var/log/nginx/error.log warn;
pid        /var/run/nginx.pid;


events {
    worker_connections  1024;
}


http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                      '$status $body_bytes_sent "$http_referer" '
                      '"$http_user_agent" "$http_x_forwarded_for"';

    access_log  /var/log/nginx/access.log  main;

    sendfile        on;
    #tcp_nopush     on;

    keepalive_timeout  65;

        upstream backend {
                server localhost:8080;
                server localhost:8081;
                server 192.0.0.1 backup;
            }
        server  {
                listen  80      default_server;
                listen  [::]:80 default_server;
                server_name     localhost;
                location / {
                        proxy_pass http://backend;
                        proxy_set_header X-Real-IP $remote_addr;
                        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                        proxy_set_header Host $http_host;

                }
        }
    #gzip  on;
   include /etc/nginx/conf.d/*.conf;

}
```


#!/bin/bash

set -o nounset

PRG="$BASH_SOURCE"

while [ -h "$PRG" ] ; do
	ls=`ls -ld "$PRG"`
	link=`expr "$ls" : '.*-> \(.*\)$'`
	if expr "$link" : '/.*' > /dev/null; then
		PRG="$link"
	else
		PRG=`dirname "$PRG"`"/$link"
	fi
done

ROOT_PATH=$(realpath $(dirname "$PRG"))

function confirm {
 read -p "$1 (y/n) : " -n 1 -r
 echo
 if [[ ! $REPLY =~ ^[Yy]$ ]]
 then
   exit
 fi
}

function ensure_remote {
  if [[ "$ENV" == "development" ]]; then
    echo "$1"
    exit 3
  fi
}

if [[ $# -gt 2 ]] && [[ "$1" == "-e" ]]; then
  ENV=$2
  shift 2
else
  ENV=${ENV:-'development'}
fi

API_HOST='localhost:80'
if [[ "$ENV" == "production" ]]; then
	API_HOST=api.music-pattern.org
elif [[ "$ENV" == "staging" ]]; then
	API_HOST=api-staging.music-pattern.org
fi

if [[ "$1" == "" ]]; then
  echo "Usage : mp <command> [arguments]"
  exit
fi

CMD="$1"
shift

echo $CMD

if [[ "$CMD" == "deploy-web" ]]; then
  ensure_remote "Deploy fontend cannot be run on the local environment. Use (for example) \"mp -e staging "$CMD"\"."
	APP_PATH=$ROOT_PATH/web
  cd $APP_PATH

  NODE_ENV="$ENV" yarn build || exit

  # Add generic redirects for netlify which work with everything routed to
  # index.htm and relative paths to main.js and main.css for phonegap
  JSPATH=`grep -o '\./static/js/main\.[a-z0-9]*\.js' build/index.html`
  JSHASH=`echo "$JSPATH" | cut -d\. -f 3`
  CSSPATH=`grep -o '\./static/css/main\.[a-z0-9]*\.css' build/index.html`
  CSSHASH=`echo "$CSSPATH" | cut -d\. -f 3`

  echo "/:path1/main.$JSHASH.js /$JSPATH 301" > build/_redirects
  echo "/:path1/:path2/main.$JSHASH.js /$JSPATH 301" >> build/_redirects
  echo "/:path1/:path2/:path3/main.$JSHASH.js /$JSPATH 301" >> build/_redirects
  echo "/:path1/:path2/:path3/:path4/main.$JSHASH.js /$JSPATH 301" >> build/_redirects
  echo "/:path1/:path2/:path3/:path4/:path5/main.$JSHASH.js /$JSPATH 301" >> build/_redirects
  echo "/:path1/:path2/:path3/:path4/:path5/:path6/main.$JSHASH.js /$JSPATH 301" >> build/_redirects

  echo "/:path1/main.$CSSHASH.css /$CSSPATH 301" >> build/_redirects
  echo "/:path1/:path2/main.$CSSHASH.css /$CSSPATH 301" >> build/_redirects
  echo "/:path1/:path2/:path3/main.$CSSHASH.css /$CSSPATH 301" >> build/_redirects
  echo "/:path1/:path2/:path3/:path4/main.$CSSHASH.css /$CSSPATH 301" >> build/_redirects
  echo "/:path1/:path2/:path3/:path4/:path5/main.$CSSHASH.css /$CSSPATH 301" >> build/_redirects
  echo "/:path1/:path2/:path3/:path4/:path5/:path6/main.$CSSHASH.css /$CSSPATH 301" >> build/_redirects

  cat "public/_redirects" >> build/_redirects

  GIT_VERSION=`git log -n 1 --pretty=format:%h`
  git diff-index HEAD --quiet --exit-code
  if [[ "$?" -gt "0" ]]; then
    GIT_VERSION="$GIT_VERSION*"
  fi
  sed -i -e "s/##VERSION##/"$GIT_VERSION"/" build/$JSPATH;

  netlify deploy -e "$ENV"

  delivery_date=`( date --version 2>/dev/null | grep -q GNU\  && date +'%F_%H-%M-%S%N' ) || ( which gdate &>/dev/null && gdate +'%F_%H-%M-%S%N' ) || ( which python &> /dev/null && python -c 'import datetime; print datetime.datetime.now().strftime("%Y-%m-%d_%H-%M-%S%f")' ) || ( date +'%F_%H-%M-%S' )`
  delivery_date=${delivery_date:0:21}
  tagname="deployed-$ENV-$delivery_date"
  git tag $tagname
  git push origin $tagname

  exit
elif [[ "$CMD" == "install" ]]; then
  RUN='cd $ROOT_PATH;
       git submodule init;
       git submodule update;
       git submodule foreach git checkout master;
			 ./mp symlink;
			 cd $ROOT_PATH/web && yarn'
elif [[ "$CMD" == "psql" ]]; then
	COLUMNS=${COLUMNS:-''};
	RUN='docker exec -it `docker ps | grep postgres | cut -d" " -f 1` bash -c "COLUMNS=\"'$COLUMNS'\" psql -U music_pattern music_pattern $*"'
elif [[ "$CMD" == "python" ]]; then
	RUN='docker exec -it `docker ps | grep flask | cut -d" " -f 1` bash -c "cd /opt/services/flaskapp/src/ && PYTHONPATH=. python -i scripts/interact.py '"$CMD $*"'"'
elif [[ "$CMD" == "rebuild-backend" ]]; then
  RUN='docker-compose build --no-cache;'
elif [[ "$CMD" == "restart-backend" ]]; then
 RUN='sudo rm -rf $ROOT_PATH/flask/static/object_store_data;
      sudo rm -rf $ROOT_PATH/flask/postgres_data;
      cd $ROOT_PATH && docker-compose up --force-recreate'
elif [[ "$CMD" == "shared" ]]; then
	RUN='cd $ROOT_PATH/shared && yarn run compile;
			 cd $ROOT_PATH/web/node_modules && ln -mp ../../shared pass-culture-shared;
			'
elif [[ "$CMD" == "start-backend" ]]; then
  RUN='cd $ROOT_PATH && docker-compose up'
elif [[ "$CMD" == "start-web" ]]; then
	RUN='cd $ROOT_PATH/web && yarn start'
elif [[ "$CMD" == "symlink" ]]; then
  RUN='cd /usr/local/bin && sudo ln -sf '"$(pwd)"'/mp mp && chmod +x mp && chmod +x '"$(pwd)"'/mp'
elif [[ "$CMD" == "reset-all-db" ]]; then
  RUN='docker exec -it `docker ps | grep flask | cut -d" " -f 1` bash -c "rm -rf /opt/services/flaskapp/src/static/object_store_data/*";
       docker exec -it `docker ps | grep postgres | cut -d" " -f 1` bash -c "psql -U music_pattern music_pattern -c \"TRUNCATE \\\"user\\\",chord,chord_note,harmony,melody,note,pattern,pitch,rhythm,role,sample,scale,scale_note,score,score_instrument,score_staff,sound,staff,voice,voice_pattern,staff_voice RESTART IDENTITY CASCADE;\""'
elif [[ "$CMD" == "reset-all-storage" ]]; then
	RUN='sudo rm -rf $ROOT_PATH/flask/static/object_store_data;'
elif [[ "$CMD" == "test-backend" ]]; then
  if [[ $# == 0 ]]; then
    confirm "Warning: your database will be wiped. Is this OK ?"
     "$ROOT_PATH"/mp -e $ENV reset-all-db
     RUN='docker exec `docker ps | grep flask | cut -d" " -f 1` bash -c "cd /opt/services/flaskapp/src/ && rm -rf static/object_store_data/thumbs/* && PYTHONPATH=. pytest tests/*"'
  else
     RUN='docker exec `docker ps | grep flask | cut -d" " -f 1` bash -c "cd /opt/services/flaskapp/src/ && rm -rf static/object_store_data/thumbs/* && PYTHONPATH=. pytest '"$*"'"'
  fi
else
	RUN='docker exec `docker ps | grep flask | cut -d" " -f 1` bash -c "cd /opt/services/flaskapp/src/ && PYTHONPATH=. python scripts/mp.py '"$CMD $*"'"'
fi


if [[ $PWD == "/home/deploy/music-pattern-main" ]]; then
	echo $RUN
  eval $RUN
else
	if [[ "$ENV" == "production" ]]; then
	  echo "$RUN" | ssh deploy@api-staging.music-pattern.org bash
	elif [[ "$ENV" == "staging" ]]; then
	  echo "$RUN" | ssh deploy@api.music-pattern.org bash
	else
		echo $RUN
	  eval $RUN
	fi
fi

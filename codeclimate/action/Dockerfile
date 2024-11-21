FROM docker:stable

COPY ../action/action.yml /action
COPY ../action/run.sh /run.sh
COPY ../action/Dockerfile /Dockerfile
COPY ../defaults/coffeelint.json /tmptmp
COPY ../defaults /codeclimate_defaults

RUN chmod +x /run.sh

RUN apk add --no-cache jq

CMD ["--help"]
ENTRYPOINT  ["/run.sh"]
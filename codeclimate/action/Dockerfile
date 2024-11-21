FROM docker:stable

COPY ./action.yml /action
COPY ./configs /code
COPY $GITHUB_WORKSPACE/configs/codeclimate/defaults /codeclimate_defaults

RUN chmod +x /run.sh

RUN apk add --no-cache jq

CMD ["--help"]
ENTRYPOINT  ["/run.sh"]
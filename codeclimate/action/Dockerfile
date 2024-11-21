FROM docker:stable

COPY ../.. /code
COPY ../defaults /codeclimate_defaults

RUN chmod +x /run.sh

RUN apk add --no-cache jq

CMD ["--help"]
ENTRYPOINT  ["/run.sh"]
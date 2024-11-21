FROM docker:stable

COPY ./code /code
COPY ./defaults /codeclimate_defaults
COPY ./run.sh /run.sh

RUN chmod +x /run.sh

RUN apk add --no-cache jq

CMD ["--help"]
ENTRYPOINT  ["/run.sh"]
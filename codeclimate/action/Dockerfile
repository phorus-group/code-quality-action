FROM docker:stable

COPY . /code
RUN ls -la /code
COPY /code/configs/codeclimate/defaults /codeclimate_defaults

RUN chmod +x /run.sh

RUN apk add --no-cache jq

CMD ["--help"]
ENTRYPOINT  ["/run.sh"]
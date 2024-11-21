#!/bin/sh

# Map input values from the GitHub Actions workflow to shell variables
SOURCE_CODE="/code/$1"
TIMEOUT_SECONDS=$2
CODECLIMATE_DEV=$3
REPORT_STDOUT=$4
REPORT_FORMAT=$5
ENGINE_MEMORY_LIMIT_BYTES=$6
CODECLIMATE_DEBUG=$7

usage="$(basename "$0") [-h] <app_path>

where:
    -h  show this help text
    app_path The path to the source code of the project you want to analyze."

while getopts 'h' option; do
  case "$option" in
    h) echo "$usage"
       exit
       ;;
    :) printf "missing argument for -%s\n" "$OPTARG" >&2
       echo "$usage" >&2
       exit 1
       ;;
   \?) printf "illegal option: -%s\n" "$OPTARG" >&2
       echo "$usage" >&2
       exit 1
       ;;
  esac
done
shift $((OPTIND - 1))

if [ $# -ne 1 ] ; then
  echo "$usage"
  exit
fi

APP_PATH=$SOURCE_CODE
REPORT_FILENAME_PREFIX="code-quality-report"
REPORT_FORMAT=${REPORT_FORMAT:-json}
DEFAULT_FILES_PATH=${DEFAULT_FILES_PATH:-/codeclimate_defaults}

DOCKER_SOCKET_PATH=${DOCKER_SOCKET_PATH:-/var/run/docker.sock}
CODECLIMATE_VERSION=${CODECLIMATE_VERSION:-0.96.0}
CODECLIMATE_IMAGE=${CODECLIMATE_IMAGE:-codeclimate/codeclimate}
CODECLIMATE_FULL_IMAGE="${CODECLIMATE_IMAGE}:${CODECLIMATE_VERSION}"

CONTAINER_TIMEOUT_SECONDS=${TIMEOUT_SECONDS:-900} # default to 15 min
ENGINE_MEMORY_LIMIT_BYTES=${ENGINE_MEMORY_LIMIT_BYTES:-1024000000} # default 1 Gb

# Copy default config files unless already present for csslint, eslint (ignore), rubocop and coffeelint
for config_file in .csslintrc .eslintignore .rubocop.yml coffeelint.json; do
  if [ ! -f "$APP_PATH/$config_file" ] ; then
    cp "$DEFAULT_FILES_PATH/$config_file" "$APP_PATH/"
  fi
done

# Copy default config file unless already present for eslint
# NB: check for all supported config files
if ! [ -f "$APP_PATH/.eslintrc.js" -o -f "$APP_PATH/.eslintrc.yaml" -o -f "$APP_PATH/.eslintrc.yml" -o -f "$APP_PATH/.eslintrc.json" -o -f "$APP_PATH/.eslintrc" ] ; then
  cp "$DEFAULT_FILES_PATH/.eslintrc.yml" "$APP_PATH/"
fi

# Detect eslint version for using proper channel
ESLINT_CHANNEL="stable"
if [ -f "$APP_PATH/package.json" ] ; then
  ESLINT_VERSION_FROM_PACKAGE_JSON=$(jq -r '[.dependencies.eslint, .devDependencies.eslint] | map(select (. != null)) | first' "$APP_PATH/package.json")
  # Supported notation: ~5.3.0, ^5.3.0, 5.3.0
  ESLINT_MAJOR_VERSION=$(echo "$ESLINT_VERSION_FROM_PACKAGE_JSON" | sed -E 's/^[~^]?([0-9]+).*/\1/')

  # codeclimate-eslint has no versions greater than 8 ATM
  # See https://github.com/codeclimate/codeclimate/blob/master/config/engines.yml#L66
  if [ -n "$ESLINT_MAJOR_VERSION" ] && [ "$ESLINT_MAJOR_VERSION" -le 8 ]; then
    ESLINT_CHANNEL="eslint-$ESLINT_MAJOR_VERSION"
  fi
fi

# Render default config file unless already present for code climate
# NB: check for all supported config files
if ! [ -f  "$APP_PATH/.codeclimate.yml" -o -f "$APP_PATH/.codeclimate.json" ] ; then
  sed -e "s/__ESLINT_CHANNEL__/\"$ESLINT_CHANNEL\"/" "$DEFAULT_FILES_PATH/.codeclimate.yml.template" > "$APP_PATH/.codeclimate.yml"
fi

# Pull the code climate image in advance of running the container to
# suppress progress.  The `--quiet` option is not passed to support
# Docker 18.09 or earlier: https://github.com/docker/cli/pull/882
docker pull "${CODECLIMATE_FULL_IMAGE}" > /dev/null

# We need to run engines:install before analyze to avoid hitting timeout errors.
# See: https://github.com/codeclimate/codeclimate/issues/866#issuecomment-418758879
# We also dump the output to a /dev/null to not mess up the result when REPORT_STDOUT is enabled.
docker run --rm \
    --env CODECLIMATE_CODE="$SOURCE_CODE" \
    --env CODECLIMATE_DEBUG="$CODECLIMATE_DEBUG" \
    --env CONTAINER_TIMEOUT_SECONDS="$CONTAINER_TIMEOUT_SECONDS" \
    --volume "$SOURCE_CODE":/code \
    --volume /tmp/cc:/tmp/cc \
    --volume "$DOCKER_SOCKET_PATH":/var/run/docker.sock \
    "${CODECLIMATE_FULL_IMAGE}" --no-check-version engines:install > /dev/null

if [ $? -ne 0 ]; then
    echo "Could not install code climate engines for the repository at $APP_PATH"
    exit 1
fi

if echo "$REPORT_FORMAT" | grep -Eq '(json|html)' ; then
  # Run the code climate container.
  # SOURCE_CODE env variable must be provided when launching this script. It allow
  # code climate engines to mount the source code dir into their own container.
  # TIMEOUT_SECONDS env variable is optional. It allows you to increase the timeout
  # window for the analyze command.
  # CODECLIMATE_DEBUG env variable is optional. It enables Code Climate debug
  # logging.
  # ENGINE_MEMORY_LIMIT_BYTES env variable is optional. It configures the default
  # allocated memory with which each engine runs. This is simply passed along into
  # Docker's --memory arg
  docker run --rm \
      --env CODECLIMATE_CODE="$SOURCE_CODE" \
      --env CODECLIMATE_DEBUG="$CODECLIMATE_DEBUG" \
      --env CONTAINER_TIMEOUT_SECONDS="$CONTAINER_TIMEOUT_SECONDS" \
      --env ENGINE_MEMORY_LIMIT_BYTES="$ENGINE_MEMORY_LIMIT_BYTES" \
      --volume "$SOURCE_CODE":/code \
      --volume /tmp/cc:/tmp/cc \
      --volume "$DOCKER_SOCKET_PATH":/var/run/docker.sock \
      "${CODECLIMATE_FULL_IMAGE}" --no-check-version analyze ${CODECLIMATE_DEV:+--dev} -f "$REPORT_FORMAT" > "/tmp/raw_codeclimate.$REPORT_FORMAT"

  if [ $? -ne 0 ]; then
      echo "Could not analyze code quality for the repository at $APP_PATH"
      exit 1
  fi

  # redirect STDOUT to disk (default), unless REPORT_STDOUT is set
  if [ -z "$REPORT_STDOUT" ]; then
    exec > "$APP_PATH/$REPORT_FILENAME_PREFIX.$REPORT_FORMAT"
  fi

  if [ "$REPORT_FORMAT" = "json" ]; then
    # Only keep "issue" type
    jq -c 'map(select(.type | test("issue"; "i")))' "/tmp/raw_codeclimate.$REPORT_FORMAT"
  elif [ "$REPORT_FORMAT" = "html" ]; then
    cat "/tmp/raw_codeclimate.$REPORT_FORMAT"
  fi
else
  echo "Invalid REPORT_FORMAT value. Must be one of: json|html"
  exit 1
fi

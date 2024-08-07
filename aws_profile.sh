#!/bin/bash

function _is_awscli_v1() {
  if aws --version | egrep "aws-cli/1" > /dev/null; then
    return 0
  else
    return 1
  fi
}

function _get_aws_profiles() {
  # Try the "list-profiles" subcommand first, which is introduced in awscli v2,
  # and if not, fall back to check the config file directly.
  local a=
  if _is_awscli_v1 ; then
    a=$(
      egrep -o '^\[[^]]+]' "${AWS_CONFIG_FILE:-$HOME/.aws/config}" 2>/dev/null \
      | sed 's/\[//g' | sed 's/\]//g' \
      | tr -s '\n' ' '
    )
  else
    a=$(aws configure list-profiles 2> /dev/null | tr -s '\n' ' ')
  fi
  echo $a
}

function _find_profile() {
  local profile="$1"
  [ -z "$profile" ] && return 1

  local a=$(_get_aws_profiles)

  echo $a | egrep "$profile" > /dev/null && return 0 || return 1
}

function _awscli_env_vars() {
  # Historically, awscli supports AWS_DEFAULT_PROFILE whereas almost
  # all other SDKs support AWS_PROFILE. The good news is that awscli
  # has been updated to support both since 2015/4. Thus we only list
  # AWS_PROFILE in this function, and always set AWS_DEFAULT_PROFILE
  # to AWS_PROFILE in the main function below.
  # https://github.com/aws/aws-cli/issues/1281
  # https://github.com/boto/boto/issues/3287

  # We list both AWS_SECURITY_TOKEN and AWS_SESSION_TOKEN here because
  # as of boto v2.39.0, ansible doesn't work without AWS_SECURITY_TOKEN.
  # And Ansible doesn't work because old boto only supports
  # AWS_SECURITY_TOKEN, but not AWS_SESSION_TOKEN. AWS has standardized
  # to use AWS_SESSION_TOKEN, and boto just needs to catch up.
  # https://aws.amazon.com/blogs/security/a-new-and-standardized-way-to-manage-credentials-in-the-aws-sdks/
  # https://github.com/boto/boto/issues/3298
  echo "AWS_PROFILE"                \
       "AWS_ACCESS_KEY_ID"          \
       "AWS_CREDENTIAL_EXPIRATION"  \
       "AWS_SECRET_ACCESS_KEY"      \
       "AWS_SESSION_TOKEN"          \
       "AWS_SESSION_TOKEN_EXPIRE"   \
       "AWS_SECURITY_TOKEN"
}

function _show_awscli_env_vars() {
  local i=
  for i in $(_awscli_env_vars) ; do
    eval echo "$i=\${$i}"
  done 
}

function _reset_awscli_env_vars() {
  local i=
  for i in $(_awscli_env_vars) ; do
    unset $i
  done 
}

function aws_get_mfa_session_token() {

  local mfa_token="$1"
  if [ -z "$mfa_token" ] ; then
    echo "Usage: $FUNCNAME <mfa_token>" 1>&2
    return 1
  fi

  # Unset the environment variables related to this function, otherwise
  # it may try to use an expired session token to obtain a new token and
  # fail.
  unset AWS_ACCESS_KEY_ID
  unset AWS_SECRET_ACCESS_KEY
  unset AWS_SESSION_TOKEN
  unset AWS_SECURITY_TOKEN
  unset AWS_SESSION_TOKEN_EXPIRE

  # See https://docs.aws.amazon.com/cli/latest/topic/config-vars.html
  # for how to configure mfa_serial in AWS CLI config file.
  local mfa_serial=
  mfa_serial=$(aws configure get mfa_serial) || {
    echo "Failed to get mfa_serial. Please set it in ~/.aws/config file." 1>&2
    return 1
  }

  local session_token=( $(aws sts get-session-token     \
                          --serial-number "$mfa_serial" \
                          --token-code "$mfa_token"     \
                          --output text) )
  
  [ "${#session_token[*]}" -eq 0 ] && {
    echo "Failed to get session token." 1>&2
    return 1
  }

  export AWS_ACCESS_KEY_ID=${session_token[1]}
  export AWS_SECRET_ACCESS_KEY=${session_token[3]}
  export AWS_SESSION_TOKEN=${session_token[4]}
  export AWS_SECURITY_TOKEN=$AWS_SESSION_TOKEN
  export AWS_SESSION_TOKEN_EXPIRE=${session_token[2]}
}

function aws_profile() {
  # usage: aws_profile <profile> [mfa_token]

  if [[ -z "$1" ]]; then
      _show_awscli_env_vars
      return 0
  fi

  local aws_profiles="$(_get_aws_profiles)"

  # reset env variables before setting new ones
  _reset_awscli_env_vars

  if _find_profile "$1" ; then
      export AWS_PROFILE=$1
      export AWS_DEFAULT_PROFILE=$AWS_PROFILE

      # Most programs can figure out the correct region when AWS_PROFILE is
      # defined and ~/.aws/config is properly configured, and some can not.
      # Exporting AWS_REGION for those that cannot.
      export AWS_REGION=$(aws configure get region --profile $AWS_PROFILE)
      export AWS_DEFAULT_REGION=$AWS_REGION

      if _is_awscli_v1 ; then
        if [[ -n "$2" ]] ; then
          if aws_get_mfa_session_token "$2" ; then
            _show_awscli_env_vars
          fi
        fi
      else
        aws sso login
        eval $(aws configure export-credentials --format env)
        _show_awscli_env_vars
      fi
  else
      echo "\`$1' is not recognized." 1>&2
      echo "recognized profile names are: $aws_profiles" 1>&2
      return 1
  fi
}

#!/bin/bash

function _awscli_env_vars() {
  # Historically, awscli supports AWS_DEFAULT_PROFILE whereas almost
  # all other SDKs support AWS_PROFILE. The good news is that awscli
  # has been updated to support both since 2015/4. Thus we only list
  # AWS_PROFILE here, and always set AWS_DEFAULT_PROFILE to AWS_PROFILE
  # in the main function below.
  # https://github.com/aws/aws-cli/issues/1281
  # https://github.com/boto/boto/issues/3287

  # As of boto v2.39.0, AWS_SECURITY_TOKEN is needed or ansible won't
  # work. Ansible not working is because old boto originally supported
  # AWS_SECURITY_TOKEN environment variable, but not AWS_SESSION_TOKEN.
  # AWS has standardized use AWS_SESSION_TOKEN since, and boto just needs
  # to catch up.
  # https://aws.amazon.com/blogs/security/a-new-and-standardized-way-to-manage-credentials-in-the-aws-sdks/
  # https://github.com/boto/boto/issues/3298
  echo "AWS_PROFILE"              \
       "AWS_ACCESS_KEY_ID"        \
       "AWS_SECRET_ACCESS_KEY"    \
       "AWS_SESSION_TOKEN"        \
       "AWS_SESSION_TOKEN_EXPIRE" \
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

function _get_aws_profiles() {
  local a=$(egrep -o '^\[[^]]+]' "${AWS_CREDENTIALS_FILE:-$HOME/.aws/credentials}" 2>/dev/null)
  echo "$a" | sed 's/\[//g' | sed 's/\]//g' | tr -s '\n' ' '
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

  # TODO: Add support for multiple MFAs. Currently if MY_MFA_SERIAL is
  # defined as an environment variable, it is used across all profiles.
  # A work around is to set MY_MFA_SERIAL on the command line.
  # For example,
  # MY_MFA_SERIAL=my_mfa_serial aws_profile <profile> <token>
  #
  local mfa_serial=${MY_MFA_SERIAL:=default_mfa_serial}

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

  if aws configure list --profile "$1" &> /dev/null ; then
      export AWS_PROFILE=$1
      export AWS_DEFAULT_PROFILE=$AWS_PROFILE

      # Most programs can figure out the correct region when AWS_PROFILE is
      # defined and ~/.aws/config is probably configured, and some can not.
      # Exporting AWS_REGION for those that cannot.
      export AWS_REGION=$(aws configure get region --profile $AWS_PROFILE)
      export AWS_DEFAULT_REGION=$AWS_REGION

      if [[ -n "$2" ]] ; then
        if aws_get_mfa_session_token "$2" ; then
          _show_awscli_env_vars
        fi
     fi
  else
      echo "\`$1' is not recognized." 1>&2
      echo "recognized profile names are: $aws_profiles" 1>&2
      return 1
  fi
}

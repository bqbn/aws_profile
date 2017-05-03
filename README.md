# aws_profile

A shell script that helps switch AWS profiles for AWS command line tools

## Install

```bash
git clone https://github.com/bqbn/aws_profile.git
```

## Usage

1. Source the script on the command line session or put the source command in .bashrc or .bash_profile file.

    ```bash
    source aws_profile.sh
    ```

2. Run the aws_profile command to switch among AWS profiles.

    ```bash
    [MY_MFA_SERIAL=my_mfa_serial] aws_profile <profile> [mfa_token]
    ```

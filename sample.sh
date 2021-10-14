#! /usr/bin/env bash
### Connect to and Disconnect from the UCSF VPN
###
### Usage:
###  ucsf-vpn <command> [flags] [options]
###
### Commands:
###  start            Connect to VPN
###  stop             Disconnect from VPN
###  restart          Disconnect and reconnect to VPN
###  toggle           Connect to or disconnect from VPN
###  status           Display VPN connection status
###  details          Display connection details in JSON format
###  log              Display log file
###  troubleshoot     Scan log file for errors (only for '--method=pulse')
###
### Options:
###  --token=<token>  One-time two-factor authentication (2FA) token or method:
###                    - 'prompt' (user is prompted to enter the token),
###                    - 'push' ("approve and confirm" in Duo app; default),
###                    - 'phone' (receive phone call and "press any key"),
###                    - 'sms' (receive code via text message),
###                    -  6 or 7 digit token (from Duo app), or
###                    -  44-letter YubiKey token ("press YubiKey")
###  --user=<user>    UCSF Active Directory ID (username)
###  --pwd=<pwd>      UCSF Active Directory ID password
###
###  --server=<host>  VPN server (default is 'remote.ucsf.edu')
###  --realm=<realm>  VPN realm (default is 'Dual-Factor Pulse Clients')
###  --url=<url>      VPN URL (default is https://{{server}}/pulse)
###  --method=<mth>   Either 'openconnect' (default) or 'pulse'
###  --validate=<how> Either 'ipinfo', 'pid', or 'pid,ipinfo'
###  --theme=<theme>  Either 'cli' (default) or 'none'
###
### Flags:
###  --verbose        More verbose output
###  --help           Display full help
###  --version        Display version
###  --force          Force command
###
### Examples:
###  ucsf-vpn start --user=alice --token=push
###  ucsf-vpn stop
###  UCSF_VPN_TOKEN=prompt ucsf-vpn start --user=alice --pwd=secrets
###  ucsf-vpn start
###
### ---
###
### Environment variables:
###  UCSF_VPN_METHOD       Default value for --method
###  UCSF_VPN_SERVER       Default value for --server
###  UCSF_VPN_TOKEN        Default value for --token
###  UCSF_VPN_THEME        Default value for --theme
###  UCSF_VPN_VALIDATE     Default value for --validate
###  UCSF_VPN_PING_SERVER  Ping server to validate internet (default: 9.9.9.9)
###  UCSF_VPN_EXTRAS       Additional arguments passed to OpenConnect
###
### Commands and Options for Pulse Security Client only (--method=pulse):
###  open-gui         Open the Pulse Secure GUI
###  close-gui        Close the Pulse Secure GUI (and any VPN connections)
###
###  --gui            Connect to VPN via Pulse Secure GUI
###  --no-gui         Connect to VPN via Pulse Secure CLI (default)
###  --speed=<factor> Control speed of --gui interactions (default is 1.0)
###
### Any other options are passed to Pulse Secure CLI as is (only --no-gui).
###
### User credentials:
### If user credentials (--user and --pwd) are neither specified nor given
### in ~/.netrc, then you will be prompted to enter them. To specify them
### in ~/.netrc file, use the following format:
###
###   machine remote.ucsf.edu
###       login alice
###       password secrets
###
### For security, the ~/.netrc file should be readable only by
### the user / owner of the file. If not, then 'ucsf-vpn start' will
### set its permission accordingly (by calling chmod go-rwx ~/.netrc).
###
### Requirements:
### * Requirements when using OpenConnect (CLI):
###   - OpenConnect (>= 7.08) (installed: {{openconnect_version}})
###   - sudo
### * Requirements when using Junos Pulse Secure Client (GUI):
###   - Junos Pulse Secure client (>= 5.3) (installed: {{pulsesvc_version}})
###   - Ports 4242 (UDP) and 443 (TCP)
###   - `curl`
###   - `xdotool` (when using 'ucsf-vpn start --method=pulse --gui')
###   - No need for sudo rights
###
### Pulse Secure GUI configuration:
### Calling 'ucsf-vpn start --method=pulse --gui' will, if missing,
### automatically add a valid VPN connection to the Pulse Secure GUI
### with the following details:
###  - Name: UCSF
###  - URL: https://remote.ucsf.edu/pulse
### You may change the name to you own liking.
###
### Troubleshooting:
### * Verify your username and password at https://remote.ucsf.edu/.
###   This should be your UCSF Active Directory ID (username); neither
###   MyAccess SFID (e.g. 'sf*****') nor UCSF email address will work.
### * If you are using the Pulse Secure client (`ucsf-vpn --method=pulse`),
###   - Make sure ports 4242 & 443 are not used by other processes
###   - Make sure 'https://remote.ucsf.edu/pulse' is used as the URL
###   - Run 'ucsf-vpn troubleshoot' to inspect the Pulse Secure logs
###
### Useful resources:
### * UCSF VPN information:
###   - https://software.ucsf.edu/content/vpn-virtual-private-network
### * UCSF Web-based VPN Interface:
###   - https://remote-vpn01.ucsf.edu/ (preferred)
###   - https://remote.ucsf.edu/
### * UCSF Two-Factory Authentication (2FA):
###   - https://it.ucsf.edu/services/duo-two-factor-authentication
### * UCSF Managing Your Passwords:
###   - https://it.ucsf.edu/services/managing-your-passwords
###
### Version: 5.3.0
### Copyright: Henrik Bengtsson (2016-2020)
### License: GPL (>= 2.1) [https://www.gnu.org/licenses/gpl.html]
### Source: https://github.com/HenrikBengtsson/ucsf-vpn
call="$0 $*"

export PULSEPATH=${PULSEPATH:-/usr/local/pulse}
export PATH="${PULSEPATH}:${PATH}"
export LD_LIBRARY_PATH="${PULSEPATH}:${LD_LIBRARY_PATH}"

# -------------------------------------------------------------------------
# Output utility functions
# -------------------------------------------------------------------------
function _tput() {
    if [[ $theme == "none" ]]; then
        return
    fi
    tput "$@" 2> /dev/null
}

function mecho() { echo "$@" 1>&2; }
function mdebug() {
    if ! $debug; then
        return
    fi
    {
        _tput setaf 8 ## gray
        echo "DEBUG: $*"
        _tput sgr0    ## reset
    } 1>&2
}
function merror() {
    local info version
    {
        info="ucsf-vpn $(version)"
        version=$(openconnect_version 2> /dev/null)
        if [[ -n $version ]]; then
            info="$info, OpenConnect $version"
        else
            info="$info, OpenConnect version unknown"
        fi
        [[ -n $info ]] && info=" [$info]"
        _tput setaf 1 ## red
        echo "ERROR: $*$info"
        _tput sgr0    ## reset
    } 1>&2
    _exit 1
}
function mwarn() {
    {
        _tput setaf 3 ## yellow
        echo "WARNING: $*"
        _tput sgr0    ## reset
    } 1>&2
}
function minfo() {
    if ! $verbose; then
        return
    fi
    {
        _tput setaf 4 ## blue
        echo "INFO: $*"
        _tput sgr0    ## reset
    } 1>&2
}
function mok() {
    {
        _tput setaf 2 ## green
        echo "OK: $*"
        _tput sgr0    ## reset
    } 1>&2
}
function mdeprecated() {
    {
        _tput setaf 3 ## yellow
        echo "DEPRECATED: $*"
        _tput sgr0    ## reset
    } 1>&2
}
function mnote() {
    {
        _tput setaf 11  ## bright yellow
        echo "NOTE: $*"
        _tput sgr0    ## reset
    } 1>&2
}

function _exit() {
    local value

    value=${1:-0}
    pii_cleanup
    mdebug "Exiting with exit code $value"
    exit "$value"
}


# -------------------------------------------------------------------------
# CLI utility functions
# -------------------------------------------------------------------------
function version() {
    grep -E "^###[ ]*Version:[ ]*" "$0" | sed 's/###[ ]*Version:[ ]*//g'
}

function help() {
    local what res

    what=$1
    res=$(grep "^###" "$0" | grep -vE '^(####|### whatis: )' | cut -b 5- | sed "s/{{pulsesvc_version}}/$(pulsesvc_version)/" | sed "s/{{openconnect_version}}/$(openconnect_version)/")

    if [[ $what == "full" ]]; then
        res=$(echo "$res" | sed '/^---/d')
    else
        res=$(echo "$res" | sed '/^---/Q')
    fi

    if [[ ${UCSF_TOOLS} == "true" ]]; then
        res=$(printf "%s\\n" "${res[@]}" | sed -E 's/([^/])ucsf-vpn/\1ucsf vpn/')
    fi
    printf "%s\\n" "${res[@]}"
}


# -------------------------------------------------------------------------
# Sudo tools
# -------------------------------------------------------------------------
function assert_sudo() {
    local cmd

    cmd=$1

    if sudo -v -n 2> /dev/null; then
        mdebug "'sudo' is already active"
        minfo "Administrative (\"sudo\") rights already establish"
        return
    fi
    mdebug "'sudo' is not active"

    if [[ -n $cmd ]]; then
        if [[ ${UCSF_TOOLS} == "true" ]]; then
            cmd=" ('ucsf vpn $cmd')"
        else
            cmd=" ('ucsf-vpn $cmd')"
        fi
    fi

    {
        mwarn "This action$cmd requires administrative (\"sudo\") rights."
        _tput setaf 11  ## bright yellow
        sudo -v -p "Enter the password for your account ('$USER') on your local computer ('$HOSTNAME'): "
#        _tput setaf 15  ## bright white
        _tput sgr0      ## reset
    } 1>&2

    ## Assert success
    if ! sudo -v -n 2> /dev/null; then
        merror "Failed to establish 'sudo' access. Please check your password. It might also be that you do not have administrative rights on this machine."
    fi

    minfo "Administrative (\"sudo\") rights establish"
}


# -------------------------------------------------------------------------
# Connection, e.g. checking whether connected to the VPN or not
# -------------------------------------------------------------------------
function connection_details() {
    mdebug "connection_details()"
    if [[ ! -f "$pii_file" ]]; then
        if ! is_online; then
            merror "Internet connection is not working"
        fi
        minfo "Verified that internet connection works"
        minfo "Getting public IP (from https://ipinfo.io/ip)"
        mdebug "Calling: curl --silent https://ipinfo.io/json > \"$pii_file\""
        curl --silent https://ipinfo.io/json > "$pii_file"
        if [[ ! -f "$pii_file" ]]; then
            merror "Failed to get public IP (from https://ipinfo.io/ip)"
        fi
        mdebug "Public connection information: $(tr -d $'\n' < "$pii_file" | sed 's/  / /g')"
    fi
    cat "$pii_file"
    echo
}

function public_ip() {
    mdebug "public_ip()"
    connection_details | grep -F '"ip":' | sed -E 's/[ ",]//g' | cut -d : -f 2
}

function public_hostname() {
    mdebug "public_hostname()"
    connection_details | grep -F '"hostname":' | sed -E 's/[ ",]//g' | cut -d : -f 2
}

function public_org() {
    mdebug "public_org()"
    connection_details | grep -F '"org":' | cut -d : -f 2 | sed -E 's/(^[ ]*"|",[ ]*$)//g'
}

function public_info() {
    local ip hostname org

    mdebug "public_info()"
    ip=$(public_ip)
    hostname=$(public_hostname)
    org=$(public_org)
    printf "ip=%s, hostname='%s', org='%s'" "$ip" "$hostname" "$org"
}

function is_online() {
    local ping_server

    ping_servers=${UCSF_VPN_PING_SERVER:-9.9.9.9}
    mdebug "Ping servers: [n=${#ping_servers}]: $ping_servers"
    for ping_server in $ping_servers; do
      mdebug "Ping server: '$ping_server'"
      minfo "Pinging '$ping_server' once"
      if ping -c 1 -W 1 "$ping_server" > /dev/null 2> /dev/null; then
          return 0
      fi
    done
    return 1
}

function is_connected() {
    mdebug "is_connected()"
    ## NOTE: It appears that field 'hostname' is not always returned, e.g. when
    ## calling it multiple times in a row some calls done report that field.
    ## Because of this, we test the status on the field 'org' instead.
    connection_details | grep -q -E "org.*[:].*AS5653 University of California San Francisco"
}

function status() {
    local assert connected mcmd pid msg

    assert=$1
    mdebug "assert='$assert'"
    minfo "validate='$validate'"

    connected=false
    mcmd="echo"

    if [[ $validate == *pid* ]]; then
        pid=$(openconnect_pid)
        if [[ $pid == "-1" ]]; then
            connected=false
            msg="No \'openconnect\' process running"
            if [[ $assert == "connected" ]]; then
                mcmd="merror"
            elif [[ $assert == "disconnected" ]]; then
                mcmd="mok"
            fi
        else
            connected=true
            msg="\'openconnect\' process running \(PID=$pid\)"
            if [[ $assert == "connected" ]]; then
                mcmd="mok"
            elif [[ $assert == "disconnected" ]]; then
                mcmd="merror"
            fi
        fi
        eval "$mcmd" "OpenConnect status: $msg"
    fi

    if [[ $validate == *ipinfo* ]]; then
        mcmd="echo"
        if is_connected; then
            connected=true
            if [[ $assert == "disconnected" ]]; then
                mcmd="merror"
            elif [[ $assert == "connected" ]]; then
                mcmd="mok"
            fi
        else
            connected=false
            if [[ $assert == "disconnected" ]]; then
                mcmd="mok"
            elif [[ $assert == "connected" ]]; then
                mcmd="merror"
            fi
        fi
        eval "$mcmd" "Public IP information: $(public_info)"
     fi

    if $connected; then
        msg="Connected to the VPN"
    else
        msg="Not connected to the VPN"
    fi

    eval "$mcmd" "$msg"
}


# -------------------------------------------------------------------------
# Credentials, e.g. .netrc, prompting for password, etc.
# -------------------------------------------------------------------------
function source_netrc() {
    local rcfile pattern found bfr

    rcfile=${NETRC:-~/.netrc}
    ## No such file?
    if [[ ! -f "${rcfile}" ]]; then
        mdebug "No .netrc file: $rcfile"
        return;
    fi
    mdebug "Detected .netrc file: $rcfile"
    ## Force file to be accessible only by user
    chmod go-rwx "${rcfile}"

    mdebug "- search: ${netrc_machines[*]}"
    found=false
    for machine in "${netrc_machines[@]}"; do
        pattern="^[ \\t]*machine[ \\t]+${machine}([ \\t]+|$)"
        mdebug "- search pattern: ${pattern}"

        ## No such machine?
        grep -q -E "${pattern}" "${rcfile}"

        # shellcheck disable=SC2181
        if [[ $? -eq 0 ]]; then
            mdebug "- found: ${machine}"
            found=true
            break
        fi
    done

    if ! $found; then
        mdebug "- no such machine: $machine"
        return 0
    fi

    bfr=$(awk "/${pattern}/{print; flag=1; next}/machine[ \\t]/{flag=0} flag;" "${rcfile}")
    [[ -z $bfr ]] && merror "Internal error - failed to extract ${server} credentials from ${rcfile} searching for ${netrc_machines}"

    user=$(echo "${bfr}" | grep -F "login" | sed -E 's/.*login[[:space:]]+([^[:space:]]+).*/\1/g')
    pwd=$(echo "${bfr}" | grep -F "password" | sed -E 's/.*password[[:space:]]+([^[:space:]]+).*/\1/g')

    mdebug "- user=${user}"
    if [[ -z "${pwd}" ]]; then
        mdebug "- pwd=<missing>"
    else
        mdebug "- pwd=<hidden>"
     fi
}

function prompt_user() {
    user=$1
    if [[ -n "${user}" ]]; then return; fi
    mdebug "PROMPT: Asking user to enter username:"
    while [ -z "${user}" ]; do
        {
            _tput setaf 11  ## bright yellow
            printf "Enter your UCSF Active Directory username: "
            _tput setaf 15  ## bright white
            read -r user
            _tput sgr0      ## reset
        } 1>&2
        user=${user/ /}
    done
    mdebug "- user=${user}"
}

function prompt_pwd() {
    pwd=$1
    if [[ -n "${pwd}" ]]; then return; fi
    mdebug "PROMPT: Asking user to enter password:"
    while [ -z "${pwd}" ]; do
        {
            _tput setaf 11  ## bright yellow
            printf "Enter your UCSF Active Directory password: "
            _tput setaf 15  ## bright white
            read -r -s pwd
            _tput sgr0      ## reset
        } 1>&2
        pwd=${pwd/ /}
    done
    mecho "<password>"

    if [[ -z "${pwd}" ]]; then
        mdebug "- pwd=<missing>"
    else
        mdebug "- pwd=<hidden>"
    fi
}

function type_of_token() {
    local token

    token=$1

    ## Hardcoded methods
    if [[ ${token} =~ ^phone[1-9]*$ ]]; then
        ## Tested with 'phone' and 'phone2', but for some reason
        ## the same phone number is called although I've got two
        ## different registered.  Also 'phone1' and 'phone3' gives
        ## an error.
        mdebug "Will authenticate via a call to a registered phone number"
        echo "phone call"
        return
    elif [[ ${token} == "push" ]]; then
        mdebug "Will authenticate via push (approve and confirm in Duo app)"
        echo "push"
        return
    elif [[ ${token} =~ ^(sms|text)[1-9]*$ ]]; then
        mdebug "Will send token via SMS"
        echo "SMS token"
        return
    elif [[ ${token} == "false" ]]; then
        mdebug "Will not use token (in the form)"
        echo "none"
        return
    fi

    ## YubiKey token (44 lower-case letters)
    if [[ ${#token} -eq 44 ]] && [[ ${token} =~ ^[a-z]+$ ]]; then
        mdebug "YubiKey token detected"
        echo "YubiKey token"
        return
    fi

    ## Digital token
    if [[ ${token} =~ ^[0-9]+$ ]]; then
        if [[ ${#token} -eq 6 ]]; then
            mdebug "Six-digit token detected"
            echo "six-digit token"
            return
        elif [[ ${#token} -eq 7 ]]; then
            mdebug "Seven-digit token detected"
            echo "seven-digit token"
            return
        fi
    fi

    echo "unknown"
}

function prompt_token() {
    local type

    token=$1
    if [[ ${token} == "prompt" || ${token} == "true" ]]; then token=; fi
    if [[ -n "${token}" ]]; then return; fi

    mdebug "PROMPT: Asking user to enter one-time token:"
    type="unknown token"
    while [ -z "${token}" ]; do
        {
            _tput setaf 11  ## bright yellow
            printf "Enter 'push' (default), 'phone', 'sms', a 6 or 7 digit token, or press your YubiKey: "
            _tput setaf 15  ## bright white
            read -r -s token
            _tput sgr0      ## reset
            ## Default?
            if [[ -z $token ]]; then
                token="push"
            fi
        } 1>&2
        token=${token/ /}
        type=$(type_of_token "$token")
        if [[ $type == "unknown token" ]]; then
            {
                _tput setaf 1 ## red
                printf "\\nERROR: Not a valid token ('push', 'phone', 'sms', 6 or 7 digits, or 44-letter YubiKey sequence)\\n"
                _tput sgr0      ## reset
            } 1>&2
            token=
        fi
    done
    mecho "<$type>"

    if [[ -z "${token}" ]]; then
        mdebug "- token=<missing>"
    else
        mdebug "- token=<hidden>"
    fi
}


# -------------------------------------------------------------------------
# Pulse Secure Client
# -------------------------------------------------------------------------
function div() {
    if [ "$2" == "1" ] || [ "$2" == "1.0" ]; then
        echo "$1"
    else
        # shellcheck disable=SC2003
        expr "$1/$2" | bc -l
    fi
}

function pulsesvc_version() {
    local res

    res=$(pulsesvc --version 2> /dev/null)
    # shellcheck disable=SC2181
    if [[ $? -ne 0 ]]; then
        echo "<PLEASE INSTALL>"
    else
        printf "%s\\n" "${res[@]}" | grep -F "Release Version" | sed -E 's/.*:[ ]+//'
    fi
}

function is_pulseUi_running() {
    ps -C pulseUi > /dev/null
}

function pulseUi_find_connection() {
    local config_home confile idx ii con  # IFS too?

    config_home="$HOME/.pulse_secure/pulse"
    confile="$config_home/.pulse_Connections.txt"
    [[ -f "$confile" ]] || pulseUi_add_connection
    [[ -f "$confile" ]] || merror "No Pulse GUI connection file: $confile"
    mdebug "Pulse connections file: $confile"
    mdebug "$(< "$confile")"

    # shellcheck disable=SC2207
    IFS=$'\r\n' cons=( $(grep -E "^[ \\t]*{.+}[ \\t]*$" < "$confile") )
    mdebug "Number of connections: ${#cons[@]}"
    mdebug "Searching for VPN URL: $url"

    idx=-1
    for ii in "${!cons[@]}"; do
        con="${cons[$ii]/^ */}"
        mdebug "- connection $ii: $con"
        if echo "$con" | grep -q -F "\"$url\"" &> /dev/null; then
            idx=$ii
            break
        fi
    done

    mdebug "Index of connection found: $idx"

    echo "$idx"
}

function pulseUi_add_connection() {
    local config_home confile name con

    config_home="$HOME/.pulse_secure/pulse"
    confile="$config_home/.pulse_Connections.txt"
    name="UCSF"
    mdebug "Pulse connections file: $confile"
    con="{\"connName\": \"$name\", \"preferredCert\": \"\", \"baseUrl\": \"$url\"}"
    mdebug "Appending connection: $con"
    echo "$con" >> "$confile"
    mecho "Appended missing '$name' connection: $url"
}

function pulse_start_gui() {
    if is_pulseUi_running; then
        mwarn "Pulse Secure GUI is already running"
        return
    fi

    ## Start the Pulse Secure GUI
    ## NOTE: Sending stderr to dev null to silence warnings on
    ## "(pulseUi:26614): libsoup-CRITICAL **: soup_cookie_jar_get_cookies:
    ##  assertion 'SOUP_IS_COOKIE_JAR (jar)' failed"
    mdebug "Pulse Secure GUI client: $(command -v pulseUi)"
    minfo "Launching the Pulse Secure GUI ($(command -v pulseUi))"
    pulseUi 2> /dev/null &
}

function pulse_open_gui() {
    if ! $force; then
      if is_connected; then
          mwarn "Already connected to the VPN [$(public_info)]"
          _exit 0
      fi
    fi

    mdebug "call: $call"
    mdebug "call: pulseUi"

    if $dryrun; then
        _exit 0
    fi

    ## Start the Pulse Secure GUI
    pulse_start_gui
}

function pulse_close_gui() {
    if ! is_pulseUi_running; then return; fi

    mdebug "Closing Pulse Secure GUI"

    ## Try with 'xdotool'?
    if command -v xdotool &> /dev/null; then
        xdotool search --all --onlyvisible --pid "$(pidof pulseUi)" --name "Pulse Secure" windowkill
    else
        pkill -QUIT pulseUi && mdebug "Killed Pulse Secure GUI"
    fi
}

function wait_for_pulse_window_to_close() {
    local wid wids

    wid=$1
    mdebug "Waiting for Pulse Secure Window ID ($wid) to close ..."
    while true; do
       wids=$(xdotool search --all --onlyvisible --name "Pulse Secure")
       echo "$wids" | grep -q "$wid" && break
       sleep 0.2
    done
    mdebug "Waiting for Pulse Secure Window ID ($wid) to close ... done"
}

function pulse_start() {
    local conidx step wid wid2 wid3 cmd opts extra

    ## Validate request
    if [[ "$realm" == "Dual-Factor Pulse Clients" ]]; then
        if ! $gui; then
            merror "Using --realm='$realm' (two-factor authentication; 2FA) is not supported when using --no-gui"
        fi
    elif [[ "$realm" == "Single-Factor Pulse Clients" ]]; then
        if [ -n "${token}" ] && [ "${token}" != "false" ]; then
            merror "Passing a --token='$token' with --realm='$realm' (two-factor authentication; 2FA) does not make sense"
        fi
    fi
    if [ -n "${token}" ] && [ "${token}" != "false" ]; then
        if ! $gui; then
            merror "Using --token='$token' suggests two-factor authentication (2FA), which is currently not supported when using --no-gui"
        fi
    fi

    if ! $force; then
      if is_connected; then
          mwarn "Already connected to the VPN [$(public_info)]"
          _exit 0
      fi
    fi

    ## Check for valid connection in Pulse Secure GUI
    conidx=-1
    if $gui; then
        ## If Pulse Secure GUI is open, we need to close it
        ## before peeking at its connections config file.
        if is_pulseUi_running; then
            close_gui
            sleep "$(div 0.5 "$speed")"
        fi
        conidx=$(pulseUi_find_connection)
        [[ $conidx -eq -1 ]] && pulseUi_add_connection
        conidx=$(pulseUi_find_connection)
        [[ $conidx -eq -1 ]] && merror "Pulse Secure GUI does not have a connection for the VPN: $url"
    fi

    ## Load user credentials from file?
    source_netrc

    ## Prompt for username and password, if missing
    prompt_user "${user}"
    prompt_pwd "${pwd}"

    ## Prompt for 2FA token?
    if [[ "$realm" == "Dual-Factor Pulse Clients" ]]; then
        ## Prompt for one-time token, if requested
        prompt_token "${token}"
    fi

    if $gui; then
        step=1

        ## Check for 'xdotool'
        command -v xdotool &> /dev/null || merror "Cannot enter credentials in GUI, because 'xdotool' could not be located."

        ## Start Pulse Secure GUI
        pulse_start_gui

        sleep "$(div 1.0 "$speed")"
        wid=$(xdotool search --all --onlyvisible --pid "$(pidof pulseUi)" --name "Pulse Secure")
        if [[ -z "$wid" ]]; then
            merror "Failed to locate the Pulse Secure GUI window"
        fi
        mecho "Pulse Secure GUI automation:"
        mdebug "Pulse Secure Window ID: $wid"
        mdebug "Clicking pulseUi 'Connect': $((7 + 2 * conidx)) TABs + ENTER"
        cmd="xdotool search --all --onlyvisible --pid $(pidof pulseUi) --name 'Pulse Secure' windowmap --sync windowactivate --sync windowfocus --sync windowraise mousemove --window %1 --sync 0 0 sleep 0.1 click 1 sleep 0.1 key --delay 50 --repeat "$((7 + 2 * conidx))" Tab sleep 0.1 key Return"
        mdebug " - $cmd"
        mecho " ${step}. selecting connection"
        step=$((step + 1))
        eval "$cmd"

        mdebug "Minimizing Pulse Secure GUI"
        xdotool windowminimize "$wid"

        sleep "$(div 2.0 "$speed")"
        wid2=$(xdotool search --all --onlyvisible --name "Pulse Secure")
        mdebug "Pulse Secure Window IDs: $wid2"
        wid2=$(echo "$wid2" | grep -vF "$wid")
        mdebug "Pulse Secure Popup Window ID: $wid2"
        if [[ -z "$wid2" ]]; then
            merror "Failed to locate the Pulse Secure GUI popup window"
        fi

        ## Click-through UCSF announcement message?
        if $notification; then
            mdebug "Clicking on 'Proceed'"
            cmd="xdotool windowactivate --sync $wid2 key --delay 50 --repeat 2 Tab key Return"
            mdebug " - $cmd"
            eval "$cmd"
            mecho " ${step}. clicking through UCSF notification popup window (--no-notification if it doesn't exist)"
            step=$((step + 1))
            sleep "$(div 2.0 "$speed")"
        else
            mecho " ${step}. skipping UCSF notification popup window (--notification if it exists)"
            step=$((step + 1))
        fi

        mdebug "Entering user credentials (username and password)"
        xdotool windowactivate --sync "$wid2" type "$user"
        xdotool windowactivate --sync "$wid2" key --delay 50 Tab type "$pwd"
        ## Single- or Dual-Factor Pulse Clients?
        extra=
        [[ "$realm" == "Dual-Factor Pulse Clients" ]] && extra="Down"
        cmd="xdotool windowactivate --sync $wid2 key --delay 50 Tab $extra Tab Return"
        mdebug " - $cmd"
        eval "$cmd"
        mecho " ${step}. entering user credentials and selecting realm"
        step=$((step + 1))


        if [[ ${token} != "false" ]]; then
            mdebug "Using two-factor authentication (2FA) token"

            sleep "$(div 1.0 "$speed")"
            wid3=$(xdotool search --all --onlyvisible --name "Pulse Secure")
            mdebug "Pulse Secure Window IDs: $wid3"
            wid3=$(echo "$wid3" | grep -vF "$wid")
            mdebug "Pulse Secure Popup Window ID: $wid3"
            if [[ -z "$wid3" ]]; then
                merror "Failed to locate the Pulse Secure GUI popup window"
            fi

            mdebug "Entering token"
            mecho " ${step}. entering 2FA token"
            step=$((step + 1))
            cmd="xdotool windowactivate --sync $wid3 type $token"
            mdebug " - $cmd"
            eval "$cmd"
            cmd="xdotool windowactivate --sync $wid3 key Return"
            mdebug " - $cmd"
            eval "$cmd"

            ## Wait for popup window to close
            wait_for_pulse_window_to_close "$wid3"
        else
            ## Wait for popup window to close
            wait_for_pulse_window_to_close "$wid2"
        fi
        mecho " ${step}. connecting ..."
        step=$((step + 1))
    else
      if [[ "$realm" == "Dual-Factor Pulse Clients" ]]; then
          merror "Using --realm='$realm' (two-factor authentication; 2FA) is not supported when using --no-gui"
      fi
      if [ -n "${token}" ] && [ "${token}" != "false" ]; then
          merror "Using --token='$token' suggests two-factor authentication (2FA), which is currently not supported when using --no-gui"
      fi
      ## Pulse Secure options
      opts="$extras"
      opts="$opts -h ${server}"

      if [[ -n $user ]]; then
          opts="-u $user $opts"
      fi

      if ! $debug; then
          opts="-log-level 5 $opts"
      fi

      mdebug "call: $call"
      mdebug "user: $user"
      if [[ -n $pwd ]]; then
          mdebug "pwd: <hidden>"
      else
          mdebug "pwd: <not specified>"
      fi
      mdebug "opts: $opts"
      mdebug "call: pulsesvc $opts -r \"${realm}\""

      if $dryrun; then
          if [[ -n $pwd ]]; then
              echo "echo \"<pwd>\" | pulsesvc $opts -r \"${realm}\" | grep -viF password &"
          else
              echo "pulsesvc $opts -r \"${realm}\" &"
          fi
          _exit 0
      fi

      if [[ -n $pwd ]]; then
          echo "$pwd" | pulsesvc "$opts" -r "${realm}" | grep -viF password &
      else
          pulsesvc "$opts" -r "${realm}" &
      fi
    fi
}

function pulse_stop() {
    if ! $force; then
      if is_connected; then
          ## Close/kill the Pulse Secure GUI
          pulse_close_gui

          mwarn "Already connected to the VPN [$(public_info)]"
          _exit 0
      fi
      mdebug "Public IP (before): $ip"
    fi

    ## Close/kill the Pulse Secure GUI
    pulse_close_gui

    ## Kill any running pulsesvc processes
    pulsesvc -Kill
    mdebug "Killed local ('pulsesvc') VPN process"
}


function pulse_troubleshoot() {
    local config_home confile match ii con prefix logfile ## IFS too?

    minfo "Assumed path to Pulse Secure (PULSEPATH): $PULSEPATH"
    command -v pulsesvc || merror "Pulse Secure software 'pulsesvc' not found (in neither PULSEPATH nor PATH)."

    minfo "Pulse Secure software: $res"
    pulsesvc --version

    config_home="$HOME/.pulse_secure/pulse"
    [[ -d "$config_home" ]] || merror "Pulse user-specific folder: $config_home"
    minfo "Pulse user configuration folder: $config_home"

    confile="$config_home/.pulse_Connections.txt"
    [[ -f "$confile" ]] || merror "No Pulse GUI connection file: $confile"
    minfo "Pulse connections file: $confile"
    # shellcheck disable=SC2207
    IFS=$'\r\n' cons=( $(grep -E "^[ \\t]*{.+}[ \\t]*$" < "$confile") )
    minfo "Number of connections: ${#cons[@]}"
    match=false
    for ii in "${!cons[@]}"; do
        con="${cons[$ii]/^ */}"
        if echo "$con" | grep -q -F "\"$url\"" &> /dev/null; then
            prefix=">>>"
            match=true
        else
            prefix="   "
        fi
        >&2 printf " %s %d. %s\\n" "$prefix" "$((ii + 1))" "${con/ *$/}"
    done
    if $match; then
        minfo "Found connection with URL of interest: $url"
    else
        mwarn "No connection with URL of interest: $url"
    fi

    logfile="$config_home/pulsesvc.log"
    [[ -f "$logfile" ]] || merror "No log file: $logfile"

    minfo "Log file: $logfile"
    grep -q -F Error "$logfile" &> /dev/null || { mok "No errors found: $logfile"; _exit 0; }

    mwarn "Detected the following errors in the log file: $(grep -F Error "$logfile" | >&2 tail -3)"
}


# -------------------------------------------------------------------------
# OpenConnect
# -------------------------------------------------------------------------
function openconnect_version() {
    local res

    res=$(openconnect --version 2> /dev/null)
    # shellcheck disable=SC2181
    if [[ $? -ne 0 ]]; then
        echo "<PLEASE INSTALL>"
    else
        printf "%s\\n" "${res[@]}" | grep -F "version" | sed -E 's/.*v//'
    fi
}

function openconnect_pid() {
    local pid

    ## Is there a PID file?
    if [[ ! -f "$pid_file" ]]; then
        mdebug "PID file does not exists: $pid_file"
        echo "-1"
        return
    fi

    mdebug "PID file exists: $pid_file"
    pid=$(cat "$pid_file")
    mdebug "PID recorded in file: $pid"

    ## Is the process still running?
    if ps -p "$pid" > /dev/null; then
        mdebug "Process is running: $pid"
        echo "$pid"
        return
    fi

    ## Remove stray PID file
    rm "$pid_file"
    mwarn "Removed stray PID file with non-existing process (PID=$pid): $pid_file"
    echo "-1"
}

function openconnect_start() {
    local pid opts two_pwds pid fh_stderr stderr reason

    mdebug "openconnect_start() ..."

    pid=$(openconnect_pid)
    if [[ "$pid" != "-1" ]]; then
        if [[ ! $force ]]; then
            merror "A VPN process ('openconnect' PID $pid) is already running."
        fi
    fi

    if ! $force; then
        if [[ $validate == *pid* ]] && [[ $(openconnect_pid) != "-1" ]]; then
           mwarn "Skipping - already connected to the VPN"
           return
        elif [[ $validate == *ipinfo* ]] && is_connected; then
           mwarn "Skipping - already connected to the VPN"
           return
        fi
    fi

    ## Assert that OpenConnect is not already running
    if [[ -f "$pid_file" ]]; then
        merror "Hmm, this might be a bug. Do you already have an active VPN connection? (Detected PID file '$pid_file'; if incorrect, remove with 'sudo rm $pid_file')"
    fi

    if ! is_online; then
        merror "Internet connection is not working"
    fi

    minfo "Preparing to connect to VPN server '$server'"

    assert_sudo "start"

    ## Load user credentials from file?
    source_netrc

    ## Prompt for username and password, if missing
    prompt_user "${user}"
    prompt_pwd "${pwd}"

    ## Prompt for 2FA token?
    if [[ "$realm" == "Dual-Factor Pulse Clients" ]]; then
        ## Prompt for one-time token, if requested
        prompt_token "${token}"
    fi

    ## openconnect options
    opts="$extras"
    opts="$opts --juniper ${url}"
    opts="$opts --background"

    if [[ -n $user ]]; then
        opts="$opts --user=$user"
    fi
    if [[ -n $pwd ]]; then
        opts="$opts --passwd-on-stdin"
    fi

    opts="$opts --pid-file=$pid_file"

    if ! $debug; then
        opts="$opts --quiet"
    fi

    mdebug "call: $call"
    mdebug "user: $user"
    if [[ -n $pwd ]]; then
        mdebug "pwd: <hidden>"
    else
        mdebug "pwd: <not specified>"
    fi
    if [[ -n $token ]]; then
        if [[ $token == "prompt" ]]; then
            mdebug "token: <prompt>"
        elif [[ $token == "push" || $token =~ ^(phone|sms|text)[1-9]*$ ]]; then
            mdebug "token: $token"
        else
            mdebug "token: <hidden>"
        fi
    else
        mdebug "token: <not specified>"
    fi
    mdebug "opts: $opts"
    mdebug "call: sudo openconnect $opts --authgroup=\"$realm\""

    if [[ $token == "push" ]]; then
         mnote "Open the Duo Mobile app on your smartphone or tablet to confirm ..."
    elif [[ $token =~ ^phone[1-9]*$ ]]; then
         mnote "Be prepared to answer your phone to confirm ..."
    elif [[ $token =~ ^(sms|text)[1-9]*$ ]]; then
         merror "Sending tokens via SMS is not supported by the OpenConnect interface"
    fi

    minfo "Connecting to VPN server '${server}'"

    if $dryrun; then
        _exit 0
    fi

    fh_stderr=$(mktemp)

    if [[ -n $pwd && -n $token ]]; then
        case "${UCSF_VPN_TWO_PWDS:-password-token}" in
            "password-token")
                two_pwds="$pwd\n$token\n"
                ;;
            "token-password")
                two_pwds="$token\n$pwd\n"
                ;;
            *)
                merror "Unknown value of UCSF_VPN_TWO_PWDS: '$UCSF_VPN_TWO_PWDS'"
                ;;
        esac
        # shellcheck disable=SC2086
        sudo printf "$two_pwds" | sudo openconnect $opts --authgroup="$realm" 2> "$fh_stderr"
    else
        # shellcheck disable=SC2086
        sudo openconnect $opts --authgroup="$realm" 2> "$fh_stderr"
    fi

    ## Update IP-info file
    pii_file=$(make_pii_file)

    ## Cleanup
    if [[ -f "$fh_stderr" ]]; then
        stderr=$(cat "$fh_stderr")
        sudo rm "$fh_stderr"
    else
        stderr=
    fi
    mdebug "OpenConnect standard error:"
    mdebug "$stderr"

    pid=$(openconnect_pid)
    if [[ "$pid" == "-1" ]]; then
        echo "$stderr"

        ## Post-mortem analysis of the standard error.
        ## (a) When the wrong username or password is entered, we will get:
        ##       username:password:
        ##       fgets (stdin): Inappropriate ioctl for device
        ## (b) When the username and password is correct but the wrong token
        ##     is provided, or user declines, we will get:
        ##       password#2:
        ##       username:fgets (stdin): Resource temporarily unavailable

        ## Was the wrong token given?
        if echo "$stderr" | grep -q -E "password#2"; then
            reason="Likely reason: 2FA token not accepted"
        elif echo "$stderr" | grep -q -F "username:password"; then
            reason="Likely reason: Incorrect username or password"
        else
            reason="Check your username, password, and token"
        fi
        merror "Failed to connect to VPN server (no running OpenConnect process). ${reason}"
    fi
    minfo "Connected to VPN server"
}

function openconnect_stop() {
    local pid kill_timeout

    mdebug "openconnect_stop() ..."

    pid=$(openconnect_pid)
    if [[ "$pid" == "-1" ]]; then
        mwarn "Could not detect a VPN ('openconnect') process. Skipping."
        return
        merror "Failed to located a VPN ('openconnect') process. Are you really connected by VPN? If so, you could manually kill *all* OpenConnect processes by calling 'sudo pkill -INT openconnect'. CAREFUL!"
    fi

    minfo "Disconnecting from VPN server"

    assert_sudo "stop"

    mdebug "Killing OpenConnect process: sudo kill -s INT \"$pid\" 2> /dev/null"
    sudo kill -s INT "$pid" 2> /dev/null

     ## Wait for process to terminate
    kill_timeout=10
    timeout $kill_timeout tail --pid="$pid" -f /dev/null

    ## Update IP-info file
    pii_file=$(make_pii_file)

    ## Assert that the process was terminated
    if ps -p "$pid" > /dev/null; then
        merror "Failed to terminate VPN process ('openconnect' with PID $pid). You could manually kill *all* OpenConnect processes by calling 'sudo pkill -INT openconnect'. CAREFUL!"
    fi

    ## OpenConnect should remove PID file when terminated properly,
    ## but if not, let us remove it here
    if [[ -f "$pid_file" ]]; then
        rm -f "$pid_file"
        mwarn "OpenConnect PID file removed manually: $pid_file"
    fi

    minfo "Disconnected from VPN server"
}


# -------------------------------------------------------------------------
# XDG and cache utility functions
# -------------------------------------------------------------------------
function xdg_config_path() {
    local path

    ## https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html
    path=${XDG_CONFIG_HOME:-$HOME/.config}/ucsf-vpn
    if [ ! -d "$path" ]; then
        mkdir -p "$path"
    fi
    echo "$path"
}

function make_pii_file() {
    pii_cleanup
    mktemp --dry-run --tmpdir="$(xdg_config_path)" --suffix=-ipinfo.json
}

function pii_cleanup() {
    if [[ -f "$pii_file" ]]; then
         mdebug "Removing file: $pii_file"
        rm "$pii_file"
    fi
}


# -------------------------------------------------------------------------
# MAIN
# -------------------------------------------------------------------------
pid_file="$(xdg_config_path)/openconnect.pid"
pii_file=$(make_pii_file)

## Actions
action=

## VPN method: 'openconnect' or 'pulse' (default)
method=${UCSF_VPN_METHOD:-openconnect}

## Options
server=${UCSF_VPN_SERVER:-remote.ucsf.edu}
url=
theme=${UCSF_VPN_THEME:-cli}
force=false
debug=false
verbose=false
validate=
dryrun=false
realm=
extras=${UCSF_VPN_EXTRAS}
gui=true
notification=false
speed=1.0

## User credentials
user=
pwd=
token=${UCSF_VPN_TOKEN:-push}

# Parse command-line options
while [[ $# -gt 0 ]]; do
    mdebug "Next CLI argument: $1"
    ## Commands:
    if [[ "$1" == "start" ]]; then
        action=start
    elif [[ "$1" == "stop" ]]; then
        action=stop
    elif [[ "$1" == "toggle" ]]; then
        action=toggle
        force=true
    elif [[ "$1" == "restart" ]]; then
        action=restart
        force=true
    elif [[ "$1" == "status" ]]; then
        action=status
    elif [[ "$1" == "details" ]]; then
        action=details
    elif [[ "$1" == "log" ]]; then
        action=log
    elif [[ "$1" == "troubleshoot" ]]; then
        action=troubleshoot
    elif [[ "$1" == "open-gui" ]]; then
        action=open-gui
    elif [[ "$1" == "close-gui" ]]; then
        action=close-gui

    ## Options (--flags):
    elif [[ "$1" == "--help" ]]; then
        action=help
    elif [[ "$1" == "--version" ]]; then
        action=version
    elif [[ "$1" == "--debug" ]]; then
        debug=true
    elif [[ "$1" == "--verbose" ]]; then
        verbose=true
    elif [[ "$1" == "--force" ]]; then
        force=true
    elif [[ "$1" == "--dry-run" ]]; then
        dryrun=true
    elif [[ "$1" == "--dryrun" ]]; then
        merror "Did you mean to use '--dry-run'?"
    elif [[ "$1" == "--notification" ]]; then
        notification=true
    elif [[ "$1" == "--no-notification" ]]; then
        notification=false
    elif [[ "$1" == "--gui" ]]; then
        gui=true
    elif [[ "$1" == "--no-gui" ]]; then
        gui=false

    ## Options (--key=value):
    elif [[ "$1" =~ ^--.*=.*$ ]]; then
        key=${1//--}
        key=${key//=*}
        value=${1//--[[:alpha:]]*=}
        mdebug "Key-value option '$1' parsed to key='$key', value='$value'"
        if [[ -z $value ]]; then
            merror "Option '--$key' must not be empty"
        fi
        if [[ "$key" == "method" ]]; then
            method=$value
        elif [[ "$key" == "url" ]]; then
            url=$value
        elif [[ "$key" == "server" ]]; then
            server=$value
        elif [[ "$key" == "realm" ]]; then
            realm=$value
        elif [[ "$key" == "user" ]]; then
            user=$value
        elif [[ "$key" == "pwd" ]]; then
            pwd=$value
        elif [[ "$key" == "token" ]]; then
            token=$value
        elif [[ "$key" == "speed" ]]; then
            speed=$value
        elif [[ "$key" == "theme" ]]; then
            theme=$value
        elif [[ "$key" == "validate" ]]; then
            validate=$value
        fi

    ## DEPRECATED: Options (--key value):
    elif [[ "$1" == "--skip" ]]; then
        mdeprecated "Command-line option '$1' is deprecated and ignored."
    elif [[ "$1" =~ ^--(method|pwd|realm|server|speed|token|url|user)$ ]]; then
        mdeprecated "Command-line option format '$1 $2' is deprecated. Use '$1=$2' instead."
        key=${1//--}
        shift
        if [[ "$key" == "method" ]]; then
            method=$1
        elif [[ "$key" == "url" ]]; then
            url=$1
        elif [[ "$key" == "server" ]]; then
            server=$1
        elif [[ "$key" == "realm" ]]; then
            realm=$1
        elif [[ "$key" == "user" ]]; then
            user=$1
        elif [[ "$key" == "pwd" ]]; then
            pwd=$1
        elif [[ "$key" == "token" ]]; then
            token=$1
        elif [[ "$key" == "speed" ]]; then
            speed=$1
        fi

    ## Additional options to be appended (rarely needed)
    else
        extras="$extras $1"
    fi
    shift
done


## --help should always be available prior to any validation errors
if [[ -z $action ]]; then
    help
    _exit 0
elif [[ $action == "help" ]]; then
    help full
    _exit 0
fi


## Use default URL?
[[ -z "$url" ]] && url=https://${server}/pulse


# -------------------------------------------------------------------------
# Validate options
# -------------------------------------------------------------------------
## Validate 'method'
if [[ ${method} == "openconnect" ]]; then
    mdebug "Method: $method"
elif [[ ${method} == "pulse" ]]; then
    mdebug "Method: $method"
else
    merror "Unknown value on option --method: '$method'"
fi

## Validate 'realm'
if [[ -z $realm ]]; then
    if $gui; then
        realm="Dual-Factor Pulse Clients"
    else
        realm="Single-Factor Pulse Clients"
    fi
fi
if [[ $realm == "Single-Factor Pulse Clients" ]]; then
    true
elif [[ $realm == "Dual-Factor Pulse Clients" ]]; then
    true
elif [[ $realm == "single" ]]; then
    realm="Single-Factor Pulse Clients"
elif [[ $realm == "dual" ]]; then
    realm="Dual-Factor Pulse Clients"
else
    merror "Unknown value on option --realm: '$realm'"
fi

## Validate 'token':
if [[ ${token} == "true" ]]; then  ## Backward compatibility
    token="prompt"
fi
if [[ $realm != "Dual-Factor Pulse Clients" ]]; then
    token=false
elif [[ ${token} == "prompt" || ${token} == "true" ]]; then
    mdebug "Will prompt user for 2FA token"
elif [[ ${token} == "false" ]]; then
    mdebug "Will not use 2FA authenatication"
elif [[ $(type_of_token "$token") == "unknown" ]]; then
    merror "The token (--token) must be 6 or 7 digits or 44 letters (YubiKey)"
fi

## Validate 'theme'
if [[ ! $theme =~ ^(cli|none)$ ]]; then
    merror "Unknown --theme value: '$theme'"
fi

## Validate 'validate'
if [[ $method == "openconnect" ]]; then
    if [[ -z $validate ]]; then
        validate=${UCSF_VPN_VALIDATE:-pid,ipinfo}
    elif [[ ! $validate =~ ^(ipinfo|pid|pid,ipinfo)$ ]]; then
        merror "Unknown --validate value: '$validate'"
    fi
elif [[ $method == "pulse" ]]; then
    if [[ -z $validate ]]; then
        validate=${UCSF_VPN_VALIDATE:-ipinfo}
    elif [[ ! $validate =~ ^(ipinfo)$ ]]; then
        merror "Unknown --validate value: '$validate'"
    fi
fi

## Validate 'speed'
if [[ ! ${speed} =~ ^[0-9]+[.0-9]*$ ]]; then
    merror "Invalid --speed argument: '$speed'"
fi


# -------------------------------------------------------------------------
# Initiate
# -------------------------------------------------------------------------
## Regular expression for locating the proper netrc entry
if [[ "$server" == "remote.ucsf.edu" ]]; then
    netrc_machines=${server}
else
    netrc_machines=("${server}" remote.ucsf.edu)
fi

mdebug "call: $call"
mdebug "action: $action"
mdebug "VPN server: $server"
mdebug "Realm: '$realm'"
mdebug "user: $user"
if [[ -z "${pwd}" ]]; then
    mdebug "pwd=<missing>"
else
    mdebug "pwd=<hidden>"
fi
if [[ -z "${token}" ]]; then
    mdebug "token=<missing>"
elif [[ $token == "prompt" ]]; then
    mdebug "token=<prompt>"
elif [[ $token == "push" || $token == "sms" || $token =~ ^phone[1-9]*$ ]]; then
    mdebug "token=$token"
else
    mdebug "token=<hidden>"
fi
mdebug "verbose: $verbose"
mdebug "force: $force"
mdebug "validate: $validate"
mdebug "dryrun: $dryrun"
mdebug "extras: $extras"
mdebug "method: $method"
mdebug "gui: $gui"
mdebug "speed: $speed"
mdebug "netrc machines: ${netrc_machines[*]}"
mdebug "pid_file: $pid_file"
mdebug "openconnect_pid: $(openconnect_pid)"
mdebug "pii_file: $pii_file"


# -------------------------------------------------------------------------
# Actions
# -------------------------------------------------------------------------
if [[ $action == "version" ]]; then
    version
    _exit 0
fi

if [[ $action == "status" ]]; then
    status
elif [[ $action == "details" ]]; then
    connection_details
    _exit $?
elif [[ $action == "open-gui" ]]; then
    if [[ $method != "pulse" ]]; then
        merror "ucsf vpn open-gui requires --method=pulse: $method"
    fi
    pulse_open_gui
    res=$?
    _exit $res
elif [[ $action == "close-gui" ]]; then
    if [[ $method != "pulse" ]]; then
        merror "ucsf vpn open-gui requires --method=pulse: $method"
    fi
    pulse_close_gui
    res=$?
    _exit $res
elif [[ $action == "start" ]]; then
    if [[ $method == "openconnect" ]]; then
        openconnect_start
        res=$?
    elif [[ $method == "pulse" ]]; then
        pulse_start
        res=$?
        sleep "$(div 4.0 "$speed")"
    fi
    status "connected"
elif [[ $action == "stop" ]]; then
    if [[ $method == "openconnect" ]]; then
        openconnect_stop
        res=$?
    elif [[ $method == "pulse" ]]; then
        pulse_stop
        res=$?
        sleep "$(div 1.0 "$speed")"
    fi
    status "disconnected"
elif [[ $action == "restart" ]]; then
    if [[ $method == "openconnect" ]]; then
        if is_connected; then
            openconnect_stop
        fi
        openconnect_start
        res=$?
    elif [[ $method == "pulse" ]]; then
        pulse_stop
        sleep "$(div 1.0 "$speed")"
        is_online
        pulse_start
        sleep "$(div 4.0 "$speed")"
        res=$?
    fi
    status "connected"
elif [[ $action == "toggle" ]]; then
    if ! is_connected; then
      if [[ $method == "openconnect" ]]; then
          openconnect_start
      elif [[ $method == "pulse" ]]; then
          pulse_start
          sleep "$(div 4.0 "$speed")"
      fi
      status "connected"
    else
      if [[ $method == "openconnect" ]]; then
          openconnect_stop
      elif [[ $method == "pulse" ]]; then
          pulse_stop
          sleep "$(div 1.0 "$speed")"
      fi
      status "disconnected"
    fi
elif [[ $action == "log" ]]; then
    if [[ $method == "openconnect" ]]; then
        LOGFILE=/var/log/syslog
        minfo "Displaying 'VPN' entries in log file: $LOGFILE"
        if [[ ! -f $LOGFILE ]]; then
            mwarn "No such log file: $LOGFILE"
            _exit 1
        fi
        grep VPN "$LOGFILE"
    elif [[ $method == "pulse" ]]; then
        LOGFILE=$HOME/.pulse_secure/pulse/pulsesvc.log
        minfo "Displaying log file: $LOGFILE"
        if [[ ! -f $LOGFILE ]]; then
            mwarn "No such log file: $LOGFILE"
            _exit 1
        fi
        cat "$LOGFILE"
    fi
elif [[ $action == "troubleshoot" ]]; then
    if [[ $method == "openconnect" ]]; then
        merror "ucsf-vpn troubleshoot is not implemented for --method=openconnect"
    elif [[ $method == "pulse" ]]; then
        pulse_troubleshoot
    fi
fi


_exit 0
#!/bin/bash

# NB: sometimes the script will produce the message
# "wlan0     Interface doesn't support scanning : Device or resource busy"
# This has nothing to do with the script. Usually this is just a random
# bug of the call "/sbin/iwlist wlan0 scanning" and running the script again
# solves the problem

# TODO: we are excluding channels by name, but in Racurs there are 2 networks with ESSID "Racurs", so
# need to distinguish channels not only by name, but also by frequency.

# TODO(MAYBE): print suggested channel. It is difficult to visually analyze the output

# /sbin/iwlist wlan0 scanning | grep "Signal level" | tr -s '()=' ' ' | sed -nr '{s/.*Signal level ([0-9+-]+).*/\1/;p;q}'

# Shows the total power in mWatts emitted by all routers for each WiFi channel in order to help you
# to choose the channel with the least amount of noise for your WiFi router

# required: bc (An arbitrary precision calculator language), sed (stream editor)
#           iwlist, iwconfig (wireless-tools package)

# NB1: The script tries to automatically detect the name of your wifi interface. Detection is done by calling
#      'iwconfig' program, which is a part of 'wireless-tools' package. If for some reason the detection does
#      not work for you and know the name of your wireless interface (for most people it is 'wlan0'. you can
#      call '/sbin/ifconfig -a' and try to guess) then comment out line 'XXX', uncomment line 'YYY' and put
#      the correct name of the wireless interface there.

wlan_interface=$(/sbin/iwconfig 2>/dev/null | sed -n "/ESSID/{s/[[:space:]].*//;p;q;}") # XXX
#wlan_interface="wlan0"                                                            # YYY

#echo Using wireless interface \'${wlan_interface}\'

# obtain the ESSID of your wifi network, in order to exclude it from power calculation
#myessid=$(/sbin/iwconfig 2>/dev/null | sed -nr '/ESSID/{s/.*ESSID://;p;q;}')

declare -a tmp
tmp=( $(/sbin/iwconfig 2>/dev/null | sed -nr '/ESSID/{s/.*ESSID://;p;q;}') )
# also possible to use iwconfig with ${wlan_interface}, but not sure if there is a sense.
# if PC has several wifi devices, ${wlan_interface} will get not currect, but rather first in the list.
#tmp=( $(/sbin/iwconfig ${wlan_interface} 2>/dev/null | sed -nr '/ESSID/{s/.*ESSID://;p;q;}') )

# Long ESSID names have double quotes present in their names. We do not remove these literals, because
# later we compare this string with strings, where double quotes will be present too, since they will
# be obtained using the same 'sed' command
myessid="${tmp[@]}"

myessid=$(/sbin/iwconfig 2>/dev/null | sed -nr '/ESSID/{s/.*ESSID:([^[:space:]]*).*/\1/;p;q;}')
my_freq=$(/sbin/iwconfig wlan0 2>/dev/null | sed -nr '/requency/{s/.*requency:([^[:space:]]*)[[:space:]].*/\1/;p;q;}')
echo Currently using ${myessid}, ${my_freq} GHz

#if [[ "${myessid}" = "off/any" ]]; then
#  myessid=""
#  echo OFF
#fi

# NB2: we assume that only 11 WiFi channels are available. if in your country it is more, change the variable
# accordingly

wchan_number=13

# In order to get information about the power on each wifi channel we use the program 'iwlist', which is a part
# of 'wireless-tools' package, and do a pretty primitive parsing. If they change the format of output, this may
# not work.

#3. we use very primitive parsing and assume that the output of "/sbin/iwlist wlan0 scanning" is
#        Frequency:2.437 GHz (Channel 6)
#        Quality=64/70  Signal level=-46 dBm  
# then we remove '(', ')' and '=' and assume that channel number has the 4-th position
# and the signal level has 5-th position. At this point I see no reason to make the parsing
# more intelligent.
# although a pretty robust parsing would be search for position of 'Channel' and read the next position
# and search for "level=" how we did in Leonov phase diagram calculations. may be when we decide to
# make the script public...

# 4. we assumbe that "/sbin/iwlist wlan0 scanning" prints dB info for the power of the signal, not the
# amplitude. if the assumption is wrong, we should change the formula
# pow_i=$(float_eval_local "e ( l(10.) * ${arr[4]} / 10. )")
# to
# pow_i=$(float_eval_local "e ( l(10.) * ${arr[4]} / 20. )")

# 5. we assume that signal levels are given in [dBm], then output powers are in [mW]

# 6. The total power for a channel is calculated as P_{tot} = \sum_{i=1}^n exp(db_i/10)

# Evaluate a floating point number expression.
function float_eval_local()
{
    float_scale=12 # number of digits after decimal point

    local stat=0
    local result=0.0
    if [[ $# -gt 0 ]]; then
        result=$(echo "scale=$float_scale; $*" | bc -l -q 2>/dev/null)
        stat=$?
        if [[ $stat -eq 0  &&  -z "$result" ]]; then stat=1; fi
    fi
    echo $result
    return $stat
}

if [[ $USER != "root" ]]; then
  echo "WARNING: It is better to run the script under the 'root' account because for some reason under a regular user the script does not show all occupied channels"
  echo
fi

(( i=0 ))

while read -r line; do
  (( ++i ))

  if [[ -z ${signal_level} ]]; then
    signal_level=$(echo ${line} | sed -nr '/evel/{s/.*[Ll]evel[[:space:]]*([[:digit:]+-]*).*/\1/;p;q;}')
  fi
  #if [[ ${signal_level} ]]; then echo level=${signal_level}; fi

  if [[ -z ${chan_num} ]]; then
    chan_num=$(echo ${line} | sed -nr '/requency/{s/.*[Cc]hannel[[:space:]]*([[:digit:]]*).*/\1/;p;q;}')
  fi

  if [[ -z ${chan_freq} ]]; then
    chan_freq=$(echo ${line} | sed -nr '/requency/{s/.*requency:([^[:space:]^[:alpha:]]*).*/\1/;p;q;}')
  fi

  if [[ -z ${essid} ]]; then
    essid="$(echo ${line} | sed -nr '/ESSID/{s/.*ESSID:[[:space:]]*(.*)/\1/;p;q;}')"
  fi

  # alternative way to detect essid. was created in order to account for essid's
  # with spaces, but seems that a simpler way works fine
  # if [[ -z ${mmm} ]]; then
  #  tmp=( $(echo ${line} | sed -nr '/ESSID/{s/.*ESSID://;p;q;}') )
  #  mmm=${tmp[0]}
  # fi
  # if [[ ${mmm} ]]; then echo ESSID=${mmm}; fi

  if ((i%3==0)); then
    if [[ $essid = $myessid && ${chan_freq} = ${my_freq} ]]; then
      echo Excluding ${myessid}, ${chan_freq} GHz
    else
      echo Adding ${essid}, ${chan_freq} GHz
      pow_i=$(float_eval_local "e ( l(10.) * ${signal_level} / 10. )")
      [[ ! ${intens[$chan_num]+abc} ]] && intens[$chan_num]="0."
      intens[$chan_num]=$(float_eval_local "${intens[$chan_num]} + $pow_i ")
    fi

    signal_level=""
    chan_num=""
    essid=""
    chan_freq=""
  fi

#done < <(/sbin/iwlist ${wlan_interface} scanning | grep "Frequency\|Signal level\|ESSID:" | tr -s '()=' ' ')
done < <(/sbin/iwlist ${wlan_interface} scanning | grep "Frequency\|level\|ESSID:" | tr -s '()=' ' ')

echo -n "Channel   "
# if a channel is unused, put 0
for ((i=1; i<=${wchan_number}; ++i)); do [[ ! ${intens[$i]+abc} ]] && intens[$i]="0"; done

for x in ${!intens[*]}; do

  # we add spaces for aligning shorter numbers
  case $x in
    [0-9]) space="    ";;
    [1-9][0-9]) space="   ";;
    *) space="  ";;
  esac

  if [[ "${intens[$x]}" == "0" ]]; then
    echo -en "\e[2;42;30m    ${x}${space}\e[0m" # 48 - background is set, no idea what '5' is for.
  else
    echo -en "\e[2;41;30m    ${x}${space}\e[0m" # 48 - background is set, no idea what '5' is for.
  fi

done

echo
echo -n "Power [mW]"

for x in ${!intens[*]}; do

  # we add spaces for aligning shorter numbers
  case $color in
  [0-9]) space="  ";;
  [1-9][0-9]) space=" ";;
  *) space="   ";;
  esac

  if [[ "${intens[$x]}" == "0" ]]; then
    printf "\e[2;42;30m    0    \e[0m"
  else
    printf "\e[2;41;30m %.1e \e[0m" ${intens[$x]}
  fi
done

echo

exit 0



#echo -en "\e[48;5;1m ${x}${space}\e[0m" # 48 - background is set. 
printf "\e[48;5;2m    0    \e[0m"
else
#echo -en "\e[48;5;2m ${x}${space}\e[0m" # 48 - background is set. 
printf "\e[48;5;1m %.1e \e[0m" ${intens[$x]}


for x in ${!intens[*]}; do
printf "[%.1e] " ${intens[$x]}
done

echo

for x in ${!intens[*]}; do
printf "[%d, %.1e] " $x ${intens[$x]}
done

echo

# /sbin/iwlist wlan0 scanning | grep "Frequency\|Signal level"
#                    Frequency:2.437 GHz (Channel 6)
#                    Quality=48/70  Signal level=-62 dBm  
#                    Frequency:2.432 GHz (Channel 5)
#                    Quality=28/70  Signal level=-82 dBm  
#                    Frequency:2.462 GHz (Channel 11)
#                    Quality=27/70  Signal level=-83 dBm  


#/sbin/iwlist wlan0 scanning | grep "Frequency\|Signal level" | awk 'NR%2==0 {print} NR%2==1 {print $2}'
#/sbin/iwlist eth1 scanning | grep "Frequency\|Signal level" | awk 'NR%2==0 {print} NR%2==1 {print $2}'

#while IFS= read -r line; do echo "$line" ; done < /input/file/name
#float_eval_local 2.1^4

# P_{tot} = \sum_{i=1}^n P_i
# db_i = 10 log(P_i/p)
# P_i = p exp(db_i/10)
# P_{tot} = p \sum_{i=1}^n exp(db_i/10)

#                    Frequency:2.437 GHz (Channel 6)
#                    Quality=66/70  Signal level=-44 dBm  
#                    ESSID:"Racurs"
